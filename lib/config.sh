#!/usr/bin/env bash
# Loads ./pgpu.conf and fills defaults. Safe to source repeatedly.
pgpu_load_config() {
  local dir="${1:-$PWD}"
  [ -f "$dir/pgpu.conf" ] && . "$dir/pgpu.conf"
  : "${IMAGE:=pgpu-image}"
  : "${DOCKERFILE:=Dockerfile}"
  : "${GPUS:=all}"
  : "${HF_CACHE:=.hf_cache}"
  : "${WORKDIR:=/workspace}"
  : "${NETWORK:=host}"
  : "${TRAIN_CMD:=}"
  : "${PROFILE_CMD:=}"
  if [ -z "${MOUNTS+x}" ] || [ "${#MOUNTS[@]}" -eq 0 ]; then
    MOUNTS=("$PWD:/workspace" "$PWD/$HF_CACHE:/root/.cache/huggingface")
  fi
  export IMAGE DOCKERFILE GPUS HF_CACHE WORKDIR NETWORK TRAIN_CMD PROFILE_CMD
}
pgpu_require_config() {
  [ -n "${IMAGE:-}" ] || { log_fail "IMAGE is not set (add it to pgpu.conf)"; return 1; }
}
