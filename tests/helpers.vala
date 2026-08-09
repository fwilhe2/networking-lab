/* helpers.vala
 *
 * Shared test scaffolding, compiled into every core test binary.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

/* Normalising is the only way into the application, so tests build their
 * fixtures the same way the editor does. A fixture that fails to normalise is
 * a broken test, not a failed assertion. */
public State parse_topology (string json) {
    try {
        return normalize_json (json);
    } catch (Error e) {
        Test.fail_printf ("fixture did not normalise: %s", e.message);
        assert_not_reached ();
    }
}

public void assert_strings_equal (string[] actual, string[] expected) {
    if (actual.length != expected.length) {
        Test.fail_printf ("expected %d entries, got %d: [%s]",
                          expected.length, actual.length, string.joinv (", ", actual));
        assert_not_reached ();
    }

    for (var i = 0; i < expected.length; i++) {
        if (actual[i] != expected[i]) {
            Test.fail_printf ("at %d: expected \"%s\", got \"%s\" (whole list: [%s])",
                              i, expected[i], actual[i], string.joinv (", ", actual));
            assert_not_reached ();
        }
    }
}

public string[] network_names (GenericArray<Network> nets) {
    var result = new string[nets.length];
    for (var i = 0; i < nets.length; i++) {
        result[i] = nets[i].name;
    }
    return result;
}

public string[] diagnostic_messages (GenericArray<Diagnostic> diagnostics) {
    var result = new string[diagnostics.length];
    for (var i = 0; i < diagnostics.length; i++) {
        result[i] = diagnostics[i].message;
    }
    return result;
}
