/* terminal.vala
 *
 * A terminal onto a device's container, and the tabbed pane that holds them
 * (PLAN 9.3). The command is the one the properties panel already shows —
 * `docker exec -it <name> vtysh` for a router, `… sh` for a host — which is the
 * point of the feature: nothing new to learn, just somewhere to run it.
 *
 * VTE is an **optional** build dependency. The GNOME 50 runtime does not carry
 * vte-2.91-gtk4, and the Flatpak has no route to the docker socket anyway
 * (PLAN 9.5), so a build without it is a designer that says so rather than a
 * build failure. Everything version-dependent is behind HAVE_VTE in this one
 * file; the rest of src/ui/ sees the same two classes either way.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

namespace NetworkingLab {

    /* Defined once here and used by the properties panel too, so the command a
     * user is told to run and the one the terminal runs cannot drift apart. */
    public string[] terminal_command (Core.Node node) {
        return node.device_type == DeviceType.ROUTER
            ? new string[] { "docker", "exec", "-it", node.name, "vtysh" }
            : new string[] { "docker", "exec", "-it", node.name, "sh" };
    }

    public string terminal_command_line (Core.Node node) {
        return string.joinv (" ", terminal_command (node));
    }

    /* Anything worth watching in a terminal, not just a shell: streamed logs
     * are the same widget with a different command, which is what makes them
     * scrollable, colourful and interruptible with Ctrl+C for free. */
    public class DeviceTerminal : Gtk.Box {

        public string device_name { get; construct; }

        /* The session ended — the command exited, or the container is gone. */
        public signal void finished ();

        private string[] command;

        public DeviceTerminal (string device_name, string[] command) {
            Object (device_name: device_name, orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.command = command;
            start ();
        }

#if HAVE_VTE
        private Vte.Terminal? terminal = null;

        private void start () {
            var vte = new Vte.Terminal ();
            vte.vexpand = true;
            vte.hexpand = true;
            vte.set_scrollback_lines (5000);
            vte.set_scroll_on_output (false);
            vte.set_scroll_on_keystroke (true);
            vte.set_mouse_autohide (true);
            terminal = vte;

            apply_theme ();
            var style = Adw.StyleManager.get_default ();
            style.notify["dark"].connect (apply_theme);

            /* A container that has gone takes its session with it. Saying so
             * beats a black rectangle that ignores the keyboard. */
            vte.child_exited.connect ((status) => {
                report (exit_message (status));
                finished ();
            });

            var scroller = new Gtk.ScrolledWindow ();
            scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroller.child = vte;
            append (scroller);

            vte.spawn_async (Vte.PtyFlags.DEFAULT, null, command, null,
                             GLib.SpawnFlags.SEARCH_PATH, null, -1, null,
                             (source, pid, error) => {
                if (error != null) {
                    report (_("Could not run %s: %s")
                                .printf (command[0], ((!) error).message));
                    finished ();
                }
            });
        }

        /* VTE does not follow the platform colours on its own, and a light
         * terminal in a dark window is the first thing anyone notices. */
        private void apply_theme () {
            if (terminal == null) {
                return;
            }

            var dark = Adw.StyleManager.get_default ().dark;
            var foreground = Gdk.RGBA ();
            var background = Gdk.RGBA ();
            foreground.parse (dark ? "#f6f5f4" : "#1b1e23");
            background.parse (dark ? "#1d2126" : "#ffffff");
            ((!) terminal).set_colors (foreground, background, null);
        }

        public void grab_terminal_focus () {
            if (terminal != null) {
                ((!) terminal).grab_focus ();
            }
        }

        /* VTE reports the raw wait status, not an exit code: stopping the lab
         * under a live session produces 35072, which is 137 << 8 and means
         * nothing to anyone. Decode it. */
        private string exit_message (int status) {
            if (Process.if_exited (status)) {
                var code = Process.exit_status (status);
                return code == 0
                    ? _("The session ended.")
                    : _("The session ended with status %d — the container may be gone.")
                          .printf (code);
            }

            if (Process.if_signaled (status)) {
                return _("The session was killed by signal %d — the container is gone.")
                           .printf (Process.term_sig (status));
            }

            return _("The session ended.");
        }

        /* One line under the terminal rather than a dialog: the session is
         * over, but its scrollback is still worth reading. */
        private void report (string message) {
            var banner = new Adw.Banner (message);
            banner.revealed = true;
            append (banner);
        }
#else
        private void start () {
            var page = new Adw.StatusPage ();
            page.icon_name = "utilities-terminal-symbolic";
            page.title = _("No terminal in this build");
            page.description =
                _("This build was compiled without VTE, so it cannot open a session. Run the command yourself:\n\n%s")
                    .printf (string.joinv (" ", command));
            page.vexpand = true;
            append (page);
        }

        public void grab_terminal_focus () {
        }
#endif
    }

    /* One tab per device, kept across selection changes — clicking elsewhere on
     * the canvas must not throw a session away. */
    public class TerminalPane : Gtk.Box {

        /* The last tab closed; the window hides the pane again. */
        public signal void emptied ();

        private Adw.TabView tabs;
        private HashTable<string, Adw.TabPage> pages;

        public TerminalPane () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        }

        construct {
            pages = new HashTable<string, Adw.TabPage> (str_hash, str_equal);

            tabs = new Adw.TabView ();
            tabs.vexpand = true;

            var bar = new Adw.TabBar ();
            bar.view = tabs;
            bar.autohide = false;

            append (bar);
            append (tabs);

            tabs.close_page.connect ((page) => {
                forget (page);
                tabs.close_page_finish (page, true);
                if (tabs.n_pages == 0) {
                    emptied ();
                }
                return true;
            });
        }

        public void open (Core.Node node) {
            open_tab (node.name, node.name, terminal_command (node));
        }

        /* Logs get their own tab rather than replacing the session: watching a
         * device and typing at it are two different things, often at once. */
        public void open_logs (Core.Node node, string[] command) {
            open_tab ("logs:" + node.name,
                      _("%s logs").printf (node.name),
                      command);
        }

        private void open_tab (string key, string title, string[] command) {
            var existing = pages.lookup (key);
            if (existing != null) {
                tabs.selected_page = existing;
                focus_selected ();
                return;
            }

            var terminal = new DeviceTerminal (title, command);
            var page = tabs.append (terminal);
            page.title = title;
            page.tooltip = string.joinv (" ", command);
            pages.insert (key, page);

            tabs.selected_page = page;
            focus_selected ();
        }

        public bool is_empty () {
            return tabs.n_pages == 0;
        }

        /* The tab key is not the title — a logs tab is keyed "logs:r1" but
         * titled "r1 logs" — so the page has to be looked up by identity. */
        private void forget (Adw.TabPage page) {
            /* get_keys () rather than foreach (): valac's GHFunc cast for a
               closure adds a compiler warning to the baseline, and this list is
               four entries long on a busy day. */
            foreach (var key in pages.get_keys ()) {
                if (pages.lookup (key) == page) {
                    pages.remove (key);
                    return;
                }
            }
        }

        private void focus_selected () {
            var page = tabs.selected_page;
            if (page == null) {
                return;
            }
            var terminal = ((!) page).child as DeviceTerminal;
            if (terminal != null) {
                ((!) terminal).grab_terminal_focus ();
            }
        }
    }
}
