/* window.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

namespace NetworkingLab {

    [GtkTemplate (ui = "/io/github/fwilhe2/NetworkingLab/window.ui")]
    public class Window : Adw.ApplicationWindow {

        [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] private unowned Gtk.ScrolledWindow canvas_scroller;
        [GtkChild] private unowned Gtk.Button zoom_reset_button;
        [GtkChild] private unowned Gtk.Label status_label;

        private GLib.Settings settings;
        private Canvas canvas;

        public Window (Gtk.Application app) {
            Object (application: app);
        }

        construct {
            settings = new GLib.Settings (Config.APP_ID);

            /* HIG: remember the window geometry between sessions. */
            settings.bind ("window-width", this, "default-width", SettingsBindFlags.DEFAULT);
            settings.bind ("window-height", this, "default-height", SettingsBindFlags.DEFAULT);
            settings.bind ("window-maximized", this, "maximized", SettingsBindFlags.DEFAULT);

            canvas = new Canvas ();
            canvas.notify["zoom"].connect (() => {
                zoom_reset_button.label = canvas.zoom_label ();
            });
            canvas_scroller.child = canvas;

            var zoom_in = new SimpleAction ("zoom-in", null);
            zoom_in.activate.connect (() => canvas.zoom_in ());
            add_action (zoom_in);

            var zoom_out = new SimpleAction ("zoom-out", null);
            zoom_out.activate.connect (() => canvas.zoom_out ());
            add_action (zoom_out);

            var zoom_reset = new SimpleAction ("zoom-reset", null);
            zoom_reset.activate.connect (() => canvas.zoom_reset ());
            add_action (zoom_reset);

            /* Until loading and autosave land in phase 7, the demo is what
               there is to look at. */
            canvas.state = demo_state ();
            report (_("Demo topology loaded."));
        }

        /* The status bar of SPEC 8.8. Transient results also raise a toast, as
           the HIG expects; see PLAN.md. */
        public void report (string message) {
            status_label.label = message;
        }

        public void report_toast (string message) {
            report (message);
            toast_overlay.add_toast (new Adw.Toast (message) { timeout = 3 });
        }
    }
}
