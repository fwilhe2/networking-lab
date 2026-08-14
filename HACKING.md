# Hacking on Networking Lab

Vala + GTK 4 + libadwaita, built with Meson, following the
[GNOME Human Interface Guidelines](https://developer.gnome.org/hig/). `README.md`
is for people using the application; this is for people changing it.

## Build and test

```sh
meson setup _build
meson compile -C _build
meson test -C _build --print-errorlogs
meson devenv -C _build networking-lab          # run uninstalled
```

`meson devenv` is what puts the compiled GSettings schema on the schema path;
running `_build/src/ui/networking-lab` directly aborts with *Settings schema … is
not installed*.

Four test suites:

| Suite | What it covers |
| --- | --- |
| `data` | Validates the desktop entry, the AppStream metainfo and the GSettings schema |
| `core` | Unit tests for the model, addressing, validation and the compiler — no GTK |
| `lab` | The engine layer, driven against stub `podman`/`docker` the test writes itself |
| `integration` | Boots the demo under a real engine and asserts that OSPF converges |

The first three run by default. The fourth needs podman or docker and is excluded by the
default test setup, so it has to be asked for:

```sh
meson test -C _build --suite core
meson test -C _build --setup engine --suite integration --print-errorlogs
```

It takes about 70 seconds warm, several minutes on a cold image cache, and exits
77 — meson's *skipped* — when no engine or no new enough compose is around.

## Architecture in one paragraph

`src/core/` is a static library with no GTK and no I/O: the document model and
the compiler, which is a pure function from state to `{ yaml, warnings }`. That
is what makes the golden-file test possible — the demo topology must compile
byte-for-byte to `tests/data/demo.docker-compose.yml`. `src/lab/` is everything
that touches the outside world (the container engine, subprocesses, the filesystem) and is
still GTK-free, so the lifecycle is testable from a plain test binary.
`src/ui/` is the application; `src/cli/` is `netlab-compile`, a headless driver
that turns JSON on stdin into a compose file on stdout. Nothing under
`src/core/` may `using Gtk`.

`CLAUDE.md` documents the parts that bite: the app ID being load-bearing in six
places, the coupling between `.ui` templates and Vala GType names, the expected
build warnings, and the VTE dependency being optional on purpose.

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

Two launch configurations are provided. *Run and Debug Networking Lab* is the
ordinary one; *Debug Networking Lab (break on GLib criticals)* sets
`G_DEBUG=fatal-criticals`, so a `g_critical()` traps into the debugger with the
stack that caused it instead of scrolling past in the console. That is the
fastest way to find the origin of a GTK complaint.

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
  is the part of `meson devenv` the app actually needs. `_build/src/ui/networking-lab`
  runs straight from a terminal there — outside the container it still aborts
  without `meson devenv`.
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

## Driving the app for a visual check

The canvas is one Cairo-drawn widget, so nothing inside it is reachable through
the accessibility tree — checking that a selection ring lands on the right
device, or that the rubber band follows the cursor, means clicking coordinates
and looking at the result.

```sh
tools/run-app.sh --x11 --demo &
tools/drive.py --out /tmp/shots select drag link refuse
```

`tools/run-app.sh` puts the compiled GSettings schema on the path and stops any
instance still running — GApplication is single-instance, so without that a
second launch just re-presents the old window and you end up testing the previous
binary. `--x11` forces the X11 backend, which is what gives the window an id to
screenshot. `--demo` seeds the demo topology into a throwaway `XDG_DATA_HOME`, so
a driving session cannot overwrite your real one.

`tools/drive.py` needs `python3-xlib` and ImageMagick's `import`. Run it with
`--help` for the list of scenarios. Two traps are worth knowing in advance: a
focused VTE terminal swallows `F10` and the plain-key shortcuts, so the menu is
unreachable until you click the canvas; and a screenshot of a window that is not
visible is the last frame that was drawn, not the current state.

## Packaging

```sh
tools/build-deb.sh     # Debian 13, in a debian:trixie container
tools/build-rpm.sh     # Fedora 44, in a fedora:44 container
```

Both build inside the target distribution's container, run the test suite as
part of the build, and drop the result in `dist/`. `DIST=…` moves the output;
`DEBIAN_VERSION=` and `FEDORA_VERSION=` move the target. The packaging metadata
is `debian/` and `networking-lab.spec`; `CLAUDE.md` has the notes on both, and
`RELEASING.md` has the checklist for cutting a release.

## Container image

`Containerfile` is a multi-stage build: the first stage compiles and runs the
validation tests, the second carries only the runtime libraries and the installed
binary.

```sh
podman build -f Containerfile -t networking-lab .   # or: docker build …
```

Because the test suite runs inside the builder stage, a successful image build is
also a passing build.

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

For a pure X11 host, swap the Wayland socket for
`-e DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix`.

## Continuous integration

`.github/workflows/ci.yml` runs five jobs on push, PR and manual dispatch:

| Job | What it does |
| --- | --- |
| **Build & test** | Compiles in a `debian:trixie` container and runs `meson test`; uploads `meson-logs/` on failure |
| **Flatpak** | Builds against `org.gnome.Sdk//50` and uploads an installable `.flatpak` bundle |
| **Container image** | Builds `Containerfile` with buildx, pushing to GHCR on non-PR events |
| **Debian package** | Runs `tools/build-deb.sh` and uploads the `.deb` |
| **RPM package** | Runs `tools/build-rpm.sh` and uploads the `.rpm` |

The GHCR push uses the built-in `GITHUB_TOKEN` via the job's `packages: write`
permission, so there are no secrets to configure. The two package jobs run the
same scripts a developer runs, so a green job means the documented command works
rather than some CI-only variant of it.

## Layout

```
meson.build                     project setup, config.h, compiler flags
src/
  config.vapi                   exposes config.h values to Vala
  core/                         document model and compiler — no GTK, no I/O
    ipv4.vala names.vala        addressing and naming helpers
    state.vala model.vala       the document
    serialize.vala normalize.vala   JSON in and out, and the trust boundary
    derive.vala validate.vala   networks, interfaces, diagnostics
    compile.vala demo.vala      the compose file, and the demo topology
  lab/                          the engine, subprocesses, the lab directory — no GTK
    paths.vala engine.vala compose.vala session.vala
  cli/netlab-compile.vala       headless driver for the core library
  ui/
    application.vala window.vala window.ui    the shell
    canvas.vala palette.vala properties.vala  the editor
    lab-controller.vala terminal.vala         running it
    generate-dialog.vala shortcuts-dialog.vala preferences-dialog.vala
tests/                          unit tests, plus lab.integration.sh
data/                           desktop entry, AppStream, GSettings, icons
po/                             translation infrastructure
tools/                          run-app.sh, drive.py, build-deb.sh, build-rpm.sh
debian/  networking-lab.spec    distribution packaging
Containerfile                   multi-stage container build
.devcontainer/  .vscode/        dev container and editor wiring
PLAN.md  RELEASING.md  CLAUDE.md
```

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

The executable and the Meson project are named `networking-lab`, but the Meson
variables in `src/meson.build` and the GResource `c_name` use `networking_lab` —
a hyphen is valid in neither identifier.

## Expected build warnings

Five `-Wincompatible-pointer-types` warnings, four pointing at
`src/ui/application.vala` and one at `src/lab/engine.vala`. They are
const-correctness artifacts of valac's generated C, not defects in the Vala
source, and cannot be suppressed from the command line: valac writes
`#pragma GCC diagnostic warning "-Wincompatible-pointer-types"` into the C it
produces, which outranks any `-Wno-` flag. Every other generated-code warning is
already silenced in the top-level `meson.build`. Treat these five as the
baseline, not as regressions.

## Version floors

Vala ≥ 0.56, Meson ≥ 1.0, GLib ≥ 2.72, json-glib ≥ 1.6, GTK ≥ 4.12,
libadwaita ≥ 1.5. VTE (`vte-2.91-gtk4`, which itself wants GTK ≥ 4.14) is
optional: without it the application builds without the embedded terminal.

libadwaita is pinned at 1.5 for `AdwDialog`, `AdwAboutDialog` and
`AdwPreferencesDialog`. There is deliberately no keyboard-shortcuts *window*:
`GtkShortcutsWindow` is deprecated as of GTK 4.18 and its replacement
`AdwShortcutsDialog` needs libadwaita 1.8, so `?` opens a hand-rolled dialog
instead.

## License

GPL-3.0-or-later. If you relicense, three places have to move together or the
application will advertise a licence it is not under:

| Place | Value |
| --- | --- |
| SPDX headers in `src/*.vala`, `src/config.vapi` | `GPL-3.0-or-later` |
| `<project_license>` in `data/io.github.fwilhe2.NetworkingLab.metainfo.xml.in` | `GPL-3.0-or-later` |
| `license_type` in `src/ui/application.vala` | `Gtk.License.GPL_3_0` |

GTK's `GPL_3_0` means "version 3 **or later**"; the version-3-only enum is the
separate `GPL_3_0_ONLY`. The `<metadata_license>` in the AppStream file is
`CC0-1.0`, which covers the metadata rather than the code, and is the Flathub
convention.

## Reference

- [Vala documentation](https://docs.vala.dev)
- [GTK 4 API reference](https://docs.gtk.org/gtk4/)
- [libadwaita API reference](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/)
- [GNOME Human Interface Guidelines](https://developer.gnome.org/hig/)
