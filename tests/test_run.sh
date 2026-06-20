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
# regression: the `--` separator must be stripped, not passed to the container
while IFS= read -r line; do [ "$line" = "--" ] && { echo "  FAIL: stray -- in argv"; exit 1; }; done <<< "$out"
pass "no stray -- token"
# regression: train/profile-style invocation (-- bash -lc) must also be clean
out2="$(cd "$tmp" && PGPU_PRINT=1 bash "$HERE/../bin/pgpu" run -- bash -lc 'echo hi' 2>&1)"
assert_contains "$out2" "bash" "train-style: bash is in argv"
assert_contains "$out2" "-lc" "train-style: -lc is in argv"
while IFS= read -r line; do [ "$line" = "--" ] && { echo "  FAIL: stray -- in train-style argv"; exit 1; }; done <<< "$out2"
pass "no stray -- in train-style argv"
pass "run argv"
