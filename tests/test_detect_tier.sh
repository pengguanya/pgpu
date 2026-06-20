#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/../lib/log.sh"
. "$HERE/../lib/detect.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Simulate the 2026-06-20 box: podman 4.9.3, no /etc/cdi write, no subuid, NFS home
get() { printf '%s\n' "$1" | grep "^$2=" | cut -d= -f2-; }
detect_podman_version() { echo "4.9.3"; }   # stub
detect_etc_cdi_writable() { return 1; }      # stub: no sudo
detect_subuid() { return 1; }                # stub: missing
detect_home_is_nfs() { return 0; }           # stub: NFS
out="$(PGPU_STORE_BASE="$tmp/store" pgpu_resolve_tier)"
assert_eq "$(get "$out" TIER)" "2" "old podman + no sudo -> tier 2"
assert_eq "$(get "$out" IGNORE_CHOWN)" "1" "no subuid -> ignore_chown"
assert_eq "$(get "$out" STORE_REDIRECT)" "1" "NFS home -> redirect"
assert_eq "$(get "$out" NEED_STATIC_PODMAN)" "1" "tier 2 needs static podman"

# Simulate a clean modern box: podman 5.8.3, /etc/cdi writable, subuid present, local home
detect_podman_version() { echo "5.8.3"; }
detect_etc_cdi_writable() { return 0; }
detect_subuid() { return 0; }
detect_home_is_nfs() { return 1; }
out="$(pgpu_resolve_tier)"
assert_eq "$(get "$out" TIER)" "0" "modern + sudo + subuid -> tier 0"
assert_eq "$(get "$out" IGNORE_CHOWN)" "0" "subuid present -> no ignore_chown"

# Modern podman but no sudo -> tier 1
detect_etc_cdi_writable() { return 1; }
out="$(pgpu_resolve_tier)"
assert_eq "$(get "$out" TIER)" "1" "modern + no sudo -> tier 1"
pass "tier resolution"
