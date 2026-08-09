/* canvas.vala
 *
 * The topology drawing (SPEC 8.2). A plain Cairo redraw of the whole scene on
 * every change: at this scale a diffing renderer buys nothing, and the code
 * stays a direct reading of the document.
 *
 * Read-only for now — selection, dragging and linking arrive in phase 6.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

namespace NetworkingLab {

    /* The canvas palette. The reference implementation ships two token sets and
     * a manual toggle; here they follow the system through AdwStyleManager, as
     * the HIG asks. See PLAN.md for that divergence. */
    private struct Palette {
        Gdk.RGBA background;
        Gdk.RGBA surface;
        Gdk.RGBA grid;
        Gdk.RGBA text;
        Gdk.RGBA muted;
        Gdk.RGBA link;
        Gdk.RGBA router;
        Gdk.RGBA switch_;
        Gdk.RGBA pc;
        Gdk.RGBA server;

        public static Gdk.RGBA rgb (string spec) {
            var color = Gdk.RGBA ();
            color.parse (spec);
            return color;
        }

        public static Palette for_theme (bool dark) {
            if (dark) {
                return Palette () {
                    background = rgb ("#16191d"), surface = rgb ("#1b1f24"),
                    grid = rgb ("#22272e"), text = rgb ("#e6e9ee"), muted = rgb ("#9aa3ae"),
                    link = rgb ("#5c6672"), router = rgb ("#4d8fe0"), switch_ = rgb ("#4fae86"),
                    pc = rgb ("#98a2b0"), server = rgb ("#a98ad6"),
                };
            }

            return Palette () {
                background = rgb ("#ffffff"), surface = rgb ("#ffffff"),
                grid = rgb ("#edeff2"), text = rgb ("#1b1e23"), muted = rgb ("#6a717b"),
                link = rgb ("#9aa2ac"), router = rgb ("#2c6bbd"), switch_ = rgb ("#2f7d5d"),
                pc = rgb ("#5b6472"), server = rgb ("#7a52a8"),
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

        private State _state;
        public State state {
            get { return _state; }
            set { _state = value; queue_draw (); }
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
            _state = new State ();

            set_content_width (CANVAS_WIDTH);
            set_content_height (CANVAS_HEIGHT);
            set_draw_func (draw);

            /* Follow the system light/dark preference. */
            Adw.StyleManager.get_default ().notify["dark"].connect (queue_draw);
        }

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
            var palette = Palette.for_theme (Adw.StyleManager.get_default ().dark);

            set_source (cr, palette.background);
            cr.paint ();

            cr.scale (_zoom, _zoom);

            draw_grid (cr, palette);
            draw_links (cr, palette);
            draw_nodes (cr, palette);
        }

        private void draw_grid (Cairo.Context cr, Palette palette) {
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

        private void draw_links (Cairo.Context cr, Palette palette) {
            for (var i = 0; i < _state.links.length; i++) {
                var link = _state.links[i];
                var a = _state.node_by_id (link.a);
                var b = _state.node_by_id (link.b);
                if (a == null || b == null) {
                    continue;
                }

                set_source (cr, palette.link);
                cr.set_line_width (1.75);
                cr.move_to (a.x, a.y);
                cr.line_to (b.x, b.y);
                cr.stroke ();

                /* Only the last octet: the full address is in the panel, and
                   the drawing just needs enough to tell endpoints apart. */
                draw_endpoint_label (cr, palette, a, b, link, link.a, 0.28);
                draw_endpoint_label (cr, palette, a, b, link, link.b, 0.72);
            }
        }

        private void draw_endpoint_label (Cairo.Context cr, Palette palette,
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

        private void draw_nodes (Cairo.Context cr, Palette palette) {
            for (var i = 0; i < _state.nodes.length; i++) {
                var node = _state.nodes[i];

                cr.save ();
                cr.translate (node.x, node.y);
                draw_icon (cr, palette, node);
                cr.restore ();

                /* Clear of the r=30 selection ring, which would otherwise
                   strike through the label. */
                draw_centred_text (cr, node.name, node.x, node.y + 44, 12, palette.text);

                if (node.is_switch () && node.subnet != "") {
                    draw_centred_text (cr, node.subnet, node.x, node.y + 57, 10.5, palette.muted);
                }
            }
        }

        private void draw_icon (Cairo.Context cr, Palette palette, Core.Node node) {
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
