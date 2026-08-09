/* model.vala
 *
 * Constants and the device type, shared by everything in the core library.
 *
 * Nothing in this directory may depend on GTK: the compiler has to stay a pure
 * function over the document so it can be tested without a UI. See PLAN.md.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Core {

    /* Canvas geometry (SPEC 8.2). Logical units; zoom scales them for display. */
    public const int CANVAS_WIDTH = 2200;
    public const int CANVAS_HEIGHT = 1400;
    public const int GRID = 28;
    public const int SNAP = 14;
    public const int CANVAS_MARGIN = 60;

    public const double[] ZOOM_STEPS = { 0.5, 0.65, 0.8, 1.0, 1.25, 1.5, 2.0 };

    /* Whole-document snapshots, oldest dropped past this many (SPEC 4.1). */
    public const int HISTORY_LIMIT = 60;

    /* SPEC 2.1 defaults. */
    public const string DEFAULT_PROJECT_NAME = "netlab";
    public const string DEFAULT_ROUTER_IMAGE = "quay.io/frrouting/frr:10.1.2";
    public const string DEFAULT_HOST_IMAGE = "alpine:3.20";
    public const string DEFAULT_SERVER_IMAGE = "python:3.12-alpine";

    public errordomain TopologyError {
        /* normalize_state () refuses only what is not a topology at all. */
        NOT_A_TOPOLOGY,
    }

    public enum DeviceType {
        ROUTER,
        SWITCH,
        PC,
        SERVER;

        /* The identifier used in the document and in exported JSON. */
        public string id () {
            switch (this) {
                case ROUTER: return "router";
                case SWITCH: return "switch";
                case PC:     return "pc";
                case SERVER: return "server";
                default:     assert_not_reached ();
            }
        }

        /* The prefix new device names are built from (SPEC 4). */
        public string prefix () {
            switch (this) {
                case ROUTER: return "r";
                case SWITCH: return "sw";
                case PC:     return "pc";
                case SERVER: return "srv";
                default:     assert_not_reached ();
            }
        }

        /* A switch is a docker network, not a container: it is never a service. */
        public bool is_service () {
            return this != SWITCH;
        }

        /* Unknown types are dropped on import rather than rejected (SPEC 7.1). */
        public static bool try_parse (string s, out DeviceType type) {
            switch (s) {
                case "router": type = ROUTER; return true;
                case "switch": type = SWITCH; return true;
                case "pc":     type = PC;     return true;
                case "server": type = SERVER; return true;
                default:       type = ROUTER; return false;
            }
        }
    }
}
