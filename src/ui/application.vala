/* application.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab {

    public class Application : Adw.Application {

        private GLib.Settings settings;

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

        /* Not construct: Adw.StyleManager is only usable once Adw.Application
         * has run adw_init, which happens in the chained-up startup. */
        public override void startup () {
            base.startup ();

            settings = new GLib.Settings (Config.APP_ID);
            settings.changed["color-scheme"].connect (apply_color_scheme);
            apply_color_scheme ();

            start_watchdog ();
        }

        /* A stall the user can name.
         *
         * A blocked main loop and a busy one look identical from the outside:
         * GTK stops drawing, the window stops answering, and there is nothing
         * afterwards to say how long it lasted or when. This timer should run
         * every WATCHDOG_SECONDS; whatever it is late by is time the main loop
         * spent somewhere it could not be interrupted, and that number in the
         * log is the difference between "it freezes sometimes" and a bug that
         * can be found.
         *
         * One wakeup every two seconds, and it prints nothing at all unless
         * something actually blocked. */
        private const uint WATCHDOG_SECONDS = 2;
        private const int64 WATCHDOG_TOLERANCE_US = 1000000;

        private void start_watchdog () {
            var last = get_monotonic_time ();

            Timeout.add_seconds (WATCHDOG_SECONDS, () => {
                var now = get_monotonic_time ();
                var late = now - last - WATCHDOG_SECONDS * 1000000;
                last = now;

                if (late > WATCHDOG_TOLERANCE_US) {
                    warning ("main loop blocked for %.1fs", late / 1000000.0);
                }
                return Source.CONTINUE;
            });
        }

        /* SPEC 8.7 pins light and ignores the system preference; the HIG does
         * not, so the default follows the system and the override is a
         * preference — see PLAN.md. */
        private void apply_color_scheme () {
            switch (settings.get_string ("color-scheme")) {
                case "light":
                    Adw.StyleManager.get_default ().color_scheme = Adw.ColorScheme.FORCE_LIGHT;
                    break;
                case "dark":
                    Adw.StyleManager.get_default ().color_scheme = Adw.ColorScheme.FORCE_DARK;
                    break;
                default:
                    Adw.StyleManager.get_default ().color_scheme = Adw.ColorScheme.DEFAULT;
                    break;
            }
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
