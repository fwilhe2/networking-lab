/* derive.vala
 *
 * The derived model (SPEC 2.4 and 2.5). Networks, interface names and
 * interface order are computed from nodes and links on demand and never
 * persisted — which is why reordering links renumbers eth<i>.
 *
 * Emission order matters: it is the order the compose file uses.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Core {

    public class Attachment : Object {
        public string node_id;
        public Link link;

        public Attachment (string node_id, Link link) {
            this.node_id = node_id;
            this.link = link;
        }
    }

    /* One L2/L3 segment: a switch, or a point-to-point link between two
     * non-switch devices. */
    public class Network : Object {
        public string key;
        public string name;
        public string subnet;
        public GenericArray<Attachment> attachments = new GenericArray<Attachment> ();

        public Network (string key, string name, string subnet) {
            this.key = key;
            this.name = name;
            this.subnet = subnet;
        }

        public bool holds (string node_id, Link link) {
            for (var i = 0; i < attachments.length; i++) {
                if (attachments[i].node_id == node_id && attachments[i].link == link) {
                    return true;
                }
            }
            return false;
        }
    }

    public class Iface : Object {
        public string eth;
        public Network net;
        public Link link;
        public string ip;

        public Iface (string eth, Network net, Link link, string ip) {
            this.eth = eth;
            this.net = net;
            this.link = link;
            this.ip = ip;
        }
    }

    /* Switches first in node order, then point-to-point links in link order.
     *
     * A p2p network's name is built from the current device names, so renaming
     * a device renames its p2p networks — and can collide with a switch name,
     * which is what the second validation check is for. */
    public GenericArray<Network> networks_of (State state) {
        var result = new GenericArray<Network> ();

        for (var i = 0; i < state.nodes.length; i++) {
            var sw = state.nodes[i];
            if (!sw.is_switch ()) {
                continue;
            }

            var net = new Network ("sw:" + sw.id, sw.name, sw.subnet);
            for (var j = 0; j < state.links.length; j++) {
                var link = state.links[j];
                if (link.touches (sw.id)) {
                    net.attachments.add (new Attachment (link.other_end (sw.id), link));
                }
            }
            result.add (net);
        }

        for (var i = 0; i < state.links.length; i++) {
            var link = state.links[i];
            var a = state.node_by_id (link.a);
            var b = state.node_by_id (link.b);
            if (a == null || b == null || a.is_switch () || b.is_switch ()) {
                continue;
            }

            var net = new Network ("p2p:" + link.id,
                                   "p2p_%s_%s".printf (a.name, b.name),
                                   link.subnet);
            net.attachments.add (new Attachment (a.id, link));
            net.attachments.add (new Attachment (b.id, link));
            result.add (net);
        }

        return result;
    }

    /* Interface numbering walks the link array, so it follows link creation
     * order. A switch never appears in its own network's attachments, which is
     * how it ends up with no interfaces and therefore no service. */
    public GenericArray<Iface> interfaces_of (State state, string node_id,
                                              GenericArray<Network>? known_networks = null) {
        var nets = known_networks ?? networks_of (state);
        var result = new GenericArray<Iface> ();

        for (var i = 0; i < state.links.length; i++) {
            var link = state.links[i];
            if (!link.touches (node_id)) {
                continue;
            }

            for (var j = 0; j < nets.length; j++) {
                if (nets[j].holds (node_id, link)) {
                    result.add (new Iface ("eth%d".printf (result.length),
                                           nets[j], link, link.ip_for (node_id)));
                    break;
                }
            }
        }

        return result;
    }

    public GenericArray<string> used_ips_on (Network net) {
        var result = new GenericArray<string> ();
        for (var i = 0; i < net.attachments.length; i++) {
            var ip = net.attachments[i].link.ip_for (net.attachments[i].node_id);
            if (ip != "") {
                result.add (ip);
            }
        }
        return result;
    }

    /* SPEC 3.2. Routers take the bottom of the range, hosts start ten in, and
     * docker's gateway is never handed out. Returns "" when the subnet is full. */
    public string next_free_ip (Network net, bool for_router) {
        var info = cidr_info (net.subnet);

        var used = new GenericSet<uint32> (direct_hash, direct_equal);
        var taken = used_ips_on (net);
        for (var i = 0; i < taken.length; i++) {
            used.add (ip_to_int (taken[i]));
        }
        used.add (info.last);

        var start = for_router ? info.first : info.base_address + 10;
        if (start > info.last) {
            start = info.first;
        }

        for (var n = start; n <= info.last; n++) {
            if (!used.contains (n)) {
                return int_to_ip (n);
            }
        }

        return "";
    }
}
