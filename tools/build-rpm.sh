#!/bin/sh
# Build the RPM inside a Fedora container, so the host needs nothing but
# docker.
#
#   tools/build-rpm.sh              # -> dist/networking-lab-0.1.0-1.fc44.x86_64.rpm
#   FEDORA_VERSION=45 tools/build-rpm.sh
#
# The version is pinned rather than tracking `latest`, so that a build a year
# from now is still the build described in the spec file's comment. Bumping it
# is one variable and a re-run.
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

FEDORA_VERSION=${FEDORA_VERSION:-44}
DOCKER=${DOCKER:-docker}

root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/dist
mkdir -p "$out"

meson_version=$(sed -n 's/^ *version: *.\([0-9][^'"'"']*\).*/\1/p' "$root/meson.build" | head -n1)
spec_version=$(sed -n 's/^Version: *\(.*\)/\1/p' "$root/networking-lab.spec")

if [ "$meson_version" != "$spec_version" ]; then
    echo "$0: meson.build says $meson_version, networking-lab.spec says $spec_version" >&2
    exit 1
fi

echo "Building networking-lab $meson_version for fedora:$FEDORA_VERSION"

$DOCKER run --rm \
    -v "$root:/src:ro,z" \
    -v "$out:/out:z" \
    -e VERSION="$meson_version" \
    "fedora:$FEDORA_VERSION" \
    bash -eux -c '
        dnf -y install rpm-build rpmdevtools "dnf-command(builddep)"
        rpmdev-setuptree

        # %autosetup expects the tarball to unpack into name-version/, so build
        # it under that directory name rather than renaming afterwards.
        mkdir -p "/tmp/networking-lab-$VERSION"
        tar -C /src \
            --exclude=./_build --exclude=./run --exclude=./dist \
            --exclude=./.git --exclude=./_flatpak --exclude=./_repo \
            -cf - . | tar -C "/tmp/networking-lab-$VERSION" -xf -

        tar -C /tmp -czf ~/rpmbuild/SOURCES/"networking-lab-$VERSION.tar.gz" \
            "networking-lab-$VERSION"
        cp /src/networking-lab.spec ~/rpmbuild/SPECS/

        dnf -y builddep ~/rpmbuild/SPECS/networking-lab.spec
        rpmbuild -bb ~/rpmbuild/SPECS/networking-lab.spec

        cp ~/rpmbuild/RPMS/*/networking-lab-*.rpm /out/
        chmod 0644 /out/networking-lab-*.rpm
    '

echo
ls -1 "$out"/networking-lab-*.rpm
