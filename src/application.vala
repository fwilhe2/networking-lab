/* application.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Starter {

    public class Application : Adw.Application {

        public Application () {
            Object (
                application_id: Config.APP_ID,
                flags: ApplicationFlags.DEFAULT_FLAGS,
                resource_base_path: "/com/example/Starter"
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
                application_name = _("Starter"),
                application_icon = Config.APP_ID,
                developer_name = "Your Name",
                version = Config.VERSION,
                developers = { "Your Name <you@example.com>" },
                copyright = "© 2026 Your Name",
                license_type = Gtk.License.GPL_3_0,
                website = "https://example.com",
                issue_url = "https://example.com/issues",
                /* Translators: replace with your name(s), one per line. */
                translator_credits = _("translator-credits"),
            };

            about.present (active_window);
        }
    }
}
