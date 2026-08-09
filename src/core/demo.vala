/* demo.vala
 *
 * The demo topology of SPEC section 9:
 *
 *   pc1 ── sw1 ── r1 ══ r2 ── sw2 ── srv1
 *
 * with OSPF between the routers. It must generate zero warnings, and after
 * `docker compose up -d` and a minute or so of convergence, pc1 must be able
 * to ping srv1 across both routers.
 *
 * It is defined as a document rather than as constructor calls so it goes
 * through normalize_state () like every other way into the application.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Core {

    public const string DEMO_JSON = """
{
  "projectName": "netlab-demo",
  "images": {
    "router": "quay.io/frrouting/frr:10.1.2",
    "host": "alpine:3.20",
    "server": "python:3.12-alpine"
  },
  "isolated": true,
  "counters": { "router": 2, "switch": 2, "pc": 1, "server": 1, "subnet": 3, "link": 5, "node": 6 },
  "nodes": [
    { "id": "n1", "type": "pc",     "name": "pc1",  "x": 120,  "y": 260, "gw": "10.0.1.1" },
    { "id": "n2", "type": "switch", "name": "sw1",  "x": 300,  "y": 260, "subnet": "10.0.1.0/24" },
    { "id": "n3", "type": "router", "name": "r1",   "x": 480,  "y": 160, "frrExtra": "router ospf\n network 10.0.0.0/8 area 0" },
    { "id": "n4", "type": "router", "name": "r2",   "x": 700,  "y": 160, "frrExtra": "router ospf\n network 10.0.0.0/8 area 0" },
    { "id": "n5", "type": "switch", "name": "sw2",  "x": 880,  "y": 260, "subnet": "10.0.2.0/24" },
    { "id": "n6", "type": "server", "name": "srv1", "x": 1060, "y": 260, "gw": "10.0.2.1", "httpPort": "80" }
  ],
  "links": [
    { "id": "l1", "a": "n1", "b": "n2", "ips": { "n1": "10.0.1.10" } },
    { "id": "l2", "a": "n2", "b": "n3", "ips": { "n3": "10.0.1.1" } },
    { "id": "l3", "a": "n3", "b": "n4", "subnet": "10.0.3.0/24", "ips": { "n3": "10.0.3.1", "n4": "10.0.3.2" } },
    { "id": "l4", "a": "n4", "b": "n5", "ips": { "n4": "10.0.2.1" } },
    { "id": "l5", "a": "n5", "b": "n6", "ips": { "n6": "10.0.2.10" } }
  ]
}
""";

    public State demo_state () {
        try {
            return normalize_json (DEMO_JSON);
        } catch (Error e) {
            /* The demo is a compile-time constant: if it does not normalise,
               the build is broken, not the input. */
            error ("the demo topology is not a valid document: %s", e.message);
        }
    }
}
