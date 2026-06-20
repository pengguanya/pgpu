#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/../lib/log.sh"
. "$HERE/../lib/detect.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# CDI spec dirs support keyed on major version
detect_has_cdi_spec_dirs "5.8.3" && r=yes || r=no; assert_eq "$r" "yes" "5.x supports cdi_spec_dirs"
detect_has_cdi_spec_dirs "4.9.3" && r=yes || r=no; assert_eq "$r" "no" "4.x lacks cdi_spec_dirs"

# subuid probe against a fake file
printf 'someoneelse:100000:65536\n' > "$tmp/subuid"
PGPU_SUBUID_FILE="$tmp/subuid" detect_subuid && r=yes || r=no
assert_eq "$r" "no" "no subuid entry for current user"
printf '%s:100000:65536\n' "$USER" >> "$tmp/subuid"
PGPU_SUBUID_FILE="$tmp/subuid" detect_subuid && r=yes || r=no
assert_eq "$r" "yes" "subuid entry present"

# apparmor probe against a fake sysctl file
printf '1\n' > "$tmp/aa"
PGPU_APPARMOR_FILE="$tmp/aa" detect_apparmor_userns_restricted && r=yes || r=no
assert_eq "$r" "yes" "apparmor restriction detected"
printf '0\n' > "$tmp/aa"
PGPU_APPARMOR_FILE="$tmp/aa" detect_apparmor_userns_restricted && r=yes || r=no
assert_eq "$r" "no" "apparmor unrestricted"

# etc/cdi writable probe against a writable temp dir vs non-creatable path
PGPU_ETC_CDI="$tmp/cdi" detect_etc_cdi_writable && r=yes || r=no
assert_eq "$r" "yes" "writable cdi dir creatable"
pass "detect probes"
