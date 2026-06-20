#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
# Force tier 2 scenario via env-stubbed probes through a fake podman + paths
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '#!/usr/bin/env bash\necho "podman version 4.9.3"\n' > "$tmp/podman"
chmod +x "$tmp/podman"
printf 'someoneelse:100000:65536\n' > "$tmp/subuid"
printf '0\n' > "$tmp/aa"

out="$(PGPU_PODMAN="$tmp/podman" PGPU_ETC_CDI="/etc/definitely-not-writable-$$" \
      PGPU_SUBUID_FILE="$tmp/subuid" PGPU_APPARMOR_FILE="$tmp/aa" \
      PGPU_STORE_BASE="$tmp/store" \
      bash "$HERE/../bin/pgpu" doctor 2>&1)"
assert_contains "$out" "Resolved tier: 2" "doctor prints resolved tier 2 for old podman without sudo"
pass "doctor"
