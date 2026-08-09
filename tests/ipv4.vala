/* ipv4.vala
 *
 * SPEC section 10, checklist items 1-3.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

void test_round_trip () {
    assert (ip_to_int ("0.0.0.0") == 0);
    assert (ip_to_int ("255.255.255.255") == 0xffffffffu);
    assert (ip_to_int ("10.0.1.1") == 0x0a000101u);

    assert (int_to_ip (0) == "0.0.0.0");
    assert (int_to_ip (0xffffffffu) == "255.255.255.255");
    assert (int_to_ip (0x0a000101u) == "10.0.1.1");
}

void test_cidr_info () {
    var info = cidr_info ("10.0.1.0/24");
    assert (info.length == 24);
    assert (info.base_address == ip_to_int ("10.0.1.0"));
    assert (info.broadcast == ip_to_int ("10.0.1.255"));
    /* The first usable address is the base plus one. */
    assert (info.first == cidr_info ("10.0.1.1/32").base_address);
    assert (info.last == ip_to_int ("10.0.1.254"));

    /* A host route: mask covers everything. */
    assert (cidr_info ("10.0.1.7/32").base_address == ip_to_int ("10.0.1.7"));
}

void test_docker_gateway () {
    /* Docker takes the last usable address on every network. */
    assert (docker_gateway ("10.0.1.0/24") == "10.0.1.254");
    assert (docker_gateway ("192.168.4.0/30") == "192.168.4.2");
    assert (docker_gateway ("172.16.0.0/16") == "172.16.255.254");
}

void test_valid_ip () {
    assert (valid_ip ("10.0.0.1"));
    assert (valid_ip ("0.0.0.0"));
    assert (valid_ip ("255.255.255.255"));

    assert (!valid_ip ("10.0.0.256"));
    assert (!valid_ip ("10.0.0"));
    assert (!valid_ip (""));
    assert (!valid_ip ("10.0.0.1.1"));
    assert (!valid_ip ("10.0.0.a"));
    assert (!valid_ip ("10.0.0.1 "));
    assert (!valid_ip ("10.0.0.0001"));
}

void test_valid_cidr () {
    assert (valid_cidr ("10.0.1.0/24"));
    assert (valid_cidr ("10.0.0.0/8"));
    assert (valid_cidr ("10.0.1.0/29"));

    /* /30 leaves no room for docker's gateway plus two endpoints. */
    assert (!valid_cidr ("10.0.1.0/30"));
    assert (!valid_cidr ("10.0.0.0/7"));
    assert (!valid_cidr ("10.0.1.0"));
    assert (!valid_cidr ("10.0.1.0/"));
    assert (!valid_cidr ("10.0.1.0/24/24"));
    assert (!valid_cidr ("10.0.1.256/24"));
}

void test_in_subnet () {
    /* Network and broadcast addresses are outside; .1 and .254 are inside. */
    assert (!in_subnet ("10.0.1.0", "10.0.1.0/24"));
    assert (in_subnet ("10.0.1.1", "10.0.1.0/24"));
    assert (in_subnet ("10.0.1.254", "10.0.1.0/24"));
    assert (!in_subnet ("10.0.1.255", "10.0.1.0/24"));
    assert (!in_subnet ("10.0.2.1", "10.0.1.0/24"));
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/core/ipv4/round-trip", test_round_trip);
    Test.add_func ("/core/ipv4/cidr-info", test_cidr_info);
    Test.add_func ("/core/ipv4/docker-gateway", test_docker_gateway);
    Test.add_func ("/core/ipv4/valid-ip", test_valid_ip);
    Test.add_func ("/core/ipv4/valid-cidr", test_valid_cidr);
    Test.add_func ("/core/ipv4/in-subnet", test_in_subnet);

    return Test.run ();
}
