#!/bin/sh
# Build the Debian package inside a Debian stable container, so the host needs
# nothing but docker and the result does not depend on what happens to be
# installed here.
#
#   tools/build-deb.sh              # -> dist/networking-lab_0.1.0_amd64.deb
#   DEBIAN_VERSION=sid tools/build-deb.sh
#
# The source tree is copied into the container rather than built in place: a
# Debian build writes its artifacts to the *parent* directory and leaves
# debian/.debhelper and friends behind, none of which belongs in a git
# checkout.
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

DEBIAN_VERSION=${DEBIAN_VERSION:-trixie}
DOCKER=${DOCKER:-docker}

root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/dist
mkdir -p "$out"

# The version lives in three files that must agree. A mismatch here is much
# easier to read than the one dpkg-buildpackage produces three minutes later.
meson_version=$(sed -n 's/^ *version: *.\([0-9][^'"'"']*\).*/\1/p' "$root/meson.build" | head -n1)
changelog_version=$(sed -n '1s/^networking-lab (\([^)]*\)).*/\1/p' "$root/debian/changelog")

if [ "$meson_version" != "$changelog_version" ]; then
    echo "$0: meson.build says $meson_version, debian/changelog says $changelog_version" >&2
    exit 1
fi

echo "Building networking-lab $meson_version for debian:$DEBIAN_VERSION"

$DOCKER run --rm \
    -v "$root:/src:ro,z" \
    -v "$out:/out:z" \
    -e DEBIAN_FRONTEND=noninteractive \
    "debian:$DEBIAN_VERSION" \
    bash -eux -c '
        apt-get update
        apt-get install -y --no-install-recommends \
            build-essential devscripts equivs dpkg-dev lintian

        # Everything except the build trees and the git history. A configured
        # _build carries absolute host paths and would only confuse meson.
        mkdir -p /build
        tar -C /src \
            --exclude=./_build --exclude=./run --exclude=./dist \
            --exclude=./.git --exclude=./_flatpak --exclude=./_repo \
            -cf - . | tar -C /build -xf -
        cd /build

        # mk-build-deps reads debian/control directly, which apt-get build-dep
        # cannot do without deb-src entries the container image does not have.
        mk-build-deps -i -r -t "apt-get -y --no-install-recommends" debian/control

        dpkg-buildpackage -b -us -uc

        lintian --no-tag-display-limit ../networking-lab_*.deb || true

        cp ../networking-lab_*.deb ../networking-lab_*.buildinfo ../networking-lab_*.changes /out/
        chmod 0644 /out/networking-lab_*
    '

echo
ls -1 "$out"/networking-lab_*.deb
