#!/usr/bin/env bash
#
# Runs every time the dev container starts.
set -euo pipefail

# Docker re-creates the /dev/dri nodes on a private tmpfs and drops the host's
# ACL while doing it, so the container user cannot open the render node and Mesa
# falls back to llvmpipe with a wall of libEGL warnings. Widening the mode here
# only touches the container's own /dev — the host nodes keep their 0660+ACL.
if [ -d /dev/dri ]; then
    sudo chmod a+rw /dev/dri/card* /dev/dri/render* 2>/dev/null || true
fi
