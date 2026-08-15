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

        /* Searched after PATH. A GUI application on macOS inherits launchd's
         * minimal PATH — /usr/bin:/bin:/usr/sbin:/sbin — not the one the user's
         * shell builds, so neither Homebrew nor the Podman Desktop installer is
         * on it and an app launched from Finder would report "not installed"
         * while the terminal two windows over runs podman happily. Harmless
         * elsewhere: three stat calls, and /usr/local/bin is a real place to
         * install things on Linux too. */
        public const string[] EXTRA_DIRS = {
            "/opt/homebrew/bin",    /* Homebrew, Apple silicon */
            "/usr/local/bin",       /* Homebrew on Intel; Docker Desktop's symlink */
            "/opt/podman/bin",      /* the podman-installer .pkg */
        };

        public string program { get; private set; }
        public string compose_version { get; private set; default = ""; }

        private Engine (string program) {
            this.program = program;
        }

        /* PATH first, then the well-known directories. An absolute NETLAB_ENGINE
         * is honoured as-is, because g_find_program_in_path returns an absolute
         * argument unchanged when it is executable — which is the escape hatch
         * for an engine installed somewhere nobody expected.
         *
         * `extra_dirs` is a parameter only so the test can point it at a
         * sandbox; every caller uses the default. */
        public static string? find_program (string name, string[] extra_dirs = EXTRA_DIRS) {
            var found = Environment.find_program_in_path (name);
            if (found != null) {
                return found;
            }

            foreach (var dir in extra_dirs) {
                var candidate = Path.build_filename (dir, name);
                if (FileUtils.test (candidate, FileTest.IS_EXECUTABLE)) {
                    return candidate;
                }
            }
            return null;
        }

        /* The engine's plain name, for the commands the user is shown and the
         * terminal runs. Falls back to the first candidate so there is always
         * something to print, including before a probe has run. */
        public static string program_name () {
            foreach (var name in candidates ()) {
                if (find_program (name) != null) {
                    return Path.get_basename (name);
                }
            }
            return Path.get_basename (candidates ()[0]);
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
                program = find_program (name);
                if (program != null) {
                    break;
                }
            }
            if (program == null) {
                throw new LabError.NOT_INSTALLED (
                    "no container engine found (looked for %s on PATH and in %s)"
                        .printf (string.joinv (", ", candidates ()),
                                 string.joinv (", ", EXTRA_DIRS)));
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
                    "%s is not reachable (%s)%s".printf (name, ready.message (), hint (name)));
            }

            return engine;
        }

        /* What to actually do about an engine that does not answer. compose
         * delegates through a socket, and the message it prints when that
         * socket is missing describes a docker daemon whatever the engine is,
         * so the useful half of the report is this line.
         *
         * podman is not reachable for a different reason on each platform: on
         * macOS the Linux VM is not running, on Linux the socket unit is not
         * started. The platform is a build-time fact, hence the define rather
         * than a run-time test. */
        private static string hint (string name) {
            if (name != "podman") {
                return "";
            }
#if MACOS
            return "\n\nTry: podman machine start";
#else
            return "\n\nTry: systemctl --user start podman.socket";
#endif
        }

        /* The engine's own directory, ahead of whatever PATH we inherited.
         *
         * Finding the program is only half of it: `podman compose` is not a
         * subcommand but a lookup of an external provider — the docker-compose
         * binary — on the PATH podman is *given*. An app launched from Finder
         * hands it launchd's PATH, so podman found in /opt/homebrew/bin would
         * then fail to find the compose provider sitting beside it and report
         * no compose support. Passing its directory down fixes both halves with
         * one line. */
        private string child_path () {
            var inherited = Environment.get_variable ("PATH") ?? "/usr/bin:/bin";
            return Path.get_dirname (program) + Path.SEARCHPATH_SEPARATOR_S + inherited;
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

        /* Nothing waits forever. An engine that accepts a command and never
         * answers — a socket in a half-open state, a compose provider stopped
         * on a question — would otherwise leave the caller's `yield` pending
         * for the rest of the session: the poll guard stays set, the lab stays
         * STARTING, and Run stays insensitive. From the outside that is
         * indistinguishable from the application having frozen, which is the
         * whole reason these two numbers exist.
         *
         * Two budgets, because `ps` and `up` are not the same kind of wait.
         * `ps` answers in about 70ms against a real podman; `up` on a cold
         * cache pulls three images. */
        public const uint TIMEOUT_QUICK = 30;
        public const uint TIMEOUT_BOOT = 900;

        public async CommandResult run (string[] arguments, Cancellable? cancellable = null,
                                        uint timeout_seconds = TIMEOUT_QUICK) throws Error {
            string[] command = { program };
            foreach (var argument in arguments) {
                command += argument;
            }

            /* Neither STDIN_PIPE nor STDIN_INHERIT, so GSubprocess gives the
             * child /dev/null: an engine that asks a question — podman's
             * short-name prompt is the one to expect — reads EOF and fails
             * instead of waiting on a stdin nobody is watching. */
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE
                                                   | SubprocessFlags.STDERR_PIPE);
            launcher.setenv ("PATH", child_path (), true);
            var process = launcher.spawnv (command);

            /* Cancelling the read as well as killing the child, because the two
             * are not the same thing: communicate waits for end-of-file, and a
             * grandchild that inherited the pipes — `podman compose` starts an
             * external provider — holds them open after its parent is gone.
             * Waiting on that is the hang this is here to end. */
            var guard = new Cancellable ();
            ulong chained = 0;
            if (cancellable != null) {
                chained = ((!) cancellable).connect (() => guard.cancel ());
            }

            var expired = false;
            uint timer = 0;
            if (timeout_seconds > 0) {
                timer = Timeout.add_seconds (timeout_seconds, () => {
                    timer = 0;
                    expired = true;
                    process.force_exit ();
                    guard.cancel ();
                    return Source.REMOVE;
                });
            }

            string? output = null;
            string? errors = null;
            try {
                yield process.communicate_utf8_async (null, guard, out output, out errors);
            } catch (Error e) {
                /* The timeout cancels the guard itself, so its own cancellation
                 * is the expected outcome rather than a failure to report. */
                if (!expired) {
                    throw e;
                }
            } finally {
                if (timer != 0) {
                    Source.remove (timer);
                }
                if (chained != 0) {
                    ((!) cancellable).disconnect (chained);
                }
            }

            if (expired) {
                return new CommandResult (-1, output ?? "",
                                          "%s did not answer within %us"
                                              .printf (string.joinv (" ", command), timeout_seconds));
            }

            /* A signalled process has no exit status; -1 keeps `ok` false
             * without pretending to know which signal it was. */
            var status = process.get_if_exited () ? process.get_exit_status () : -1;
            return new CommandResult (status, output ?? "", errors ?? "");
        }

        public async CommandResult run_checked (string[] arguments, Cancellable? cancellable = null,
                                                uint timeout_seconds = TIMEOUT_QUICK) throws Error {
            var result = yield run (arguments, cancellable, timeout_seconds);
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
