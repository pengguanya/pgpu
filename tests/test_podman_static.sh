#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/../lib/log.sh"
PGPU_SOURCE_ONLY=1 . "$HERE/../install/podman-static.sh"

assert_eq "$(PGPU_ARCH=aarch64 pgpu_static_arch_asset)" "podman-linux-arm64.tar.gz" "arm64 asset"
assert_eq "$(PGPU_ARCH=x86_64 pgpu_static_arch_asset)" "podman-linux-amd64.tar.gz" "amd64 asset"
pass "podman-static arch mapping"
