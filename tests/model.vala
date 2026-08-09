/* model.vala
 *
 * Unit tests for the core library. These link against libnetlab-core only —
 * if a test here ever needs GTK, something has leaked out of the UI layer.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

void test_device_type_ids () {
    assert (DeviceType.ROUTER.id () == "router");
    assert (DeviceType.SWITCH.id () == "switch");
    assert (DeviceType.PC.id () == "pc");
    assert (DeviceType.SERVER.id () == "server");
}

void test_device_type_prefixes () {
    assert (DeviceType.ROUTER.prefix () == "r");
    assert (DeviceType.SWITCH.prefix () == "sw");
    assert (DeviceType.PC.prefix () == "pc");
    assert (DeviceType.SERVER.prefix () == "srv");
}

void test_device_type_parsing () {
    DeviceType type;

    assert (DeviceType.try_parse ("router", out type));
    assert (type == DeviceType.ROUTER);

    assert (DeviceType.try_parse ("srv", out type) == false);
    assert (DeviceType.try_parse ("", out type) == false);
    assert (DeviceType.try_parse ("Router", out type) == false);
}

void test_only_switches_are_networks () {
    /* A switch is one L2 segment, emitted as a docker network rather than as a
       container. Every other type becomes a service. */
    assert (DeviceType.SWITCH.is_service () == false);
    assert (DeviceType.ROUTER.is_service ());
    assert (DeviceType.PC.is_service ());
    assert (DeviceType.SERVER.is_service ());
}

void test_canvas_constants () {
    /* Nodes snap to half-grid steps, and the margin has to leave room for the
       selection ring and both labels. */
    assert (SNAP * 2 == GRID);
    assert (CANVAS_MARGIN > GRID);
    assert (CANVAS_WIDTH == 2200 && CANVAS_HEIGHT == 1400);

    /* Zoom steps are ascending and include an unscaled step. */
    var previous = 0.0;
    var found_identity = false;
    foreach (var step in ZOOM_STEPS) {
        assert (step > previous);
        previous = step;
        if (step == 1.0) {
            found_identity = true;
        }
    }
    assert (found_identity);
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/core/device-type/ids", test_device_type_ids);
    Test.add_func ("/core/device-type/prefixes", test_device_type_prefixes);
    Test.add_func ("/core/device-type/parsing", test_device_type_parsing);
    Test.add_func ("/core/device-type/services", test_only_switches_are_networks);
    Test.add_func ("/core/constants/canvas", test_canvas_constants);

    return Test.run ();
}
