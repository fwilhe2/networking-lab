/* engine.vala
 *
 * Finding a container engine and running it. Every call is asynchronous,
 * because `up` on a cold image cache pulls hundreds of megabytes and takes
 * minutes — blocking the main loop for that would freeze the window mid-boot.
 *
 * The engine is docker or podman, whichever is on PATH; what is actually
 * depended on is compose v2, which `podman compose` delegates to. Both speak
 * the same CLI for everything used here — `compose`, `info`, `exec` — so the
 * only engine-specific thing in the application is the program name.
 *
 * It is a run-time dependency, never a build-time one. Its absence is an
 * ordinary, expected outcome that the caller reports; it is not an error the
 * application is entitled to be surprised by.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Lab {

    public errordomain LabError {
        NOT_INSTALLED,      /* no container engine on PATH */
        NO_COMPOSE,         /* the engine is there, compose is not */
        COMPOSE_TOO_OLD,    /* older than COMPOSE_FLOOR */
        UNAVAILABLE,        /* the engine did not answer */
        FAILED,             /* a command exited non-zero */
        BUSY,               /* the session is already starting or stopping */
    }

    /* The generated file uses inline `configs.content`, which compose gained in
     * 2.23.1. Anything older fails in the middle of `up` with a message about
     * a missing file, which is a confusing way to learn you need an upgrade. */
    public const string COMPOSE_FLOOR = "2.23.1";

    public class CommandResult : Object {
        public int status;
        public string output;
        public string errors;

        public bool ok {
            get { return status == 0; }
        }

        public CommandResult (int status, string output, string errors) {
            this.status = status;
            this.output = output;
            this.errors = errors;
        }

        /* stderr, falling back to stdout: compose reports progress and failures
         * on stderr, but `config` and `ps` put their diagnostics on stdout. */
        public string message () {
            var text = errors.strip ();
            if (text == "") {
                text = output.strip ();
            }
            return text == "" ? "exit status %d".printf (status) : text;
        }
    }

    public class Engine : Object {
        /* In order, and overridable with NETLAB_ENGINE on a machine that has
         * both. podman first: it is rootless by default, which is the safer of
         * the two to hand a generated file to. */
        public const string[] CANDIDATES = { "podman", "docker" };

        public string program { get; private set; }
        public string compose_version { get; private set; default = ""; }

        private Engine (string program) {
            this.program = program;
        }

        /* The engine's plain name, for the commands the user is shown and the
         * terminal runs. Falls back to the first candidate so there is always
         * something to print, including before a probe has run. */
        public static string program_name () {
            foreach (var name in candidates ()) {
                if (Environment.find_program_in_path (name) != null) {
                    return name;
                }
            }
            return candidates ()[0];
        }

        private static string[] candidates () {
            var chosen = Environment.get_variable ("NETLAB_ENGINE");
            return chosen != null && chosen != ""
                ? new string[] { (!) chosen }
                : CANDIDATES;
        }

        /* Locates the engine and establishes that it can actually be used:
         * compose exists, it is new enough, and the engine answers. Each
         * failure gets its own error code, because the fix differs for each and
         * the user is the one who has to apply it. */
        public static async Engine probe (Cancellable? cancellable = null) throws Error {
            string? program = null;
            foreach (var name in candidates ()) {
                program = Environment.find_program_in_path (name);
                if (program != null) {
                    break;
                }
            }
            if (program == null) {
                throw new LabError.NOT_INSTALLED (
                    "no container engine on PATH (looked for %s)"
                        .printf (string.joinv (", ", candidates ())));
            }

            var engine = new Engine ((!) program);
            var name = Path.get_basename ((!) program);

            var version = yield engine.run ({ "compose", "version", "--short" }, cancellable);
            if (!version.ok) {
                throw new LabError.NO_COMPOSE (
                    "%s has no compose v2 support (%s)".printf (name, version.message ()));
            }

            /* podman prints its "Executing external compose provider" notice on
             * stderr, so stdout is still just the version — but take the last
             * non-empty line rather than the whole of stdout in case an engine
             * puts a banner there too. */
            var found = last_line (version.output);
            if (!version_at_least (found, COMPOSE_FLOOR)) {
                throw new LabError.COMPOSE_TOO_OLD (
                    "compose %s is older than %s, which inline configs need"
                        .printf (found, COMPOSE_FLOOR));
            }
            engine.compose_version = found;

            /* `compose ls` rather than `info`, because it is the path every
             * other call takes. `podman info` answers happily while the socket
             * compose delegates through is not running — checked, not assumed —
             * and a probe that says READY there produces a cryptic failure on
             * the first press of Run instead of a reason up front. */
            var ready = yield engine.run ({ "compose", "ls" }, cancellable);
            if (!ready.ok) {
                throw new LabError.UNAVAILABLE (
                    "%s is not reachable (%s)%s".printf (
                        name, ready.message (),
                        name == "podman"
                            ? "\n\nTry: systemctl --user start podman.socket"
                            : ""));
            }

            return engine;
        }

        private static string last_line (string text) {
            var found = "";
            foreach (var line in text.split ("\n")) {
                if (line.strip () != "") {
                    found = line.strip ();
                }
            }
            return found;
        }

        public async CommandResult run (string[] arguments, Cancellable? cancellable = null) throws Error {
            string[] command = { program };
            foreach (var argument in arguments) {
                command += argument;
            }

            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            var process = launcher.spawnv (command);

            string? output;
            string? errors;
            yield process.communicate_utf8_async (null, cancellable, out output, out errors);

            /* A signalled process has no exit status; -1 keeps `ok` false
             * without pretending to know which signal it was. */
            var status = process.get_if_exited () ? process.get_exit_status () : -1;
            return new CommandResult (status, output ?? "", errors ?? "");
        }

        public async CommandResult run_checked (string[] arguments, Cancellable? cancellable = null) throws Error {
            var result = yield run (arguments, cancellable);
            if (!result.ok) {
                throw new LabError.FAILED (result.message ());
            }
            return result;
        }

        /* Component-wise, so 5.4.0 is newer than 2.23.1 — which a string
         * comparison gets right only by accident and gets wrong at 10.x. */
        public static bool version_at_least (string found, string floor) {
            var mine = strip_v (found).split (".");
            var want = strip_v (floor).split (".");

            for (var i = 0; i < want.length; i++) {
                /* int.parse stops at the first non-digit, so a build suffix
                 * like "2.29.7-desktop.1" compares as 2.29.7. */
                var a = i < mine.length ? int.parse (mine[i]) : 0;
                var b = int.parse (want[i]);
                if (a != b) {
                    return a > b;
                }
            }
            return true;
        }

        private static string strip_v (string version) {
            return version.has_prefix ("v") ? version.substring (1) : version;
        }
    }
}
