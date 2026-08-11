/* preferences-dialog.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab {

    [GtkTemplate (ui = "/io/github/fwilhe2/NetworkingLab/preferences-dialog.ui")]
    public class PreferencesDialog : Adw.PreferencesDialog {

        /* The order of the AdwComboRow items, as setting values. */
        private const string[] COLOR_SCHEMES = { "default", "light", "dark" };

        [GtkChild] private unowned Adw.ComboRow color_scheme_row;

        private GLib.Settings settings;

        construct {
            settings = new GLib.Settings (Config.APP_ID);

            /* No settings.bind: the setting is a string and the row is an
               index, and a hand-edited value has to land somewhere sane. */
            color_scheme_row.selected = index_of (settings.get_string ("color-scheme"));
            color_scheme_row.notify["selected"].connect (() => {
                settings.set_string ("color-scheme", COLOR_SCHEMES[color_scheme_row.selected]);
            });
        }

        private uint index_of (string scheme) {
            for (var i = 0; i < COLOR_SCHEMES.length; i++) {
                if (COLOR_SCHEMES[i] == scheme) {
                    return i;
                }
            }
            return 0;
        }
    }
}
