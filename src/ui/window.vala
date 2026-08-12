/* window.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

namespace NetworkingLab {

    [GtkTemplate (ui = "/io/github/fwilhe2/NetworkingLab/window.ui")]
    public class Window : Adw.ApplicationWindow {

        [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] private unowned Adw.OverlaySplitView palette_split;
        [GtkChild] private unowned Adw.OverlaySplitView properties_split;
        [GtkChild] private unowned Gtk.ToggleButton palette_toggle;
        [GtkChild] private unowned Gtk.ToggleButton properties_toggle;
        [GtkChild] private unowned Gtk.ScrolledWindow canvas_scroller;
        [GtkChild] private unowned Gtk.Paned canvas_paned;
        [GtkChild] private unowned Gtk.Button zoom_reset_button;
        [GtkChild] private unowned Gtk.ToggleButton select_mode_button;
        [GtkChild] private unowned Gtk.ToggleButton link_mode_button;
        [GtkChild] private unowned Gtk.Label status_label;
        [GtkChild] private unowned Gtk.Label lab_status_label;
        [GtkChild] private unowned Gtk.Button run_button;
        [GtkChild] private unowned Adw.ButtonContent run_button_content;

        private GLib.Settings settings;
        private Document document;
        private Canvas canvas;
        private Properties properties;
        private LabController lab;
        private TerminalPane terminals;

        public Window (Gtk.Application app) {
            Object (application: app);
        }

        construct {
            settings = new GLib.Settings (Config.APP_ID);

            /* HIG: remember the window geometry between sessions. */
            settings.bind ("window-width", this, "default-width", SettingsBindFlags.DEFAULT);
            settings.bind ("window-height", this, "default-height", SettingsBindFlags.DEFAULT);
            settings.bind ("window-maximized", this, "maximized", SettingsBindFlags.DEFAULT);

            document = new Document ();
            document.status.connect (report);

            canvas = new Canvas (document);
            canvas.device_activated.connect (open_terminal_for);
            canvas.notify["zoom"].connect (() => {
                zoom_reset_button.label = canvas.zoom_label ();
            });
            canvas_scroller.child = canvas;

            /* The lab is a view of the document, not part of it: it is never
               undone, never autosaved, and the designer works without it. */
            lab = new LabController (document);
            canvas.lab = lab;
            lab.changed.connect (on_lab_changed);
            lab.failed.connect (show_failure);

            terminals = new TerminalPane ();
            terminals.emptied.connect (hide_terminals);

            properties = new Properties (document);
            palette_split.sidebar = new Palette ();
            properties_split.sidebar = properties;
            bind_sidebar_toggles ();

            /* The panel shows derived values — interface lists, connected
               devices — so it has to follow the document, not just selection. */
            document.changed.connect (properties.rebuild);

            install_actions ();

            select_mode_button.toggled.connect (() => {
                if (select_mode_button.active) {
                    set_link_mode (false);
                }
            });
            link_mode_button.toggled.connect (() => {
                if (link_mode_button.active) {
                    set_link_mode (true);
                }
            });

            on_lab_changed ();

            /* The last session, if there was one. A first run starts empty —
               the demo is one menu item away (SPEC 7). */
            if (document.load_autosave ()) {
                report (_("Restored the last session."));
            } else {
                report (_("Drag a device from the palette to start."));
            }

            /* The autosave is written on a timeout, so the last edit of the
               session would otherwise be lost on close. */
            close_request.connect (() => {
                document.flush_autosave ();
                return false;
            });
        }

        /* A collapsed sidebar is reachable only through its toggle, so the
           toggles appear exactly when the breakpoint takes the sidebar away. */
        private void bind_sidebar_toggles () {
            palette_split.bind_property ("collapsed", palette_toggle, "visible",
                                         BindingFlags.SYNC_CREATE);
            palette_split.bind_property ("show-sidebar", palette_toggle, "active",
                                         BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
            properties_split.bind_property ("collapsed", properties_toggle, "visible",
                                            BindingFlags.SYNC_CREATE);
            properties_split.bind_property ("show-sidebar", properties_toggle, "active",
                                            BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        }

        private void install_actions () {
            add_simple_action ("zoom-in", () => canvas.zoom_in ());
            add_simple_action ("zoom-out", () => canvas.zoom_out ());
            add_simple_action ("zoom-reset", () => canvas.zoom_reset ());
            add_simple_action ("undo", () => document.undo ());
            add_simple_action ("redo", () => document.redo ());
            add_simple_action ("delete-selection", () => document.delete_selection ());
            add_simple_action ("duplicate", () => document.duplicate_selection ());
            add_simple_action ("select-mode", () => set_link_mode (false));
            add_simple_action ("link-mode", () => set_link_mode (true));
            add_simple_action ("load-demo", () => confirm_load_demo ());
            add_simple_action ("clear", () => confirm_clear ());
            add_simple_action ("cancel", () => on_escape ());
            add_simple_action ("generate", () => new GenerateDialog (document).present (this));
            add_simple_action ("shortcuts", () => new ShortcutsDialog ().present (this));
            add_simple_action ("import", () => on_import ());
            add_simple_action ("export", () => on_export ());
            add_simple_action ("run-lab", () => on_run_lab ());
            add_simple_action ("open-terminal", () => on_open_terminal ());
            add_simple_action ("open-logs", () => on_open_logs ());
        }

        private delegate void ActionCallback ();

        private void add_simple_action (string name, owned ActionCallback callback) {
            var action = new SimpleAction (name, null);
            action.activate.connect (() => callback ());
            add_action (action);
        }

        /* Esc unwinds one step at a time: pending link, then link mode. */
        private void on_escape () {
            if (document.cancel_link ()) {
                return;
            }
            set_link_mode (false);
        }

        private void set_link_mode (bool active) {
            canvas.link_mode = active;
            document.cancel_link ();

            select_mode_button.active = !active;
            link_mode_button.active = active;

            report (active
                ? _("Link mode: click two devices to connect them.")
                : _("Select mode."));
        }

        /* ── import / export (SPEC 7) ───────────────────────────────── */

        private void on_import () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Import Topology");
            dialog.modal = true;
            dialog.filters = topology_filters ();

            dialog.open.begin (this, null, (source, res) => {
                File file;
                try {
                    file = dialog.open.end (res);
                } catch (Error e) {
                    /* Dismissing the chooser is not a failure worth reporting. */
                    if (!(e is Gtk.DialogError.DISMISSED)) {
                        report_toast (_("Import failed: %s").printf (e.message));
                    }
                    return;
                }

                try {
                    /* load_bytes, not load_contents: valac's binding for the
                       latter hands g_file_load_contents a guint8** where it
                       wants char**, which would add a fifth compiler warning
                       to the baseline documented in CLAUDE.md. The length is
                       passed explicitly because a GBytes is not guaranteed to
                       be NUL-terminated. */
                    var data = file.load_bytes (null, null).get_data ();
                    var text = data == null ? "" : ((string) data).substring (0, data.length);
                    var dropped = document.import_json (text);
                    var name = file.get_basename ();
                    report_toast (dropped > 0
                        ? ngettext ("Imported %s — skipped %d invalid entry.",
                                    "Imported %s — skipped %d invalid entries.",
                                    dropped).printf (name, dropped)
                        : _("Imported %s.").printf (name));
                } catch (Error e) {
                    report_toast (_("Import failed: %s").printf (e.message));
                }
            });
        }

        private void on_export () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Export Topology");
            dialog.modal = true;
            dialog.initial_name = "%s.netlab.json".printf (document.state.project_name);
            dialog.filters = topology_filters ();

            dialog.save.begin (this, null, (source, res) => {
                try {
                    var file = dialog.save.end (res);
                    write_text (file, to_json (document.state));
                    report_toast (_("Exported %s.").printf (file.get_basename ()));
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) {
                        report_toast (_("Export failed: %s").printf (e.message));
                    }
                }
            });
        }

        private ListStore topology_filters () {
            var topologies = new Gtk.FileFilter ();
            topologies.name = _("Topologies");
            topologies.add_suffix ("json");

            var filters = new ListStore (typeof (Gtk.FileFilter));
            filters.append (topologies);
            return filters;
        }

        /* ── running the lab (PLAN 9.2) ─────────────────────────────── */

        private void on_run_lab () {
            if (!lab.can_run) {
                return;
            }

            if (lab.state == Lab.LabState.UP) {
                confirm_stop_lab ();
                return;
            }

            var result = compile (document.state);

            var errors = new GenericArray<string> ();
            for (var i = 0; i < result.warnings.length; i++) {
                if (result.warnings[i].is_error) {
                    errors.add (result.warnings[i].message);
                }
            }

            if (errors.length == 0) {
                start_lab (result.yaml);
                return;
            }

            /* SPEC 5 keeps warnings from blocking *generation*, and that stays
               true — the generate dialog still shows the file whatever the
               diagnostics say. Booting is the case where it is worth asking: a
               duplicate address or an unreachable gateway costs a minute of
               pulling and then fails in a way that reads like a docker problem
               (PLAN 9.2). */
            var dialog = new Adw.AlertDialog (
                _("Start the lab despite errors?"),
                ngettext ("This problem will probably keep the lab from working:",
                          "These problems will probably keep the lab from working:",
                          errors.length));
            dialog.set_extra_child (message_list (errors));
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("start", _("Start Anyway"));
            dialog.set_response_appearance ("start", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response == "start") {
                    start_lab (result.yaml);
                }
            });
            dialog.present (this);
        }

        private void start_lab (string yaml) {
            report (_("Starting the lab — the first run pulls images."));
            lab.start.begin (yaml, (source, res) => {
                lab.start.end (res);
                if (lab.state == Lab.LabState.UP) {
                    report_toast (_("Lab started."));
                }
            });
        }

        /* `down` destroys containers and networks, and with them anything
           configured through vtysh and not saved. Worth one question. */
        private void confirm_stop_lab () {
            var dialog = new Adw.AlertDialog (
                _("Stop the lab?"),
                _("The containers and their networks are removed. Anything configured inside a device and not saved is lost."));
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("stop", _("Stop"));
            dialog.set_response_appearance ("stop", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response != "stop") {
                    return;
                }
                report (_("Stopping the lab…"));
                lab.stop.begin ((source, res) => {
                    lab.stop.end (res);
                    if (lab.state == Lab.LabState.DOWN) {
                        report_toast (_("Lab stopped."));
                    }
                });
            });
            dialog.present (this);
        }

        /* ── terminals (PLAN 9.3) ───────────────────────────────────── */

        private void on_open_terminal () {
            var node = document.selected_node ();
            if (node == null) {
                report (_("Select a device first."));
                return;
            }
            open_terminal_for ((!) node);
        }

        /* Also the canvas's double-click, which has a device in hand and no
           selection to consult. */
        private void open_terminal_for (Core.Node node) {
            if (!reachable (node)) {
                return;
            }

            show_terminals ();
            terminals.open (node);
            report (_("Terminal on %s.").printf (node.name));
        }

        private void on_open_logs () {
            var node = document.selected_node ();
            if (node == null) {
                report (_("Select a device first."));
                return;
            }

            if (!reachable ((!) node)) {
                return;
            }

            var command = lab.logs_command (((!) node).name);
            if (command == null) {
                report (_("The lab is not running."));
                return;
            }

            show_terminals ();
            terminals.open_logs ((!) node, (!) command);
            report (_("Logs for %s.").printf (((!) node).name));
        }

        /* The two refusals every device action shares: a switch is not a
           container at all, and a device that is not up has nothing to attach
           to. Saying so beats a tab that dies the moment it opens. */
        private bool reachable (Core.Node node) {
            if (!node.device_type.is_service ()) {
                report (_("A switch is a docker network, not a container — there is nothing to log into."));
                return false;
            }

            if (lab.mark_for (node.name) != DeviceMark.RUNNING) {
                report_toast (_("%s is not running — start the lab first.").printf (node.name));
                return false;
            }

            return true;
        }

        /* Attached on first use rather than kept empty: a Paned with a
           zero-height end child still shows its handle. */
        private void show_terminals () {
            if (canvas_paned.end_child == terminals) {
                return;
            }

            canvas_paned.end_child = terminals;

            /* Two thirds to the drawing, which is what is being worked on. */
            var height = canvas_paned.get_height ();
            if (height > 0) {
                canvas_paned.position = height * 2 / 3;
            }
        }

        private void hide_terminals () {
            canvas_paned.end_child = null;
            canvas.grab_focus ();
        }

        private void on_lab_changed () {
            lab_status_label.label = lab.summary ();
            canvas.queue_draw ();

            var up = lab.state == Lab.LabState.UP;

            run_button.sensitive = lab.can_run;
            run_button.tooltip_text = run_tooltip ();
            run_button_content.icon_name = up
                ? "media-playback-stop-symbolic"
                : "media-playback-start-symbolic";

            switch (lab.state) {
                case Lab.LabState.STARTING:
                    run_button_content.label = _("Starting…");
                    break;
                case Lab.LabState.STOPPING:
                    run_button_content.label = _("Stopping…");
                    break;
                case Lab.LabState.UP:
                    run_button_content.label = _("Stop");
                    break;
                default:
                    run_button_content.label = _("Run");
                    break;
            }

            if (up) {
                run_button.add_css_class ("destructive-action");
            } else {
                run_button.remove_css_class ("destructive-action");
            }
        }

        private string run_tooltip () {
            switch (lab.availability) {
                case LabController.Availability.CHECKING:
                    return _("Checking whether docker is available…");
                case LabController.Availability.UNAVAILABLE:
                    return lab.unavailable_reason;
                default:
                    return lab.state == Lab.LabState.UP
                        ? _("Stop the lab and remove its containers")
                        : _("Start the lab with docker compose");
            }
        }

        /* Docker's own words, not a summary of them: `up` fails for reasons
           this application cannot anticipate, and the output is the fix. */
        private void show_failure (string title, string detail) {
            report (title);

            var dialog = new Adw.AlertDialog (title, null);
            dialog.set_extra_child (output_view (detail));
            dialog.add_response ("close", _("Close"));
            dialog.default_response = "close";
            dialog.close_response = "close";
            dialog.present (this);
        }

        private Gtk.Widget output_view (string text) {
            var view = new Gtk.TextView ();
            view.editable = false;
            view.monospace = true;
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            view.top_margin = view.bottom_margin = view.left_margin = view.right_margin = 8;
            view.buffer.text = text;

            var scroller = new Gtk.ScrolledWindow ();
            scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroller.propagate_natural_height = true;
            scroller.max_content_height = 260;
            scroller.width_request = 380;
            scroller.child = view;

            var frame = new Gtk.Frame (null);
            frame.child = scroller;
            return frame;
        }

        private Gtk.Widget message_list (GenericArray<string> messages) {
            var list = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);

            for (var i = 0; i < messages.length; i++) {
                var label = new Gtk.Label ("• " + messages[i]);
                label.xalign = 0;
                label.wrap = true;
                label.add_css_class ("error");
                list.append (label);
            }

            var scroller = new Gtk.ScrolledWindow ();
            scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroller.propagate_natural_height = true;
            scroller.max_content_height = 200;
            scroller.width_request = 380;
            scroller.child = list;
            return scroller;
        }

        /* ── confirmations ──────────────────────────────────────────── */

        private void confirm_load_demo () {
            if (document.state.nodes.length == 0) {
                load_demo ();
                return;
            }

            var dialog = new Adw.AlertDialog (
                _("Replace the topology with the demo?"),
                _("The current devices and links are replaced. This can be undone."));
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("replace", _("Replace"));
            dialog.set_response_appearance ("replace", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response == "replace") {
                    load_demo ();
                }
            });
            dialog.present (this);
        }

        private void load_demo () {
            document.replace (demo_state ());
            report (_("Demo topology loaded."));
        }

        private void confirm_clear () {
            if (document.state.nodes.length == 0) {
                document.clear ();
                return;
            }

            var dialog = new Adw.AlertDialog (
                _("Clear the topology?"),
                _("Every device and link is removed. The lab settings are kept. This can be undone."));
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("clear", _("Clear"));
            dialog.set_response_appearance ("clear", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response == "clear") {
                    document.clear ();
                }
            });
            dialog.present (this);
        }

        /* The status bar of SPEC 8.8. */
        public void report (string message) {
            status_label.label = message;
        }

        /* Results worth interrupting for also raise a toast, as the HIG
           expects; see PLAN.md. */
        public void report_toast (string message) {
            report (message);
            toast_overlay.add_toast (new Adw.Toast (message) { timeout = 3 });
        }
    }
}
