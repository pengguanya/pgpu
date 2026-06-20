#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/../lib/log.sh"

out="$(log_pass "hello" 2>&1)"
assert_contains "$out" "hello" "log_pass emits message"
out="$(PGPU_QUIET=1 log_info "quiet" 2>&1 || true)"
assert_eq "$out" "" "PGPU_QUIET suppresses info"
out="$(log_fail "boom" 2>&1)"
assert_contains "$out" "boom" "log_fail emits message"
pass "log.sh"
