/* canvas.vala
 *
 * The topology drawing (SPEC 8.2). A plain Cairo redraw of the whole scene on
 * every change: at this scale a diffing renderer buys nothing, and the code
 * stays a direct reading of the document.
 *
 * Hit testing is done against the same coordinates the drawing uses, so what
 * can be clicked is exactly what can be seen.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

namespace NetworkingLab {

    /* The canvas palette. The reference implementation ships two token sets and
     * a manual toggle; here they follow the system through AdwStyleManager, as
     * the HIG asks. See PLAN.md for that divergence. */
    private struct CanvasColors {
        Gdk.RGBA background;
        Gdk.RGBA surface;
        Gdk.RGBA grid;
        Gdk.RGBA text;
        Gdk.RGBA muted;
        Gdk.RGBA link;
        Gdk.RGBA accent;
        Gdk.RGBA router;
        Gdk.RGBA switch_;
        Gdk.RGBA pc;
        Gdk.RGBA server;
        /* Lab marks (PLAN 9.2). Distinct from the device colours: green here
         * means "this container is up", not "this is a switch". */
        Gdk.RGBA running;
        Gdk.RGBA stopped;

        public static Gdk.RGBA rgb (string spec) {
            var color = Gdk.RGBA ();
            color.parse (spec);
            return color;
        }

        public static CanvasColors for_theme (bool dark) {
            if (dark) {
                return CanvasColors () {
                    background = rgb ("#16191d"), surface = rgb ("#1b1f24"),
                    grid = rgb ("#22272e"), text = rgb ("#e6e9ee"), muted = rgb ("#9aa3ae"),
                    link = rgb ("#5c6672"), accent = rgb ("#4d8fe0"),
                    router = rgb ("#4d8fe0"), switch_ = rgb ("#4fae86"),
                    pc = rgb ("#98a2b0"), server = rgb ("#a98ad6"),
                    running = rgb ("#57d787"), stopped = rgb ("#e06c6c"),
                };
            }

            return CanvasColors () {
                background = rgb ("#ffffff"), surface = rgb ("#ffffff"),
                grid = rgb ("#edeff2"), text = rgb ("#1b1e23"), muted = rgb ("#6a717b"),
                link = rgb ("#9aa2ac"), accent = rgb ("#2c6bbd"),
                router = rgb ("#2c6bbd"), switch_ = rgb ("#2f7d5d"),
                pc = rgb ("#5b6472"), server = rgb ("#7a52a8"),
                running = rgb ("#2e9e5b"), stopped = rgb ("#c0392b"),
            };
        }

        public Gdk.RGBA for_device (DeviceType type) {
            switch (type) {
                case DeviceType.ROUTER: return router;
                case DeviceType.SWITCH: return switch_;
                case DeviceType.PC:     return pc;
                default:                return server;
            }
        }
    }

    public class Canvas : Gtk.DrawingArea {

        /* Selection ring, pending-link ring and rubber band all use the
           accent colour, as the reference does. */
        private const string ACCENT = "#2c6bbd";
        private const string ACCENT_DARK = "#4d8fe0";

        /* Anything within this of a device centre counts as hitting it; the
           icons differ in shape but the ring is r=30. */
        private const double NODE_HIT_RADIUS = 30;
        /* Links are thin, so they get a generous corridor (the reference draws
           a transparent 14px hit line under each). */
        private const double LINK_HIT_DISTANCE = 7;

        public Document document { get; construct; }

        /* Set once the window has one. Null until then, and null for good in a
         * build or a sandbox where the lab cannot run — the drawing simply has
         * no marks on it. */
        public LabController? lab { get; set; default = null; }

        private State topology { get { return document.state; } }

        /* In-flight drag: which device, the grab offset, and where it began. */
        private string drag_id = "";
        private double drag_dx;
        private double drag_dy;
        private double drag_from_x;
        private double drag_from_y;
        private bool dragging = false;

        /* Where the button went down, in widget pixels. A press is only a drag
           once the pointer has left the threshold around this point. */
        private double press_x;
        private double press_y;

        /* Cursor position in canvas coordinates, for the rubber band. */
        private double pointer_x;
        private double pointer_y;

        /* Set while Alt is held, to place a device off the grid. */
        private bool free_placement = false;

        public Canvas (Document document) {
            Object (document: document);
        }

        private double _zoom = 1.0;
        public double zoom {
            get { return _zoom; }
            private set {
                _zoom = value;
                set_content_width ((int) (CANVAS_WIDTH * _zoom));
                set_content_height ((int) (CANVAS_HEIGHT * _zoom));
                notify_property ("zoom");
                queue_draw ();
            }
        }

        construct {
            set_content_width (CANVAS_WIDTH);
            set_content_height (CANVAS_HEIGHT);
            set_draw_func (draw);
            focusable = true;

            /* Follow the system light/dark preference. */
            Adw.StyleManager.get_default ().notify["dark"].connect (queue_draw);

            document.changed.connect (queue_draw);

            var click = new Gtk.GestureClick ();
            click.set_button (Gdk.BUTTON_PRIMARY);
            click.pressed.connect (on_pressed);
            click.released.connect (on_released);
            /* A gesture that is cancelled — the pointer grab is broken, another
               widget claims the sequence — never emits `released`, which would
               otherwise leave a device stuck to the cursor. */
            click.cancel.connect (() => end_drag ());
            add_controller (click);

            var motion = new Gtk.EventControllerMotion ();
            motion.motion.connect ((wx, wy) => {
                on_motion (motion.get_current_event_state (), wx, wy);
            });
            add_controller (motion);

            /* Ctrl+wheel zooms; a plain wheel is left to the scrolled window. */
            var scroll = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL);
            scroll.scroll.connect (on_scroll);
            add_controller (scroll);

            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect (on_key_pressed);
            keys.key_released.connect (on_key_released);
            add_controller (keys);

            var drop = new Gtk.DropTarget (typeof (string), Gdk.DragAction.COPY);
            drop.drop.connect (on_drop);
            add_controller (drop);
        }

        /* ── input ──────────────────────────────────────────────────── */

        /* Widget coordinates are scaled by the zoom; the document is not. */
        private double to_canvas (double v) {
            return v / _zoom;
        }

        private void on_pressed (Gtk.GestureClick gesture, int n_press, double wx, double wy) {
            grab_focus ();

            var x = to_canvas (wx);
            var y = to_canvas (wy);
            var modifiers = gesture.get_current_event_state ();
            free_placement = (modifiers & Gdk.ModifierType.ALT_MASK) != 0;

            var node = node_at (x, y);
            if (node != null) {
                var linking = link_mode || (modifiers & Gdk.ModifierType.SHIFT_MASK) != 0;
                if (linking) {
                    continue_link (node);
                    return;
                }

                document.select_node (node.id);
                drag_id = node.id;
                drag_dx = node.x - x;
                drag_dy = node.y - y;
                drag_from_x = node.x;
                drag_from_y = node.y;
                dragging = false;
                press_x = wx;
                press_y = wy;
                return;
            }

            var link = link_at (x, y);
            if (link != null) {
                document.select_link (link.id);
                return;
            }

            /* Empty canvas cancels a pending link, or clears the selection. */
            if (!document.cancel_link ()) {
                document.clear_selection ();
            }
        }

        private void continue_link (Core.Node node) {
            if (document.pending_link == "") {
                document.begin_link (node.id);
                document.report (_("Linking from %s — click the second device (Esc to cancel).")
                                 .printf (node.name));
                return;
            }

            if (document.pending_link == node.id) {
                return;
            }

            var from = document.pending_link;
            document.begin_link ("");
            document.connect_devices (from, node.id);
        }

        private void on_motion (Gdk.ModifierType state, double wx, double wy) {
            pointer_x = to_canvas (wx);
            pointer_y = to_canvas (wy);

            if (drag_id != "") {
                /* If the button is no longer down, the release was lost — to a
                   grab, a cancelled gesture, or a click that ended off the
                   widget. Without this the device would follow the pointer
                   around with nothing pressed. */
                if ((state & Gdk.ModifierType.BUTTON1_MASK) == 0) {
                    end_drag ();
                    return;
                }

                /* Selecting is a click, and a click is never perfectly still.
                   Until the pointer has travelled past the threshold this is
                   still a click, so the position is left exactly as it was —
                   otherwise a pixel of hand movement would snap the device to
                   the grid and land in the undo history as a move. */
                if (!dragging && !past_drag_threshold (wx, wy)) {
                    return;
                }

                dragging = true;
                move_node (topology, drag_id, pointer_x + drag_dx, pointer_y + drag_dy, free_placement);
                queue_draw ();
            } else if (document.pending_link != "") {
                queue_draw ();
            }
        }

        /* Widget pixels, not document units: this is about how far a hand
           wobbles on screen, which does not change with the zoom. */
        private bool past_drag_threshold (double wx, double wy) {
            var settings = Gtk.Settings.get_default ();
            var threshold = settings == null ? 8 : ((!) settings).gtk_dnd_drag_threshold;

            return (wx - press_x).abs () >= threshold
                || (wy - press_y).abs () >= threshold;
        }

        private void on_released (Gtk.GestureClick gesture, int n_press, double x, double y) {
            if (drag_id != "" && dragging) {
                document.commit_drag (drag_id, drag_from_x, drag_from_y);
            }
            end_drag ();
        }

        private void end_drag () {
            drag_id = "";
            dragging = false;
        }

        private bool on_scroll (Gtk.EventControllerScroll controller, double dx, double dy) {
            if ((controller.get_current_event_state () & Gdk.ModifierType.CONTROL_MASK) == 0) {
                return false;
            }
            if (dy < 0) {
                zoom_in ();
            } else if (dy > 0) {
                zoom_out ();
            }
            return true;
        }

        private bool on_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
            if (keyval == Gdk.Key.Alt_L || keyval == Gdk.Key.Alt_R) {
                free_placement = true;
                return false;
            }

            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                return false;
            }

            var big = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            switch (keyval) {
                case Gdk.Key.Left:  document.nudge_selection (-1, 0, big); return true;
                case Gdk.Key.Right: document.nudge_selection (1, 0, big);  return true;
                case Gdk.Key.Up:    document.nudge_selection (0, -1, big); return true;
                case Gdk.Key.Down:  document.nudge_selection (0, 1, big);  return true;
                default: return false;
            }
        }

        private void on_key_released (uint keyval, uint keycode, Gdk.ModifierType state) {
            if (keyval == Gdk.Key.Alt_L || keyval == Gdk.Key.Alt_R) {
                free_placement = false;
            }
        }

        private bool on_drop (Value value, double wx, double wy) {
            DeviceType type;
            if (!DeviceType.try_parse (value.get_string (), out type)) {
                return false;
            }
            document.add_device (type, to_canvas (wx), to_canvas (wy));
            return true;
        }

        /* ── hit testing ────────────────────────────────────────────── */

        private Core.Node? node_at (double x, double y) {
            /* Last drawn is topmost, so search backwards. */
            for (var i = topology.nodes.length - 1; i >= 0; i--) {
                var node = topology.nodes[i];
                var dx = node.x - x;
                var dy = node.y - y;
                if (dx * dx + dy * dy <= NODE_HIT_RADIUS * NODE_HIT_RADIUS) {
                    return node;
                }
            }
            return null;
        }

        private Link? link_at (double x, double y) {
            for (var i = topology.links.length - 1; i >= 0; i--) {
                var link = topology.links[i];
                var a = topology.node_by_id (link.a);
                var b = topology.node_by_id (link.b);
                if (a == null || b == null) {
                    continue;
                }
                if (distance_to_segment (x, y, a.x, a.y, b.x, b.y) <= LINK_HIT_DISTANCE) {
                    return link;
                }
            }
            return null;
        }

        private double distance_to_segment (double px, double py,
                                            double ax, double ay, double bx, double by) {
            var vx = bx - ax;
            var vy = by - ay;
            var length_squared = vx * vx + vy * vy;

            /* Coincident endpoints: the segment is a point. */
            var t = length_squared == 0 ? 0
                  : ((px - ax) * vx + (py - ay) * vy) / length_squared;
            t = double.max (0, double.min (1, t));

            var cx = ax + t * vx;
            var cy = ay + t * vy;
            return Math.sqrt ((px - cx) * (px - cx) + (py - cy) * (py - cy));
        }

        /* Add-link mode: plain clicks connect devices and the mode persists,
         * so several links can be drawn in a row. */
        public bool link_mode { get; set; default = false; }

        /* ── zoom ───────────────────────────────────────────────────── */

        public void zoom_in () {
            foreach (var step in ZOOM_STEPS) {
                if (step > _zoom + 0.001) {
                    zoom = step;
                    return;
                }
            }
        }

        public void zoom_out () {
            for (var i = ZOOM_STEPS.length - 1; i >= 0; i--) {
                if (ZOOM_STEPS[i] < _zoom - 0.001) {
                    zoom = ZOOM_STEPS[i];
                    return;
                }
            }
        }

        public void zoom_reset () {
            zoom = 1.0;
        }

        public string zoom_label () {
            return "%.0f%%".printf (_zoom * 100);
        }

        /* ── drawing ────────────────────────────────────────────────── */

        private void draw (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            var palette = CanvasColors.for_theme (Adw.StyleManager.get_default ().dark);

            set_source (cr, palette.background);
            cr.paint ();

            cr.scale (_zoom, _zoom);

            draw_grid (cr, palette);
            draw_links (cr, palette);
            draw_pending_link (cr, palette);
            draw_nodes (cr, palette);
        }

        private void draw_grid (Cairo.Context cr, CanvasColors palette) {
            set_source (cr, palette.grid);
            cr.set_line_width (1.0 / _zoom);

            for (var x = 0; x <= CANVAS_WIDTH; x += GRID) {
                cr.move_to (x + 0.5, 0);
                cr.line_to (x + 0.5, CANVAS_HEIGHT);
            }
            for (var y = 0; y <= CANVAS_HEIGHT; y += GRID) {
                cr.move_to (0, y + 0.5);
                cr.line_to (CANVAS_WIDTH, y + 0.5);
            }
            cr.stroke ();
        }

        private void draw_links (Cairo.Context cr, CanvasColors palette) {
            for (var i = 0; i < topology.links.length; i++) {
                var link = topology.links[i];
                var a = topology.node_by_id (link.a);
                var b = topology.node_by_id (link.b);
                if (a == null || b == null) {
                    continue;
                }

                var selected = document.selection_kind == SelectionKind.LINK
                            && document.selection_id == link.id;

                set_source (cr, selected ? palette.accent : palette.link);
                cr.set_line_width (selected ? 4 : 1.75);
                cr.move_to (a.x, a.y);
                cr.line_to (b.x, b.y);
                cr.stroke ();

                /* Only the last octet: the full address is in the panel, and
                   the drawing just needs enough to tell endpoints apart. */
                draw_endpoint_label (cr, palette, a, b, link, link.a, 0.28);
                draw_endpoint_label (cr, palette, a, b, link, link.b, 0.72);
            }
        }

        private void draw_endpoint_label (Cairo.Context cr, CanvasColors palette,
                                          Core.Node a, Core.Node b, Link link,
                                          string end_id, double t) {
            var ip = link.ip_for (end_id);
            if (ip == "") {
                return;
            }

            var octets = ip.split (".");
            var x = a.x + (b.x - a.x) * t;
            var y = a.y + (b.y - a.y) * t;

            draw_centred_text (cr, "." + octets[octets.length - 1], x, y - 6, 10.5, palette.muted);
        }

        /* The rubber band from the first device to the cursor. */
        private void draw_pending_link (Cairo.Context cr, CanvasColors palette) {
            if (document.pending_link == "") {
                return;
            }

            var from = topology.node_by_id (document.pending_link);
            if (from == null) {
                return;
            }

            /* The dash pattern is part of the graphics state, so save/restore
               puts it back without allocating an empty pattern. */
            cr.save ();
            set_source (cr, palette.accent);
            cr.set_line_width (1.75);
            cr.set_dash (new double[] { 5, 4 }, 0);
            cr.move_to (from.x, from.y);
            cr.line_to (pointer_x, pointer_y);
            cr.stroke ();
            cr.restore ();
        }

        private void draw_nodes (Cairo.Context cr, CanvasColors palette) {
            for (var i = 0; i < topology.nodes.length; i++) {
                var node = topology.nodes[i];

                draw_rings (cr, palette, node);

                cr.save ();
                cr.translate (node.x, node.y);
                draw_icon (cr, palette, node);
                cr.restore ();

                draw_lab_mark (cr, palette, node);

                /* Clear of the r=30 selection ring, which would otherwise
                   strike through the label. */
                draw_centred_text (cr, node.name, node.x, node.y + 44, 12, palette.text);

                if (node.is_switch () && node.subnet != "") {
                    draw_centred_text (cr, node.subnet, node.x, node.y + 57, 10.5, palette.muted);
                }
            }
        }

        /* A dot on the shoulder of a device whose container exists: green for
         * running, red for one that exited. A switch is a docker network rather
         * than a container, so it never carries one.
         *
         * The halo is drawn in the background colour so the dot stays legible
         * where it overlaps the icon (PLAN 9.2). */
        private void draw_lab_mark (Cairo.Context cr, CanvasColors palette, Core.Node node) {
            if (lab == null || !node.device_type.is_service ()) {
                return;
            }

            var mark = ((!) lab).mark_for (node.name);
            if (mark == DeviceMark.NONE) {
                return;
            }

            var x = node.x + 19;
            var y = node.y - 19;

            cr.save ();
            set_source (cr, palette.background);
            cr.arc (x, y, 6.5, 0, 2 * Math.PI);
            cr.fill ();

            set_source (cr, mark == DeviceMark.RUNNING ? palette.running : palette.stopped);
            cr.arc (x, y, 4.5, 0, 2 * Math.PI);
            cr.fill ();
            cr.restore ();
        }

        /* A solid ring marks the selection; a dashed one marks the device a
         * link is being drawn from. */
        private void draw_rings (Cairo.Context cr, CanvasColors palette, Core.Node node) {
            var selected = document.selection_kind == SelectionKind.NODE
                        && document.selection_id == node.id;
            var pending = document.pending_link == node.id;

            if (!selected && !pending) {
                return;
            }

            cr.save ();
            set_source (cr, palette.accent);
            cr.set_line_width (1.75);
            if (pending) {
                cr.set_dash (new double[] { 4, 4 }, 0);
            }
            cr.new_sub_path ();
            cr.arc (node.x, node.y, 30, 0, 2 * Math.PI);
            cr.stroke ();
            cr.restore ();
        }

        private void draw_icon (Cairo.Context cr, CanvasColors palette, Core.Node node) {
            var color = palette.for_device (node.device_type);

            switch (node.device_type) {
                case DeviceType.ROUTER:
                    cr.new_sub_path ();
                    cr.arc (0, 0, 20, 0, 2 * Math.PI);
                    fill_and_stroke (cr, palette.surface, color, 2);

                    /* Two opposed arrows: traffic in, traffic out. */
                    set_source (cr, color);
                    cr.set_line_width (2);
                    cr.move_to (-11, -5); cr.line_to (3, -5); cr.line_to (-1, -9);
                    cr.move_to (3, -5);   cr.line_to (-1, -1);
                    cr.move_to (11, 6);   cr.line_to (-3, 6); cr.line_to (1, 2);
                    cr.move_to (-3, 6);   cr.line_to (1, 10);
                    cr.stroke ();
                    break;

                case DeviceType.SWITCH:
                    rounded_rect (cr, -24, -13, 48, 26, 4);
                    fill_and_stroke (cr, palette.surface, color, 2);

                    set_source (cr, color);
                    cr.set_line_width (1.8);
                    cr.move_to (-15, -4); cr.line_to (-3, -4); cr.line_to (-7, -8);
                    cr.move_to (-3, -4);  cr.line_to (-7, 0);
                    cr.move_to (15, 5);   cr.line_to (3, 5);   cr.line_to (7, 1);
                    cr.move_to (3, 5);    cr.line_to (7, 9);
                    cr.stroke ();
                    break;

                case DeviceType.PC:
                    rounded_rect (cr, -17, -16, 34, 22, 3);
                    fill_and_stroke (cr, palette.surface, color, 2);

                    set_source (cr, color);
                    cr.set_line_width (2);
                    cr.move_to (-7, 13); cr.line_to (7, 13);
                    cr.move_to (0, 6);   cr.line_to (0, 13);
                    cr.stroke ();
                    break;

                case DeviceType.SERVER:
                    rounded_rect (cr, -15, -18, 30, 15, 2.5);
                    fill_and_stroke (cr, palette.surface, color, 2);
                    rounded_rect (cr, -15, 2, 30, 15, 2.5);
                    fill_and_stroke (cr, palette.surface, color, 2);

                    set_source (cr, color);
                    cr.new_sub_path ();
                    cr.arc (-9, -10.5, 2, 0, 2 * Math.PI);
                    cr.fill ();
                    cr.new_sub_path ();
                    cr.arc (-9, 9.5, 2, 0, 2 * Math.PI);
                    cr.fill ();
                    break;
            }
        }

        /* ── cairo helpers ──────────────────────────────────────────── */

        private void set_source (Cairo.Context cr, Gdk.RGBA color) {
            cr.set_source_rgba (color.red, color.green, color.blue, color.alpha);
        }

        private void fill_and_stroke (Cairo.Context cr, Gdk.RGBA fill, Gdk.RGBA stroke, double width) {
            set_source (cr, fill);
            cr.fill_preserve ();
            set_source (cr, stroke);
            cr.set_line_width (width);
            cr.stroke ();
        }

        private void rounded_rect (Cairo.Context cr, double x, double y,
                                   double w, double h, double r) {
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r,     r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r,     y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r,     y + r,     r, Math.PI, 1.5 * Math.PI);
            cr.close_path ();
        }

        /* SVG places text on its baseline; Pango draws from the top-left, so
         * the baseline is subtracted back out. */
        private void draw_centred_text (Cairo.Context cr, string text, double x, double y,
                                        double size, Gdk.RGBA color) {
            var layout = create_pango_layout (text);
            var font = Pango.FontDescription.from_string ("Sans");
            font.set_absolute_size (size * Pango.SCALE);
            layout.set_font_description (font);

            int text_width, text_height;
            layout.get_pixel_size (out text_width, out text_height);

            set_source (cr, color);
            cr.move_to (x - text_width / 2.0, y - layout.get_baseline () / Pango.SCALE);
            Pango.cairo_show_layout (cr, layout);

            /* show_layout leaves the current point set. Without clearing it the
               next arc () would be joined to it by a stray line. */
            cr.new_path ();
        }
    }
}
