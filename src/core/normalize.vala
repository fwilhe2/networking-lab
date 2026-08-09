/* normalize.vala
 *
 * The single trust boundary (SPEC 7.1). Hand-edited files, older schema
 * versions and the autosave must never be able to corrupt the editor, so every
 * path in goes through here: import, load and the demo alike.
 *
 * It repairs rather than rejects. The only failure is "not a topology at all".
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Core {

    public State normalize_state (Json.Node? raw) throws TopologyError {
        if (raw == null || raw.get_node_type () != Json.NodeType.OBJECT) {
            throw new TopologyError.NOT_A_TOPOLOGY ("not a topology file");
        }

        var root = raw.get_object ();
        if (!is_array_member (root, "nodes") || !is_array_member (root, "links")) {
            throw new TopologyError.NOT_A_TOPOLOGY ("not a topology file");
        }

        var state = new State ();

        state.project_name = sanitize_name (scalar_member (root, "projectName") ?? DEFAULT_PROJECT_NAME);
        /* Anything but an explicit false leaves the lab sealed off. */
        state.isolated = bool_member (root, "isolated", true);

        if (root.has_member ("images") && root.get_member ("images").get_node_type () == Json.NodeType.OBJECT) {
            var images = root.get_object_member ("images");
            state.router_image = image_or_default (images, "router", DEFAULT_ROUTER_IMAGE);
            state.host_image = image_or_default (images, "host", DEFAULT_HOST_IMAGE);
            state.server_image = image_or_default (images, "server", DEFAULT_SERVER_IMAGE);
        }

        read_nodes (state, root.get_array_member ("nodes"));
        read_links (state, root.get_array_member ("links"));
        rebuild_counters (state);

        /* Last, because allocation depends on the rebuilt subnet counter. */
        for (var i = 0; i < state.nodes.length; i++) {
            var node = state.nodes[i];
            if (node.is_switch () && node.subnet == "") {
                node.subnet = state.alloc_subnet ();
            }
        }
        for (var i = 0; i < state.links.length; i++) {
            var link = state.links[i];
            if (state.is_point_to_point (link) && link.subnet == "") {
                link.subnet = state.alloc_subnet ();
            }
        }

        return state;
    }

    /* Undo snapshots are written by the application itself, so their counters
     * are trustworthy — and have to be honoured, because ids are never reused:
     * a document holding only n3 after n7 was deleted must still mint n8. The
     * rebuilt value is the floor, the recorded one can only raise it. */
    public State restore_snapshot (string text) throws TopologyError, Error {
        var state = normalize_json (text);

        var parser = new Json.Parser ();
        parser.load_from_data (text, -1);
        var root = parser.get_root ().get_object ();
        if (!root.has_member ("counters")
            || root.get_member ("counters").get_node_type () != Json.NodeType.OBJECT) {
            return state;
        }

        var recorded = root.get_object_member ("counters");
        state.counters.node = int.max (state.counters.node, counter_member (recorded, "node"));
        state.counters.link = int.max (state.counters.link, counter_member (recorded, "link"));
        state.counters.subnet = int.max (state.counters.subnet, counter_member (recorded, "subnet"));

        foreach (var type in new DeviceType[] { DeviceType.ROUTER, DeviceType.SWITCH,
                                                DeviceType.PC, DeviceType.SERVER }) {
            state.counters.set_for_type (type, int.max (state.counters.for_type (type),
                                                        counter_member (recorded, type.id ())));
        }

        return state;
    }

    private int counter_member (Json.Object counters, string name) {
        if (!counters.has_member (name)) {
            return 0;
        }
        var member = counters.get_member (name);
        if (member.get_node_type () != Json.NodeType.VALUE || member.get_value_type () != typeof (int64)) {
            return 0;
        }
        return (int) member.get_int ();
    }

    public State normalize_json (string text) throws TopologyError, Error {
        var parser = new Json.Parser ();
        try {
            parser.load_from_data (text, -1);
        } catch (Error e) {
            throw new TopologyError.NOT_A_TOPOLOGY ("not a topology file");
        }
        return normalize_state (parser.get_root ());
    }

    /* ── nodes ──────────────────────────────────────────────────────── */

    private void read_nodes (State state, Json.Array raw_nodes) {
        var used_names = new_name_set ();
        var used_ids = new_name_set ();

        for (var i = 0; i < raw_nodes.get_length (); i++) {
            var element = raw_nodes.get_element (i);
            if (element.get_node_type () != Json.NodeType.OBJECT) {
                continue;
            }
            var raw = element.get_object ();

            var type_name = scalar_member (raw, "type");
            if (type_name == null) {
                continue;
            }

            DeviceType type;
            if (!DeviceType.try_parse (type_name, out type)) {
                continue;                                   /* unknown device type */
            }

            var id = scalar_member (raw, "id");
            if (id == null || used_ids.contains (id)) {
                continue;                                   /* missing or duplicate id */
            }
            used_ids.add (id);

            var name = unique_name (
                sanitize_name (scalar_member (raw, "name") ?? "", type.prefix () + "1"),
                used_names
            );
            used_names.add (name);

            var node = new Node (id, type, name,
                                 number_member (raw, "x", 100),
                                 number_member (raw, "y", 100));

            switch (type) {
                case DeviceType.SWITCH:
                    var subnet = scalar_member (raw, "subnet") ?? "";
                    node.subnet = valid_cidr (subnet) ? subnet : "";
                    break;
                case DeviceType.ROUTER:
                    node.frr_extra = string_member (raw, "frrExtra") ?? "";
                    break;
                case DeviceType.SERVER:
                    node.gw = valid_gateway (raw);
                    node.http_port = digits_only (scalar_member (raw, "httpPort") ?? "80", "80");
                    break;
                case DeviceType.PC:
                    node.gw = valid_gateway (raw);
                    break;
            }

            state.nodes.add (node);
        }
    }

    private string valid_gateway (Json.Object raw) {
        var gw = scalar_member (raw, "gw") ?? "";
        return valid_ip (gw) ? gw : "";
    }

    /* ── links ──────────────────────────────────────────────────────── */

    private void read_links (State state, Json.Array raw_links) {
        var used_ids = new_name_set ();
        var seen_pairs = new_name_set ();

        for (var i = 0; i < raw_links.get_length (); i++) {
            var element = raw_links.get_element (i);
            if (element.get_node_type () != Json.NodeType.OBJECT) {
                continue;
            }
            var raw = element.get_object ();

            var id = scalar_member (raw, "id");
            if (id == null || used_ids.contains (id)) {
                continue;
            }

            var a = state.node_by_id (scalar_member (raw, "a") ?? "");
            var b = state.node_by_id (scalar_member (raw, "b") ?? "");
            if (a == null || b == null || a == b) {
                continue;                                   /* dangling or self link */
            }
            if (a.is_switch () && b.is_switch ()) {
                continue;                                   /* a switch is already one segment */
            }

            var pair = a.id < b.id ? a.id + "|" + b.id : b.id + "|" + a.id;
            if (seen_pairs.contains (pair)) {
                continue;                                   /* duplicate link */
            }
            seen_pairs.add (pair);
            used_ids.add (id);

            var link = new Link (id, a.id, b.id);

            if (raw.has_member ("ips") && raw.get_member ("ips").get_node_type () == Json.NodeType.OBJECT) {
                var ips = raw.get_object_member ("ips");
                foreach (var end in new Node[] { a, b }) {
                    var ip = scalar_member (ips, end.id);
                    if (!end.is_switch () && ip != null && valid_ip (ip)) {
                        link.ips.insert (end.id, ip);
                    }
                }
            }

            if (!a.is_switch () && !b.is_switch ()) {
                var subnet = scalar_member (raw, "subnet") ?? "";
                link.subnet = valid_cidr (subnet) ? subnet : "";
            }

            state.links.add (link);
        }
    }

    /* ── counters ───────────────────────────────────────────────────── */

    /* A file with counters reset to zero but n7 in use would otherwise mint a
     * colliding n1, so what the file claims is discarded entirely. */
    private void rebuild_counters (State state) {
        var counters = new Counters ();

        for (var i = 0; i < state.nodes.length; i++) {
            var node = state.nodes[i];
            counters.node = int.max (counters.node, suffix_number (node.id, "n"));

            var type = node.device_type;
            counters.set_for_type (type, int.max (counters.for_type (type),
                                                  suffix_number (node.name, type.prefix ())));

            counters.subnet = int.max (counters.subnet, subnet_number (node.subnet));
        }

        for (var i = 0; i < state.links.length; i++) {
            var link = state.links[i];
            counters.link = int.max (counters.link, suffix_number (link.id, "l"));
            counters.subnet = int.max (counters.subnet, subnet_number (link.subnet));
        }

        state.counters = counters;
    }

    /* ^<prefix>(\d+)$, or 0 when it does not match. */
    private int suffix_number (string s, string prefix) {
        if (!s.has_prefix (prefix)) {
            return 0;
        }

        var rest = s.substring (prefix.length);
        if (rest.length == 0 || rest.length > 9) {
            return 0;
        }
        for (var i = 0; i < rest.length; i++) {
            if (!rest[i].isdigit ()) {
                return 0;
            }
        }

        return int.parse (rest);
    }

    /* ^10\.0\.(\d+)\.0/24$, or 0 when it does not match. */
    private int subnet_number (string cidr) {
        if (!cidr.has_prefix ("10.0.") || !cidr.has_suffix (".0/24")) {
            return 0;
        }

        var middle = cidr.substring (5, cidr.length - 10);
        if (middle.length == 0 || middle.length > 9) {
            return 0;
        }
        for (var i = 0; i < middle.length; i++) {
            if (!middle[i].isdigit ()) {
                return 0;
            }
        }

        return int.parse (middle);
    }

    /* ── JSON accessors ─────────────────────────────────────────────── */

    private bool is_array_member (Json.Object o, string name) {
        return o.has_member (name) && o.get_member (name).get_node_type () == Json.NodeType.ARRAY;
    }

    private string? string_member (Json.Object o, string name) {
        if (!o.has_member (name)) {
            return null;
        }
        var member = o.get_member (name);
        if (member.get_node_type () != Json.NodeType.VALUE || member.get_value_type () != typeof (string)) {
            return null;
        }
        return member.get_string ();
    }

    /* Strings, numbers and booleans all reach us as text, matching the
     * reference implementation's String () coercion. */
    private string? scalar_member (Json.Object o, string name) {
        if (!o.has_member (name)) {
            return null;
        }

        var member = o.get_member (name);
        if (member.get_node_type () != Json.NodeType.VALUE) {
            return null;
        }

        var value_type = member.get_value_type ();
        if (value_type == typeof (string)) {
            return member.get_string ();
        }
        if (value_type == typeof (int64)) {
            return member.get_int ().to_string ();
        }
        if (value_type == typeof (double)) {
            return "%g".printf (member.get_double ());
        }
        if (value_type == typeof (bool)) {
            return member.get_boolean ().to_string ();
        }
        return null;
    }

    private bool bool_member (Json.Object o, string name, bool fallback) {
        if (!o.has_member (name)) {
            return fallback;
        }
        var member = o.get_member (name);
        if (member.get_node_type () != Json.NodeType.VALUE || member.get_value_type () != typeof (bool)) {
            return fallback;
        }
        return member.get_boolean ();
    }

    /* Accepts numbers and numeric strings; anything else falls back. */
    private double number_member (Json.Object o, string name, double fallback) {
        var text = scalar_member (o, name);
        if (text == null) {
            return fallback;
        }

        double parsed;
        if (!double.try_parse (text, out parsed) || !parsed.is_finite ()) {
            return fallback;
        }
        return parsed;
    }

    private string image_or_default (Json.Object images, string name, string fallback) {
        var value = string_member (images, name);
        if (value == null) {
            return fallback;
        }
        var trimmed = value.strip ();
        return trimmed == "" ? fallback : trimmed;
    }

    private string digits_only (string s, string fallback) {
        var result = new StringBuilder ();
        for (var i = 0; i < s.length; i++) {
            if (s[i].isdigit ()) {
                result.append_c (s[i]);
            }
        }
        return result.str == "" ? fallback : result.str;
    }
}
