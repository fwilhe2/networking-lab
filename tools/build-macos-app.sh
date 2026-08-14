#!/bin/bash
# Build "Networking Lab.app" — a self-contained macOS bundle.
#
#   tools/build-macos-app.sh        # -> dist/NetworkingLab-macos-arm64.zip
#
# Everything the application loads at run time goes inside the bundle: the GTK,
# libadwaita and GLib dylibs (rewritten to @executable_path by dylibbundler),
# the compiled GSettings schemas — ours *and* GTK's, since GtkFileChooser reads
# its own — the icon themes, and the gdk-pixbuf loaders. A machine that has
# never seen Homebrew can run the result; podman is the only thing it still
# needs, and only to boot a lab.
#
# Build dependencies come from Homebrew:
#
#   brew install meson ninja vala gtk4 libadwaita json-glib librsvg gettext \
#       dylibbundler
#
# bash rather than sh: this is macOS-only anyway, and the dylibbundler step
# below needs `pipefail` to notice a failure through a pipe.
#
# The bundle is ad-hoc signed at the end. That is not optional on Apple silicon:
# every rewritten dylib invalidates its signature, and macOS refuses to run an
# arm64 binary with a broken one. It is not a Developer ID signature, so a
# downloaded copy is still quarantined — see the README.
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
build=${BUILD_DIR:-$root/_build-macos}
dist=$root/dist
app="$dist/Networking Lab.app"

case $(uname) in
    Darwin) ;;
    *) echo "$0: this builds a macOS bundle and only runs on macOS" >&2; exit 1 ;;
esac

for tool in meson ninja valac dylibbundler; do
    command -v "$tool" >/dev/null || {
        echo "$0: $tool is not installed — see the header of this script" >&2
        exit 1
    }
done

brew_prefix=$(brew --prefix)

# The version lives in meson.build, debian/changelog and the spec, and now in
# Info.plist as well — read rather than typed, so it cannot become a fourth
# place to forget.
version=$(sed -n 's/^ *version: *.\([0-9][^'"'"']*\).*/\1/p' "$root/meson.build" | head -n1)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/libs"

# ── build and install into the bundle ───────────────────────────────────────
#
# The prefix *is* Contents/Resources, so meson's own install layout becomes the
# bundle's: share/glib-2.0/schemas, share/icons, share/locale. The launcher
# points XDG_DATA_DIRS at it, which is how GLib finds all three.

resources=$app/Contents/Resources

meson setup "$build" --prefix="$resources" --buildtype=release --wipe 2>/dev/null \
    || meson setup "$build" --prefix="$resources" --buildtype=release
meson compile -C "$build"
meson test -C "$build" --print-errorlogs
meson install -C "$build"

mv "$resources/bin/networking-lab" "$app/Contents/MacOS/networking-lab-bin"
rmdir "$resources/bin" 2>/dev/null || true

# ── everything GTK expects to find outside our own install ──────────────────

# GTK reads org.gtk.gtk4.Settings.FileChooser and friends through GSettings; a
# missing schema is an abort, not a warning. Brew's schemas and ours are
# compiled together into one directory.
mkdir -p "$resources/share/glib-2.0/schemas"
cp "$brew_prefix"/share/glib-2.0/schemas/*.xml "$resources/share/glib-2.0/schemas/" 2>/dev/null || true
glib-compile-schemas "$resources/share/glib-2.0/schemas"

# Adwaita carries the symbolic icons the window is built from; hicolor is the
# fallback theme every lookup ends at.
mkdir -p "$resources/share/icons"
for theme in Adwaita hicolor; do
    if [ -d "$brew_prefix/share/icons/$theme" ]; then
        cp -R "$brew_prefix/share/icons/$theme" "$resources/share/icons/"
    fi
done
gtk4-update-icon-cache -q -t -f "$resources/share/icons/Adwaita" 2>/dev/null || true

# The pixbuf loaders, plus the tool that indexes them. The index cannot be
# written here: it holds absolute paths, and the bundle's path is only known
# once someone has downloaded it — so the launcher regenerates it at startup.
loaders=$app/Contents/libs/gdk-pixbuf
mkdir -p "$loaders"
for dir in "$brew_prefix"/lib/gdk-pixbuf-2.0/2.10.0/loaders \
           "$brew_prefix"/opt/librsvg/lib/gdk-pixbuf-2.0/2.10.0/loaders; do
    [ -d "$dir" ] && cp "$dir"/*.so "$loaders/" 2>/dev/null || true
done
mkdir -p "$resources/bin"
cp "$brew_prefix/bin/gdk-pixbuf-query-loaders" "$resources/bin/" 2>/dev/null || true

# ── the launcher ────────────────────────────────────────────────────────────

cat > "$app/Contents/MacOS/networking-lab" <<'LAUNCHER'
#!/bin/sh
# CFBundleExecutable. A bundled GTK application finds nothing on its own: GLib
# looks for schemas, icons and translations along XDG_DATA_DIRS, which is what
# this sets before handing over to the real binary.
set -e

contents=$(cd "$(dirname "$0")/.." && pwd)
resources=$contents/Resources

export XDG_DATA_DIRS="$resources/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GSETTINGS_SCHEMA_DIR="$resources/share/glib-2.0/schemas"

# The loader index holds absolute paths, so it is written per machine on first
# run rather than shipped. Failing is survivable: it costs icons, not the app.
if [ -x "$resources/bin/gdk-pixbuf-query-loaders" ]; then
    export GDK_PIXBUF_MODULEDIR="$contents/libs/gdk-pixbuf"
    cache="${TMPDIR:-/tmp}/networking-lab-loaders.cache"
    if [ ! -s "$cache" ] || [ "$0" -nt "$cache" ]; then
        "$resources/bin/gdk-pixbuf-query-loaders" > "$cache" 2>/dev/null || true
    fi
    [ -s "$cache" ] && export GDK_PIXBUF_MODULE_FILE="$cache"
fi

exec "$contents/MacOS/networking-lab-bin" "$@"
LAUNCHER
chmod +x "$app/Contents/MacOS/networking-lab"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Networking Lab</string>
  <key>CFBundleDisplayName</key>       <string>Networking Lab</string>
  <key>CFBundleIdentifier</key>        <string>io.github.fwilhe2.NetworkingLab</string>
  <key>CFBundleExecutable</key>        <string>networking-lab</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>@VERSION@</string>
  <key>CFBundleVersion</key>           <string>@VERSION@</string>
  <key>LSMinimumSystemVersion</key>    <string>13.0</string>
  <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST
sed -i '' "s/@VERSION@/$version/g" "$app/Contents/Info.plist"

# ── the dylibs ──────────────────────────────────────────────────────────────
#
# -x once per Mach-O that has dependencies of its own: the binary and every
# pixbuf loader. dylibbundler copies what they need into Contents/libs and
# rewrites the load commands to @executable_path/../libs.

# -s: librsvg is a Rust build, so the SVG pixbuf loader names it
# `@rpath/librsvg-2.2.dylib` rather than by path, and dylibbundler resolves an
# @rpath entry only against a search path it was given.
set -- -b -cd -of \
    -s "$brew_prefix/lib" \
    -d "$app/Contents/libs" \
    -p "@executable_path/../libs" \
    -x "$app/Contents/MacOS/networking-lab-bin"
for loader in "$loaders"/*.so; do
    # An unmatched glob comes through as the pattern itself, which is why this
    # tests the file rather than trusting the loop — and why it continues
    # rather than && , which would make the last miss the script's exit status.
    [ -e "$loader" ] || continue
    set -- "$@" -x "$loader"
done
# Asked for a library it cannot find, dylibbundler prompts on stdin — and with
# nobody there to answer it re-asks forever: in CI that was a 500 MB log and a
# job that ran until it was cancelled. Capping the output turns that into a
# fast failure instead, because the write after `head` closes the pipe kills
# it, and the first lines name the library that needs a search path.
if ! dylibbundler "$@" 2>&1 | head -c 100000; then
    echo >&2
    echo "$0: dylibbundler failed — if the output above ends in a prompt," >&2
    echo "a dependency could not be resolved; add its directory with -s." >&2
    exit 1
fi

# ── signing ─────────────────────────────────────────────────────────────────
#
# Every Mach-O, ad-hoc (`-`). This is not cosmetic: rewriting a load command
# invalidates a signature, and macOS refuses to run an arm64 binary whose
# signature is broken — the app would die at launch on a user's machine while
# the build looked perfect.
#
# The bundle itself is deliberately *not* signed. CFBundleExecutable is the
# launcher script, and codesign cannot put a signature in a shell script: it
# accepts the request and then `codesign --verify` fails on the result. A
# bundle signature buys nothing without notarisation, which needs a Developer
# ID this project does not have.
#
# ponytail: no bundle signature, no notarisation. Both need the launcher to
# become a Mach-O — the environment it sets would move into main.vala.
find "$app/Contents/libs" -type f \( -name '*.dylib' -o -name '*.so' \) \
    -exec codesign --force --sign - {} +
codesign --force --sign - "$app/Contents/MacOS/networking-lab-bin"

# ── the zip ─────────────────────────────────────────────────────────────────
#
# ditto rather than zip: it preserves the symlinks and resource forks a signed
# bundle depends on, and unzips on any Mac without an extra tool.
zip=$dist/NetworkingLab-macos-$(uname -m).zip
rm -f "$zip"
(cd "$dist" && ditto -c -k --sequesterRsrc --keepParent "Networking Lab.app" "$zip")

echo
echo "Built $app"
echo "      $zip"
