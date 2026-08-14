/* compose.vala
 *
 * The four compose subcommands the lab needs — up, down, ps, logs — bound to
 * one project name and one generated file.
 *
 * `-p <project> -f <file>` is passed explicitly on every call rather than
 * relying on the working directory or on the `name:` key inside the file, so a
 * lab is addressed the same way whether this application started it or not.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Lab {

    public class ContainerStatus : Object {
        public string name;         /* container name — the device name, via container_name: */
        public string service;      /* compose service, identical here but not by definition */
        public string state;        /* running, exited, created, restarting, … */
        public string health;       /* empty unless the image declares a healthcheck */
        public int exit_code;

        public bool running {
            get { return state == "running"; }
        }

        public ContainerStatus (string name, string service, string state, string health, int exit_code) {
            this.name = name;
            this.service = service;
            this.state = state;
            this.health = health;
            this.exit_code = exit_code;
        }
    }

    public class Compose : Object {
        public Engine engine { get; construct; }
        public string project { get; construct; }
        public string file { get; construct; }

        public Compose (Engine engine, string project, string file) {
            Object (engine: engine, project: project, file: file);
        }

        public async void up (Cancellable? cancellable = null) throws Error {
            /* --quiet-pull because the pull progress is a redraw storm nobody
             * reads; --remove-orphans because an edited topology leaves the
             * containers of deleted devices behind otherwise. */
            yield run ({ "up", "-d", "--quiet-pull", "--remove-orphans" }, cancellable);
        }

        /* -v removes the networks and any anonymous volumes. Destroying state is
         * why the caller is expected to confirm first (PLAN 9.2). */
        public async void down (Cancellable? cancellable = null) throws Error {
            yield run ({ "down", "-v", "--remove-orphans" }, cancellable);
        }

        /* --all, not just the running ones: a container that exited on boot is
         * the single most useful thing to be able to show. */
        public async GenericArray<ContainerStatus> ps (Cancellable? cancellable = null) throws Error {
            var result = yield run ({ "ps", "--all", "--format", "json" }, cancellable);
            return parse_ps (result.output);
        }

        public async string logs (string? service, int tail, Cancellable? cancellable = null) throws Error {
            string[] arguments = { "logs", "--no-color", "--tail", tail.to_string () };
            if (service != null && service != "") {
                arguments += service;
            }

            var result = yield run (arguments, cancellable);
            return result.output + result.errors;
        }

        private async CommandResult run (string[] subcommand, Cancellable? cancellable) throws Error {
            string[] arguments = { "compose", "-p", project, "-f", file };
            foreach (var argument in subcommand) {
                arguments += argument;
            }
            return yield engine.run_checked (arguments, cancellable);
        }

        /* Two shapes are in the wild: one JSON array, or one object per line.
         * Compose 5.4.0 prints the newline-delimited form here — verified, not
         * assumed — and other builds print the array. Both are accepted,
         * because which one produced the text is not visible in it and
         * guessing wrong empties the canvas of its running marks.
         *
         * The fields used are Name, Service, State, Health and ExitCode; State
         * is "running" or "exited", also checked against real output.
         *
         * Pure and public so it can be tested without a subprocess at all. */
        public static GenericArray<ContainerStatus> parse_ps (string text) {
            var statuses = new GenericArray<ContainerStatus> ();

            var trimmed = text.strip ();
            if (trimmed == "") {
                return statuses;
            }

            var parser = new Json.Parser ();
            try {
                parser.load_from_data (trimmed);
                var root = parser.get_root ();

                if (root != null && root.get_node_type () == Json.NodeType.ARRAY) {
                    var array = root.get_array ();
                    for (var i = 0; i < array.get_length (); i++) {
                        add_status (statuses, array.get_element (i));
                    }
                    return statuses;
                }

                if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                    add_status (statuses, root);
                    return statuses;
                }
            } catch (Error e) {
                /* Not one document: fall through to the line-by-line reading. */
            }

            foreach (var line in trimmed.split ("\n")) {
                if (line.strip () == "") {
                    continue;
                }
                try {
                    var line_parser = new Json.Parser ();
                    line_parser.load_from_data (line);
                    add_status (statuses, line_parser.get_root ());
                } catch (Error e) {
                    /* One unreadable line loses one container, not the poll. */
                    continue;
                }
            }

            return statuses;
        }

        private static void add_status (GenericArray<ContainerStatus> statuses, Json.Node? node) {
            if (node == null || node.get_node_type () != Json.NodeType.OBJECT) {
                return;
            }

            var object = node.get_object ();
            var name = string_member (object, "Name");
            if (name == "") {
                return;
            }

            statuses.add (new ContainerStatus (name,
                                               string_member (object, "Service"),
                                               string_member (object, "State"),
                                               string_member (object, "Health"),
                                               int_member (object, "ExitCode")));
        }

        private static string string_member (Json.Object object, string name) {
            var node = object.get_member (name);
            if (node == null || node.get_value_type () != typeof (string)) {
                return "";
            }
            return node.get_string () ?? "";
        }

        private static int int_member (Json.Object object, string name) {
            var node = object.get_member (name);
            if (node == null || node.get_value_type () != typeof (int64)) {
                return 0;
            }
            return (int) node.get_int ();
        }
    }
}
