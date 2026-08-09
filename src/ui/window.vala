/* window.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab {

    [GtkTemplate (ui = "/io/github/fwilhe2/NetworkingLab/window.ui")]
    public class Window : Adw.ApplicationWindow {

        [GtkChild] private unowned Adw.ToastOverlay toast_overlay;

        private GLib.Settings settings;

        public Window (Gtk.Application app) {
            Object (application: app);
        }

        construct {
            settings = new GLib.Settings (Config.APP_ID);

            /* HIG: remember the window geometry between sessions. */
            settings.bind ("window-width", this, "default-width", SettingsBindFlags.DEFAULT);
            settings.bind ("window-height", this, "default-height", SettingsBindFlags.DEFAULT);
            settings.bind ("window-maximized", this, "maximized", SettingsBindFlags.DEFAULT);

        }

        /* The status bar of SPEC 8.8 lands here as toasts; see PLAN.md. */
        public void report (string message) {
            toast_overlay.add_toast (new Adw.Toast (message) { timeout = 3 });
        }
    }
}
