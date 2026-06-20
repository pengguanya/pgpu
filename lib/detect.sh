#!/usr/bin/env bash
# Read-only host probes. Each honors env overrides for testability.
detect_podman_version() {
  local p; p="$(command -v "${PGPU_PODMAN:-podman}" 2>/dev/null)" || return 0
  "$p" --version 2>/dev/null | awk '{print $3}'
}
detect_has_cdi_spec_dirs() {
  local major="${1%%.*}"; [ -n "$major" ] && [ "$major" -ge 5 ] 2>/dev/null
}
detect_gpu() { compgen -G "${PGPU_DEV:-/dev}/nvidia*" >/dev/null 2>&1; }
detect_nvidia_ctk() { command -v "${PGPU_NVIDIA_CTK:-nvidia-ctk}" 2>/dev/null || true; }
detect_etc_cdi_writable() {
  local d="${PGPU_ETC_CDI:-/etc/cdi}"
  if [ -d "$d" ]; then [ -w "$d" ]; else mkdir -p "$d" 2>/dev/null; fi
}
detect_subuid() {
  local f="${PGPU_SUBUID_FILE:-/etc/subuid}"
  [ -f "$f" ] && grep -q "^$USER:" "$f"
}
detect_apparmor_userns_restricted() {
  local f="${PGPU_APPARMOR_FILE:-/proc/sys/kernel/apparmor_restrict_unprivileged_userns}"
  [ -r "$f" ] && [ "$(cat "$f" 2>/dev/null)" = "1" ]
}
detect_home_is_nfs() {
  local h="${PGPU_HOME:-$HOME}" t
  t="$(stat -f -c %T "$h" 2>/dev/null || true)"
  case "$t" in nfs|nfs4) return 0;; *) return 1;; esac
}
