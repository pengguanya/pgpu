#!/usr/bin/env bash
# Consistent logging to stderr. Honors PGPU_QUIET=1 (suppress info/pass).
_pgpu_c() { [ -t 2 ] && printf '%s' "$1" || printf ''; }
log_info() { [ "${PGPU_QUIET:-0}" = 1 ] && return 0; printf '%s\n' "  $*" >&2; }
log_pass() { [ "${PGPU_QUIET:-0}" = 1 ] && return 0; printf '%s%s%s\n' "$(_pgpu_c $'\033[32m')" "✓ $*" "$(_pgpu_c $'\033[0m')" >&2; }
log_warn() { printf '%s%s%s\n' "$(_pgpu_c $'\033[33m')" "! $*" "$(_pgpu_c $'\033[0m')" >&2; }
log_fail() { printf '%s%s%s\n' "$(_pgpu_c $'\033[31m')" "✗ $*" "$(_pgpu_c $'\033[0m')" >&2; }
