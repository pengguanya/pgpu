#!/usr/bin/env bash
# Idempotent config writers + setup orchestration.
_pgpu_backup_once() { [ -f "$1" ] && [ ! -f "$1.pgpu.bak" ] && cp "$1" "$1.pgpu.bak"; return 0; }

pgpu_write_storage_conf() {
  local dir="$1" store_base="$2" ignore_chown="$3" redirect="$4" f="$1/storage.conf"
  _pgpu_backup_once "$f"
  { echo "[storage]"
    echo 'driver = "overlay"'
    if [ "$redirect" = 1 ]; then
      echo "graphroot = \"$store_base/storage\""
      echo "runroot   = \"$store_base/run\""
    fi
    if [ "$ignore_chown" = 1 ]; then
      echo ""; echo "[storage.options.overlay]"; echo 'ignore_chown_errors = "true"'
    fi
  } > "$f"
}

pgpu_write_containers_conf() {
  local dir="$1" cdi_dir="$2" f="$1/containers.conf"
  _pgpu_backup_once "$f"
  { echo "[engine]"
    echo "cdi_spec_dirs = [\"$cdi_dir\", \"/etc/cdi\", \"/run/cdi\"]"
  } > "$f"
}

cmd_setup() {
  local plan; plan="$(pgpu_resolve_tier)"
  eval "$(printf '%s\n' "$plan" | sed 's/^/local _/')"  # _TIER, _CDI_DIR, ...
  local conf="${PGPU_HOME:-$HOME}/.config/containers"
  mkdir -p "$conf" "$_CDI_DIR" "$_STORE_BASE/storage" "$_STORE_BASE/run"
  if [ "$_NEED_STATIC_PODMAN" = 1 ]; then
    log_info "Tier 2: installing static podman into \$HOME"
    bash "$PGPU_ROOT/install/podman-static.sh" || log_warn "static podman install failed; see install/podman-static.sh"
  fi
  if [ -n "$(detect_nvidia_ctk)" ]; then
    log_info "Generating CDI spec at $_CDI_DIR/nvidia.yaml"
    "${PGPU_NVIDIA_CTK:-nvidia-ctk}" cdi generate --output="$_CDI_DIR/nvidia.yaml" >/dev/null 2>&1 \
      && log_pass "CDI spec written" || log_warn "CDI generate failed (need sudo for /etc/cdi? try a user dir)"
  else
    log_warn "nvidia-ctk missing; skipping CDI generation"
  fi
  pgpu_write_storage_conf "$conf" "$_STORE_BASE" "$_IGNORE_CHOWN" "$_STORE_REDIRECT"
  pgpu_write_containers_conf "$conf" "$_CDI_DIR"
  log_pass "Setup complete (tier $_TIER). Try: pgpu run -- nvidia-smi"
}
