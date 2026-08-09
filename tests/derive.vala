/* derive.vala
 *
 * SPEC section 10, checklist item 9, plus the address allocator of SPEC 3.2.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

void test_demo_networks () {
    var nets = networks_of (demo_state ());

    /* Emission order is the compose file's order: switches in node order
       first, then point-to-point links in link order. */
    assert (nets.length == 3);
    assert_strings_equal (network_names (nets), new string[] { "sw1", "sw2", "p2p_r1_r2" });

    assert (nets[0].key == "sw:n2" && nets[0].subnet == "10.0.1.0/24");
    assert (nets[1].key == "sw:n5" && nets[1].subnet == "10.0.2.0/24");
    assert (nets[2].key == "p2p:l3" && nets[2].subnet == "10.0.3.0/24");

    /* sw1 carries pc1 and r1; the p2p network carries both routers. */
    assert (nets[0].attachments.length == 2);
    assert (nets[0].attachments[0].node_id == "n1");
    assert (nets[0].attachments[1].node_id == "n3");
    assert (nets[2].attachments.length == 2);
}

void test_demo_interfaces () {
    var state = demo_state ();

    var r1 = interfaces_of (state, "n3");
    assert (r1.length == 2);
    assert (r1[0].eth == "eth0" && r1[0].net.name == "sw1" && r1[0].ip == "10.0.1.1");
    assert (r1[1].eth == "eth1" && r1[1].net.name == "p2p_r1_r2" && r1[1].ip == "10.0.3.1");

    /* r2 meets the p2p link first, because l3 precedes l4. */
    var r2 = interfaces_of (state, "n4");
    assert (r2.length == 2);
    assert (r2[0].net.name == "p2p_r1_r2" && r2[0].ip == "10.0.3.2");
    assert (r2[1].net.name == "sw2" && r2[1].ip == "10.0.2.1");

    var pc1 = interfaces_of (state, "n1");
    assert (pc1.length == 1 && pc1[0].eth == "eth0" && pc1[0].ip == "10.0.1.10");
}

void test_switches_have_no_interfaces () {
    var state = demo_state ();

    /* A switch is the segment, not a device on it — which is exactly why it
       never becomes a service. */
    assert (interfaces_of (state, "n2").length == 0);
    assert (interfaces_of (state, "n5").length == 0);
}

void test_unconnected_device_has_no_interfaces () {
    var state = parse_topology ("""
        { "nodes": [ { "id": "n1", "type": "router", "name": "r1" } ], "links": [] }
    """);

    assert (networks_of (state).length == 0);
    assert (interfaces_of (state, "n1").length == 0);
}

void test_interface_order_follows_link_order () {
    /* The same topology with the links declared the other way round numbers
       the interfaces the other way round. */
    var state = parse_topology ("""
        { "nodes": [
            { "id": "n1", "type": "router", "name": "r1" },
            { "id": "n2", "type": "switch", "name": "sw1", "subnet": "10.0.1.0/24" },
            { "id": "n3", "type": "switch", "name": "sw2", "subnet": "10.0.2.0/24" }
          ], "links": [
            { "id": "l1", "a": "n1", "b": "n3" },
            { "id": "l2", "a": "n1", "b": "n2" }
          ] }
    """);

    var ifaces = interfaces_of (state, "n1");
    assert (ifaces.length == 2);
    assert (ifaces[0].net.name == "sw2");
    assert (ifaces[1].net.name == "sw1");
}

void test_used_ips () {
    var nets = networks_of (demo_state ());

    var used = used_ips_on (nets[0]);
    assert (used.length == 2);
    assert (used[0] == "10.0.1.10" && used[1] == "10.0.1.1");
}

void test_next_free_ip () {
    var nets = networks_of (demo_state ());
    var sw1 = nets[0];      /* 10.0.1.0/24, holding .10 (pc1) and .1 (r1) */

    /* Routers start at the bottom of the range, hosts ten in. */
    assert (next_free_ip (sw1, true) == "10.0.1.2");
    assert (next_free_ip (sw1, false) == "10.0.1.11");

    var sw2 = nets[1];      /* 10.0.2.0/24, holding .1 (r2) and .10 (srv1) */
    assert (next_free_ip (sw2, true) == "10.0.2.2");
    assert (next_free_ip (sw2, false) == "10.0.2.11");
}

void test_next_free_ip_never_hands_out_the_docker_gateway () {
    /* A /29 has six usable addresses; docker reserves the last. */
    var net = new Network ("k", "tiny", "10.9.9.0/29");
    var occupied = new string[] { "10.9.9.1", "10.9.9.2", "10.9.9.3", "10.9.9.4" };

    for (var i = 0; i < occupied.length; i++) {
        var link = new Link ("l%d".printf (i), "n%d".printf (i), "sw");
        link.ips.insert ("n%d".printf (i), occupied[i]);
        net.attachments.add (new Attachment ("n%d".printf (i), link));
    }

    /* .5 is the last address that is not docker's .6. */
    assert (next_free_ip (net, true) == "10.9.9.5");

    var last = new Link ("l9", "n9", "sw");
    last.ips.insert ("n9", "10.9.9.5");
    net.attachments.add (new Attachment ("n9", last));

    /* Full: .6 is the gateway and everything below it is taken. */
    assert (next_free_ip (net, true) == "");
    assert (next_free_ip (net, false) == "");
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/core/derive/demo-networks", test_demo_networks);
    Test.add_func ("/core/derive/demo-interfaces", test_demo_interfaces);
    Test.add_func ("/core/derive/switch-interfaces", test_switches_have_no_interfaces);
    Test.add_func ("/core/derive/unconnected", test_unconnected_device_has_no_interfaces);
    Test.add_func ("/core/derive/interface-order", test_interface_order_follows_link_order);
    Test.add_func ("/core/derive/used-ips", test_used_ips);
    Test.add_func ("/core/derive/next-free-ip", test_next_free_ip);
    Test.add_func ("/core/derive/next-free-ip-gateway", test_next_free_ip_never_hands_out_the_docker_gateway);

    return Test.run ();
}
