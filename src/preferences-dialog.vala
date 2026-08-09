/* preferences-dialog.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab {

    [GtkTemplate (ui = "/io/github/fwilhe2/NetworkingLab/preferences-dialog.ui")]
    public class PreferencesDialog : Adw.PreferencesDialog {

        [GtkChild] private unowned Adw.SwitchRow demo_row;

        private GLib.Settings settings;

        construct {
            settings = new GLib.Settings (Config.APP_ID);
            settings.bind ("demo-setting", demo_row, "active", SettingsBindFlags.DEFAULT);
        }
    }
}
