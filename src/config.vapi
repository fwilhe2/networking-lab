/* config.vapi
 *
 * Exposes the values Meson writes into config.h to Vala.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "config.h")]
namespace Config {
    public const string APP_ID;
    public const string GETTEXT_PACKAGE;
    public const string LOCALEDIR;
    public const string PKGDATADIR;
    public const string VERSION;
}
