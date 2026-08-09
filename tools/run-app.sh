#!/bin/sh
# Launch the app from the build tree.
#
# Two things this handles that a bare `_build/src/ui/networking-lab` does not:
#
#   * GSETTINGS_SCHEMA_DIR — without the compiled schema on the path the app
#     aborts during window construction with "Settings schema … is not
#     installed" (exit 133).
#   * a stale instance — GApplication is single-instance, so launching while an
#     older process is still registered on the session bus just re-presents the
#     old window and exits. Debugging a change against a window built from the
#     previous binary is a confusing way to spend an afternoon.
#
# Pass --x11 to force the X11 backend, which is what tools/drive.py needs in
# order to find and screenshot the window.
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

build_dir=${BUILD_DIR:-_build}
binary="$build_dir/src/ui/networking-lab"

if [ ! -x "$binary" ]; then
    echo "$0: $binary not built — run: meson compile -C $build_dir" >&2
    exit 1
fi

# -x matches the process name only. `pkill -f networking-lab` would also match
# this script's own command line and kill the shell running it.
if pkill -x networking-lab 2>/dev/null; then
    echo "$0: stopped a running instance" >&2
    sleep 1
fi

GSETTINGS_SCHEMA_DIR=$(cd "$build_dir/data" && pwd)
export GSETTINGS_SCHEMA_DIR

for arg do
    case $arg in
        --x11) export GDK_BACKEND=x11; shift ;;
    esac
done

exec "$binary" "$@"
