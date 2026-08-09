/* window.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab {

    [GtkTemplate (ui = "/io/github/fwilhe2/NetworkingLab/window.ui")]
    public class Window : Adw.ApplicationWindow {

        [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] private unowned Adw.SwitchRow demo_row;

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

            settings.bind ("demo-setting", demo_row, "active", SettingsBindFlags.DEFAULT);

            var toast_action = new SimpleAction ("show-toast", null);
            toast_action.activate.connect (on_show_toast);
            add_action (toast_action);

            var docs_action = new SimpleAction ("open-docs", null);
            docs_action.activate.connect (on_open_docs);
            add_action (docs_action);
        }

        private void on_show_toast () {
            /* HIG: toasts are transient, dismissible and never block the user. */
            toast_overlay.add_toast (new Adw.Toast (_("Hello from Vala and GTK 4")) {
                timeout = 3
            });
        }

        private void on_open_docs () {
            var launcher = new Gtk.UriLauncher ("https://docs.vala.dev");
            launcher.launch.begin (this, null, (obj, res) => {
                try {
                    launcher.launch.end (res);
                } catch (Error e) {
                    warning ("Could not open the documentation: %s", e.message);
                }
            });
        }
    }
}
