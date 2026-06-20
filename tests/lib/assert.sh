#!/usr/bin/env bash
assert_eq() { [ "$1" = "$2" ] || { echo "  FAIL: expected [$2] got [$1] ${3:+($3)}"; exit 1; }; }
assert_contains() { case "$1" in *"$2"*) ;; *) echo "  FAIL: [$1] missing [$2] ${3:+($3)}"; exit 1;; esac; }
assert_file() { [ -f "$1" ] || { echo "  FAIL: file missing: $1"; exit 1; }; }
pass() { echo "  PASS: $1"; }
