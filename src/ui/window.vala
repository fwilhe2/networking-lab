/* window.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

namespace NetworkingLab {

    [GtkTemplate (ui = "/io/github/fwilhe2/NetworkingLab/window.ui")]
    public class Window : Adw.ApplicationWindow {

        [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] private unowned Gtk.Box columns;
        [GtkChild] private unowned Gtk.ScrolledWindow canvas_scroller;
        [GtkChild] private unowned Gtk.Button zoom_reset_button;
        [GtkChild] private unowned Gtk.ToggleButton select_mode_button;
        [GtkChild] private unowned Gtk.ToggleButton link_mode_button;
        [GtkChild] private unowned Gtk.Label status_label;

        private GLib.Settings settings;
        private Document document;
        private Canvas canvas;
        private Properties properties;

        public Window (Gtk.Application app) {
            Object (application: app);
        }

        construct {
            settings = new GLib.Settings (Config.APP_ID);

            /* HIG: remember the window geometry between sessions. */
            settings.bind ("window-width", this, "default-width", SettingsBindFlags.DEFAULT);
            settings.bind ("window-height", this, "default-height", SettingsBindFlags.DEFAULT);
            settings.bind ("window-maximized", this, "maximized", SettingsBindFlags.DEFAULT);

            document = new Document ();
            document.status.connect (report);

            canvas = new Canvas (document);
            canvas.notify["zoom"].connect (() => {
                zoom_reset_button.label = canvas.zoom_label ();
            });
            canvas_scroller.child = canvas;

            properties = new Properties (document);
            columns.prepend (new Palette ());
            columns.append (properties);

            /* The panel shows derived values — interface lists, connected
               devices — so it has to follow the document, not just selection. */
            document.changed.connect (properties.rebuild);

            install_actions ();

            select_mode_button.toggled.connect (() => {
                if (select_mode_button.active) {
                    set_link_mode (false);
                }
            });
            link_mode_button.toggled.connect (() => {
                if (link_mode_button.active) {
                    set_link_mode (true);
                }
            });

            /* Until loading and autosave land in phase 7, the demo is what
               there is to look at. */
            document.replace (demo_state ());
            report (_("Demo topology loaded."));
        }

        private void install_actions () {
            add_simple_action ("zoom-in", () => canvas.zoom_in ());
            add_simple_action ("zoom-out", () => canvas.zoom_out ());
            add_simple_action ("zoom-reset", () => canvas.zoom_reset ());
            add_simple_action ("undo", () => document.undo ());
            add_simple_action ("redo", () => document.redo ());
            add_simple_action ("delete-selection", () => document.delete_selection ());
            add_simple_action ("duplicate", () => document.duplicate_selection ());
            add_simple_action ("select-mode", () => set_link_mode (false));
            add_simple_action ("link-mode", () => set_link_mode (true));
            add_simple_action ("load-demo", () => {
                document.replace (demo_state ());
                report (_("Demo topology loaded."));
            });
            add_simple_action ("clear", () => confirm_clear ());
            add_simple_action ("cancel", () => on_escape ());
        }

        private delegate void ActionCallback ();

        private void add_simple_action (string name, owned ActionCallback callback) {
            var action = new SimpleAction (name, null);
            action.activate.connect (() => callback ());
            add_action (action);
        }

        /* Esc unwinds one step at a time: pending link, then link mode. */
        private void on_escape () {
            if (document.cancel_link ()) {
                return;
            }
            set_link_mode (false);
        }

        private void set_link_mode (bool active) {
            canvas.link_mode = active;
            document.cancel_link ();

            select_mode_button.active = !active;
            link_mode_button.active = active;

            report (active
                ? _("Link mode: click two devices to connect them.")
                : _("Select mode."));
        }

        private void confirm_clear () {
            if (document.state.nodes.length == 0) {
                document.clear ();
                return;
            }

            var dialog = new Adw.AlertDialog (
                _("Clear the topology?"),
                _("Every device and link is removed. The lab settings are kept. This can be undone."));
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("clear", _("Clear"));
            dialog.set_response_appearance ("clear", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response == "clear") {
                    document.clear ();
                }
            });
            dialog.present (this);
        }

        /* The status bar of SPEC 8.8. */
        public void report (string message) {
            status_label.label = message;
        }

        /* Results worth interrupting for also raise a toast, as the HIG
           expects; see PLAN.md. */
        public void report_toast (string message) {
            report (message);
            toast_overlay.add_toast (new Adw.Toast (message) { timeout = 3 });
        }
    }
}
