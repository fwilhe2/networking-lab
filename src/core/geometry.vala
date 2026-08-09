/* geometry.vala
 *
 * Canvas placement (SPEC section 8.2).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Core {

    public struct Point {
        public int x;
        public int y;
    }

    /* Snap to half-grid steps, then keep the icon, its selection ring and both
     * labels inside the canvas. `free` is what Alt-dragging passes to place a
     * device off the grid. */
    public Point clamp_pos (double x, double y, bool free = false) {
        if (!free) {
            x = Math.round (x / SNAP) * SNAP;
            y = Math.round (y / SNAP) * SNAP;
        }

        return Point () {
            x = (int) int64.min (CANVAS_WIDTH - CANVAS_MARGIN,
                                 int64.max (CANVAS_MARGIN, (int64) Math.round (x))),
            y = (int) int64.min (CANVAS_HEIGHT - CANVAS_MARGIN,
                                 int64.max (CANVAS_MARGIN, (int64) Math.round (y))),
        };
    }
}
