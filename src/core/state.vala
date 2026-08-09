/* state.vala
 *
 * The document (SPEC section 2): the whole thing that is persisted, exported
 * and imported. Nothing derived lives here — networks and interface names are
 * computed from nodes and links on demand, in derive.vala.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Core {

    public class Node : Object {
        public string id;                       /* "n" + counters.node, never reused */
        public DeviceType device_type;
        public string name;                     /* unique, sanitised, becomes the docker identifier */
        public double x;
        public double y;

        /* Type-conditional. Empty when the type does not carry the field. */
        public string subnet = "";              /* switch: the segment's CIDR */
        public string frr_extra = "";           /* router: appended verbatim to frr.conf */
        public string gw = "";                  /* pc/server: default gateway */
        public string http_port = "80";         /* server: digits only */

        public Node (string id, DeviceType device_type, string name, double x, double y) {
            this.id = id;
            this.device_type = device_type;
            this.name = name;
            this.x = x;
            this.y = y;
        }

        public bool is_switch () {
            return device_type == DeviceType.SWITCH;
        }
    }

    public class Link : Object {
        public string id;                       /* "l" + counters.link */
        public string a;                        /* node ids; the link is undirected */
        public string b;
        public string subnet = "";              /* point-to-point links only */
        public HashTable<string, string> ips;   /* node id -> address; switches never appear */

        public Link (string id, string a, string b) {
            this.id = id;
            this.a = a;
            this.b = b;
            this.ips = new HashTable<string, string> (str_hash, str_equal);
        }

        public bool touches (string node_id) {
            return a == node_id || b == node_id;
        }

        public string other_end (string node_id) {
            return a == node_id ? b : a;
        }

        public string ip_for (string node_id) {
            return ips.lookup (node_id) ?? "";
        }
    }

    /* Ids and names are minted from these, so they must dominate everything
     * already in use — normalize_state () rebuilds them rather than trusting
     * what a file claims. */
    public class Counters : Object {
        private int[] by_type = new int[4];

        public int subnet = 0;
        public int link = 0;
        public int node = 0;

        public int for_type (DeviceType t) {
            return by_type[(int) t];
        }

        public void set_for_type (DeviceType t, int value) {
            by_type[(int) t] = value;
        }

        public int next_for_type (DeviceType t) {
            by_type[(int) t]++;
            return by_type[(int) t];
        }
    }

    public class State : Object {
        public string project_name = DEFAULT_PROJECT_NAME;

        public string router_image = DEFAULT_ROUTER_IMAGE;
        public string host_image = DEFAULT_HOST_IMAGE;      /* used by pc */
        public string server_image = DEFAULT_SERVER_IMAGE;

        public bool isolated = true;                        /* internal: true on every network */

        public Counters counters = new Counters ();
        public GenericArray<Node> nodes = new GenericArray<Node> ();
        public GenericArray<Link> links = new GenericArray<Link> ();

        public Node? node_by_id (string id) {
            for (var i = 0; i < nodes.length; i++) {
                if (nodes[i].id == id) {
                    return nodes[i];
                }
            }
            return null;
        }

        public string image_for (DeviceType t) {
            switch (t) {
                case DeviceType.ROUTER: return router_image;
                case DeviceType.SERVER: return server_image;
                default:                return host_image;
            }
        }

        /* SPEC 3.1. Called for every new switch and point-to-point link, and
         * during import repair. */
        public string alloc_subnet () {
            counters.subnet++;
            return "10.0.%d.0/24".printf (counters.subnet);
        }

        /* A link is point-to-point when neither end is a switch, which is
         * exactly when it carries its own subnet. Derived rather than stored,
         * so it cannot fall out of step with the nodes. */
        public bool is_point_to_point (Link link) {
            var a = node_by_id (link.a);
            var b = node_by_id (link.b);
            return a != null && b != null && !a.is_switch () && !b.is_switch ();
        }

        public GenericArray<string> node_names () {
            var names = new GenericArray<string> ();
            for (var i = 0; i < nodes.length; i++) {
                names.add (nodes[i].name);
            }
            return names;
        }
    }
}
