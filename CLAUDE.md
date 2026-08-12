# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A GNOME application — Vala + GTK 4 + libadwaita, built with Meson, following the GNOME
Human Interface Guidelines. It started from a template, so the UI is still the scaffolded
welcome page; the networking functionality is yet to be written.

Names in use: display name `Networking Lab`, Vala namespace / GType prefix `NetworkingLab`,
executable and Meson project `networking-lab`, app ID `io.github.fwilhe2.NetworkingLab`.
Note that Meson variables in `src/meson.build` and the GResource `c_name` use
`networking_lab` with an underscore — a hyphen is invalid in a Meson identifier and in a
C symbol.

## Commands

```sh
meson setup _build
meson compile -C _build
meson test -C _build --print-errorlogs
meson devenv -C _build networking-lab          # run uninstalled
```

Four suites: `data` validates the desktop, AppStream and GSettings files; `core` runs the
Vala unit tests in `tests/`, which link the core library without GTK; `lab` unit-tests the
lab layer against a stub `docker`; `integration` boots the demo lab under real docker.

```sh
meson test -C _build --suite core
meson test -C _build --suite lab
meson test -C _build --suite data
meson test -C _build validate-gschema   # or validate-desktop-file, validate-metainfo-file
meson test -C _build --setup docker --suite integration --print-errorlogs
```

`integration` is **excluded from the default run** — `tests/meson.build` declares two test
setups for exactly that: the default one lists it in `exclude_suites`, and `--setup docker`
does not. A `--suite integration` without `--setup docker` therefore selects nothing, which
looks like a typo but is the exclusion working. The one test in it,
`tests/lab.integration.sh`, generates the demo topology with `netlab-compile --demo`, runs
`docker compose up`, waits for OSPF to converge and asserts end-to-end reachability plus
isolation; it takes about 70s warm and several minutes cold, and exits 77 (meson's
"skipped") when docker or a compose plugin ≥ 2.23.1 is missing. It can also be run
directly: `tests/lab.integration.sh [path/to/netlab-compile]`. Meson runs tests from the
build directory and passes that path relative to it, so the script must not `cd`.

`meson compile` reconfigures itself after a `meson.build` edit; `meson setup --wipe _build`
is only needed when that fails.

```sh
podman build -f Containerfile -t networking-lab .   # builder stage runs meson test — a green build is a green suite
flatpak-builder --user --install --force-clean _flatpak io.github.fwilhe2.NetworkingLab.json
```

`.vscode/tasks.json` wraps the same Meson commands (`meson: build` is the default build
task); `.vscode/launch.json` runs the binary under gdb. Both assume the build directory is
`_build`.

## Architecture

### The core library must not depend on GTK

`src/core/` builds a static library (`netlab_core_dep`) against glib/gobject/gio/json-glib
only. `src/ui/`, `src/cli/` and `tests/` all consume it. This is the load-bearing structural
rule of the port — SPEC §1 requires the compiler to be a pure `state → {yaml, warnings}`
function testable without a UI, and the golden-file test in phase 4 depends on it. If
anything under `src/core/` ever needs `using Gtk`, it belongs in `src/ui/` instead.

Meson resolves the generated `.vapi` automatically from `link_with:` inside
`declare_dependency`, so consumers need no `--vapidir` wiring.

`netlab-compile` is deliberately not installed while it is still a stub.

### The lab layer is where the outside world starts

`src/lab/` (`netlab_lab_dep`) holds everything `src/core/` is forbidden to do: subprocesses,
the filesystem, docker. It links core and is still GTK-free, which is what lets
`tests/lab.vala` drive the whole lifecycle from a plain test binary. The split is the point —
core stays a pure function of the document, so the golden-file comparison keeps working.

`Session` derives its state from what `docker compose ps` reports, never from what it
believes it did. That is what lets it adopt a lab left running by an earlier run, and what
keeps a container that died on boot from being drawn as running. `container_name:` in the
generated file is what makes a device name and a container name the same string, which is
the whole basis of `Session.is_running (device)`.

`src/ui/lab-controller.vala` is the only file in `src/ui/` that knows docker exists. It owns
the probe, one `Lab.Session`, and a 2-second poll that runs **only while a lab is up** — a
lab that is down changes only when this application starts it, so an idle poll would be a
subprocess every two seconds for no news. The window asks it two questions: "can I run?"
(`can_run`, `availability`, `unavailable_reason`) and "is this device up?" (`mark_for`).

Two consequences of the lab being a view rather than part of the document: it is never
undone or autosaved, and **closing the window does not stop the lab**. The containers are
adopted again on the next start, which is the point — but a driving session that starts a
lab leaves it running, even though `tools/run-app.sh --demo` throws its `XDG_DATA_HOME`
away. The compose file goes with the temp directory; the containers do not. `docker compose
-p netlab-demo down -v` cleans up.

`tests/lab.vala` writes a stub `docker` into a temp directory and puts it **earlier on
PATH**; behaviour is driven by `NETLAB_STUB_*` environment variables (compose version,
daemon reachability, which subcommand fails, canned `ps` output), and every invocation is
appended to a log the tests assert against. `XDG_DATA_HOME` is redirected into the same
sandbox — set in `install_stub ()` before `Test.init`, because GLib caches the data
directory on first use. A failing run keeps the sandbox and prints its path.

### VTE is an optional dependency, on purpose

`src/ui/terminal.vala` is compiled either way. `src/ui/meson.build` looks for
`vte-2.91-gtk4` with `required: false` and adds `--define=HAVE_VTE` when it is there;
everything version-dependent is behind that one flag inside that one file, so the rest of
`src/ui/` sees the same `DeviceTerminal` and `TerminalPane` in both builds. Without VTE the
terminal is an `AdwStatusPage` printing the `docker exec` command to run yourself.

It is optional because **the GNOME 50 runtime does not ship `vte-2.91-gtk4`** — checked, not
assumed — and the Flatpak cannot reach the docker socket anyway, so a terminal there would
be dead weight. Making it required would mean building VTE from source in the manifest to
support a feature that sandbox cannot use.

Note also that `vte-2.91-gtk4` pulls in `gtk4 >= 4.14` through pkg-config, above this
project's own 4.12 floor. On an older GTK the dependency is simply not found and the build
falls back — which is the intended outcome, not a configure error.

The dependency has to be added in **four** places, and the runtime one is the one that gets
forgotten — a missing shared library does not fail an image build, only the app at launch:

| Place | Package |
| --- | --- |
| `.github/workflows/ci.yml` | `libvte-2.91-gtk4-dev` |
| `Containerfile` builder stage | `libvte-2.91-gtk4-dev` |
| `Containerfile` runtime stage | `libvte-2.91-gtk4-0` |
| `.devcontainer/Dockerfile` | `libvte-2.91-gtk4-dev` |

### The app ID is a cross-cutting string

`io.github.fwilhe2.NetworkingLab` and its slash form `/io/github/fwilhe2/NetworkingLab` are load-bearing in six
places that must agree. A mismatch fails at **runtime**, not build time:

| Place | Form |
| --- | --- |
| `meson.build` `application_id` | dotted → `config.h` → `Config.APP_ID` |
| `src/ui/application.vala` `resource_base_path` | slashed |
| `src/ui/networking-lab.gresource.xml` `prefix` | slashed |
| `[GtkTemplate (ui = ...)]` in `window.vala`, `preferences-dialog.vala` | slashed + filename |
| `data/io.github.fwilhe2.NetworkingLab.gschema.xml` schema `id` and `path` | dotted and slashed |
| `data/` filenames, icon filenames, `.desktop` `Icon=` | dotted |

`GLib.Settings (Config.APP_ID)` binds the schema to the ID, so a mismatch aborts the
process during window construction.

### .ui templates are coupled to Vala by GType name

`<template class="NetworkingLabWindow" parent="AdwApplicationWindow">` resolves to `namespace
NetworkingLab` + `class Window`. Renaming either side without the other breaks template loading
silently. Same for `NetworkingLabPreferencesDialog`.

### config.h ↔ config.vapi

Root `meson.build` generates `config.h` with `configure_file`; `src/config.vapi` redeclares
those symbols with `cprefix = ""` so `Config.APP_ID` compiles down to the bare `APP_ID`
macro. Adding a build-time constant means editing both files.

### Adding a .ui file takes three edits

1. `src/ui/networking-lab.gresource.xml` — bundle it into the binary
2. `po/POTFILES` — so its strings get extracted
3. `src/ui/meson.build` — only when a matching `.vala` is added

valac type-checks `[GtkTemplate]` and `[GtkChild]` only because `src/ui/meson.build` passes
`--gresources=`. Without that flag a wrong child id becomes a runtime failure instead of a
compile error.

## Version floors

`meson.build` pins libadwaita >= 1.5 for `AdwDialog` / `AdwAboutDialog` /
`AdwPreferencesDialog`. There is deliberately **no keyboard-shortcuts window**:
`GtkShortcutsWindow` is deprecated as of GTK 4.18, and its replacement
`AdwShortcutsDialog` needs libadwaita 1.8. Don't add one without raising the floor.

## Expected build warnings — do not "fix"

Five `-Wincompatible-pointer-types` warnings — four pointing at `src/ui/application.vala`,
one at `src/lab/docker.vala` (`g_subprocess_launcher_spawnv`) — are unavoidable. valac emits
`#pragma GCC diagnostic warning "-Wincompatible-pointer-types"`
into its generated C, which outranks any `-Wno-` flag on the command line. They are
const-correctness artifacts of generated code, not defects in the Vala source. Every other
generated-code warning is already suppressed in the root `meson.build` — including
`-Wno-unused-function`, which async methods need: valac emits a ref/unref pair per captured
block and uses neither when the block only reads. Treat these five as baseline, not
regressions.

## Driving the UI

`tools/run-app.sh --x11 --demo &` then `tools/drive.py <scenario>` clicks the canvas
over XTEST and screenshots the window. The canvas is a single Cairo-drawn widget, so
no part of it is reachable through the accessibility tree — coordinates are the only
handle. `--demo` is needed because the app restores the last session at startup
rather than loading the demo; it seeds the autosave inside a throwaway
`XDG_DATA_HOME`, so a driving session cannot overwrite the real one. Menu items are
reached with `App.menu()`, which opens the primary menu with `F10` and walks it with
the arrow keys — a popover's coordinates move with the window size. The file chooser
is deliberately not driven: it is a separate toplevel, so a screenshot would capture
the window behind it and then steal its focus.

**A focused VTE terminal swallows the keyboard**, including `F10` and the plain-key
shortcuts. That is correct terminal behaviour, but it means `App.menu()` does nothing once a
terminal has focus — click the canvas first. Clicking the canvas *does* move the focus
(`on_pressed` calls `grab_focus`), so one click is enough. Adding an item to the primary
menu also means updating `MENU_ITEMS` in `tools/drive.py`: `menu()` walks the popover by
index, and a popover is a separate surface that `import` does not capture, so a wrong index
fails silently and invisibly.

A screenshot of a window that is not visible — moved off-screen, occluded, on another
workspace — is the **last frame that was drawn**, not the current state. GTK stops
redrawing what nobody can see, so `import` happily returns a stale picture of a perfectly
healthy app. If the UI looks frozen, check `ps -o wchan` first: an idle main loop sits in
`do_sys_poll`.

Three more things there are not obvious, and each cost real time before it was
understood:

- **`import` takes the input focus with it.** Every synthetic event after a
  screenshot lands somewhere else unless the focus is restored, which makes a
  perfectly good interaction look broken.
- **GApplication is single-instance.** Launching while an older process is still
  registered re-presents the *old* window, so you end up checking a change against
  the previous binary. `run-app.sh` kills it first.
- **`pkill -f networking-lab` matches the shell running it** and kills your own
  session. Use `pkill -x networking-lab`.

Layout bugs in particular only show up on screen: `hexpand` propagates *up* from
children unless set explicitly, a `GtkCheckButton`'s own label does not wrap so its
minimum width becomes the panel's, and a `GtkScrolledWindow` with `hscrollbar-policy:
NEVER` adopts its child's full natural width. All three squeezed the canvas out of
the window at some point.

The three columns are two nested `AdwOverlaySplitView`s, collapsed by two
`AdwBreakpoint`s in `window.ui`. Two rules govern them: when several breakpoints
apply libadwaita uses the **last** one, so the wider condition has to be declared
first; and a setter's value is **reverted** when its breakpoint stops applying,
which is what brings the sidebars back on widening. `min-sidebar-width` and
`max-sidebar-width` are pinned to the same value for the palette because the default
width fraction would otherwise stretch it.

## Runtime notes

- `meson devenv` is required to run uninstalled — it puts the compiled schema on the
  GSettings path. Running `_build/src/ui/networking-lab` directly aborts with
  `Settings schema 'io.github.fwilhe2.NetworkingLab' is not installed` (exit 133). The dev container
  exports `GSETTINGS_SCHEMA_DIR` itself, so the bare binary does run there.
- The app icon only resolves after a real install; uninstalled runs fall back.
- The session is autosaved to `$XDG_DATA_HOME/networking-lab/autosave.netlab.json` and
  restored at startup, so a run picks up whatever the previous one left behind. It goes
  back through `normalize_state`, exactly like an imported file — the copy on disk is as
  hand-editable as any other. A failure starts empty rather than reporting.
- `gnome.post_install()` skips schema compilation and icon caching when `DESTDIR` is set.
  The `Containerfile` compensates by running `glib-compile-schemas` and
  `gtk4-update-icon-cache` against the staged tree — keep that in sync if install rules change.
- The container image intentionally does not set `GTK_A11Y=none`. The accessibility-bus
  warning when running containerized is expected; silencing it would disable accessibility.

## Dev container

`.devcontainer/` is a *development* environment and shares nothing with `Containerfile`,
which builds a runtime image. Four things there are not obvious:

- **`_build` is a Docker volume**, mounted over `${containerWorkspaceFolder}/_build`. A
  build tree configured on the host bakes in host absolute paths and breaks the moment
  Meson re-runs under `/workspaces`, so host and container must not share one. Docker
  creates the volume root-owned; `post-create.sh` chowns it before configuring.
- **`vala-language-server` is built from source** in a first stage, because Debian does not
  package it. Bumping `DEBIAN_VERSION` may require bumping `VLS_VERSION` with it — VLS
  links against a specific `libvala-0.56`.
- **The whole host `XDG_RUNTIME_DIR` is bind-mounted** at `/run/user/1000`, which is what
  makes Wayland, the session bus and at-spi work. That also means `GApplication`
  single-instance rules span host and container.
- **`post-start.sh` chmods `/dev/dri/*`** because Docker re-creates those nodes on a
  private tmpfs and drops the host ACL that granted the user access. It runs every start,
  not just on create, since `/dev` is rebuilt each time. It cannot affect the host nodes.

Debugging maps to `.vala` rather than generated C only because `buildtype=debug` makes
Meson pass `--debug` to valac. Anything that changes the build type breaks that.

The valac problem matcher in `.vscode/tasks.json` resolves paths relative to
`${workspaceFolder}/_build`, because valac prints them relative to the directory ninja
runs in.

## Renaming

If the app ID or project name ever changes again, rename the files whose *names* carry the
ID first, then `sed` file contents — and afterwards check `src/meson.build`, whose variable
names and `c_name` must stay valid identifiers. A missed file surfaces as a confusing Meson
or runtime error rather than an obvious one, so re-verify the Meson build, the container
build, the CI workflow's manifest reference and the `.vscode` / `.devcontainer` paths.
