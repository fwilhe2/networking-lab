/* edit.vala
 *
 * The editing operations of SPEC section 4. The interesting parts are the
 * automatic addressing and the default-gateway convenience of 3.2 and 3.3.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

private State empty () {
    return parse_topology ("{\"nodes\":[],\"links\":[]}");
}

void test_add_node_names_and_defaults () {
    var state = empty ();

    var r1 = add_node (state, DeviceType.ROUTER, 100, 100);
    var r2 = add_node (state, DeviceType.ROUTER, 200, 200);
    var sw1 = add_node (state, DeviceType.SWITCH, 300, 300);
    var srv1 = add_node (state, DeviceType.SERVER, 400, 400);

    assert (r1.id == "n1" && r1.name == "r1");
    assert (r2.id == "n2" && r2.name == "r2");
    assert (sw1.id == "n3" && sw1.name == "sw1");
    assert (srv1.id == "n4" && srv1.name == "srv1");

    /* A switch is a segment, so it gets one immediately. */
    assert (sw1.subnet == "10.0.1.0/24");
    assert (srv1.http_port == "80");
    assert (r1.frr_extra == "" && srv1.gw == "");

    /* Positions are snapped and clamped. */
    assert (r1.x == 98 && r1.y == 98);
}

void test_add_node_de_duplicates_names () {
    var state = empty ();

    add_node (state, DeviceType.ROUTER, 100, 100).name = "r2";
    var second = add_node (state, DeviceType.ROUTER, 200, 200);

    /* The counter says r2, which is taken, so it becomes r22. */
    assert (second.name == "r22");
}

void test_add_link_refusals () {
    var state = empty ();
    var sw1 = add_node (state, DeviceType.SWITCH, 100, 100);
    var sw2 = add_node (state, DeviceType.SWITCH, 200, 200);
    var r1 = add_node (state, DeviceType.ROUTER, 300, 300);

    LinkRefusal refusal;

    assert (add_link (state, sw1.id, sw2.id, out refusal) == null);
    assert (refusal == LinkRefusal.SWITCH_TO_SWITCH);

    assert (add_link (state, r1.id, sw1.id, out refusal) != null);
    assert (refusal == LinkRefusal.NONE);

    /* Same pair, either way round. */
    assert (add_link (state, sw1.id, r1.id, out refusal) == null);
    assert (refusal == LinkRefusal.ALREADY_CONNECTED);

    assert (add_link (state, r1.id, r1.id, out refusal) == null);
    assert (refusal == LinkRefusal.NO_SUCH_DEVICE);

    assert (add_link (state, r1.id, "n99", out refusal) == null);
    assert (refusal == LinkRefusal.NO_SUCH_DEVICE);

    assert (state.links.length == 1);
}

void test_add_link_addresses_both_ends () {
    var state = empty ();
    var sw1 = add_node (state, DeviceType.SWITCH, 100, 100);   /* 10.0.1.0/24 */
    var r1 = add_node (state, DeviceType.ROUTER, 200, 200);
    var pc1 = add_node (state, DeviceType.PC, 300, 300);

    LinkRefusal refusal;
    var to_router = add_link (state, r1.id, sw1.id, out refusal);
    var to_pc = add_link (state, pc1.id, sw1.id, out refusal);

    /* Routers take the bottom of the range, hosts start ten in. */
    assert (to_router.ip_for (r1.id) == "10.0.1.1");
    assert (to_pc.ip_for (pc1.id) == "10.0.1.10");

    /* A switch is never addressed. */
    assert (to_router.ip_for (sw1.id) == "");
    assert (to_pc.ip_for (sw1.id) == "");
}

void test_point_to_point_link_gets_its_own_subnet () {
    var state = empty ();
    var r1 = add_node (state, DeviceType.ROUTER, 100, 100);
    var r2 = add_node (state, DeviceType.ROUTER, 200, 200);

    LinkRefusal refusal;
    var link = add_link (state, r1.id, r2.id, out refusal);

    assert (link.subnet == "10.0.1.0/24");
    assert (link.ip_for (r1.id) == "10.0.1.1");
    assert (link.ip_for (r2.id) == "10.0.1.2");
}

void test_gateway_convenience_from_a_router_on_the_segment () {
    var state = empty ();
    var sw1 = add_node (state, DeviceType.SWITCH, 100, 100);
    var r1 = add_node (state, DeviceType.ROUTER, 200, 200);
    var pc1 = add_node (state, DeviceType.PC, 300, 300);

    LinkRefusal refusal;
    add_link (state, r1.id, sw1.id, out refusal);      /* r1 gets 10.0.1.1 */
    add_link (state, pc1.id, sw1.id, out refusal);

    /* The host is pointed at the router already on that segment. */
    assert (pc1.gw == "10.0.1.1");
}

void test_gateway_convenience_from_the_other_end () {
    var state = empty ();
    var r1 = add_node (state, DeviceType.ROUTER, 100, 100);
    var pc1 = add_node (state, DeviceType.PC, 200, 200);

    LinkRefusal refusal;
    add_link (state, pc1.id, r1.id, out refusal);

    /* Directly connected: the gateway is the router's own address on the
       point-to-point link. */
    assert (pc1.gw == "10.0.1.1");
}

void test_gateway_convenience_leaves_an_existing_gateway_alone () {
    var state = empty ();
    var sw1 = add_node (state, DeviceType.SWITCH, 100, 100);
    var r1 = add_node (state, DeviceType.ROUTER, 200, 200);
    var pc1 = add_node (state, DeviceType.PC, 300, 300);
    pc1.gw = "10.0.1.99";

    LinkRefusal refusal;
    add_link (state, r1.id, sw1.id, out refusal);
    add_link (state, pc1.id, sw1.id, out refusal);

    assert (pc1.gw == "10.0.1.99");
}

void test_no_gateway_when_there_is_no_router () {
    var state = empty ();
    var sw1 = add_node (state, DeviceType.SWITCH, 100, 100);
    var pc1 = add_node (state, DeviceType.PC, 200, 200);

    LinkRefusal refusal;
    add_link (state, pc1.id, sw1.id, out refusal);

    /* Validation reports this later as an advisory. */
    assert (pc1.gw == "");
}

void test_delete_node_takes_its_links () {
    var state = demo_state ();

    delete_node (state, "n3");      /* r1, which carries l2 and l3 */

    assert (state.node_by_id ("n3") == null);
    assert (state.nodes.length == 5);
    assert (state.links.length == 3);
    for (var i = 0; i < state.links.length; i++) {
        assert (!state.links[i].touches ("n3"));
    }
}

void test_duplicate_copies_settings_but_not_links () {
    var state = demo_state ();
    var r1 = state.node_by_id ("n3");

    var copy = duplicate_node (state, "n3");

    assert (copy.name == "r3");
    assert (copy.frr_extra == r1.frr_extra);

    /* Offset by two grid squares, then snapped like any other placement:
       480+56 = 536 lands on 532, and 160+56 = 216 lands on 210. */
    assert (copy.x == 532 && copy.y == 210);

    /* Wiring is deliberately not copied. */
    assert (interfaces_of (state, copy.id).length == 0);
}

void test_ids_are_never_reused () {
    var state = empty ();
    add_node (state, DeviceType.ROUTER, 100, 100);
    var second = add_node (state, DeviceType.ROUTER, 200, 200);

    delete_node (state, second.id);
    var third = add_node (state, DeviceType.ROUTER, 300, 300);

    assert (third.id == "n3");
}

void test_snapshots_preserve_counters () {
    var state = empty ();
    add_node (state, DeviceType.ROUTER, 100, 100);
    var second = add_node (state, DeviceType.ROUTER, 200, 200);
    delete_node (state, second.id);

    /* Only n1 survives, but the next id must still be n3: rebuilding the
       counters alone would hand out n2 a second time. */
    State restored;
    try {
        restored = restore_snapshot (to_json (state));
    } catch (Error e) {
        Test.fail_printf ("snapshot did not restore: %s", e.message);
        return;
    }

    assert (restored.counters.node == 2);
    assert (add_node (restored, DeviceType.ROUTER, 300, 300).id == "n3");
}

void test_clear_keeps_the_lab_settings () {
    var state = demo_state ();
    state.project_name = "keepme";
    state.isolated = false;
    state.router_image = "frr:11";

    clear_topology (state);

    assert (state.nodes.length == 0);
    assert (state.links.length == 0);
    assert (state.counters.node == 0);
    assert (state.project_name == "keepme");
    assert (!state.isolated);
    assert (state.router_image == "frr:11");
}

void test_move_snaps_unless_free () {
    var state = demo_state ();

    move_node (state, "n1", 100, 100, false);
    assert (state.node_by_id ("n1").x == 98);

    move_node (state, "n1", 100, 100, true);
    assert (state.node_by_id ("n1").x == 100);

    /* Always inside the margin. */
    move_node (state, "n1", -900, 99999, true);
    assert (state.node_by_id ("n1").x == CANVAS_MARGIN);
    assert (state.node_by_id ("n1").y == CANVAS_HEIGHT - CANVAS_MARGIN);
}

void test_name_is_taken () {
    var state = demo_state ();

    assert (name_is_taken (state, "r1", "n1"));
    assert (!name_is_taken (state, "r1", "n3"));   /* r1 is n3, so it may keep it */
    assert (!name_is_taken (state, "nothing", "n1"));
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/core/edit/add-node", test_add_node_names_and_defaults);
    Test.add_func ("/core/edit/add-node-dedup", test_add_node_de_duplicates_names);
    Test.add_func ("/core/edit/link-refusals", test_add_link_refusals);
    Test.add_func ("/core/edit/link-addressing", test_add_link_addresses_both_ends);
    Test.add_func ("/core/edit/p2p-subnet", test_point_to_point_link_gets_its_own_subnet);
    Test.add_func ("/core/edit/gateway-segment", test_gateway_convenience_from_a_router_on_the_segment);
    Test.add_func ("/core/edit/gateway-direct", test_gateway_convenience_from_the_other_end);
    Test.add_func ("/core/edit/gateway-kept", test_gateway_convenience_leaves_an_existing_gateway_alone);
    Test.add_func ("/core/edit/gateway-absent", test_no_gateway_when_there_is_no_router);
    Test.add_func ("/core/edit/delete-node", test_delete_node_takes_its_links);
    Test.add_func ("/core/edit/duplicate", test_duplicate_copies_settings_but_not_links);
    Test.add_func ("/core/edit/ids-not-reused", test_ids_are_never_reused);
    Test.add_func ("/core/edit/snapshot-counters", test_snapshots_preserve_counters);
    Test.add_func ("/core/edit/clear", test_clear_keeps_the_lab_settings);
    Test.add_func ("/core/edit/move", test_move_snaps_unless_free);
    Test.add_func ("/core/edit/name-taken", test_name_is_taken);

    return Test.run ();
}
