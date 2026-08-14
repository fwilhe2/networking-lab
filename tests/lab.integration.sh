#!/usr/bin/env bash
#
# End-to-end check: generate the demo topology's compose file with netlab-compile, boot
# it, and assert that the lab actually works — OSPF converges between the two routers and
# pc1 reaches srv1 two hops away, while the internet stays out of reach.
#
# This is the only test that needs a container engine, so it is kept out of the default
# `meson test` run by the test setups in tests/meson.build:
#
#   meson test -C _build --setup engine --suite integration --print-errorlogs
#
# It can also be run directly, against a build tree or an explicit binary:
#
#   tests/lab.integration.sh [path/to/netlab-compile]
#
# Exit 77 (meson's "skipped") when no engine or no new enough compose is around; inline
# `configs.content` in the generated file needs compose v2.23.1+.
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Deliberately no `cd`: meson runs this from the build directory and passes the binary's
# path relative to it, so changing directory would break the argument it just handed us.
# The fallback is anchored to the source tree instead.
COMPILE="${1:-${NETLAB_COMPILE:-$(dirname "$0")/../_build/src/cli/netlab-compile}}"
PROJECT="netlab-selftest"

pass=0
fail=0
note() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

skip() { printf 'skipping: %s\n' "$1" >&2; exit 77; }

[ -x "$COMPILE" ] || { echo "not executable: $COMPILE — build it first" >&2; exit 1; }
# podman or docker, picked the same way the application picks it (src/lab/engine.vala):
# NETLAB_ENGINE wins, otherwise the first one on PATH, podman first. `podman compose`
# delegates to the same compose v2 binary, which is what is actually depended on here.
ENGINE="${NETLAB_ENGINE:-}"
if [ -z "$ENGINE" ]; then
  for candidate in podman docker; do
    if command -v "$candidate" >/dev/null; then ENGINE="$candidate"; break; fi
  done
fi
[ -n "$ENGINE" ] || skip "no container engine (podman or docker) is installed"

# `<engine> compose version --short` prints e.g. 2.29.7, or fails outright when only the
# standalone v1 docker-compose is around. The generated file is v2-plugin syntax.
compose_version="$($ENGINE compose version --short 2>/dev/null | tail -n1 || true)"
[ -n "$compose_version" ] || skip "$ENGINE has no compose v2"

# sort -V puts the older of the two first; if that is not 2.23.1, the found version is
# older than the floor.
if [ "$(printf '%s\n2.23.1\n' "$compose_version" | sort -V | head -n1)" != "2.23.1" ]; then
  skip "compose $compose_version is older than 2.23.1 (no inline configs.content)"
fi

$ENGINE info >/dev/null 2>&1 || skip "$ENGINE is not reachable"

WORK="$(mktemp -d)"
COMPOSE="$WORK/docker-compose.yml"

cleanup() {
  note "Tearing down"
  $ENGINE compose -p "$PROJECT" -f "$COMPOSE" down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

note "Generating the compose file from the demo topology"
"$COMPILE" --demo >"$COMPOSE" 2>"$WORK/diagnostics"
if grep -q '^error:' "$WORK/diagnostics"; then
  sed 's/^/  /' "$WORK/diagnostics" >&2
  bad "the demo topology generated validation errors"
  exit 1
fi
ok "generated with no validation errors"

check "compose file passes schema validation" \
  "$ENGINE compose -p '$PROJECT' -f '$COMPOSE' config"

note "Starting the lab"
$ENGINE compose -p "$PROJECT" -f "$COMPOSE" up -d --quiet-pull
ok "containers started"

# FRR takes a while here: interfaces come up, then the OSPF adjacency reaches Full
# (~45s), and only after the next SPF run are routes installed (~60s). Poll the thing we
# actually care about — end-to-end reachability — rather than the adjacency state, which
# goes Full well before the data plane works.
note "Waiting for the lab to converge (can take ~90s)"
converged=false
for _ in $(seq 1 60); do
  if $ENGINE exec pc1 ping -c1 -W2 10.0.2.10 >/dev/null 2>&1; then converged=true; break; fi
  sleep 2
done
$converged && ok "pc1 reached srv1 (routing converged)" || bad "no end-to-end connectivity within 120s"

note "Checking the data plane"
check "all four containers are running" \
  "[ \$($ENGINE compose -p '$PROJECT' -f '$COMPOSE' ps --status running -q | wc -l) -eq 4 ]"

check "r1 has both interfaces addressed" \
  "$ENGINE exec r1 vtysh -c 'show int brief' | grep -q '10.0.3.1/24'"

check "r1 sees r2 in OSPF state Full" \
  "$ENGINE exec r1 vtysh -c 'show ip ospf neighbor' | grep -q Full"

check "vtysh is quiet (no missing-config errors)" \
  "! $ENGINE exec r1 vtysh -c 'show version' 2>&1 | grep -q \"Can't open configuration file\""

check "r1 learned sw2's subnet via OSPF" \
  "$ENGINE exec r1 vtysh -c 'show ip route ospf' | grep -q '10.0.2.0/24'"

check "pc1 has its default route" \
  "$ENGINE exec pc1 ip route | grep -q 'default via 10.0.1.1'"

check "pc1 pings its gateway" \
  "$ENGINE exec pc1 ping -c2 -W3 10.0.1.1"

check "pc1 pings srv1 across two routers" \
  "$ENGINE exec pc1 ping -c2 -W3 10.0.2.10"

check "srv1 serves HTTP to pc1" \
  "$ENGINE exec pc1 wget -qO- -T5 http://10.0.2.10/"

check "the lab is isolated from the internet" \
  "! $ENGINE exec pc1 ping -c1 -W3 1.1.1.1"

note "Result: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
