/* geometry.vala
 *
 * SPEC section 10, checklist item 6.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

void test_snapping () {
    /* 100 / 14 rounds to 7, so the icon lands on 98. */
    var snapped = clamp_pos (100, 100);
    assert (snapped.x == 98 && snapped.y == 98);

    /* Alt-dragging keeps the exact position. */
    var free = clamp_pos (100, 100, true);
    assert (free.x == 100 && free.y == 100);

    /* Already on a step: unchanged. */
    var on_step = clamp_pos (98, 112);
    assert (on_step.x == 98 && on_step.y == 112);
}

void test_clamping () {
    /* Nothing may sit closer to an edge than the margin. */
    var top_left = clamp_pos (0, 0);
    assert (top_left.x == CANVAS_MARGIN && top_left.y == CANVAS_MARGIN);

    var negative = clamp_pos (-500, -500, true);
    assert (negative.x == CANVAS_MARGIN && negative.y == CANVAS_MARGIN);

    var bottom_right = clamp_pos (99999, 99999);
    assert (bottom_right.x == CANVAS_WIDTH - CANVAS_MARGIN);
    assert (bottom_right.y == CANVAS_HEIGHT - CANVAS_MARGIN);

    /* Clamping applies after snapping, so the result stays inside even when
       the snap would have pushed it out. */
    var edge = clamp_pos (CANVAS_WIDTH - 10, CANVAS_HEIGHT - 10);
    assert (edge.x <= CANVAS_WIDTH - CANVAS_MARGIN);
    assert (edge.y <= CANVAS_HEIGHT - CANVAS_MARGIN);
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/core/geometry/snapping", test_snapping);
    Test.add_func ("/core/geometry/clamping", test_clamping);

    return Test.run ();
}
