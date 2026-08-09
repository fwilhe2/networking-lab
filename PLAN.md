# Implementation plan — NetLab Designer as a GNOME app

Port the [NetLab Designer](https://github.com/fwilhe2/NetLab-Designer) reference
implementation (a single dependency-free `index.html`) to this repository as a native
Vala + GTK 4 + libadwaita application. `SPEC.md` in that repository is the contract; its
`docs/demo.docker-compose.yml` is the byte-level fixture that proves the port correct.

## The one structural rule

SPEC §1 and §11 require the compiler to be a pure function `state → { yaml, warnings }`,
importable and testable in isolation from the UI. Here that means a **separate build
target**, not merely a separate file:

| Target | Dependencies |
| --- | --- |
| `src/core/` — static library | glib, gobject, gio, json-glib. **No GTK** |
| `src/ui/` — the application | core + gtk4 + libadwaita |
| `src/cli/` — `netlab-compile` | core only; stdin JSON → stdout YAML |
| `tests/` — unit tests | core only |

Nothing under `src/core/` may `using Gtk`. Enforce it from Phase 0; it is what keeps the
golden-file test possible and the compiler re-implementable.

The CLI target is small and pays for itself immediately: it makes the golden-file
comparison a shell one-liner and gives the lab a headless path.

## File layout

```
src/core/
  ipv4.vala        ipToInt/intToIp, validIp, validCidr, CidrInfo, inSubnet, dockerGateway
  names.vala       sanitizeName, uniqueName
  model.vala       Node, Link, State, Counters; allocSubnet, nextFreeIp
  serialize.vala   State ↔ JSON via json-glib
  normalize.vala   normalizeState — the single trust boundary
  derive.vala      networks (§2.4), interfaces (§2.5)
  validate.vala    ordered Diagnostic list (§5)
  compile.vala     text emission (§6)
  demo.vala        the §9 topology as a constant

src/ui/
  window.vala            header, mode buttons, status bar, wiring
  canvas.vala            Gtk.DrawingArea + Cairo: draw, zoom, hit-test, gestures
  palette.vala           four Gtk.DragSource items
  properties.vala        the context-sensitive panel (§8.4)
  generate-dialog.vala   validation list + YAML + copy/download
  document.vala          state + history + autosave, emits `changed`

src/cli/
  netlab-compile.vala

tests/
  data/demo.docker-compose.yml   copied from the reference repo
  *.vala                         GLib.Test cases, linked against core only
```

`Document` is the only mutable object the UI touches. Every mutation follows the same
shape — `push_history()` → mutate → emit `changed` → redraw, re-render the panel,
persist — which is precisely SPEC §4.1 and keeps undo honest by construction.

## Phases

Each phase ends at a gate that can be checked before moving on.

### Phase 0 — build plumbing

- Add the `json-glib-1.0` dependency.
- Split `src/meson.build` into the core / ui / cli targets above; add a `core` test suite.
- Remove the template's demo code: the toast action, `demo_row`, the `demo-setting`
  schema key and its preferences row.

*Gate:* `meson test -C _build` green, the app still builds and runs.

### Phase 1 — IPv4 and name helpers

SPEC §3 and the `sanitizeName` / `uniqueName` rules in §4. Direct port; all arithmetic on
`uint32`.

*Gate:* checklist items 1–5 as `Test.add_func` cases —
`dockerGateway("10.0.1.0/24") == "10.0.1.254"`, `validCidr` rejects `/30`, `inSubnet`
excludes network and broadcast, `sanitizeName("***") == "dev"`,
`uniqueName("r1", {r1,r2}) == "r12"`.

### Phase 2 — model, JSON, normalization

SPEC §2 and §7.1. Counters are rebuilt from the ids actually in use, never trusted from
the file; subnet allocation for switches and p2p links happens **last**, after the
rebuild.

*Gate:* checklist items 6–7 — `normalizeState` throws on `null`, `42`, `"nope"`, `{}`,
`{nodes:[]}`, `{links:[]}`; drops dangling, self and switch↔switch links; de-duplicates
`pc1` → `pc12` → `pc13`; discards invalid addresses and unknown types.

### Phase 3 — derived model and validation

SPEC §2.4, §2.5, §5. Emission order is load-bearing: switches in node order first, then
p2p networks in link order. Interface numbering walks `state.links` in array order.

*Gate:* checklist item 8 — the demo's networks are `['p2p_r1_r2','sw1','sw2']`, and r1's
interfaces are `eth0 → sw1 10.0.1.1`, `eth1 → p2p_r1_r2 10.0.3.1`.

### Phase 4 — the compiler

SPEC §6, emitted as text lines through a `StringBuilder`. No YAML serializer: the inline
`# eth0` comments, the flow-map `configs` entries and the block scalars are part of the
contract.

*Gate — the decisive one:* compile the §9 demo topology and assert byte equality against
`tests/data/demo.docker-compose.yml`. Plus checklist items 11–14: `priority: 100` on
eth0 and `99` on eth1, `network_mode: none` for an unconnected device, `isolated`
toggling exactly one `internal: true` per network, the four error classes, and `frrExtra`
indented with tabs expanded to two spaces.

**After this phase the port is provably correct with no UI at all.**

### Phase 5 — canvas, read-only

`Gtk.DrawingArea` inside a `Gtk.ScrolledWindow`; logical size 2200 × 1400; full Cairo
redraw on every change, as the reference does. 28px grid, device glyphs with name labels,
switch subnet label, links as straight lines with each endpoint's last octet at 28% and
72%. Zoom sets the content size to `2200 × z` and applies `cr.scale (z, z)`.

*Gate:* load the demo topology and see it drawn correctly.

### Phase 6 — editing

- Palette `Gtk.DragSource` → canvas `Gtk.DropTarget` carrying the device type as a string.
- `GestureClick` for selection and link-building, `GestureDrag` for moves,
  `EventControllerKey` for nudging and shortcuts, `EventControllerScroll` for Ctrl+wheel
  zoom.
- Snap to 14px unless `Alt` is held; clamp to a 60px margin.
- History: whole-document JSON snapshots, capped at 60, pushed immediately before each
  mutation.
- Properties panel with reject-and-revert on invalid input (SPEC §8.4) — never silently
  coerce.

*Gate:* build the demo topology by hand in the UI, generate, and get the golden file.

### Phase 7 — application shell

Generate dialog (`Adw.Dialog` with a monospace `TextView`), `Gtk.FileDialog` for import /
export / download, `Gdk.Clipboard` for copy, `Adw.AlertDialog` for the two confirmations,
autosave to `$XDG_DATA_HOME/networking-lab/autosave.netlab.json`, theme preference in
GSettings, and the shortcut help dialog.

### Phase 8 — integration test

Port `test/lab.integration.sh` from the reference repo: boot the demo, wait for OSPF to
converge, assert `pc1 → 10.0.2.10` answers, both r1 interfaces are addressed, the OSPF
neighbour is `Full`, and `ping 1.1.1.1` **fails** (isolation). Requires docker, so it
stays out of the default `meson test` run.

## Deliberate divergences from the spec

SPEC.md describes browser behaviour that conflicts with the GNOME HIG in three places.
The proposed column is the GNOME-side choice.

| SPEC | Proposed here |
| --- | --- |
| §8.8 — the status bar is the *only* notification channel | `AdwToast` for transient results; keep a status label for mode and hover state |
| §8.7 — light by default, `prefers-color-scheme` deliberately ignored | Follow the system via `Adw.StyleManager`, with an override in preferences |
| §8.1/§8.4 — fixed three-column layout, 132px and 300px | `AdwOverlaySplitView`, collapsing at narrow widths per the existing breakpoint |

## Known wrinkles

- **No `AdwShortcutsDialog`.** It needs libadwaita 1.8; the floor here is 1.5 and the
  development machine has 1.7.6. `GtkShortcutsWindow` is deprecated as of GTK 4.18. The
  `?` help dialog will therefore be a hand-rolled `AdwDialog` containing
  `AdwPreferencesGroup` rows.
- **Sharing a Vala static library across targets** needs `--vapidir` and `--pkg` wiring so
  the app, the CLI and the tests all see the generated `.vapi`. If that proves awkward,
  the fallback is to compile the core sources into each target directly — same isolation
  guarantee, marginally slower builds.
- **Interface numbering follows link order** (SPEC §11). Reordering links renumbers
  `eth<i>`. Carried over as-is; making link order explicit in the UI is a possible later
  improvement, not part of this port.
