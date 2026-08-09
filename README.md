# Networking Lab

A Vala + GTK 4 + libadwaita application built with Meson, following the
[GNOME Human Interface Guidelines](https://developer.gnome.org/hig/).

## Build and run

```sh
meson setup _build
meson compile -C _build
meson devenv -C _build networking-lab
```

`meson devenv` puts the compiled GSettings schema on the schema path, so the app
runs from the build tree without installing. The app icon only resolves once
installed, so the welcome page shows a fallback icon until then.

```sh
meson test -C _build      # validates the desktop, AppStream and GSettings files
meson install -C _build   # installs into the configured prefix
```

## Developing in VS Code

`.devcontainer/` describes a container with the toolchain, `gdb` and
`vala-language-server` in it; `.vscode/` wires that up to the editor's build,
test, run and debug commands. You need the
[Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
extension, Docker, and a Linux host running Wayland or X11 — the container draws
on your display server, so the app opens a window on your desktop like any other.

Open the folder, run **Dev Containers: Reopen in Container**, wait for the image
to build, then press **F5**.

| Command | What it does |
| --- | --- |
| **F5** | Build, then run under `gdb`. Breakpoints in `.vala` files work |
| **Ctrl+Shift+B** | `meson compile -C _build` |
| **Run Task → meson: test** | `meson test -C _build --print-errorlogs` |
| **Run Task → meson: run** | Start the app without the debugger |

Two launch configurations are provided. *Run and Debug Networking Lab* is the ordinary
one; *Debug Networking Lab (break on GLib criticals)* sets `G_DEBUG=fatal-criticals`, so
a `g_critical()` traps into the debugger with the stack that caused it instead of
scrolling past in the console. That is the fastest way to find the origin of a
GTK complaint.

Breakpoints land in Vala rather than in generated C because Meson passes
`--debug` to valac for `buildtype=debug`, which writes `#line` directives back to
the `.vala` sources. Keep the build in `debug` or you will be stepping through
`_build/src/ui/networking-lab.p/*.c`.

Some details worth knowing before you change the setup:

- **The build directory is a Docker volume**, not the host's `_build`. A build
  tree configured on the host records host paths and breaks when Meson re-runs
  from `/workspaces`, so the two are deliberately kept apart. Building on the
  host and in the container at the same time is fine.
- **`GSETTINGS_SCHEMA_DIR` is preset** in the container to `_build/data`, which
  is the part of `meson devenv` the app actually needs. `_build/src/ui/networking-lab` runs
  straight from a terminal there — outside the container it still aborts without
  `meson devenv`.
- **The host's `XDG_RUNTIME_DIR` is mounted whole**, which brings the Wayland
  socket, the session bus, the accessibility bus and PipeWire with it. Sharing
  the session bus means `GApplication` single-instance rules span host and
  container: if the app is already running on your desktop, launching it in the
  container re-presents that window and exits. Drop `DBUS_SESSION_BUS_ADDRESS`
  from `containerEnv` for an isolated instance.
- **`--device=/dev/dri` gives hardware GL.** Docker re-creates the device nodes
  without the host's ACL, so `post-start.sh` widens their mode inside the
  container — that touches the container's private `/dev`, not the host's. On a
  machine with no `/dev/dri`, remove the `--device` line and Mesa falls back to
  software rendering.
- **GLib and GTK frames show as `???`** in backtraces, because Debian ships those
  libraries without debug symbols. Adding `ENV DEBUGINFOD_URLS=https://debuginfod.debian.net`
  to the dev `Dockerfile` and `"text": "set debuginfod enabled on"` to the
  `setupCommands` in `launch.json` fetches them on demand, at the cost of a slow
  first debug session.

To use Podman instead of Docker, point the extension at it with
`"dev.containers.dockerPath": "podman"` in your user settings.

### Driving the app for a visual check

The canvas is one Cairo-drawn widget, so nothing inside it is reachable through
the accessibility tree — checking that a selection ring lands on the right
device, or that the rubber band follows the cursor, means clicking coordinates
and looking at the result.

```sh
tools/run-app.sh --x11 &
tools/drive.py --out /tmp/shots select drag link refuse
```

`tools/run-app.sh` puts the compiled GSettings schema on the path and stops any
instance still running — GApplication is single-instance, so without that a
second launch just re-presents the old window and you end up testing the
previous binary. `--x11` forces the X11 backend, which is what gives the window
an id to screenshot.

`tools/drive.py` needs `python3-xlib` and ImageMagick's `import`. Run it with
`--help` for the list of scenarios.

### Flatpak

```sh
flatpak install flathub org.gnome.Platform//50 org.gnome.Sdk//50
flatpak-builder --user --install --force-clean _flatpak io.github.fwilhe2.NetworkingLab.json
flatpak run io.github.fwilhe2.NetworkingLab
```

### Container

`Containerfile` is a multi-stage build: the first stage compiles and runs the
validation tests, the second carries only the runtime libraries and the
installed binary.

```sh
podman build -f Containerfile -t networking-lab .   # or: docker build -f Containerfile -t networking-lab .
```

Because the test suite runs inside the builder stage, a successful image build
is also a passing build.

Running a GTK app from a container means handing it your compositor socket and
session bus. On a Wayland host:

```sh
U=$(id -u)
podman run --rm \
    --userns=keep-id \
    --security-opt label=disable \
    --tmpfs /run/user/$U \
    -e XDG_RUNTIME_DIR=/run/user/$U \
    -e WAYLAND_DISPLAY \
    -e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$U/bus \
    -v $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:/run/user/$U/$WAYLAND_DISPLAY \
    -v $XDG_RUNTIME_DIR/bus:/run/user/$U/bus \
    networking-lab
```

Two things to expect:

- **`Unable to connect to the accessibility bus`.** The at-spi bus is not shared
  into the container. The app runs fine; screen readers will not see it. Sharing
  `$XDG_RUNTIME_DIR/at-spi` fixes it. The image deliberately does *not* set
  `GTK_A11Y=none` to hide the message — that would disable accessibility.
- **The container may exit immediately with status 0.** Sharing the host session
  bus means `GApplication` single-instance rules apply: if an instance is already
  registered — including one you started on the host, or a container that has not
  finished shutting down — the new process just re-presents the existing window
  and exits. Drop `DBUS_SESSION_BUS_ADDRESS` and the bus mount to get an isolated
  instance.

For a pure X11 host, swap the Wayland socket for `-e DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix`.

## Continuous integration

`.github/workflows/ci.yml` runs three jobs on push, PR and manual dispatch:

| Job | What it does |
| --- | --- |
| **Build & test** | Compiles in a `debian:trixie` container and runs `meson test`; uploads `meson-logs/` on failure |
| **Flatpak** | Builds against `org.gnome.Sdk//50` and uploads an installable `.flatpak` bundle |
| **Container image** | Builds `Containerfile` with buildx, pushing to GHCR on non-PR events |

The container job needs no setup. The GHCR push uses the built-in `GITHUB_TOKEN`
via the job's `packages: write` permission, so no secrets to configure.

## Layout

```
meson.build                     project setup, config.h, compiler flags
src/
  config.vapi                   exposes config.h values to Vala
  core/                         the document model and compiler — no GTK
    model.vala                  device type, canvas and document constants
  cli/
    netlab-compile.vala         headless driver for the core library
  ui/
    meson.build                 the executable, deps, GResource bundle
    main.vala                   entry point, gettext setup
    application.vala            AdwApplication: actions, accels, about dialog
    window.vala                 main window: GSettings bindings, win.* actions
    window.ui                   main window template + primary menu
    preferences-dialog.vala     preferences dialog
    preferences-dialog.ui       preferences template
    networking-lab.gresource.xml  bundles the .ui files into the binary
tests/                          unit tests for core, suite `core`
data/
  *.desktop.in                  desktop entry
  *.metainfo.xml.in             AppStream metadata (needed by software centres)
  *.gschema.xml                 GSettings schema
  icons/hicolor/...             app icon and symbolic icon
po/                             translation infrastructure
tools/
  run-app.sh                    run from the build tree, schema path and all
  drive.py                      drive the window over XTEST, screenshot it
io.github.fwilhe2.NetworkingLab.json
                                Flatpak manifest
Containerfile                   multi-stage container build
.dockerignore                   keeps build dirs out of the container context
.devcontainer/
  devcontainer.json             dev container: display sockets, GPU, build volume
  Dockerfile                    toolchain, gdb, vala-language-server
  post-create.sh                first-run Meson configure
  post-start.sh                 per-start /dev/dri permission fix
.vscode/
  tasks.json                    build, test, run; valac problem matcher
  launch.json                   gdb launch configs
  settings.json                 file associations, Meson build folder
  extensions.json               recommended extensions
.github/workflows/ci.yml        CI: build & test, Flatpak, container image
PLAN.md                         the implementation plan
CLAUDE.md                       notes for Claude Code sessions
LICENSE                         GPL-3.0 text
```

## What the scaffolding provides

| Area | Where |
| --- | --- |
| `AdwApplicationWindow` + `AdwToolbarView` + `AdwHeaderBar` | `src/ui/window.ui` |
| Adaptive layout via `AdwBreakpoint` | `src/ui/window.ui` |
| Boxed lists (`AdwPreferencesGroup` + rows) | `src/ui/window.ui` |
| Toasts (`AdwToastOverlay`) | `src/ui/window.vala` |
| `AdwAboutDialog` / `AdwPreferencesDialog` | `src/ui/application.vala` |
| GSettings bindings, incl. window geometry | `src/ui/window.vala` |
| `GtkTemplate` / `GtkChild` in Vala | `src/ui/window.vala` |
| Translatable strings with `_()` | throughout |

## HIG conventions baked in

- **Adaptive.** The window's minimum size is 360×294 — the phone form factor the
  HIG asks apps to scale down to. Below 550sp a breakpoint moves the view
  switcher from the header bar into a bottom bar, so it stays thumb-reachable.
- **Header bar.** No separate menu bar. A single primary menu (`GtkMenuButton`
  with `primary=True`) sits at the end of the header bar and holds only
  app-level items.
- **Content width.** Long-form content sits in an `AdwClamp` so lines never
  stretch past a comfortable measure.
- **Feedback.** Confirmation uses a toast, which is transient and never blocks.
- **Shortcuts.** `Ctrl+,` preferences, `Ctrl+Q` quit, `Ctrl+W` close window.
- **Empty state.** The home view uses `AdwStatusPage`, the standard pattern for
  welcome and empty states.
- **Metadata.** Ships a desktop entry, an AppStream file with an OARS content
  rating, and both a full-colour and a symbolic icon.

### Not included

No keyboard-shortcuts window. `GtkShortcutsWindow` is deprecated as of GTK 4.18,
and its replacement, `AdwShortcutsDialog`, arrived in libadwaita 1.8 — this
project targets 1.5. On libadwaita ≥ 1.8, add an `AdwShortcutsDialog` and wire
it to `app.shortcuts` with the `Ctrl+?` accel.

## The app ID

`io.github.fwilhe2.NetworkingLab` and its slash form
`/io/github/fwilhe2/NetworkingLab` appear in six places that must agree — a
mismatch aborts the process at runtime rather than failing the build:

| Place | Form |
| --- | --- |
| `application_id` in `meson.build` | dotted |
| `resource_base_path` in `src/ui/application.vala` | slashed |
| `prefix` in `src/ui/networking-lab.gresource.xml` | slashed |
| `[GtkTemplate (ui = ...)]` in `window.vala`, `preferences-dialog.vala` | slashed |
| schema `id` and `path` in `data/*.gschema.xml` | dotted and slashed |
| `data/` filenames, icon filenames, `Icon=` in the desktop entry | dotted |

The GType names in the `.ui` templates (`NetworkingLabWindow`,
`NetworkingLabPreferencesDialog`) are the Vala `namespace` + `class`
concatenated, and must keep matching the Vala side.

Note that the executable and the Meson project are named `networking-lab`, but
the Meson variables in `src/meson.build` and the GResource `c_name` use
`networking_lab` — a hyphen is not valid in either identifier.

## Note on build warnings

The build emits a few `-Wincompatible-pointer-types` warnings pointing at
`src/ui/application.vala`. They come from const-correctness in valac's generated C,
not from your code, and cannot be suppressed from the command line: valac writes
`#pragma GCC diagnostic warning "-Wincompatible-pointer-types"` into the C it
produces, which outranks any `-Wno-` flag. All other generated-code warnings are
already silenced in the top-level `meson.build`.

## Requirements

Vala ≥ 0.56, Meson ≥ 1.0, GTK ≥ 4.12, libadwaita ≥ 1.5, GLib ≥ 2.72.

## License

GPL-3.0-or-later. The full text is in [`LICENSE`](LICENSE), and every source
file carries an `SPDX-License-Identifier: GPL-3.0-or-later` header.

If you relicense, three places have to move together or the app will advertise
a licence it isn't under:

| Place | Value |
| --- | --- |
| SPDX headers in `src/*.vala`, `src/config.vapi` | `GPL-3.0-or-later` |
| `<project_license>` in `data/io.github.fwilhe2.NetworkingLab.metainfo.xml.in` | `GPL-3.0-or-later` |
| `license_type` in `src/ui/application.vala` | `Gtk.License.GPL_3_0` |

Note that GTK's `GPL_3_0` means "version 3 **or later**" — the version-3-only
enum is the separate `GPL_3_0_ONLY`. The `<metadata_license>` in the AppStream
file is `CC0-1.0`; that covers the metadata itself, not the code, and is the
Flathub convention.

## Reference

- [Vala documentation](https://docs.vala.dev)
- [GTK 4 API reference](https://docs.gtk.org/gtk4/)
- [libadwaita API reference](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/)
- [GNOME Human Interface Guidelines](https://developer.gnome.org/hig/)
