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

Two suites: `data` validates the desktop, AppStream and GSettings files; `core` runs the
Vala unit tests in `tests/`, which link the core library without GTK.

```sh
meson test -C _build --suite core
meson test -C _build --suite data
meson test -C _build validate-gschema   # or validate-desktop-file, validate-metainfo-file
```

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

Four `-Wincompatible-pointer-types` warnings pointing at `src/ui/application.vala` are
unavoidable. valac emits `#pragma GCC diagnostic warning "-Wincompatible-pointer-types"`
into its generated C, which outranks any `-Wno-` flag on the command line. They are
const-correctness artifacts of generated code, not defects in the Vala source. Every other
generated-code warning is already suppressed in the root `meson.build`. Treat these four as
baseline, not regressions.

## Driving the UI

`tools/run-app.sh --x11 &` then `tools/drive.py <scenario>` clicks the canvas over
XTEST and screenshots the window. The canvas is a single Cairo-drawn widget, so no
part of it is reachable through the accessibility tree — coordinates are the only
handle. Three things there are not obvious, and each cost real time before it was
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

## Runtime notes

- `meson devenv` is required to run uninstalled — it puts the compiled schema on the
  GSettings path. Running `_build/src/ui/networking-lab` directly aborts with
  `Settings schema 'io.github.fwilhe2.NetworkingLab' is not installed` (exit 133). The dev container
  exports `GSETTINGS_SCHEMA_DIR` itself, so the bare binary does run there.
- The app icon only resolves after a real install; uninstalled runs fall back.
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
