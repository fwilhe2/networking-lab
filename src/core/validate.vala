/* validate.vala
 *
 * SPEC section 5. Warnings never block generation: the compose file is always
 * produced and always downloadable, because a half-drawn lab is still worth
 * booting. Errors render red, advisories amber.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Core {

    public class Diagnostic : Object {
        public bool is_error;
        public string message;

        public Diagnostic (bool is_error, string message) {
            this.is_error = is_error;
            this.message = message;
        }
    }

    public GenericArray<Diagnostic> validate (State state,
                                              GenericArray<Network>? known_networks = null) {
        var nets = known_networks ?? networks_of (state);
        var result = new GenericArray<Diagnostic> ();

        /* 1. Two devices cannot share a docker identifier. */
        var names = new_name_set ();
        for (var i = 0; i < state.nodes.length; i++) {
            var name = state.nodes[i].name;
            if (names.contains (name)) {
                result.add (new Diagnostic (true, "Duplicate name \"%s\".".printf (name)));
            }
            names.add (name);
        }

        /* 2. A switch named p2p_r1_r2 would collide with a generated network
         *    name, and docker would merge the two segments. */
        var net_names = new_name_set ();
        for (var i = 0; i < nets.length; i++) {
            var name = nets[i].name;
            if (net_names.contains (name)) {
                result.add (new Diagnostic (true,
                    "Two networks are both named \"%s\" — rename a device.".printf (name)));
            }
            net_names.add (name);
        }

        /* 3. Addressing, per network. */
        for (var i = 0; i < nets.length; i++) {
            var net = nets[i];
            var seen = new HashTable<string, string> (str_hash, str_equal);

            for (var j = 0; j < net.attachments.length; j++) {
                var attachment = net.attachments[j];
                var device = state.node_by_id (attachment.node_id);
                if (device == null) {
                    continue;
                }

                var ip = attachment.link.ip_for (attachment.node_id);
                if (ip == "") {
                    result.add (new Diagnostic (true,
                        "%s has no IP on %s.".printf (device.name, net.name)));
                    continue;
                }

                if (!in_subnet (ip, net.subnet)) {
                    result.add (new Diagnostic (true,
                        "%s: %s is outside %s (%s).".printf (device.name, ip, net.name, net.subnet)));
                }

                if (ip == docker_gateway (net.subnet)) {
                    result.add (new Diagnostic (true,
                        ("%s: %s collides with the docker gateway on %s " +
                         "(last usable address is reserved).").printf (device.name, ip, net.name)));
                }

                var owner = seen.lookup (ip);
                if (owner != null) {
                    result.add (new Diagnostic (true,
                        "Duplicate IP %s on %s (%s and %s).".printf (ip, net.name, owner, device.name)));
                }
                seen.insert (ip, device.name);
            }
        }

        /* 4. Advisories. Switches are segments, not devices, so they are not
         *    expected to be addressed or connected. */
        for (var i = 0; i < state.nodes.length; i++) {
            var device = state.nodes[i];
            if (device.is_switch ()) {
                continue;
            }

            var interfaces = interfaces_of (state, device.id, nets);
            var is_host = device.device_type == DeviceType.PC
                       || device.device_type == DeviceType.SERVER;

            if (is_host && interfaces.length > 0 && device.gw == "") {
                result.add (new Diagnostic (false,
                    "%s has no default gateway set — it can only reach its own subnet."
                    .printf (device.name)));
            }

            if (interfaces.length == 0) {
                result.add (new Diagnostic (false,
                    "%s is not connected to anything.".printf (device.name)));
            }
        }

        return result;
    }

    public bool has_errors (GenericArray<Diagnostic> diagnostics) {
        for (var i = 0; i < diagnostics.length; i++) {
            if (diagnostics[i].is_error) {
                return true;
            }
        }
        return false;
    }
}
