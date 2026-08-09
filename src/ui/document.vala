/* document.vala
 *
 * The one mutable thing the UI touches. Every mutation follows the same shape:
 * push_history () first, mutate, then emit changed. Undo is whole-document JSON
 * snapshots — the documents are kilobytes and 60 entries are cheap, so the
 * command pattern would be more code for no visible gain (SPEC 4.1).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

namespace NetworkingLab {

    public enum SelectionKind {
        NONE,
        NODE,
        LINK,
    }

    public class Document : Object {

        public State state { get; private set; }

        public SelectionKind selection_kind { get; private set; default = SelectionKind.NONE; }
        public string selection_id { get; private set; default = ""; }

        /* The first device of a link being drawn, or "" when none is pending. */
        public string pending_link { get; private set; default = ""; }

        private GenericArray<string> past = new GenericArray<string> ();
        private GenericArray<string> future = new GenericArray<string> ();

        /* The document changed and the drawing is stale. */
        public signal void changed ();
        /* The selection changed and the properties panel is stale. */
        public signal void selection_changed ();
        /* One line of feedback for the status bar (SPEC 8.8). */
        public signal void status (string message);

        public bool can_undo { get { return past.length > 0; } }
        public bool can_redo { get { return future.length > 0; } }

        public Document () {
            state = new State ();
        }

        /* ── history ────────────────────────────────────────────────── */

        /* Call immediately *before* mutating. Property fields commit on focus
         * loss rather than per keystroke, so one edit is one entry. */
        public void push_history () {
            past.add (to_json (state));
            if (past.length > HISTORY_LIMIT) {
                past.remove_index (0);
            }
            future.length = 0;
            notify_property ("can-undo");
            notify_property ("can-redo");
        }

        public void undo () {
            if (past.length == 0) {
                status (_("Nothing to undo."));
                return;
            }
            future.add (to_json (state));
            restore (past.steal_index (past.length - 1));
            status (_("Undo."));
        }

        public void redo () {
            if (future.length == 0) {
                status (_("Nothing to redo."));
                return;
            }
            past.add (to_json (state));
            restore (future.steal_index (future.length - 1));
            status (_("Redo."));
        }

        private void restore (string snapshot) {
            try {
                state = restore_snapshot (snapshot);
            } catch (Error e) {
                /* Snapshots are our own output; failing to read one is a bug. */
                warning ("could not restore a snapshot: %s", e.message);
                return;
            }

            clear_selection_state ();
            notify_property ("can-undo");
            notify_property ("can-redo");
            changed ();
            selection_changed ();
        }

        private void clear_selection_state () {
            selection_kind = SelectionKind.NONE;
            selection_id = "";
            pending_link = "";
        }

        /* Replaces the whole document, undoably — import, demo, clear. */
        public void replace (State replacement) {
            push_history ();
            state = replacement;
            clear_selection_state ();
            changed ();
            selection_changed ();
        }

        /* ── selection ──────────────────────────────────────────────── */

        public void select_node (string id) {
            selection_kind = SelectionKind.NODE;
            selection_id = id;
            selection_changed ();
            changed ();
        }

        public void select_link (string id) {
            selection_kind = SelectionKind.LINK;
            selection_id = id;
            selection_changed ();
            changed ();
        }

        public void clear_selection () {
            if (selection_kind == SelectionKind.NONE) {
                return;
            }
            selection_kind = SelectionKind.NONE;
            selection_id = "";
            selection_changed ();
            changed ();
        }

        public Core.Node? selected_node () {
            return selection_kind == SelectionKind.NODE ? state.node_by_id (selection_id) : null;
        }

        public Link? selected_link () {
            if (selection_kind != SelectionKind.LINK) {
                return null;
            }
            for (var i = 0; i < state.links.length; i++) {
                if (state.links[i].id == selection_id) {
                    return state.links[i];
                }
            }
            return null;
        }

        /* ── pending link ───────────────────────────────────────────── */

        public void begin_link (string node_id) {
            pending_link = node_id;
            changed ();
        }

        public bool cancel_link () {
            if (pending_link == "") {
                return false;
            }
            pending_link = "";
            changed ();
            status (_("Link cancelled."));
            return true;
        }

        /* ── mutations ──────────────────────────────────────────────── */

        public Core.Node add_device (DeviceType type, double x, double y) {
            push_history ();
            var node = add_node (state, type, x, y);
            select_node (node.id);
            changed ();
            status (_("Added %s.").printf (node.name));
            return node;
        }

        public bool connect_devices (string a_id, string b_id) {
            var a = state.node_by_id (a_id);
            var b = state.node_by_id (b_id);

            push_history ();

            LinkRefusal refusal;
            var link = add_link (state, a_id, b_id, out refusal);

            if (link == null) {
                /* Nothing changed, so the snapshot would be a dead undo step. */
                drop_last_history_entry ();
                status (refusal.message ());
                return false;
            }

            select_link (link.id);
            changed ();
            status (_("Linked %s ↔ %s.").printf (a.name, b.name));
            return true;
        }

        public void delete_selection () {
            if (selection_kind == SelectionKind.NONE) {
                return;
            }

            push_history ();

            if (selection_kind == SelectionKind.NODE) {
                var node = state.node_by_id (selection_id);
                delete_node (state, selection_id);
                status (node != null ? _("Deleted %s.").printf (node.name) : _("Deleted."));
            } else {
                delete_link (state, selection_id);
                status (_("Link deleted."));
            }

            selection_kind = SelectionKind.NONE;
            selection_id = "";
            changed ();
            selection_changed ();
        }

        public void duplicate_selection () {
            var source = selected_node ();
            if (source == null) {
                status (_("Select a device to duplicate."));
                return;
            }

            push_history ();
            var copy = duplicate_node (state, source.id);
            select_node (copy.id);
            changed ();
            status (_("Duplicated %s as %s (links are not copied).").printf (source.name, copy.name));
        }

        public void nudge_selection (int dx, int dy, bool big) {
            var node = selected_node ();
            if (node == null) {
                return;
            }

            var step = big ? GRID * 2 : SNAP;
            push_history ();
            move_node (state, node.id, node.x + dx * step, node.y + dy * step, true);
            changed ();
        }

        /* A drag is one entry, recorded with the pre-drag position, so undo
         * puts the device back where it started rather than mid-path. */
        public void commit_drag (string node_id, double before_x, double before_y) {
            var node = state.node_by_id (node_id);
            if (node == null || (node.x == before_x && node.y == before_y)) {
                return;
            }

            var x = node.x;
            var y = node.y;
            node.x = before_x;
            node.y = before_y;
            push_history ();
            node.x = x;
            node.y = y;
        }

        public void clear () {
            push_history ();
            clear_topology (state);
            clear_selection_state ();
            changed ();
            selection_changed ();
            status (_("Cleared."));
        }

        /* Edits from the properties panel: the caller has already validated,
         * so this only wraps the snapshot and the redraw around it. */
        public void begin_edit () {
            push_history ();
        }

        public void end_edit (string message = "") {
            changed ();
            if (message != "") {
                status (message);
            }
        }

        public void report (string message) {
            status (message);
        }

        private void drop_last_history_entry () {
            if (past.length > 0) {
                past.remove_index (past.length - 1);
                notify_property ("can-undo");
            }
        }
    }
}
