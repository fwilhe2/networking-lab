/* lab-controller.vala
 *
 * The UI's view of a running lab: the engine probe, one Lab.Session, and the
 * poll that keeps the canvas honest about what is actually up.
 *
 * This is the only place in src/ui/ that knows a container engine exists.
 * Everything below it is in src/lab/ and GTK-free; everything above it asks two
 * questions — "can I run?" and "is this device up?" — and gets a widget-shaped
 * answer.
 *
 * The engine is a run-time dependency. Its absence is an ordinary outcome that
 * leaves the designer fully usable and the run control insensitive with a
 * reason attached, never a failure at startup (PLAN 9.2, 9.5).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

namespace NetworkingLab {

    public enum DeviceMark {
        NONE,       /* no container: the lab is down, or this device is new */
        RUNNING,
        STOPPED,    /* a container exists but is not running — the useful failure */
    }

    public class LabController : Object {

        public enum Availability {
            CHECKING,
            READY,
            UNAVAILABLE,
        }

        /* Long enough not to spawn a `compose ps` storm, short enough
         * that a container coming up appears on the canvas while the user is
         * still looking at it. */
        private const uint POLL_SECONDS = 2;

        public Document document { get; construct; }

        public Availability availability { get; private set; default = Availability.CHECKING; }
        public string unavailable_reason { get; private set; default = ""; }

        /* State, container list, or availability moved. */
        public signal void changed ();
        /* Something the user must see rather than a status line: the output of
         * a failed `up` is the difference between "it broke" and a fix. */
        public signal void failed (string title, string detail);

        private Lab.Engine? engine = null;
        private Lab.Session? session = null;
        private uint poll_source = 0;
        private bool polling = false;

        public LabController (Document document) {
            Object (document: document);
        }

        construct {
            probe.begin ();
        }

        public Lab.LabState state {
            get { return session == null ? Lab.LabState.DOWN : session.state; }
        }

        public bool can_run {
            get { return availability == Availability.READY && !state.busy (); }
        }

        /* ── availability ───────────────────────────────────────────── */

        private async void probe () {
            /* A hole from the sandbox to the engine socket is a hole to root on
             * the host, so the Flatpak deliberately does not have one. Saying so
             * is better than a run control that fails on every press (PLAN 9.5). */
            if (FileUtils.test ("/.flatpak-info", FileTest.EXISTS)) {
                availability = Availability.UNAVAILABLE;
                unavailable_reason =
                    _("The Flatpak sandbox cannot reach the container engine. Generate the compose file and run it yourself.");
                changed ();
                return;
            }

            try {
                engine = yield Lab.Engine.probe ();
            } catch (Error e) {
                availability = Availability.UNAVAILABLE;
                unavailable_reason = e.message;
                changed ();
                return;
            }

            availability = Availability.READY;
            changed ();

            /* A lab left running by an earlier session is adopted rather than
             * ignored: the compose project name is the whole address. */
            yield poll ();
        }

        /* ── lifecycle ──────────────────────────────────────────────── */

        public async void start (string yaml) {
            var lab = require_session ();
            if (lab == null) {
                return;
            }

            try {
                yield lab.start (yaml);
            } catch (Error e) {
                failed (_("The lab could not be started"), e.message);
                changed ();
                return;
            }

            watch ();
            changed ();
        }

        public async void stop () {
            var lab = require_session ();
            if (lab == null) {
                return;
            }

            try {
                yield lab.stop ();
            } catch (Error e) {
                failed (_("The lab could not be stopped"), e.message);
                changed ();
                return;
            }

            changed ();
        }

        /* ── what the canvas and the status bar ask ─────────────────── */

        public DeviceMark mark_for (string device_name) {
            if (session == null) {
                return DeviceMark.NONE;
            }

            var status = session.status_for (device_name);
            if (status == null) {
                return DeviceMark.NONE;
            }
            return status.running ? DeviceMark.RUNNING : DeviceMark.STOPPED;
        }

        /* `compose logs -f`, addressed the same way every other call is:
         * by project name and generated file. Run in a terminal rather than
         * piped into a text view, which is what gives it colour, scrollback and
         * a working Ctrl+C for nothing (PLAN 9.4). */
        public string[]? logs_command (string device_name) {
            if (engine == null || session == null) {
                return null;
            }

            return {
                ((!) engine).program, "compose",
                "-p", ((!) session).project,
                "-f", ((!) session).compose_file,
                "logs", "-f", "--tail", "200", device_name,
            };
        }

        public string summary () {
            switch (availability) {
                case Availability.CHECKING:
                    return _("Checking for a container engine…");
                case Availability.UNAVAILABLE:
                    return _("Lab unavailable");
                default:
                    break;
            }

            switch (state) {
                case Lab.LabState.STARTING:
                    return _("Starting the lab…");
                case Lab.LabState.STOPPING:
                    return _("Stopping the lab…");
                case Lab.LabState.UP:
                    var running = ((!) session).running_count ();
                    var total = ((!) session).container_count ();
                    /* Partly up is the interesting case, and the one a plain
                     * "running" would round away. */
                    return running == total
                        ? ngettext ("Lab running: %d device", "Lab running: %d devices", running)
                              .printf (running)
                        : _("Lab running: %d of %d devices").printf (running, total);
                default:
                    return _("Lab not running");
            }
        }

        /* ── polling ────────────────────────────────────────────────── */

        /* Only while there is something to watch. A lab that is down changes
         * only when this application starts it, so an idle poll would be a
         * subprocess every two seconds for no news. */
        private void watch () {
            if (poll_source != 0 || session == null) {
                return;
            }

            poll_source = Timeout.add_seconds (POLL_SECONDS, () => {
                if (session == null || (state == Lab.LabState.DOWN && !polling)) {
                    poll_source = 0;
                    return Source.REMOVE;
                }
                poll.begin ();
                return Source.CONTINUE;
            });
        }

        private async void poll () {
            var lab = require_session ();
            if (lab == null || polling) {
                return;
            }

            /* `ps` is quick, but not quicker than the timer on a loaded
             * machine; overlapping polls would queue up behind each other. */
            polling = true;
            try {
                yield lab.refresh ();
            } catch (Error e) {
                /* A failed poll keeps the last picture. Reporting it would put
                 * a dialog on screen every two seconds. */
                debug ("lab poll failed: %s", e.message);
            }
            polling = false;

            if (lab.state != Lab.LabState.DOWN) {
                watch ();
            }
            changed ();
        }

        /* The session is bound to a compose project name, which comes from the
         * document and can be edited. Rebinding while a lab is up would strand
         * the containers it started, so a rename takes effect once it is down. */
        private Lab.Session? require_session () {
            if (engine == null) {
                return null;
            }

            var wanted = Lab.project_name_for (document.state.project_name);
            if (session == null
                || (session.project != wanted && session.state == Lab.LabState.DOWN)) {
                session = new Lab.Session ((!) engine, wanted);
                session.changed.connect (() => changed ());
            }

            return session;
        }
    }
}
