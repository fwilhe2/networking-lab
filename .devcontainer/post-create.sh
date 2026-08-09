#!/usr/bin/env bash
#
# Runs once, after the dev container is created.
set -euo pipefail

# _build is a Docker volume, so Docker creates it root-owned on first use.
if [ ! -w _build ]; then
    sudo chown "$(id -u):$(id -g)" _build
fi

# buildtype=debug is Meson's default, but say it out loud: it is what makes
# Meson pass --debug to valac, which writes #line directives back to the .vala
# sources. Without them gdb stops in generated C instead of your code.
if [ -f _build/build.ninja ]; then
    meson setup --reconfigure _build
else
    meson setup _build --buildtype=debug
fi

meson compile -C _build
