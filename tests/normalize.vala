/* normalize.vala
 *
 * SPEC section 10, checklist items 7-8: the trust boundary repairs anything
 * that is a topology at all, and refuses only what is not.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

private State parse (string json) {
    try {
        return normalize_json (json);
    } catch (Error e) {
        Test.fail_printf ("normalize_json rejected valid input: %s", e.message);
        assert_not_reached ();
    }
}

private void assert_rejected (string json) {
    try {
        normalize_json (json);
        Test.fail_printf ("expected `%s` to be rejected", json);
    } catch (Error e) {
        /* Expected. */
    }
}

void test_rejects_non_topologies () {
    /* The only failure mode: it is not a topology at all. */
    assert_rejected ("null");
    assert_rejected ("42");
    assert_rejected ("\"nope\"");
    assert_rejected ("{}");
    assert_rejected ("{\"nodes\":[]}");
    assert_rejected ("{\"links\":[]}");
    assert_rejected ("[]");
    assert_rejected ("not json at all");
    assert_rejected ("{\"nodes\":{},\"links\":[]}");
}

void test_accepts_the_empty_topology () {
    var state = parse ("{\"nodes\":[],\"links\":[]}");

    assert (state.nodes.length == 0);
    assert (state.links.length == 0);
    assert (state.project_name == "netlab");
    assert (state.isolated);
    assert (state.router_image == DEFAULT_ROUTER_IMAGE);
    assert (state.host_image == DEFAULT_HOST_IMAGE);
    assert (state.server_image == DEFAULT_SERVER_IMAGE);
}

void test_lab_settings () {
    var state = parse ("""
        { "projectName": "My Lab!", "isolated": false,
          "images": { "router": "  frr:latest  ", "host": "   ", "server": 7 },
          "nodes": [], "links": [] }
    """);

    assert (state.project_name == "mylab");
    assert (!state.isolated);
    assert (state.router_image == "frr:latest");    /* trimmed */
    assert (state.host_image == DEFAULT_HOST_IMAGE); /* blank falls back */
    assert (state.server_image == DEFAULT_SERVER_IMAGE); /* non-string falls back */

    /* Anything but an explicit false leaves the lab sealed. */
    assert (parse ("{\"nodes\":[],\"links\":[]}").isolated);
    assert (parse ("{\"isolated\":\"no\",\"nodes\":[],\"links\":[]}").isolated);
}

void test_drops_unusable_nodes () {
    var state = parse ("""
        { "nodes": [
            { "id": "n1", "type": "router",  "name": "r1" },
            { "id": "n2", "type": "toaster", "name": "t1" },
            { "id": "n1", "type": "pc",      "name": "pc1" },
            {              "type": "pc",     "name": "pc2" },
            "not an object",
            { "id": "n5", "type": "server",  "name": "srv1" }
          ], "links": [] }
    """);

    assert (state.nodes.length == 2);
    assert (state.nodes[0].id == "n1" && state.nodes[0].device_type == DeviceType.ROUTER);
    assert (state.nodes[1].id == "n5" && state.nodes[1].device_type == DeviceType.SERVER);
}

void test_de_duplicates_names () {
    var state = parse ("""
        { "nodes": [
            { "id": "n1", "type": "pc", "name": "pc1" },
            { "id": "n2", "type": "pc", "name": "pc1" },
            { "id": "n3", "type": "pc", "name": "pc1" }
          ], "links": [] }
    """);

    assert (state.nodes[0].name == "pc1");
    assert (state.nodes[1].name == "pc12");
    assert (state.nodes[2].name == "pc13");
}

void test_repairs_node_fields () {
    var state = parse ("""
        { "nodes": [
            { "id": "n1", "type": "switch", "name": "sw1", "subnet": "nonsense" },
            { "id": "n2", "type": "pc",     "name": "!!!",  "gw": "10.0.0.256", "x": "250", "y": 3.5 },
            { "id": "n3", "type": "server", "name": "srv1", "httpPort": "8o8o", "gw": "10.0.1.1" },
            { "id": "n4", "type": "server", "name": "srv2", "httpPort": "abc" },
            { "id": "n5", "type": "router", "name": "r1",   "frrExtra": 42, "x": "nope" }
          ], "links": [] }
    """);

    /* An invalid switch subnet is replaced by a freshly allocated one. */
    assert (state.nodes[0].subnet == "10.0.1.0/24");

    /* An unusable name falls back to the type prefix, a bad gateway is dropped,
       and a numeric string is still a number. */
    assert (state.nodes[1].name == "pc1");
    assert (state.nodes[1].gw == "");
    assert (state.nodes[1].x == 250);
    assert (state.nodes[1].y == 3.5);

    assert (state.nodes[2].http_port == "88");    /* digits only: "8o8o" loses the letters */
    assert (state.nodes[2].gw == "10.0.1.1");
    assert (state.nodes[3].http_port == "80");    /* nothing left, so the default */

    assert (state.nodes[4].frr_extra == "");      /* not a string */
    assert (state.nodes[4].x == 100);             /* unparseable, so the default */
}

void test_drops_unusable_links () {
    var state = parse ("""
        { "nodes": [
            { "id": "n1", "type": "pc",     "name": "pc1" },
            { "id": "n2", "type": "switch", "name": "sw1", "subnet": "10.0.1.0/24" },
            { "id": "n3", "type": "switch", "name": "sw2", "subnet": "10.0.2.0/24" },
            { "id": "n4", "type": "router", "name": "r1" }
          ], "links": [
            { "id": "l1", "a": "n1", "b": "n2" },
            { "id": "l2", "a": "n2", "b": "n1" },
            { "id": "l3", "a": "n1", "b": "n1" },
            { "id": "l4", "a": "n2", "b": "n3" },
            { "id": "l5", "a": "n1", "b": "n9" },
            { "id": "l1", "a": "n4", "b": "n2" },
            { "id": "l7", "a": "n4", "b": "n2" }
          ] }
    """);

    /* Kept: l1 (pc1-sw1) and l7 (r1-sw1). Dropped: the reversed duplicate, the
       self link, switch-to-switch, the dangling end and the duplicate id. */
    assert (state.links.length == 2);
    assert (state.links[0].id == "l1");
    assert (state.links[1].id == "l7");
}

void test_repairs_link_addresses () {
    var state = parse ("""
        { "nodes": [
            { "id": "n1", "type": "pc",     "name": "pc1" },
            { "id": "n2", "type": "switch", "name": "sw1", "subnet": "10.0.1.0/24" },
            { "id": "n3", "type": "router", "name": "r1" },
            { "id": "n4", "type": "router", "name": "r2" }
          ], "links": [
            { "id": "l1", "a": "n1", "b": "n2",
              "ips": { "n1": "10.0.1.10", "n2": "10.0.1.99" } },
            { "id": "l2", "a": "n3", "b": "n4", "subnet": "bogus",
              "ips": { "n3": "10.0.3.1", "n4": "999.0.0.1" } }
          ] }
    """);

    /* A switch never carries an address, even when the file gives it one. */
    assert (state.links[0].ip_for ("n1") == "10.0.1.10");
    assert (state.links[0].ip_for ("n2") == "");
    /* A switched link owns no subnet — the switch does. */
    assert (state.links[0].subnet == "");
    assert (!state.is_point_to_point (state.links[0]));

    /* Point-to-point: invalid subnet replaced, invalid address dropped. */
    assert (state.is_point_to_point (state.links[1]));
    assert (valid_cidr (state.links[1].subnet));
    assert (state.links[1].ip_for ("n3") == "10.0.3.1");
    assert (state.links[1].ip_for ("n4") == "");
}

void test_rebuilds_counters () {
    /* Counters in the file are deliberately wrong: trusting them would mint a
       colliding n1 for the next device. */
    var state = parse ("""
        { "counters": { "node": 0, "link": 0, "subnet": 0, "router": 0, "pc": 0 },
          "nodes": [
            { "id": "n7", "type": "router", "name": "r4" },
            { "id": "n3", "type": "switch", "name": "sw2", "subnet": "10.0.9.0/24" },
            { "id": "n5", "type": "pc",     "name": "pc2" }
          ], "links": [
            { "id": "l4", "a": "n7", "b": "n3" }
          ] }
    """);

    assert (state.counters.node == 7);
    assert (state.counters.link == 4);
    assert (state.counters.subnet == 9);
    assert (state.counters.for_type (DeviceType.ROUTER) == 4);
    assert (state.counters.for_type (DeviceType.SWITCH) == 2);
    assert (state.counters.for_type (DeviceType.PC) == 2);
    assert (state.counters.for_type (DeviceType.SERVER) == 0);

    /* The next allocation therefore clears everything already in use. */
    assert (state.alloc_subnet () == "10.0.10.0/24");
}

void test_allocates_missing_subnets_without_overlap () {
    var state = parse ("""
        { "nodes": [
            { "id": "n1", "type": "switch", "name": "sw1" },
            { "id": "n2", "type": "switch", "name": "sw2", "subnet": "10.0.4.0/24" },
            { "id": "n3", "type": "switch", "name": "sw3" },
            { "id": "n4", "type": "router", "name": "r1" },
            { "id": "n5", "type": "router", "name": "r2" }
          ], "links": [
            { "id": "l1", "a": "n4", "b": "n5" }
          ] }
    """);

    /* Allocation runs after the counters are rebuilt, so nothing collides with
       the 10.0.4.0/24 already in the file. */
    assert (state.nodes[1].subnet == "10.0.4.0/24");   /* kept, so the counter starts at 4 */
    assert (state.nodes[0].subnet == "10.0.5.0/24");
    assert (state.nodes[2].subnet == "10.0.6.0/24");
    assert (state.links[0].subnet == "10.0.7.0/24");   /* switches first, then p2p links */
}

void test_round_trips_through_json () {
    var original = parse ("""
        { "projectName": "netlab-demo", "isolated": false,
          "images": { "router": "frr:11", "host": "alpine:3.21", "server": "python:3.13" },
          "nodes": [
            { "id": "n1", "type": "pc",     "name": "pc1", "x": 120, "y": 240, "gw": "10.0.1.1" },
            { "id": "n2", "type": "switch", "name": "sw1", "subnet": "10.0.1.0/24" },
            { "id": "n3", "type": "router", "name": "r1",  "frrExtra": "router ospf" },
            { "id": "n4", "type": "router", "name": "r2" },
            { "id": "n5", "type": "server", "name": "srv1", "httpPort": "8080" }
          ], "links": [
            { "id": "l1", "a": "n1", "b": "n2", "ips": { "n1": "10.0.1.10" } },
            { "id": "l2", "a": "n3", "b": "n4", "subnet": "10.0.3.0/24",
              "ips": { "n3": "10.0.3.1", "n4": "10.0.3.2" } }
          ] }
    """);

    var again = parse (to_json (original));

    assert (again.project_name == "netlab-demo");
    assert (!again.isolated);
    assert (again.router_image == "frr:11");
    assert (again.host_image == "alpine:3.21");
    assert (again.server_image == "python:3.13");
    assert (again.nodes.length == 5);
    assert (again.links.length == 2);

    for (var i = 0; i < original.nodes.length; i++) {
        assert (again.nodes[i].id == original.nodes[i].id);
        assert (again.nodes[i].name == original.nodes[i].name);
        assert (again.nodes[i].device_type == original.nodes[i].device_type);
        assert (again.nodes[i].x == original.nodes[i].x);
        assert (again.nodes[i].y == original.nodes[i].y);
        assert (again.nodes[i].subnet == original.nodes[i].subnet);
        assert (again.nodes[i].frr_extra == original.nodes[i].frr_extra);
        assert (again.nodes[i].gw == original.nodes[i].gw);
        assert (again.nodes[i].http_port == original.nodes[i].http_port);
    }

    assert (again.links[1].subnet == "10.0.3.0/24");
    assert (again.links[1].ip_for ("n3") == "10.0.3.1");
    assert (again.links[1].ip_for ("n4") == "10.0.3.2");

    /* Counters survive because they are rebuilt to the same values. */
    assert (again.counters.node == original.counters.node);
    assert (again.counters.link == original.counters.link);
    assert (again.counters.subnet == original.counters.subnet);
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/core/normalize/rejects-non-topologies", test_rejects_non_topologies);
    Test.add_func ("/core/normalize/empty", test_accepts_the_empty_topology);
    Test.add_func ("/core/normalize/lab-settings", test_lab_settings);
    Test.add_func ("/core/normalize/drops-nodes", test_drops_unusable_nodes);
    Test.add_func ("/core/normalize/de-duplicates-names", test_de_duplicates_names);
    Test.add_func ("/core/normalize/repairs-node-fields", test_repairs_node_fields);
    Test.add_func ("/core/normalize/drops-links", test_drops_unusable_links);
    Test.add_func ("/core/normalize/repairs-link-addresses", test_repairs_link_addresses);
    Test.add_func ("/core/normalize/rebuilds-counters", test_rebuilds_counters);
    Test.add_func ("/core/normalize/allocates-subnets", test_allocates_missing_subnets_without_overlap);
    Test.add_func ("/core/normalize/json-round-trip", test_round_trips_through_json);

    return Test.run ();
}
