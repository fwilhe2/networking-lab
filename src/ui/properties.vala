/* properties.vala
 *
 * The context-sensitive panel of SPEC 8.4, rebuilt on every selection change.
 *
 * Invalid input is rejected and reverted with a message, never silently
 * coerced: a device that quietly ends up on a different address than the one
 * that was typed is worse than one that refuses the address.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

namespace NetworkingLab {

    public class Properties : Gtk.Box {

        /* Caps the natural width of wrapping labels. With hscrollbar NEVER a
         * scrolled window reports its child's full natural width, so an
         * uncapped paragraph would widen the panel and squeeze the canvas. */
        private const int PANEL_WIDTH_CHARS = 34;

        public Document document { get; construct; }

        private Gtk.Box content;

        public Properties (Document document) {
            Object (document: document);
        }

        construct {
            orientation = Gtk.Orientation.VERTICAL;
            width_request = 300;
            /* hexpand propagates up from children unless it is set explicitly,
               and the entries inside set it — without this the panel splits the
               window with the canvas instead of staying a sidebar. */
            hexpand = false;

            content = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            content.margin_top = 12;
            content.margin_bottom = 12;
            content.margin_start = 12;
            content.margin_end = 12;

            var scroller = new Gtk.ScrolledWindow ();
            /* AUTOMATIC rather than NEVER: with NEVER the scrolled window
               adopts its child's whole width as a minimum, and the panel then
               squeezes the canvas out of the window. The labels are capped to
               PANEL_WIDTH_CHARS, so nothing actually scrolls sideways. */
            scroller.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            scroller.propagate_natural_width = false;
            scroller.vexpand = true;
            scroller.child = content;
            append (scroller);

            document.selection_changed.connect (rebuild);
            rebuild ();
        }

        public void rebuild () {
            Gtk.Widget? child = content.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                content.remove (child);
                child = next;
            }

            switch (document.selection_kind) {
                case SelectionKind.LINK:
                    var link = document.selected_link ();
                    if (link == null) {
                        document.clear_selection ();
                        return;
                    }
                    build_link (link);
                    break;

                case SelectionKind.NODE:
                    var node = document.selected_node ();
                    if (node == null) {
                        document.clear_selection ();
                        return;
                    }
                    build_node (node);
                    break;

                default:
                    build_lab_settings ();
                    break;
            }
        }

        /* ── nothing selected: the lab itself ───────────────────────── */

        private void build_lab_settings () {
            var state = document.state;

            content.append (heading (_("Lab settings")));

            content.append (text_field (_("Project name"), state.project_name, (value) => {
                document.begin_edit ();
                document.state.project_name = sanitize_name (value, DEFAULT_PROJECT_NAME);
                document.end_edit ();
                return document.state.project_name;
            }));

            content.append (image_field (_("Router image (FRR)"), state.router_image, (value) => {
                document.state.router_image = value;
            }));
            content.append (image_field (_("PC image"), state.host_image, (value) => {
                document.state.host_image = value;
            }));
            content.append (image_field (_("Server image"), state.server_image, (value) => {
                document.state.server_image = value;
            }));

            /* A CheckButton's own label does not wrap, and its minimum width
               would set the whole panel's. */
            var isolated_label = new Gtk.Label (
                _("Isolated networks (no internet access from devices)"));
            isolated_label.wrap = true;
            isolated_label.xalign = 0;
            isolated_label.max_width_chars = PANEL_WIDTH_CHARS;

            var isolated = new Gtk.CheckButton ();
            isolated.child = isolated_label;
            isolated.active = state.isolated;
            isolated.toggled.connect (() => {
                document.begin_edit ();
                document.state.isolated = isolated.active;
                document.end_edit ();
            });
            content.append (isolated);

            content.append (hint (
                _("Select a device or link to edit it.\n\n" +
                  "A switch becomes a docker bridge network — one L2 segment and one subnet. " +
                  "A direct link between two devices becomes a point-to-point network.\n\n" +
                  "Routers run FRR, so vtysh gives a classic IOS-style CLI.")));
        }

        /* ── a link ─────────────────────────────────────────────────── */

        private void build_link (Link link) {
            var state = document.state;
            var a = state.node_by_id (link.a);
            var b = state.node_by_id (link.b);
            if (a == null || b == null) {
                return;
            }

            content.append (heading (_("Link")));
            content.append (hint ("%s ↔ %s".printf (a.name, b.name)));

            if (state.is_point_to_point (link)) {
                content.append (text_field (_("Subnet (point-to-point network)"), link.subnet, (value) => {
                    return commit_subnet (value, link.subnet, (accepted) => link.subnet = accepted);
                }));
            }

            foreach (var end in new Core.Node[] { a, b }) {
                if (end.is_switch ()) {
                    continue;
                }
                var end_id = end.id;
                content.append (text_field (_("IP of %s").printf (end.name), link.ip_for (end_id), (value) => {
                    return commit_address (value, link.ip_for (end_id), (accepted) => {
                        set_address (link, end_id, accepted);
                    });
                }));
            }

            content.append (delete_button (_("Delete link")));
        }

        /* ── a device ───────────────────────────────────────────────── */

        private void build_node (Core.Node node) {
            content.append (heading (device_title (node.device_type)));

            content.append (text_field (_("Name"), node.name, (value) => {
                return commit_name (node, value);
            }));

            if (node.is_switch ()) {
                build_switch (node);
            } else {
                build_device (node);
            }

            content.append (delete_button (_("Delete")));
        }

        private void build_switch (Core.Node node) {
            content.append (text_field (_("Subnet"), node.subnet, (value) => {
                return commit_subnet (value, node.subnet, (accepted) => node.subnet = accepted);
            }));

            content.append (label_for (_("Connected devices")));

            var nets = networks_of (document.state);
            Network? net = null;
            for (var i = 0; i < nets.length; i++) {
                if (nets[i].key == "sw:" + node.id) {
                    net = nets[i];
                }
            }

            if (net == null || net.attachments.length == 0) {
                content.append (hint (_("Nothing connected yet.")));
                return;
            }

            for (var i = 0; i < net.attachments.length; i++) {
                var attachment = net.attachments[i];
                var device = document.state.node_by_id (attachment.node_id);
                if (device == null) {
                    continue;
                }
                var ip = attachment.link.ip_for (attachment.node_id);
                content.append (read_only_row (device.name, ip == "" ? _("no IP") : ip));
            }
        }

        private void build_device (Core.Node node) {
            content.append (label_for (_("Interfaces")));

            var interfaces = interfaces_of (document.state, node.id);
            if (interfaces.length == 0) {
                content.append (hint (_("Not connected. Use Add Link.")));
            }

            for (var i = 0; i < interfaces.length; i++) {
                var iface = interfaces[i];
                var link = iface.link;
                var node_id = node.id;

                content.append (read_only_row (iface.eth,
                    "→ %s (%s)".printf (iface.net.name, iface.net.subnet)));
                content.append (text_field ("", iface.ip, (value) => {
                    return commit_address (value, link.ip_for (node_id), (accepted) => {
                        set_address (link, node_id, accepted);
                    });
                }));
            }

            var is_host = node.device_type == DeviceType.PC || node.device_type == DeviceType.SERVER;
            if (is_host) {
                content.append (text_field (_("Default gateway"), node.gw, (value) => {
                    return commit_address (value, node.gw, (accepted) => node.gw = accepted);
                }));
            }

            if (node.device_type == DeviceType.SERVER) {
                content.append (text_field (_("HTTP port"), node.http_port, (value) => {
                    document.begin_edit ();
                    node.http_port = digits_or_default (value);
                    document.end_edit ();
                    return node.http_port;
                }));
            }

            if (node.device_type == DeviceType.ROUTER) {
                content.append (label_for (_("Extra FRR config (appended to frr.conf)")));

                var view = new Gtk.TextView ();
                view.monospace = true;
                view.top_margin = view.bottom_margin = view.left_margin = view.right_margin = 6;
                view.wrap_mode = Gtk.WrapMode.NONE;
                view.buffer.text = node.frr_extra;

                /* Commit on focus loss, so one edit is one undo entry. */
                var focus = new Gtk.EventControllerFocus ();
                focus.leave.connect (() => {
                    if (view.buffer.text == node.frr_extra) {
                        return;
                    }
                    document.begin_edit ();
                    node.frr_extra = view.buffer.text;
                    document.end_edit ();
                });
                view.add_controller (focus);

                var frame = new Gtk.Frame (null);
                frame.height_request = 120;
                frame.child = view;
                content.append (frame);
            }

            content.append (label_for (_("Shell")));
            content.append (shell_row (node));
            content.append (lab_actions (node));
        }

        /* ── commit helpers ─────────────────────────────────────────── */

        private delegate void Accept (string value);

        private string commit_name (Core.Node node, string raw) {
            var name = sanitize_name (raw, "");
            if (name == "") {
                document.report (_("Name cannot be empty."));
                return node.name;
            }
            if (name_is_taken (document.state, name, node.id)) {
                document.report (_("Name \"%s\" is already taken.").printf (name));
                return node.name;
            }

            document.begin_edit ();
            node.name = name;
            document.end_edit ();
            /* The shell command and any p2p network names embed the name. */
            rebuild ();
            return name;
        }

        private string commit_subnet (string raw, string current, Accept accept) {
            var value = raw.strip ();
            if (!valid_cidr (value)) {
                document.report (_("Invalid subnet (use CIDR, /8–/29)."));
                return current;
            }

            document.begin_edit ();
            accept (value);
            document.end_edit ();
            return value;
        }

        /* An empty address is allowed: it means "not configured yet", which
         * validation reports as an error at generation time. */
        private string commit_address (string raw, string current, Accept accept) {
            var value = raw.strip ();
            if (value != "" && !valid_ip (value)) {
                document.report (_("Invalid IP address."));
                return current;
            }

            document.begin_edit ();
            accept (value);
            document.end_edit ();
            return value;
        }

        private void set_address (Link link, string node_id, string ip) {
            if (ip == "") {
                link.ips.remove (node_id);
            } else {
                link.ips.insert (node_id, ip);
            }
        }

        private string digits_or_default (string raw) {
            var digits = new StringBuilder ();
            for (var i = 0; i < raw.length; i++) {
                if (raw[i].isdigit ()) {
                    digits.append_c (raw[i]);
                }
            }
            return digits.str == "" ? "80" : digits.str;
        }

        /* ── widgets ────────────────────────────────────────────────── */

        private delegate string Commit (string value);

        private Gtk.Widget heading (string text) {
            var label = new Gtk.Label (text);
            label.xalign = 0;
            label.add_css_class ("title-4");
            return label;
        }

        private Gtk.Widget label_for (string text) {
            var label = new Gtk.Label (text);
            label.xalign = 0;
            label.wrap = true;
            label.max_width_chars = PANEL_WIDTH_CHARS;
            label.add_css_class ("dim-label");
            label.add_css_class ("caption");
            return label;
        }

        private Gtk.Widget hint (string text) {
            var label = new Gtk.Label (text);
            label.xalign = 0;
            label.wrap = true;
            label.max_width_chars = PANEL_WIDTH_CHARS;
            label.add_css_class ("dim-label");
            label.add_css_class ("caption");
            return label;
        }

        /* Commits on Enter and on focus loss, never per keystroke — SPEC 4.1
         * wants one undo entry per edit. The commit returns the value that was
         * actually accepted, which is what the field is reset to. */
        private Gtk.Widget text_field (string caption, string value, owned Commit commit) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            if (caption != "") {
                box.append (label_for (caption));
            }

            var entry = new Gtk.Entry ();
            entry.text = value;
            entry.hexpand = true;
            entry.width_chars = 12;
            entry.max_width_chars = 12;

            /* Guards against re-entering while the field is being reset to the
               accepted value, which would otherwise commit a second time. */
            var committing = false;

            entry.activate.connect (() => {
                if (committing) {
                    return;
                }
                committing = true;
                entry.text = commit (entry.text);
                committing = false;
            });

            var focus = new Gtk.EventControllerFocus ();
            focus.leave.connect (() => {
                if (committing) {
                    return;
                }
                committing = true;
                entry.text = commit (entry.text);
                committing = false;
            });
            entry.add_controller (focus);

            box.append (entry);
            return box;
        }

        private Gtk.Widget image_field (string caption, string value, owned Accept accept) {
            return text_field (caption, value, (raw) => {
                var trimmed = raw.strip ();
                if (trimmed == "") {
                    document.report (_("Image cannot be empty."));
                    return value;
                }
                document.begin_edit ();
                accept (trimmed);
                document.end_edit ();
                return trimmed;
            });
        }

        private Gtk.Widget read_only_row (string name, string detail) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);

            var left = new Gtk.Label (name);
            left.xalign = 0;
            left.add_css_class ("monospace");

            var right = new Gtk.Label (detail);
            right.xalign = 1;
            right.hexpand = true;
            right.ellipsize = Pango.EllipsizeMode.MIDDLE;
            right.add_css_class ("dim-label");
            right.add_css_class ("caption");

            box.append (left);
            box.append (right);
            return box;
        }

        private Gtk.Widget shell_row (Core.Node node) {
            /* The same command the terminal runs — defined once in
               terminal.vala so the two cannot drift apart. */
            var command = terminal_command_line (node);

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

            var label = new Gtk.Label (command);
            label.xalign = 0;
            label.hexpand = true;
            label.selectable = true;
            label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            label.add_css_class ("monospace");
            label.add_css_class ("caption");

            var copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic");
            copy.tooltip_text = _("Copy");
            copy.clicked.connect (() => {
                get_clipboard ().set_text (command);
                document.report (_("Copied."));
            });

            box.append (label);
            box.append (copy);
            return box;
        }

        /* The two things you do with a running device (PLAN 9.4). They stay
           sensitive whatever the lab is doing: the window's actions know
           whether the device is up and say so, and a button that greys out
           between polls is worse than one that answers. */
        private Gtk.Widget lab_actions (Core.Node node) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            box.homogeneous = true;
            box.margin_top = 6;

            /* "Router CLI" rather than "Terminal" for a router: vtysh is not a
               shell, and the difference is the first thing that confuses. */
            var open = new Gtk.Button.with_label (
                node.device_type == DeviceType.ROUTER ? _("Router CLI") : _("Shell"));
            open.tooltip_text = _("Open a session on this device (T)");
            open.clicked.connect (() => activate_action ("win.open-terminal", null));

            var logs = new Gtk.Button.with_label (_("Logs"));
            logs.tooltip_text = _("Follow this device's output");
            logs.clicked.connect (() => activate_action ("win.open-logs", null));

            box.append (open);
            box.append (logs);
            return box;
        }

        private Gtk.Widget delete_button (string caption) {
            var button = new Gtk.Button.with_label (caption);
            button.add_css_class ("destructive-action");
            button.margin_top = 12;
            button.clicked.connect (() => document.delete_selection ());
            return button;
        }

        private string device_title (DeviceType type) {
            switch (type) {
                case DeviceType.ROUTER: return _("Router");
                case DeviceType.SWITCH: return _("Switch");
                case DeviceType.PC:     return _("PC");
                default:                return _("Server");
            }
        }
    }
}
