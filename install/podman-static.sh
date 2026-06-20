#!/usr/bin/env bash
set -euo pipefail
: "${PGPU_LOG_SOURCED:=}"
command -v log_info >/dev/null 2>&1 || { log_info(){ printf '  %s\n' "$*" >&2; }; log_pass(){ printf '  %s\n' "$*" >&2; }; log_warn(){ printf '  %s\n' "$*" >&2; }; }

PREFIX="${PGPU_PODMAN_PREFIX:-$HOME/opt/podman-static}"
REPO="mgoltzsche/podman-static"

pgpu_static_arch_asset() {
  case "${PGPU_ARCH:-$(uname -m)}" in
    aarch64|arm64) echo "podman-linux-arm64.tar.gz" ;;
    x86_64|amd64)  echo "podman-linux-amd64.tar.gz" ;;
    *) echo ""; return 1 ;;
  esac
}

main() {
  local asset url; asset="$(pgpu_static_arch_asset)" || { log_warn "unsupported arch"; exit 1; }
  url="https://github.com/$REPO/releases/latest/download/$asset"
  mkdir -p "$PREFIX"
  log_info "Downloading $url"
  curl -fL -o "/tmp/$asset" "$url"
  tar -xzf "/tmp/$asset" -C "$PREFIX" --strip-components=1
  local bin; bin="$(find "$PREFIX" -type f -name podman -perm -u+x | head -1)"
  [ -n "$bin" ] || { log_warn "podman binary not found after extract"; exit 1; }
  local bindir; bindir="$(dirname "$bin")"
  log_pass "podman installed at $bin"
  echo "Add to your shell: export PATH=\"$bindir:\$PATH\""
}

[ "${PGPU_SOURCE_ONLY:-0}" = 1 ] || main "$@"
