/* validate.vala
 *
 * SPEC section 5, and the error/advisory split of checklist item 14.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

private Diagnostic? find (GenericArray<Diagnostic> diagnostics, string fragment) {
    for (var i = 0; i < diagnostics.length; i++) {
        if (fragment in diagnostics[i].message) {
            return diagnostics[i];
        }
    }
    return null;
}

void test_demo_is_clean () {
    /* The demo has to generate nothing at all — it is the reference topology. */
    var diagnostics = validate (demo_state ());
    if (diagnostics.length != 0) {
        Test.fail_printf ("demo produced: %s", string.joinv (" | ", diagnostic_messages (diagnostics)));
    }
    assert (diagnostics.length == 0);
    assert (!has_errors (diagnostics));
}

void test_address_outside_the_subnet () {
    var state = demo_state ();
    state.links[0].ips.insert ("n1", "10.0.9.9");   /* pc1 on sw1 (10.0.1.0/24) */

    var diagnostics = validate (state);
    var found = find (diagnostics, "is outside");

    assert (found != null);
    assert (found.is_error);
    assert (found.message == "pc1: 10.0.9.9 is outside sw1 (10.0.1.0/24).");
}

void test_duplicate_address_on_a_segment () {
    var state = demo_state ();
    state.links[0].ips.insert ("n1", "10.0.1.1");   /* already r1's address on sw1 */

    var found = find (validate (state), "Duplicate IP");

    assert (found != null);
    assert (found.is_error);
    /* pc1 is attached first, so it is the one already seen. */
    assert (found.message == "Duplicate IP 10.0.1.1 on sw1 (pc1 and r1).");
}

void test_address_collides_with_the_docker_gateway () {
    var state = demo_state ();
    state.links[0].ips.insert ("n1", "10.0.1.254");

    var found = find (validate (state), "docker gateway");

    assert (found != null);
    assert (found.is_error);
    assert ("last usable address is reserved" in found.message);
}

void test_missing_address () {
    var state = demo_state ();
    state.links[0].ips.remove ("n1");

    var found = find (validate (state), "has no IP");

    assert (found != null);
    assert (found.is_error);
    assert (found.message == "pc1 has no IP on sw1.");
}

void test_two_networks_with_the_same_name () {
    var state = demo_state ();

    /* A switch named after the generated p2p network: docker would merge two
       segments that the drawing shows as separate. */
    var sw1 = state.node_by_id ("n2");
    sw1.name = "p2p_r1_r2";

    var found = find (validate (state), "Two networks are both named");

    assert (found != null);
    assert (found.is_error);
    assert (found.message == "Two networks are both named \"p2p_r1_r2\" — rename a device.");
}

void test_duplicate_device_name () {
    var state = demo_state ();
    state.node_by_id ("n4").name = "r1";

    var found = find (validate (state), "Duplicate name");

    assert (found != null);
    assert (found.is_error);
    assert (found.message == "Duplicate name \"r1\".");
}

void test_missing_gateway_is_only_advisory () {
    var state = demo_state ();
    state.node_by_id ("n1").gw = "";

    var diagnostics = validate (state);
    var found = find (diagnostics, "no default gateway");

    assert (found != null);
    /* Amber, not red: the lab still boots, pc1 just cannot leave its subnet. */
    assert (!found.is_error);
    assert (!has_errors (diagnostics));
}

void test_unconnected_device_is_only_advisory () {
    var state = parse_topology ("""
        { "nodes": [
            { "id": "n1", "type": "router", "name": "r1" },
            { "id": "n2", "type": "switch", "name": "sw1", "subnet": "10.0.1.0/24" }
          ], "links": [] }
    """);

    var diagnostics = validate (state);
    var found = find (diagnostics, "not connected");

    assert (found != null);
    assert (!found.is_error);
    assert (found.message == "r1 is not connected to anything.");

    /* A switch with nothing on it is a segment nobody uses, not a fault. */
    assert (find (diagnostics, "sw1") == null);
    assert (diagnostics.length == 1);
}

void test_check_order () {
    /* SPEC 5 fixes the order: names, then network names, then addressing,
       then advisories. */
    var state = demo_state ();
    state.node_by_id ("n4").name = "r1";            /* duplicate device name */
    state.links[0].ips.insert ("n1", "10.0.9.9");   /* address outside sw1 */
    state.node_by_id ("n6").gw = "";                /* advisory */

    var messages = diagnostic_messages (validate (state));

    assert (messages.length == 3);
    assert ("Duplicate name" in messages[0]);
    assert ("is outside" in messages[1]);
    assert ("no default gateway" in messages[2]);
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/core/validate/demo-is-clean", test_demo_is_clean);
    Test.add_func ("/core/validate/outside-subnet", test_address_outside_the_subnet);
    Test.add_func ("/core/validate/duplicate-address", test_duplicate_address_on_a_segment);
    Test.add_func ("/core/validate/docker-gateway", test_address_collides_with_the_docker_gateway);
    Test.add_func ("/core/validate/missing-address", test_missing_address);
    Test.add_func ("/core/validate/duplicate-network-name", test_two_networks_with_the_same_name);
    Test.add_func ("/core/validate/duplicate-device-name", test_duplicate_device_name);
    Test.add_func ("/core/validate/missing-gateway", test_missing_gateway_is_only_advisory);
    Test.add_func ("/core/validate/unconnected", test_unconnected_device_is_only_advisory);
    Test.add_func ("/core/validate/order", test_check_order);

    return Test.run ();
}
