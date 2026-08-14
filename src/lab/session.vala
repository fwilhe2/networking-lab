/* session.vala
 *
 * The lifecycle of one lab: DOWN → STARTING → UP → STOPPING → DOWN, plus the
 * per-device status that the canvas draws its running marks from.
 *
 * Nothing here blocks. `up` on a cold cache pulls three images, so the whole
 * chain — write the file, boot it, read `ps` back — is asynchronous, and the
 * intermediate STARTING and STOPPING states exist precisely because those two
 * operations are long enough for the user to watch.
 *
 * The state is derived from what `ps` reports, never from what this process
 * believes it did. That is what lets the application adopt a lab it did not
 * start, and what keeps a container that died on boot from being displayed as
 * running.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Lab {

    public enum LabState {
        DOWN,
        STARTING,
        UP,
        STOPPING;

        /* Machine-readable; the UI supplies the translated wording. */
        public string id () {
            switch (this) {
                case DOWN:     return "down";
                case STARTING: return "starting";
                case UP:       return "up";
                case STOPPING: return "stopping";
                default:       assert_not_reached ();
            }
        }

        public bool busy () {
            return this == STARTING || this == STOPPING;
        }
    }

    public class Session : Object {
        public Engine engine { get; construct; }
        public string project { get; construct; }

        public LabState state { get; private set; default = LabState.DOWN; }
        public string compose_file { get; private set; default = ""; }

        /* The state, the container list, or both moved. */
        public signal void changed ();

        private Compose compose;
        private HashTable<string, ContainerStatus> statuses;

        public Session (Engine engine, string project_name) {
            Object (engine: engine, project: project_name_for (project_name));
        }

        construct {
            statuses = new HashTable<string, ContainerStatus> (str_hash, str_equal);
            compose_file = compose_path (project);
            compose = new Compose (engine, project, compose_file);
        }

        /* Writes the generated file and boots it. The yaml is passed in rather
         * than compiled here: src/core/ owns compilation, and this layer must
         * not acquire an opinion about what a topology is. */
        public async void start (string yaml, Cancellable? cancellable = null) throws Error {
            if (state.busy ()) {
                throw new LabError.BUSY ("the lab is already %s".printf (state.id ()));
            }

            enter_state (LabState.STARTING);

            try {
                compose_file = write_compose (project, yaml);
                yield compose.up (cancellable);
            } catch (Error e) {
                /* A failed `up` still leaves whatever it managed to create, so
                 * settle before reporting: the user needs Stop to be offered. */
                yield settle ();
                throw e;
            }

            yield settle ();
        }

        public async void stop (Cancellable? cancellable = null) throws Error {
            if (state.busy ()) {
                throw new LabError.BUSY ("the lab is already %s".printf (state.id ()));
            }

            enter_state (LabState.STOPPING);

            try {
                yield compose.down (cancellable);
            } catch (Error e) {
                yield settle ();
                throw e;
            }

            yield settle ();
        }

        /* Poll. Safe to call at any time; while an operation is in flight it
         * updates the container list without touching the state, so a slow
         * `up` is not reported as finished by the poll that runs during it. */
        public async void refresh (Cancellable? cancellable = null) throws Error {
            yield refresh_statuses (cancellable);

            if (state.busy ()) {
                changed ();
                return;
            }

            enter_state (statuses.size () > 0 ? LabState.UP : LabState.DOWN);
        }

        public async string logs (string? device_name, int tail = 200,
                                  Cancellable? cancellable = null) throws Error {
            return yield compose.logs (device_name, tail, cancellable);
        }

        /* Container names are device names — the compiler emits `container_name:
         * <name>` — so the canvas can ask about a node directly. */
        public bool is_running (string device_name) {
            var status = statuses.lookup (device_name);
            return status != null && status.running;
        }

        public ContainerStatus? status_for (string device_name) {
            return statuses.lookup (device_name);
        }

        public int running_count () {
            var running = 0;
            foreach (var status in statuses.get_values ()) {
                if (status.running) {
                    running++;
                }
            }
            return running;
        }

        public int container_count () {
            return (int) statuses.size ();
        }

        /* Some containers up, some not: the interesting failure of a boot, and
         * the one the status bar should not round off to "running". */
        public bool partially_running () {
            return container_count () > 0 && running_count () < container_count ();
        }

        /* Sorted by name, because hash table order is arbitrary and a list that
         * reshuffles on every poll is unreadable. */
        public GenericArray<ContainerStatus> containers () {
            var list = new GenericArray<ContainerStatus> ();
            foreach (var status in statuses.get_values ()) {
                list.add (status);
            }
            list.sort ((a, b) => strcmp (a.name, b.name));
            return list;
        }

        private async void refresh_statuses (Cancellable? cancellable) throws Error {
            /* No file means the lab has never been generated, and `compose -f`
             * on a missing file is an error rather than an empty
             * answer. */
            if (!FileUtils.test (compose_file, FileTest.EXISTS)) {
                statuses.remove_all ();
                return;
            }

            var list = yield compose.ps (cancellable);

            /* Replaced wholesale, and only on success: a failed poll should
             * leave the last known picture rather than blank the canvas. */
            var fresh = new HashTable<string, ContainerStatus> (str_hash, str_equal);
            for (var i = 0; i < list.length; i++) {
                fresh.insert (list[i].name, list[i]);
            }
            statuses = fresh;
        }

        private async void settle () {
            try {
                yield refresh_statuses (null);
            } catch (Error e) {
                /* Keep the last picture; the operation's own error is what the
                 * caller reports. */
            }
            enter_state (statuses.size () > 0 ? LabState.UP : LabState.DOWN);
        }

        private void enter_state (LabState next) {
            state = next;
            changed ();
        }
    }
}
