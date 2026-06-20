#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
assert_file "$HERE/../Makefile"
assert_file "$HERE/../pgpu.conf.example"
assert_file "$HERE/../examples/llm-ft.conf"
assert_file "$HERE/../README.md"
out="$(make -C "$HERE/.." -n doctor 2>&1)"
assert_contains "$out" "pgpu" "make doctor invokes pgpu"
pass "cli smoke"
