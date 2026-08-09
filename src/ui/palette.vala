/* palette.vala
 *
 * The device palette (SPEC 8.1). Four items, dragged onto the canvas to create
 * a device at the drop point.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

namespace NetworkingLab {

    /* The drag payload. A device type is all the canvas needs to know. */
    public const string PALETTE_MIME = "application/x-netlab-device";

    public class Palette : Gtk.Box {

        construct {
            orientation = Gtk.Orientation.VERTICAL;
            spacing = 6;
            margin_top = 12;
            margin_bottom = 12;
            margin_start = 8;
            margin_end = 8;
            width_request = 132;
            hexpand = false;

            add_item (DeviceType.ROUTER, _("Router"), _("FRR"));
            add_item (DeviceType.SWITCH, _("Switch"), _("L2 segment"));
            add_item (DeviceType.PC, _("PC"), _("alpine"));
            add_item (DeviceType.SERVER, _("Server"), _("HTTP"));

            var hint = new Gtk.Label (_("Drag onto the canvas.\n\nShift-click two devices to connect them."));
            hint.wrap = true;
            hint.max_width_chars = 16;
            hint.xalign = 0;
            hint.margin_top = 12;
            hint.add_css_class ("dim-label");
            hint.add_css_class ("caption");
            append (hint);
        }

        private void add_item (DeviceType type, string title, string subtitle) {
            var label = new Gtk.Label (null);
            label.set_markup ("<b>%s</b>\n<small>%s</small>".printf (
                Markup.escape_text (title), Markup.escape_text (subtitle)));
            label.xalign = 0;
            label.margin_top = 6;
            label.margin_bottom = 6;
            label.margin_start = 8;
            label.margin_end = 8;

            var item = new Gtk.Frame (null);
            item.child = label;
            item.tooltip_text = _("Drag onto the canvas to add a %s").printf (title);

            var source = new Gtk.DragSource ();
            source.actions = Gdk.DragAction.COPY;
            source.prepare.connect ((x, y) => {
                var value = Value (typeof (string));
                value.set_string (type.id ());
                return new Gdk.ContentProvider.for_value (value);
            });
            item.add_controller (source);

            append (item);
        }
    }
}
