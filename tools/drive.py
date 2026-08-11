#!/usr/bin/env python3
"""Drive the running app over XTEST and screenshot what happens.

The canvas is a single Cairo-drawn widget, so nothing in it is reachable
through the accessibility tree: clicking a device means clicking a coordinate.
This script does that, and captures the window after each step, which is the
only way to check things like "does the rubber band follow the cursor" or "is
the selection ring where the device is".

    meson compile -C _build
    tools/run-app.sh --x11 --demo &
    tools/drive.py select drag link

Every scenario below clicks the demo topology's devices, so the app has to be
started with `--demo`: it restores the last session at startup rather than
loading the demo, and driving the menu item instead would mean answering the
"replace the topology?" confirmation only sometimes.

Requirements: python3-xlib, ImageMagick (`import`), and an X11 or XWayland
display. The app must be running under the X11 backend — a Wayland client has
no window id to grab, which is what `tools/run-app.sh --x11` is for.

Three traps, all of which cost real debugging time before they were understood:

  * `import` takes the input focus with it, so every synthetic event after a
    screenshot lands somewhere else. shot() restores the focus.
  * GApplication is single-instance: launching a second copy re-presents the
    first window. run-app.sh kills the old one first.
  * Coordinates are window-relative, and the canvas origin depends on the
    palette width and header height. Pass --canvas-origin if the layout moves;
    the default was measured against a device of known document position.

The file chooser is deliberately not driven from here. It is a separate
toplevel, so shot() would capture the window behind it and then take the focus
away from it; and it is GTK's widget rather than this project's code.

SPDX-License-Identifier: GPL-3.0-or-later
"""

import argparse
import subprocess
import sys
import time

try:
    from Xlib import X, XK, display
    from Xlib.ext import xtest
except ImportError:
    sys.exit("python3-xlib is not installed: apt-get install python3-xlib")

WINDOW_TITLE = "Networking Lab"

# The primary menu, top to bottom. Only the order matters: menu() walks it with
# the arrow keys, because a popover's coordinates depend on the window size.
MENU_ITEMS = ["Import", "Export", "Load Demo", "Clear",
              "Keyboard Shortcuts", "Preferences", "About"]

# Where document (0,0) sits inside the captured window image. Measured from a
# device of known position — pc1 in the demo topology is at 120,260.
DEFAULT_CANVAS_ORIGIN = (208, 101)

# Palette item centres, window-relative.
PALETTE = {"router": (135, 140), "switch": (135, 202), "pc": (135, 263), "server": (135, 324)}

d = display.Display()
root = d.screen().root


def find_window(title):
    for top in root.query_tree().children:
        for win in [top] + list(top.query_tree().children):
            try:
                name = win.get_wm_name()
            except Exception:
                continue
            if name and title in name:
                return win
    return None


class App:
    """A running window, addressed in document coordinates."""

    def __init__(self, win, canvas_origin, out_dir):
        self.win = win
        self.cx, self.cy = canvas_origin
        self.out = out_dir
        self.shots = 0

        geom = win.get_geometry()
        origin = win.translate_coords(root, 0, 0)
        self.ox, self.oy = -origin.x, -origin.y
        self.width, self.height = geom.width, geom.height
        self.focus()

    # ── addressing ──────────────────────────────────────────────────

    def win_xy(self, x, y):
        """Window-relative to absolute screen coordinates."""
        return self.ox + x, self.oy + y

    def doc_xy(self, x, y):
        """Document coordinates to absolute screen coordinates."""
        return self.ox + self.cx + x, self.oy + self.cy + y

    def visible(self, x, y):
        """Is this document point inside the canvas viewport?"""
        wx, wy = self.cx + x, self.cy + y
        return 0 <= wx < self.width and 0 <= wy < self.height

    # ── input ───────────────────────────────────────────────────────

    def focus(self):
        self.win.set_input_focus(X.RevertToParent, X.CurrentTime)
        d.sync()
        time.sleep(0.3)

    def move(self, x, y):
        xtest.fake_input(d, X.MotionNotify, x=x, y=y)
        d.sync()
        time.sleep(0.05)

    def click(self, x, y, button=1):
        self.move(x, y)
        xtest.fake_input(d, X.ButtonPress, button)
        d.sync()
        time.sleep(0.05)
        xtest.fake_input(d, X.ButtonRelease, button)
        d.sync()
        time.sleep(0.2)

    def drag(self, x1, y1, x2, y2, steps=12):
        self.move(x1, y1)
        xtest.fake_input(d, X.ButtonPress, 1)
        d.sync()
        for i in range(1, steps + 1):
            self.move(x1 + (x2 - x1) * i // steps, y1 + (y2 - y1) * i // steps)
        xtest.fake_input(d, X.ButtonRelease, 1)
        d.sync()
        time.sleep(0.3)

    def key(self, name, shift=False, ctrl=False, settle=0.25):
        code = d.keysym_to_keycode(XK.string_to_keysym(name))
        mods = []
        if ctrl:
            mods.append(d.keysym_to_keycode(XK.string_to_keysym("Control_L")))
        if shift:
            mods.append(d.keysym_to_keycode(XK.string_to_keysym("Shift_L")))
        for m in mods:
            xtest.fake_input(d, X.KeyPress, m)
        xtest.fake_input(d, X.KeyPress, code)
        xtest.fake_input(d, X.KeyRelease, code)
        for m in reversed(mods):
            xtest.fake_input(d, X.KeyRelease, m)
        d.sync()
        time.sleep(settle)

    def drop_device(self, kind, x, y):
        """Drag a palette item onto a document position."""
        self.drag(*self.win_xy(*PALETTE[kind]), *self.doc_xy(x, y))

    def menu(self, item):
        """Activate an item of the primary menu, by name.

        F10 opens it because the header's GtkMenuButton has primary=True, and
        the keyboard walks it: a popover's item coordinates depend on the
        window size and the theme, so clicking them is not reproducible.

        Opening the menu already focuses its first item, so reaching item N
        takes N presses, not N + 1.
        """
        self.key("F10")
        for _ in range(MENU_ITEMS.index(item)):
            self.key("Down")
        self.key("Return")

    def resize(self, width, height):
        """Resize the window, which is how the breakpoints are exercised."""
        self.win.configure(width=width, height=height)
        d.sync()
        time.sleep(0.5)
        self.width, self.height = width, height

    # ── output ──────────────────────────────────────────────────────

    def shot(self, name):
        self.shots += 1
        path = f"{self.out}/{self.shots:02d}-{name}.png"
        subprocess.run(["import", "-window", hex(self.win.id), path], check=True)
        print(f"  {path}")
        # `import` takes the focus with it; without this every later synthetic
        # event is delivered somewhere else.
        self.focus()


# ── scenarios ───────────────────────────────────────────────────────
#
# Positions are the demo topology's: pc1 120,260 · sw1 300,260 · r1 480,160
# · r2 700,160 · sw2 880,260 · srv1 1060,260.

def scenario_select(app):
    app.click(*app.doc_xy(480, 160))
    app.shot("selected-r1")


def scenario_drag(app):
    app.drag(*app.doc_xy(480, 160), *app.doc_xy(480, 430))
    app.shot("dragged-r1")
    app.key("z", ctrl=True)
    app.shot("undone")


def scenario_palette(app):
    app.drop_device("router", 300, 620)
    app.shot("dropped-router")


def scenario_link(app):
    """pc1 to r1 — not connected in the demo, so this is a new p2p network."""
    app.key("l")
    app.shot("link-mode")
    app.click(*app.doc_xy(120, 260))
    app.move(*app.doc_xy(320, 420))
    app.shot("rubber-band")
    app.click(*app.doc_xy(480, 160))
    app.shot("linked")


def scenario_refuse(app):
    """A switch is already one segment, so switch-to-switch must be refused."""
    app.drop_device("switch", 300, 620)
    app.key("l")
    app.click(*app.doc_xy(300, 260))
    app.click(*app.doc_xy(300, 620))
    app.shot("refused")


def scenario_delete(app):
    app.click(*app.doc_xy(480, 160))
    app.key("Delete")
    app.shot("deleted-r1")


def scenario_generate(app):
    app.key("g")
    app.shot("generate")
    app.key("Escape")


def scenario_shortcuts(app):
    app.menu("Keyboard Shortcuts")
    app.shot("shortcuts")
    app.key("Escape")


def scenario_narrow(app):
    """The breakpoints: both sidebars become overlays behind their toggles."""
    app.resize(860, 700)
    app.shot("narrow-properties-collapsed")
    app.resize(640, 700)
    app.shot("narrow-both-collapsed")
    app.resize(1100, 720)
    app.shot("wide-again")


SCENARIOS = {
    "select": scenario_select,
    "drag": scenario_drag,
    "palette": scenario_palette,
    "link": scenario_link,
    "refuse": scenario_refuse,
    "delete": scenario_delete,
    "generate": scenario_generate,
    "shortcuts": scenario_shortcuts,
    "narrow": scenario_narrow,
}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("scenario", nargs="*", default=["select"],
                        help=f"one or more of: {', '.join(SCENARIOS)} (default: select)")
    parser.add_argument("--out", default=".", help="directory for screenshots")
    parser.add_argument("--canvas-origin", default=None,
                        help="X,Y of document 0,0 within the window image")
    args = parser.parse_args()

    unknown = [s for s in args.scenario if s not in SCENARIOS]
    if unknown:
        parser.error(f"unknown scenario(s): {', '.join(unknown)}")

    win = find_window(WINDOW_TITLE)
    if win is None:
        sys.exit(f"no window titled {WINDOW_TITLE!r} — is it running under "
                 f"the X11 backend? (tools/run-app.sh --x11)")

    origin = DEFAULT_CANVAS_ORIGIN
    if args.canvas_origin:
        origin = tuple(int(v) for v in args.canvas_origin.split(","))

    app = App(win, origin, args.out)
    print(f"window {app.width}x{app.height} at {app.ox},{app.oy}, "
          f"canvas origin {origin[0]},{origin[1]}")

    for name in args.scenario:
        print(f"{name}:")
        SCENARIOS[name](app)


main()
