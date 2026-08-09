/* serialize.vala
 *
 * State to JSON. The reverse direction is normalize.vala: every path into the
 * application goes through repair, never through a plain parse.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Core {

    public string to_json (State state) {
        var builder = new Json.Builder ();

        builder.begin_object ();

        builder.set_member_name ("projectName");
        builder.add_string_value (state.project_name);

        builder.set_member_name ("images");
        builder.begin_object ();
        builder.set_member_name ("router");
        builder.add_string_value (state.router_image);
        builder.set_member_name ("host");
        builder.add_string_value (state.host_image);
        builder.set_member_name ("server");
        builder.add_string_value (state.server_image);
        builder.end_object ();

        builder.set_member_name ("isolated");
        builder.add_boolean_value (state.isolated);

        builder.set_member_name ("counters");
        builder.begin_object ();
        builder.set_member_name ("router");
        builder.add_int_value (state.counters.for_type (DeviceType.ROUTER));
        builder.set_member_name ("switch");
        builder.add_int_value (state.counters.for_type (DeviceType.SWITCH));
        builder.set_member_name ("pc");
        builder.add_int_value (state.counters.for_type (DeviceType.PC));
        builder.set_member_name ("server");
        builder.add_int_value (state.counters.for_type (DeviceType.SERVER));
        builder.set_member_name ("subnet");
        builder.add_int_value (state.counters.subnet);
        builder.set_member_name ("link");
        builder.add_int_value (state.counters.link);
        builder.set_member_name ("node");
        builder.add_int_value (state.counters.node);
        builder.end_object ();

        builder.set_member_name ("nodes");
        builder.begin_array ();
        for (var i = 0; i < state.nodes.length; i++) {
            write_node (builder, state.nodes[i]);
        }
        builder.end_array ();

        builder.set_member_name ("links");
        builder.begin_array ();
        for (var i = 0; i < state.links.length; i++) {
            write_link (builder, state, state.links[i]);
        }
        builder.end_array ();

        builder.end_object ();

        var generator = new Json.Generator ();
        generator.set_root (builder.get_root ());
        generator.pretty = true;
        generator.indent = 2;
        return generator.to_data (null);
    }

    private void write_node (Json.Builder builder, Node node) {
        builder.begin_object ();

        builder.set_member_name ("id");
        builder.add_string_value (node.id);
        builder.set_member_name ("type");
        builder.add_string_value (node.device_type.id ());
        builder.set_member_name ("name");
        builder.add_string_value (node.name);
        builder.set_member_name ("x");
        builder.add_double_value (node.x);
        builder.set_member_name ("y");
        builder.add_double_value (node.y);

        /* Only the fields the type actually carries (SPEC 2.2). */
        switch (node.device_type) {
            case DeviceType.SWITCH:
                builder.set_member_name ("subnet");
                builder.add_string_value (node.subnet);
                break;
            case DeviceType.ROUTER:
                builder.set_member_name ("frrExtra");
                builder.add_string_value (node.frr_extra);
                break;
            case DeviceType.SERVER:
                builder.set_member_name ("gw");
                builder.add_string_value (node.gw);
                builder.set_member_name ("httpPort");
                builder.add_string_value (node.http_port);
                break;
            case DeviceType.PC:
                builder.set_member_name ("gw");
                builder.add_string_value (node.gw);
                break;
        }

        builder.end_object ();
    }

    private void write_link (Json.Builder builder, State state, Link link) {
        builder.begin_object ();

        builder.set_member_name ("id");
        builder.add_string_value (link.id);
        builder.set_member_name ("a");
        builder.add_string_value (link.a);
        builder.set_member_name ("b");
        builder.add_string_value (link.b);

        /* The subnet belongs to the link only when it is point-to-point;
         * otherwise the switch owns the segment. */
        if (state.is_point_to_point (link)) {
            builder.set_member_name ("subnet");
            builder.add_string_value (link.subnet);
        }

        builder.set_member_name ("ips");
        builder.begin_object ();
        foreach (var end in new string[] { link.a, link.b }) {
            var ip = link.ips.lookup (end);
            if (ip != null) {
                builder.set_member_name (end);
                builder.add_string_value (ip);
            }
        }
        builder.end_object ();

        builder.end_object ();
    }
}
