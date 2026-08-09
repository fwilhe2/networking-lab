/* edit.vala
 *
 * The editing operations of SPEC section 4. They mutate a document and nothing
 * else — no history, no selection, no redraw — so the interesting parts
 * (address allocation, the default-gateway convenience, what a refusal means)
 * stay testable without a UI. Pushing history is the caller's job.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Core {

    /* Why a link was not created. Refusals are reported, never silent. */
    public enum LinkRefusal {
        NONE,
        SWITCH_TO_SWITCH,
        ALREADY_CONNECTED,
        NO_SUCH_DEVICE;

        public string message () {
            switch (this) {
                case SWITCH_TO_SWITCH:
                    return "Switch-to-switch links are not supported: each switch is one L2 " +
                           "segment. Use a router between them.";
                case ALREADY_CONNECTED:
                    return "These two are already connected.";
                case NO_SUCH_DEVICE:
                    return "That device is no longer there.";
                default:
                    return "";
            }
        }
    }

    public Node add_node (State state, DeviceType type, double x, double y) {
        var ordinal = state.counters.next_for_type (type);
        state.counters.node++;

        var taken = new_name_set ();
        for (var i = 0; i < state.nodes.length; i++) {
            taken.add (state.nodes[i].name);
        }

        var position = clamp_pos (x, y);
        var node = new Node (
            "n%d".printf (state.counters.node),
            type,
            unique_name ("%s%d".printf (type.prefix (), ordinal), taken),
            position.x,
            position.y
        );

        /* A switch is a segment, so it needs one the moment it exists. */
        if (type == DeviceType.SWITCH) {
            node.subnet = state.alloc_subnet ();
        }

        state.nodes.add (node);
        return node;
    }

    public Link? add_link (State state, string a_id, string b_id, out LinkRefusal refusal) {
        refusal = LinkRefusal.NONE;

        var a = state.node_by_id (a_id);
        var b = state.node_by_id (b_id);
        if (a == null || b == null || a == b) {
            refusal = LinkRefusal.NO_SUCH_DEVICE;
            return null;
        }

        if (a.is_switch () && b.is_switch ()) {
            refusal = LinkRefusal.SWITCH_TO_SWITCH;
            return null;
        }

        for (var i = 0; i < state.links.length; i++) {
            if (state.links[i].touches (a_id) && state.links[i].touches (b_id)) {
                refusal = LinkRefusal.ALREADY_CONNECTED;
                return null;
            }
        }

        state.counters.link++;
        var link = new Link ("l%d".printf (state.counters.link), a.id, b.id);
        if (!a.is_switch () && !b.is_switch ()) {
            link.subnet = state.alloc_subnet ();
        }
        state.links.add (link);

        var net = network_holding (state, link);
        if (net == null) {
            return link;
        }

        /* Address both non-switch ends, then point any host without a gateway
         * at a router on the same segment. */
        foreach (var end in new Node[] { a, b }) {
            if (!end.is_switch ()) {
                link.ips.insert (end.id, next_free_ip (net, end.device_type == DeviceType.ROUTER));
            }
        }

        foreach (var end in new Node[] { a, b }) {
            var is_host = end.device_type == DeviceType.PC || end.device_type == DeviceType.SERVER;
            if (!is_host || end.gw != "") {
                continue;
            }

            var gateway = first_router_address (state, net);
            if (gateway != "") {
                end.gw = gateway;
            } else if (a.device_type == DeviceType.ROUTER || b.device_type == DeviceType.ROUTER) {
                var router = a.device_type == DeviceType.ROUTER ? a : b;
                end.gw = link.ip_for (router.id);
            }
        }

        return link;
    }

    private Network? network_holding (State state, Link link) {
        var nets = networks_of (state);
        for (var i = 0; i < nets.length; i++) {
            for (var j = 0; j < nets[i].attachments.length; j++) {
                if (nets[i].attachments[j].link == link) {
                    return nets[i];
                }
            }
        }
        return null;
    }

    private string first_router_address (State state, Network net) {
        for (var i = 0; i < net.attachments.length; i++) {
            var attachment = net.attachments[i];
            var device = state.node_by_id (attachment.node_id);
            var ip = attachment.link.ip_for (attachment.node_id);
            if (device != null && device.device_type == DeviceType.ROUTER && ip != "") {
                return ip;
            }
        }
        return "";
    }

    /* Deleting a device takes its links with it: a link to nothing is not a
     * thing the document can represent. */
    public void delete_node (State state, string id) {
        for (var i = state.links.length - 1; i >= 0; i--) {
            if (state.links[i].touches (id)) {
                state.links.remove_index (i);
            }
        }
        for (var i = state.nodes.length - 1; i >= 0; i--) {
            if (state.nodes[i].id == id) {
                state.nodes.remove_index (i);
            }
        }
    }

    public void delete_link (State state, string id) {
        for (var i = state.links.length - 1; i >= 0; i--) {
            if (state.links[i].id == id) {
                state.links.remove_index (i);
            }
        }
    }

    /* Links are deliberately not copied — a duplicated device is a starting
     * point, not a second copy of the same wiring. */
    public Node? duplicate_node (State state, string id) {
        var source = state.node_by_id (id);
        if (source == null) {
            return null;
        }

        var copy = add_node (state, source.device_type,
                             source.x + GRID * 2, source.y + GRID * 2);
        copy.frr_extra = source.frr_extra;
        copy.gw = source.gw;
        copy.http_port = source.http_port;
        return copy;
    }

    public bool name_is_taken (State state, string name, string except_id) {
        for (var i = 0; i < state.nodes.length; i++) {
            if (state.nodes[i].id != except_id && state.nodes[i].name == name) {
                return true;
            }
        }
        return false;
    }

    /* Nudging passes free: the step is already grid-sized, and re-snapping
     * would drag the other axis along whenever a device sits off-grid. */
    public void move_node (State state, string id, double x, double y, bool free) {
        var node = state.node_by_id (id);
        if (node == null) {
            return;
        }

        var position = clamp_pos (x, y, free);
        node.x = position.x;
        node.y = position.y;
    }

    /* Keeps the lab settings: they describe how the document is built, not
     * what is in it. */
    public void clear_topology (State state) {
        state.nodes = new GenericArray<Node> ();
        state.links = new GenericArray<Link> ();
        state.counters = new Counters ();
    }
}
