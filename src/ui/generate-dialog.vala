/* generate-dialog.vala
 *
 * The generate dialog of SPEC 8.5: the validation list above the compose file
 * itself, with Copy and Save As.
 *
 * The list is advisory only. SPEC 5 is explicit that warnings never block
 * generation — a half-drawn lab is still worth looking at — so the YAML is
 * shown and saveable whatever the diagnostics say.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

namespace NetworkingLab {

    public class GenerateDialog : Adw.Dialog {

        public Document document { get; construct; }

        private string yaml;

        public GenerateDialog (Document document) {
            Object (document: document);
        }

        construct {
            title = _("Compose File");
            content_width = 820;
            content_height = 640;

            var result = compile (document.state);
            yaml = result.yaml;

            var header = new Adw.HeaderBar ();

            var copy_button = new Gtk.Button.with_label (_("Copy"));
            copy_button.tooltip_text = _("Copy the compose file to the clipboard");
            copy_button.clicked.connect (on_copy);
            header.pack_start (copy_button);

            var save_button = new Gtk.Button.with_label (_("Save As…"));
            save_button.add_css_class ("suggested-action");
            save_button.clicked.connect (on_save);
            header.pack_end (save_button);

            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            body.margin_top = 12;
            body.margin_bottom = 12;
            body.margin_start = 12;
            body.margin_end = 12;
            body.append (diagnostics_view (result.warnings));
            body.append (yaml_view ());

            var view = new Adw.ToolbarView ();
            view.add_top_bar (header);
            view.content = body;
            child = view;
        }

        /* Errors red, advisories amber (SPEC 8.5). The list is capped in height
         * so that a badly broken lab still leaves the YAML visible. */
        private Gtk.Widget diagnostics_view (GenericArray<Diagnostic> diagnostics) {
            var list = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            list.margin_top = 6;
            list.margin_bottom = 6;
            list.margin_start = 6;
            list.margin_end = 6;

            if (diagnostics.length == 0) {
                list.append (diagnostic_row ("object-select-symbolic", "success",
                    _("No problems found.")));
            }

            for (var i = 0; i < diagnostics.length; i++) {
                var diagnostic = diagnostics[i];
                list.append (diagnostic_row (
                    diagnostic.is_error ? "dialog-error-symbolic" : "dialog-warning-symbolic",
                    diagnostic.is_error ? "error" : "warning",
                    diagnostic.message));
            }

            var scroller = new Gtk.ScrolledWindow ();
            scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroller.propagate_natural_height = true;
            scroller.max_content_height = 180;
            scroller.child = list;

            var frame = new Gtk.Frame (null);
            frame.child = scroller;
            return frame;
        }

        private Gtk.Widget diagnostic_row (string icon_name, string style, string message) {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);

            var icon = new Gtk.Image.from_icon_name (icon_name);
            icon.valign = Gtk.Align.START;
            icon.add_css_class (style);

            var label = new Gtk.Label (message);
            label.xalign = 0;
            label.wrap = true;
            label.hexpand = true;

            row.append (icon);
            row.append (label);
            return row;
        }

        private Gtk.Widget yaml_view () {
            var text = new Gtk.TextView ();
            text.editable = false;
            text.monospace = true;
            text.wrap_mode = Gtk.WrapMode.NONE;
            text.top_margin = text.bottom_margin = text.left_margin = text.right_margin = 8;
            text.buffer.text = yaml;

            var scroller = new Gtk.ScrolledWindow ();
            scroller.vexpand = true;
            scroller.child = text;

            var frame = new Gtk.Frame (null);
            frame.child = scroller;
            return frame;
        }

        private void on_copy () {
            get_clipboard ().set_text (yaml);
            document.report (_("Compose file copied to clipboard."));
        }

        private void on_save () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Save Compose File");
            dialog.initial_name = "docker-compose.yml";
            dialog.modal = true;

            dialog.save.begin (get_root () as Gtk.Window, null, (source, res) => {
                try {
                    var file = dialog.save.end (res);
                    write_text (file, yaml);
                    document.report (_("Saved %s.").printf (file.get_basename ()));
                } catch (Error e) {
                    /* Dismissing the chooser is not a failure worth reporting. */
                    if (!(e is Gtk.DialogError.DISMISSED)) {
                        document.report (_("Could not save: %s").printf (e.message));
                    }
                }
            });
        }
    }

    /* Shared by the generate dialog and the window's export. */
    internal void write_text (File file, string contents) throws Error {
        file.replace_contents (contents.data, null, false,
                               FileCreateFlags.REPLACE_DESTINATION, null, null);
    }
}
