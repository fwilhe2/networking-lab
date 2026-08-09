# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A template GNOME application — Vala + GTK 4 + libadwaita, built with Meson, following the
GNOME Human Interface Guidelines. It exists to be renamed and grown into a real app, so
`Starter` / `starter` / `com.example.Starter` are placeholders, not product names.

## Commands

```sh
meson setup _build
meson compile -C _build
meson test -C _build --print-errorlogs
meson devenv -C _build starter          # run uninstalled
```

Three tests exist, all in suite `data`; run one by name:

```sh
meson test -C _build validate-gschema   # or validate-desktop-file, validate-metainfo-file
meson test -C _build --suite data
```

`meson compile` reconfigures itself after a `meson.build` edit; `meson setup --wipe _build`
is only needed when that fails.

```sh
podman build -f Containerfile -t starter .   # builder stage runs meson test — a green build is a green suite
flatpak-builder --user --install --force-clean _flatpak com.example.Starter.json
```

`.vscode/tasks.json` wraps the same Meson commands (`meson: build` is the default build
task); `.vscode/launch.json` runs the binary under gdb. Both assume the build directory is
`_build`.

## Architecture

### The app ID is a cross-cutting string

`com.example.Starter` and its slash form `/com/example/Starter` are load-bearing in six
places that must agree. A mismatch fails at **runtime**, not build time:

| Place | Form |
| --- | --- |
| `meson.build` `application_id` | dotted → `config.h` → `Config.APP_ID` |
| `src/application.vala` `resource_base_path` | slashed |
| `src/starter.gresource.xml` `prefix` | slashed |
| `[GtkTemplate (ui = ...)]` in `window.vala`, `preferences-dialog.vala` | slashed + filename |
| `data/com.example.Starter.gschema.xml` schema `id` and `path` | dotted and slashed |
| `data/` filenames, icon filenames, `.desktop` `Icon=` | dotted |

`GLib.Settings (Config.APP_ID)` binds the schema to the ID, so a mismatch aborts the
process during window construction.

### .ui templates are coupled to Vala by GType name

`<template class="StarterWindow" parent="AdwApplicationWindow">` resolves to `namespace
Starter` + `class Window`. Renaming either side without the other breaks template loading
silently. Same for `StarterPreferencesDialog`.

### config.h ↔ config.vapi

Root `meson.build` generates `config.h` with `configure_file`; `src/config.vapi` redeclares
those symbols with `cprefix = ""` so `Config.APP_ID` compiles down to the bare `APP_ID`
macro. Adding a build-time constant means editing both files.

### Adding a .ui file takes three edits

1. `src/starter.gresource.xml` — bundle it into the binary
2. `po/POTFILES` — so its strings get extracted
3. `src/meson.build` — only when a matching `.vala` is added

valac type-checks `[GtkTemplate]` and `[GtkChild]` only because `src/meson.build` passes
`--gresources=`. Without that flag a wrong child id becomes a runtime failure instead of a
compile error.

## Version floors

`meson.build` pins libadwaita >= 1.5 for `AdwDialog` / `AdwAboutDialog` /
`AdwPreferencesDialog`. There is deliberately **no keyboard-shortcuts window**:
`GtkShortcutsWindow` is deprecated as of GTK 4.18, and its replacement
`AdwShortcutsDialog` needs libadwaita 1.8. Don't add one without raising the floor.

## Expected build warnings — do not "fix"

Four `-Wincompatible-pointer-types` warnings pointing at `src/application.vala` are
unavoidable. valac emits `#pragma GCC diagnostic warning "-Wincompatible-pointer-types"`
into its generated C, which outranks any `-Wno-` flag on the command line. They are
const-correctness artifacts of generated code, not defects in the Vala source. Every other
generated-code warning is already suppressed in the root `meson.build`. Treat these four as
baseline, not regressions.

## Runtime notes

- `meson devenv` is required to run uninstalled — it puts the compiled schema on the
  GSettings path. Running `_build/src/starter` directly aborts with
  `Settings schema 'com.example.Starter' is not installed` (exit 133). The dev container
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

`README.md` carries the rename procedure: rename files whose *names* carry the ID, then
`sed` file contents. It is verified end-to-end (Meson build, container build, the CI
workflow's manifest reference and the `.vscode` / `.devcontainer` paths all survive it). If you change the layout, re-verify it — a
missed file surfaces as a confusing Meson or runtime error rather than an obvious one.
