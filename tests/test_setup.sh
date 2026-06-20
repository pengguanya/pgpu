#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/../lib/log.sh"
. "$HERE/../lib/setup.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
conf="$tmp/containers"; mkdir -p "$conf"

pgpu_write_storage_conf "$conf" "/tmp/u-pgpu" 1 1
assert_file "$conf/storage.conf"
body="$(cat "$conf/storage.conf")"
assert_contains "$body" 'graphroot = "/tmp/u-pgpu/storage"' "graphroot redirected"
assert_contains "$body" 'ignore_chown_errors = "true"' "ignore_chown set"

pgpu_write_containers_conf "$conf" "$HOME/.config/cdi"
assert_contains "$(cat "$conf/containers.conf")" "cdi_spec_dirs" "cdi_spec_dirs written"

# idempotency: second write creates exactly one .bak and identical content
first="$(cat "$conf/storage.conf")"
pgpu_write_storage_conf "$conf" "/tmp/u-pgpu" 1 1
assert_file "$conf/storage.conf.pgpu.bak"
assert_eq "$(cat "$conf/storage.conf")" "$first" "idempotent storage.conf"
nbak=$(ls "$conf"/storage.conf.pgpu.bak* 2>/dev/null | wc -l)
assert_eq "$nbak" "1" "exactly one backup"
pass "setup writers"
