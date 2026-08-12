/* shortcuts-dialog.vala
 *
 * The `?` help of SPEC 8.6. Hand-rolled rather than a shortcuts window:
 * GtkShortcutsWindow is deprecated as of GTK 4.18 and its replacement
 * AdwShortcutsDialog needs libadwaita 1.8, which is above this project's
 * floor — see PLAN.md.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab {

    public class ShortcutsDialog : Adw.Dialog {

        construct {
            title = _("Keyboard Shortcuts");
            content_width = 520;
            content_height = 640;

            var page = new Adw.PreferencesPage ();

            var modes = group (_("Modes"));
            modes.add (accel_row (_("Select mode"), "v"));
            modes.add (accel_row (_("Add-link mode"), "l"));
            modes.add (text_row (_("Link two devices in select mode"), _("Shift-click both")));
            modes.add (accel_row (_("Cancel link, then leave link mode"), "Escape"));
            page.add (modes);

            var editing = group (_("Editing"));
            editing.add (accel_row (_("Delete the selection"), "Delete"));
            editing.add (accel_row (_("Duplicate the selected device"), "<primary>d"));
            editing.add (accel_row (_("Undo"), "<primary>z"));
            editing.add (accel_row (_("Redo"), "<primary><shift>z"));
            editing.add (text_row (_("Nudge the selected device"), _("Arrows, Shift for a bigger step")));
            editing.add (text_row (_("Ignore the grid while dragging"), _("Hold Alt")));
            page.add (editing);

            var view = group (_("View"));
            view.add (accel_row (_("Zoom in"), "<primary>plus"));
            view.add (accel_row (_("Zoom out"), "<primary>minus"));
            view.add (accel_row (_("Reset zoom"), "<primary>0"));
            view.add (text_row (_("Zoom the canvas"), _("Ctrl and the scroll wheel")));
            page.add (view);

            var lab = group (_("Lab"));
            lab.add (accel_row (_("Open a terminal on the selected device"), "t"));
            lab.add (text_row (_("Start or stop the lab"), _("The Run button")));
            page.add (lab);

            var general = group (_("General"));
            general.add (accel_row (_("Generate the compose file"), "g"));
            general.add (accel_row (_("This list"), "question"));
            general.add (accel_row (_("Preferences"), "<primary>comma"));
            general.add (accel_row (_("Close the window"), "<primary>w"));
            general.add (accel_row (_("Quit"), "<primary>q"));
            page.add (general);

            var toolbar = new Adw.ToolbarView ();
            toolbar.add_top_bar (new Adw.HeaderBar ());
            toolbar.content = page;
            child = toolbar;
        }

        private Adw.PreferencesGroup group (string title) {
            return new Adw.PreferencesGroup () { title = title };
        }

        private Adw.ActionRow accel_row (string title, string accelerator) {
            var row = new Adw.ActionRow () { title = title };
            var keys = new Gtk.ShortcutLabel (accelerator);
            keys.valign = Gtk.Align.CENTER;
            row.add_suffix (keys);
            return row;
        }

        /* For the gestures and key ranges an accelerator cannot express. */
        private Adw.ActionRow text_row (string title, string description) {
            var row = new Adw.ActionRow () { title = title };
            var label = new Gtk.Label (description);
            label.valign = Gtk.Align.CENTER;
            label.add_css_class ("dim-label");
            row.add_suffix (label);
            return row;
        }
    }
}
