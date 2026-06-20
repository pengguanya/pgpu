#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/../lib/log.sh"
. "$HERE/../lib/config.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# defaults when no pgpu.conf
( cd "$tmp"; pgpu_load_config; assert_eq "$IMAGE" "pgpu-image" "default IMAGE"; \
  assert_eq "$GPUS" "all" "default GPUS"; pass "defaults" )

# values from pgpu.conf override defaults
cat > "$tmp/pgpu.conf" <<'EOF'
IMAGE=llm-ft
GPUS=0,1
TRAIN_CMD="python train_lora.py"
EOF
( cd "$tmp"; pgpu_load_config; assert_eq "$IMAGE" "llm-ft" "IMAGE from conf"; \
  assert_eq "$GPUS" "0,1" "GPUS from conf"; \
  assert_eq "$TRAIN_CMD" "python train_lora.py" "TRAIN_CMD from conf"; pass "override" )
