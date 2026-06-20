#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/pgpu.conf" <<'EOF'
IMAGE=llm-ft
GPUS=0,1
EOF
out="$(cd "$tmp" && PGPU_PRINT=1 bash "$HERE/../bin/pgpu" run -- nvidia-smi 2>&1)"
assert_contains "$out" "--device" "run includes --device"
assert_contains "$out" "nvidia.com/gpu=0,1" "run passes GPUS selection"
assert_contains "$out" "llm-ft" "run uses configured image"
assert_contains "$out" "nvidia-smi" "run appends the command"
pass "run argv"
