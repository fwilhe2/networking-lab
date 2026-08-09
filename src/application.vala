/* application.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab {

    public class Application : Adw.Application {

        public Application () {
            Object (
                application_id: Config.APP_ID,
                flags: ApplicationFlags.DEFAULT_FLAGS,
                resource_base_path: "/io/github/fwilhe2/NetworkingLab"
            );
        }

        construct {
            var preferences_action = new SimpleAction ("preferences", null);
            preferences_action.activate.connect (on_preferences);
            add_action (preferences_action);

            var about_action = new SimpleAction ("about", null);
            about_action.activate.connect (on_about);
            add_action (about_action);

            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (on_quit);
            add_action (quit_action);

            /* HIG: the standard app-wide shortcuts. */
            set_accels_for_action ("app.preferences", { "<primary>comma" });
            set_accels_for_action ("app.quit", { "<primary>q" });
            set_accels_for_action ("window.close", { "<primary>w" });
        }

        public override void activate () {
            /* Re-present the existing window instead of opening a second one. */
            var window = active_window as Window;
            if (window == null) {
                window = new Window (this);
            }
            window.present ();
        }

        private void on_quit () {
            quit ();
        }

        private void on_preferences () {
            var dialog = new PreferencesDialog ();
            dialog.present (active_window);
        }

        private void on_about () {
            var about = new Adw.AboutDialog () {
                application_name = _("Networking Lab"),
                application_icon = Config.APP_ID,
                developer_name = "Florian Wilhelm",
                version = Config.VERSION,
                developers = { "Florian Wilhelm <fwilhelm.wgt+github@gmail.com>" },
                copyright = "© 2026 Florian Wilhelm",
                license_type = Gtk.License.GPL_3_0,
                website = "https://github.com/fwilhe2/networking-lab",
                issue_url = "https://github.com/fwilhe2/networking-lab/issues",
                /* Translators: replace with your name(s), one per line. */
                translator_credits = _("translator-credits"),
            };

            about.present (active_window);
        }
    }
}
