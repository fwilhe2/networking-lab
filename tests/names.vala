/* names.vala
 *
 * SPEC section 10, checklist items 4-5.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

void test_sanitize_name () {
    assert (sanitize_name ("R1") == "r1");
    assert (sanitize_name ("my router!") == "myrouter");
    assert (sanitize_name ("--lead") == "lead");
    assert (sanitize_name ("***") == "dev");
    assert (sanitize_name ("") == "dev");

    /* Underscores and hyphens survive anywhere but the front. */
    assert (sanitize_name ("core-01_a") == "core-01_a");
    assert (sanitize_name ("__x") == "x");

    /* Non-ASCII is dropped rather than transliterated. */
    assert (sanitize_name ("rüter") == "rter");
    assert (sanitize_name ("日本") == "dev");
}

void test_sanitize_name_fallback () {
    assert (sanitize_name ("!!!", "router") == "router");
    assert (sanitize_name ("r1", "router") == "r1");
}

void test_unique_name () {
    var taken = new_name_set ();
    taken.add ("r1");
    taken.add ("r2");

    /* A suffix, not an increment: r1 becomes r12, never r2. */
    assert (unique_name ("r1", taken) == "r12");
    assert (unique_name ("r3", taken) == "r3");

    taken.add ("r12");
    assert (unique_name ("r1", taken) == "r13");
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/core/names/sanitize", test_sanitize_name);
    Test.add_func ("/core/names/sanitize-fallback", test_sanitize_name_fallback);
    Test.add_func ("/core/names/unique", test_unique_name);

    return Test.run ();
}
