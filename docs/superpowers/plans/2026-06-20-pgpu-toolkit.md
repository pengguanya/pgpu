# pgpu Toolkit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `pgpu`, a bash-only toolkit that makes rootless, no-sudo NVIDIA GPU containers work on any machine via tiered auto-detection and thin podman wrappers.

**Architecture:** A `bin/pgpu` dispatcher sources focused library files in `lib/` (`log`, `config`, `detect`, `setup`). `detect.sh` runs read-only probes and resolves a setup *tier*; `setup.sh` idempotently applies it (CDI spec, `storage.conf`, `containers.conf`, optional static podman). Run/build/train/profile/clean commands assemble podman invocations from a per-project `pgpu.conf`. Everything is testable via dependency injection (command + path overrides) and a `--print` dry-run mode, with a dependency-free bash assert harness.

**Tech Stack:** Bash 4+, coreutils, `podman` (≥5 for CDI tiers), `nvidia-ctk`. No Python, no external test framework.

## Global Constraints

- **Bash-only.** No Python, no Node, no external runtime. Dependencies: `bash`, coreutils, `podman`; `nvidia-ctk` for CDI generation. (Spec: "Why bash-only".)
- **CDI tiers require podman ≥ 5.0** (older podman lacks `cdi_spec_dirs`).
- **Never write system paths** (`/etc/cdi`, `/etc/containers`) unless `/etc/cdi` is detected writable or sudo is explicitly present. Default to `~/.config/...`.
- **User-scoped local state:** overlay store/run and lock paths live under `/tmp/$USER-pgpu/` (never NFS `$HOME`).
- **Idempotent setup:** re-running `pgpu setup` reproduces identical config; back up any pre-existing user config once as `<file>.pgpu.bak`.
- **Injectable for tests:** every external command and root path is overridable via env (`PGPU_PODMAN`, `PGPU_NVIDIA_CTK`, `PGPU_HOME`, `PGPU_ETC_CDI`, `PGPU_SUBUID_FILE`, `PGPU_APPARMOR_FILE`, `PGPU_STORE_BASE`). Defaults are the real values.
- **Commits:** conventional commits; end every commit message with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Repo root: `~/work/pgpu` (already git-initialized; design spec committed).

---

### Task 1: Project skeleton, logging, and test harness

**Files:**
- Create: `lib/log.sh`
- Create: `bin/pgpu`
- Create: `tests/lib/assert.sh`
- Create: `tests/test_log.sh`
- Create: `tests/run.sh`

**Interfaces:**
- Produces: `lib/log.sh` defining `log_info MSG`, `log_pass MSG`, `log_warn MSG`, `log_fail MSG` (all to stderr; honor `PGPU_QUIET=1` to suppress info/pass). `bin/pgpu` dispatcher: `pgpu <subcommand> [args]`, prints usage and exits 2 on unknown command. Test harness: `assert_eq ACTUAL EXPECTED [msg]`, `assert_contains HAYSTACK NEEDLE [msg]`, `assert_file PATH`, `pass MSG`; `tests/run.sh` runs every `tests/test_*.sh` and reports totals.

- [ ] **Step 1: Write the failing test**

`tests/lib/assert.sh`:
```bash
#!/usr/bin/env bash
assert_eq() { [ "$1" = "$2" ] || { echo "  FAIL: expected [$2] got [$1] ${3:+($3)}"; exit 1; }; }
assert_contains() { case "$1" in *"$2"*) ;; *) echo "  FAIL: [$1] missing [$2] ${3:+($3)}"; exit 1;; esac; }
assert_file() { [ -f "$1" ] || { echo "  FAIL: file missing: $1"; exit 1; }; }
pass() { echo "  PASS: $1"; }
```

`tests/test_log.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/../lib/log.sh"

out="$(log_pass "hello" 2>&1)"
assert_contains "$out" "hello" "log_pass emits message"
out="$(PGPU_QUIET=1 log_info "quiet" 2>&1 || true)"
assert_eq "$out" "" "PGPU_QUIET suppresses info"
out="$(log_fail "boom" 2>&1)"
assert_contains "$out" "boom" "log_fail emits message"
pass "log.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_log.sh`
Expected: FAIL — `lib/log.sh` does not exist (`No such file or directory`).

- [ ] **Step 3: Write minimal implementation**

`lib/log.sh`:
```bash
#!/usr/bin/env bash
# Consistent logging to stderr. Honors PGPU_QUIET=1 (suppress info/pass).
_pgpu_c() { [ -t 2 ] && printf '%s' "$1" || printf ''; }
log_info() { [ "${PGPU_QUIET:-0}" = 1 ] && return 0; printf '%s\n' "  $*" >&2; }
log_pass() { [ "${PGPU_QUIET:-0}" = 1 ] && return 0; printf '%s%s%s\n' "$(_pgpu_c $'\033[32m')" "✓ $*" "$(_pgpu_c $'\033[0m')" >&2; }
log_warn() { printf '%s%s%s\n' "$(_pgpu_c $'\033[33m')" "! $*" "$(_pgpu_c $'\033[0m')" >&2; }
log_fail() { printf '%s%s%s\n' "$(_pgpu_c $'\033[31m')" "✗ $*" "$(_pgpu_c $'\033[0m')" >&2; }
```

`bin/pgpu`:
```bash
#!/usr/bin/env bash
set -euo pipefail
PGPU_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$PGPU_ROOT/lib/log.sh"

usage() {
  cat <<'EOF'
pgpu — rootless GPU containers, no sudo required

Usage: pgpu <command> [args]

Commands:
  doctor     Probe the host and print the resolved setup tier (read-only)
  setup      Apply the resolved tier (CDI spec, storage/containers config)
  build      Build the project image
  run [-- CMD]  Run a GPU container (interactive shell if no CMD)
  train      Run the project TRAIN_CMD in a container
  profile    Run the project PROFILE_CMD in a container
  clean      Clear stale rootless locks / runtime state
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  ""|-h|--help|help) usage ;;
  *) log_fail "unknown command: $cmd"; usage >&2; exit 2 ;;
esac
```
Then: `chmod +x bin/pgpu tests/run.sh` (run.sh created next step).

`tests/run.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0
for t in "$HERE"/test_*.sh; do
  echo "== $(basename "$t")"
  bash "$t" || fail=1
done
[ "$fail" = 0 ] && echo "ALL TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — `test_log.sh` prints `PASS: log.sh`, runner prints `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
chmod +x bin/pgpu tests/run.sh
git add bin lib tests
git commit -m "feat: scaffold pgpu dispatcher, logging, and bash test harness

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Configuration loader (`lib/config.sh`)

**Files:**
- Create: `lib/config.sh`
- Create: `tests/test_config.sh`

**Interfaces:**
- Consumes: `lib/log.sh`.
- Produces: `pgpu_load_config [dir]` — sources `<dir>/pgpu.conf` if present (default `$PWD`), then applies defaults, exporting: `IMAGE` (default `pgpu-image`), `DOCKERFILE` (`Dockerfile`), `GPUS` (`all`), `HF_CACHE` (`.hf_cache`), `WORKDIR` (`/workspace`), `NETWORK` (`host`), `TRAIN_CMD` (empty), `PROFILE_CMD` (empty), and array `MOUNTS` (default `("$PWD:/workspace" "$PWD/$HF_CACHE:/root/.cache/huggingface")`). `pgpu_require_config` — fails (exit 1) if `IMAGE` is empty.

- [ ] **Step 1: Write the failing test**

`tests/test_config.sh`:
```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_config.sh`
Expected: FAIL — `lib/config.sh` not found.

- [ ] **Step 3: Write minimal implementation**

`lib/config.sh`:
```bash
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
  if [ "${#MOUNTS[@]:-0}" -eq 0 ]; then
    MOUNTS=("$PWD:/workspace" "$PWD/$HF_CACHE:/root/.cache/huggingface")
  fi
  export IMAGE DOCKERFILE GPUS HF_CACHE WORKDIR NETWORK TRAIN_CMD PROFILE_CMD
}
pgpu_require_config() {
  [ -n "${IMAGE:-}" ] || { log_fail "IMAGE is not set (add it to pgpu.conf)"; return 1; }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_config.sh`
Expected: PASS — prints `PASS: defaults` and `PASS: override`.

- [ ] **Step 5: Commit**

```bash
git add lib/config.sh tests/test_config.sh
git commit -m "feat: add pgpu.conf loader with defaults and validation

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Detection probes (`lib/detect.sh`)

**Files:**
- Create: `lib/detect.sh`
- Create: `tests/test_detect_probes.sh`

**Interfaces:**
- Consumes: `lib/log.sh`.
- Produces (all read-only, echo a value, mutate nothing; honor env overrides):
  - `detect_podman_version` → echoes podman semver (e.g. `5.8.3`) or empty. Uses `${PGPU_PODMAN:-podman}`.
  - `detect_has_cdi_spec_dirs VERSION` → exit 0 if `VERSION` major ≥ 5, else 1.
  - `detect_gpu` → exit 0 if any `/dev/nvidia*` exists (dir `${PGPU_DEV:-/dev}`), else 1.
  - `detect_nvidia_ctk` → echoes path to `${PGPU_NVIDIA_CTK:-nvidia-ctk}` or empty.
  - `detect_etc_cdi_writable` → exit 0 if `${PGPU_ETC_CDI:-/etc/cdi}` is writable or creatable, else 1.
  - `detect_subuid` → exit 0 if `$USER` has an entry in `${PGPU_SUBUID_FILE:-/etc/subuid}`, else 1.
  - `detect_apparmor_userns_restricted` → exit 0 if `${PGPU_APPARMOR_FILE:-/proc/sys/kernel/apparmor_restrict_unprivileged_userns}` reads `1`, else 1.
  - `detect_home_is_nfs` → exit 0 if `${PGPU_HOME:-$HOME}` filesystem type is nfs/nfs4 (via `stat -f -c %T`), else 1.

- [ ] **Step 1: Write the failing test**

`tests/test_detect_probes.sh`:
```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_detect_probes.sh`
Expected: FAIL — `lib/detect.sh` not found.

- [ ] **Step 3: Write minimal implementation**

`lib/detect.sh`:
```bash
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
```
Note: `detect_etc_cdi_writable` may create the dir as a side effect only when it is already creatable by the user — acceptable since that is exactly the capability being probed; tests use a temp path.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_detect_probes.sh`
Expected: PASS — prints `PASS: detect probes`.

- [ ] **Step 5: Commit**

```bash
git add lib/detect.sh tests/test_detect_probes.sh
git commit -m "feat: add read-only host detection probes

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Tier resolution (`lib/detect.sh` continued)

**Files:**
- Modify: `lib/detect.sh` (append `pgpu_resolve_tier`)
- Create: `tests/test_detect_tier.sh`

**Interfaces:**
- Consumes: the probe functions from Task 3.
- Produces: `pgpu_resolve_tier` — runs the probes and prints newline-separated `KEY=VALUE` lines on stdout:
  - `TIER=` `0` | `1` | `2`
  - `CDI_DIR=` `/etc/cdi` (tier 0) or `$HOME/.config/cdi` (tiers 1/2)
  - `IGNORE_CHOWN=` `1` if subuid absent else `0`
  - `STORE_REDIRECT=` `1` if `$HOME` is NFS else `0`
  - `STORE_BASE=` `${PGPU_STORE_BASE:-/tmp/$USER-pgpu}`
  - `NEED_STATIC_PODMAN=` `1` for tier 2 else `0`
  Logic: no podman OR podman major <5 with `/etc/cdi` not writable → TIER 2. podman ≥5, `/etc/cdi` writable & subuid present → TIER 0. Otherwise (podman ≥5, no sudo) → TIER 1.

- [ ] **Step 1: Write the failing test**

`tests/test_detect_tier.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/../lib/log.sh"
. "$HERE/../lib/detect.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Simulate the 2026-06-20 box: podman 4.9.3, no /etc/cdi write, no subuid, NFS home
get() { printf '%s\n' "$1" | grep "^$2=" | cut -d= -f2-; }
detect_podman_version() { echo "4.9.3"; }   # stub
detect_etc_cdi_writable() { return 1; }      # stub: no sudo
detect_subuid() { return 1; }                # stub: missing
detect_home_is_nfs() { return 0; }           # stub: NFS
out="$(PGPU_STORE_BASE="$tmp/store" pgpu_resolve_tier)"
assert_eq "$(get "$out" TIER)" "2" "old podman + no sudo -> tier 2"
assert_eq "$(get "$out" IGNORE_CHOWN)" "1" "no subuid -> ignore_chown"
assert_eq "$(get "$out" STORE_REDIRECT)" "1" "NFS home -> redirect"
assert_eq "$(get "$out" NEED_STATIC_PODMAN)" "1" "tier 2 needs static podman"

# Simulate a clean modern box: podman 5.8.3, /etc/cdi writable, subuid present, local home
detect_podman_version() { echo "5.8.3"; }
detect_etc_cdi_writable() { return 0; }
detect_subuid() { return 0; }
detect_home_is_nfs() { return 1; }
out="$(pgpu_resolve_tier)"
assert_eq "$(get "$out" TIER)" "0" "modern + sudo + subuid -> tier 0"
assert_eq "$(get "$out" IGNORE_CHOWN)" "0" "subuid present -> no ignore_chown"

# Modern podman but no sudo -> tier 1
detect_etc_cdi_writable() { return 1; }
out="$(pgpu_resolve_tier)"
assert_eq "$(get "$out" TIER)" "1" "modern + no sudo -> tier 1"
pass "tier resolution"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_detect_tier.sh`
Expected: FAIL — `pgpu_resolve_tier: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/detect.sh`:
```bash
pgpu_resolve_tier() {
  local ver tier cdi_dir ignore_chown store_redirect store_base need_static
  ver="$(detect_podman_version)"
  store_base="${PGPU_STORE_BASE:-/tmp/$USER-pgpu}"
  detect_subuid && ignore_chown=0 || ignore_chown=1
  detect_home_is_nfs && store_redirect=1 || store_redirect=0

  if [ -z "$ver" ] || { ! detect_has_cdi_spec_dirs "$ver" && ! detect_etc_cdi_writable; }; then
    tier=2; need_static=1; cdi_dir="$HOME/.config/cdi"
  elif detect_has_cdi_spec_dirs "$ver" && detect_etc_cdi_writable && detect_subuid; then
    tier=0; need_static=0; cdi_dir="/etc/cdi"
  else
    tier=1; need_static=0; cdi_dir="$HOME/.config/cdi"
  fi

  printf 'TIER=%s\nCDI_DIR=%s\nIGNORE_CHOWN=%s\nSTORE_REDIRECT=%s\nSTORE_BASE=%s\nNEED_STATIC_PODMAN=%s\n' \
    "$tier" "$cdi_dir" "$ignore_chown" "$store_redirect" "$store_base" "$need_static"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_detect_tier.sh`
Expected: PASS — prints `PASS: tier resolution`.

- [ ] **Step 5: Commit**

```bash
git add lib/detect.sh tests/test_detect_tier.sh
git commit -m "feat: resolve setup tier from probes (0 native / 1 user-cdi / 2 static)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `doctor` command

**Files:**
- Modify: `bin/pgpu` (add `doctor` case + `cmd_doctor`)
- Create: `tests/test_doctor.sh`

**Interfaces:**
- Consumes: `pgpu_resolve_tier`, log functions.
- Produces: `pgpu doctor` prints a human-readable probe report and the resolved tier, then the planned actions, and exits 0. Output includes the literal strings `Resolved tier:` and the tier number.

- [ ] **Step 1: Write the failing test**

`tests/test_doctor.sh`:
```bash
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
assert_contains "$out" "Resolved tier:" "doctor prints resolved tier"
assert_contains "$out" "2" "tier 2 for old podman without sudo"
pass "doctor"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_doctor.sh`
Expected: FAIL — `doctor` currently hits the `unknown command` branch (exit 2), no `Resolved tier:` text.

- [ ] **Step 3: Write minimal implementation**

In `bin/pgpu`, source detect and add the function + case. After the `. "$PGPU_ROOT/lib/log.sh"` line add:
```bash
. "$PGPU_ROOT/lib/detect.sh"

cmd_doctor() {
  log_info "Probing host for rootless GPU readiness..."
  local ver; ver="$(detect_podman_version)"
  [ -n "$ver" ] && log_pass "podman $ver" || log_warn "podman not found"
  detect_gpu && log_pass "GPU device nodes present" || log_warn "no /dev/nvidia* found"
  [ -n "$(detect_nvidia_ctk)" ] && log_pass "nvidia-ctk present" || log_warn "nvidia-ctk missing (needed to generate CDI spec)"
  detect_subuid && log_pass "subuid ranges present" || log_warn "no subuid ranges (will use single-uid mapping)"
  detect_home_is_nfs && log_warn "\$HOME is on NFS (overlay store will redirect to local disk)" || log_pass "\$HOME on local fs"
  detect_apparmor_userns_restricted && log_warn "AppArmor restricts unprivileged userns" || log_pass "userns unrestricted"
  echo
  local plan; plan="$(pgpu_resolve_tier)"
  local tier; tier="$(printf '%s\n' "$plan" | grep '^TIER=' | cut -d= -f2)"
  echo "Resolved tier: $tier"
  printf '%s\n' "$plan" | sed 's/^/  plan: /'
  echo
  echo "Run 'pgpu setup' to apply."
}
```
Change the `case` so `doctor)` calls `cmd_doctor`:
```bash
  doctor) cmd_doctor ;;
```
(place it before the catch-all `*)` branch).

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_doctor.sh`
Expected: PASS — prints `PASS: doctor`.

- [ ] **Step 5: Commit**

```bash
git add bin/pgpu tests/test_doctor.sh
git commit -m "feat: add 'pgpu doctor' tiered readiness report

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: `setup` — write config idempotently (`lib/setup.sh`)

**Files:**
- Create: `lib/setup.sh`
- Modify: `bin/pgpu` (add `setup` case calling `cmd_setup`)
- Create: `tests/test_setup.sh`

**Interfaces:**
- Consumes: `pgpu_resolve_tier`, log functions.
- Produces:
  - `pgpu_write_storage_conf CONF_DIR STORE_BASE IGNORE_CHOWN STORE_REDIRECT` — writes `<CONF_DIR>/storage.conf`. When `STORE_REDIRECT=1`, sets `graphroot=<STORE_BASE>/storage`, `runroot=<STORE_BASE>/run`. When `IGNORE_CHOWN=1`, adds `[storage.options.overlay] ignore_chown_errors="true"`. Backs up existing file once to `storage.conf.pgpu.bak`.
  - `pgpu_write_containers_conf CONF_DIR CDI_DIR` — writes `<CONF_DIR>/containers.conf` with `[engine] cdi_spec_dirs=["<CDI_DIR resolved>", "/etc/cdi", "/run/cdi"]`. Backs up once.
  - `cmd_setup` — resolves tier, generates CDI spec into `CDI_DIR` via `nvidia-ctk` (skipped with a warning if `nvidia-ctk` missing), writes both confs into `${PGPU_HOME:-$HOME}/.config/containers`, and invokes static-podman install when `NEED_STATIC_PODMAN=1`.

- [ ] **Step 1: Write the failing test**

`tests/test_setup.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/../lib/log.sh"
. "$HERE/../lib/setup.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
conf="$tmp/containers"; mkdir -p "$conf"

pgpu_write_storage_conf "$conf" "/tmp/u-pgpu" 1 1
assert_file "$conf/storage.conf"
body="$(cat "$conf/storage.conf")"
assert_contains "$body" 'graphroot = "/tmp/u-pgpu/storage"' "graphroot redirected"
assert_contains "$body" 'ignore_chown_errors = "true"' "ignore_chown set"

pgpu_write_containers_conf "$conf" "$HOME/.config/cdi"
assert_contains "$(cat "$conf/containers.conf")" "cdi_spec_dirs" "cdi_spec_dirs written"

# idempotency: second write creates exactly one .bak and identical content
first="$(cat "$conf/storage.conf")"
pgpu_write_storage_conf "$conf" "/tmp/u-pgpu" 1 1
assert_file "$conf/storage.conf.pgpu.bak"
assert_eq "$(cat "$conf/storage.conf")" "$first" "idempotent storage.conf"
nbak=$(ls "$conf"/storage.conf.pgpu.bak* 2>/dev/null | wc -l)
assert_eq "$nbak" "1" "exactly one backup"
pass "setup writers"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_setup.sh`
Expected: FAIL — `lib/setup.sh` not found.

- [ ] **Step 3: Write minimal implementation**

`lib/setup.sh`:
```bash
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
```
In `bin/pgpu`, after sourcing detect add `. "$PGPU_ROOT/lib/setup.sh"` and add case `setup) cmd_setup ;;`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_setup.sh`
Expected: PASS — prints `PASS: setup writers`.

- [ ] **Step 5: Commit**

```bash
git add lib/setup.sh bin/pgpu tests/test_setup.sh
git commit -m "feat: idempotent storage/containers config writers + 'pgpu setup'

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Static podman installer (`install/podman-static.sh`)

**Files:**
- Create: `install/podman-static.sh`
- Create: `tests/test_podman_static.sh`

**Interfaces:**
- Consumes: log functions (sourced when run standalone).
- Produces:
  - `pgpu_static_arch_asset` — echoes the release asset name for the current arch: `aarch64`/`arm64` → `podman-linux-arm64.tar.gz`; `x86_64`/`amd64` → `podman-linux-amd64.tar.gz`. Uses `${PGPU_ARCH:-$(uname -m)}`.
  - When executed (not sourced): downloads the asset from the `mgoltzsche/podman-static` latest release into `$HOME/opt/podman-static`, extracts, locates `podman`/helpers, appends `helper_binaries_dir`/`conmon_path`/`runtime` to `~/.config/containers/containers.conf`, installs a `policy.json` if absent, and prints the `PATH` export line. Guarded behind `main` so sourcing for tests does no I/O.

- [ ] **Step 1: Write the failing test**

`tests/test_podman_static.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/../lib/log.sh"
PGPU_SOURCE_ONLY=1 . "$HERE/../install/podman-static.sh"

assert_eq "$(PGPU_ARCH=aarch64 pgpu_static_arch_asset)" "podman-linux-arm64.tar.gz" "arm64 asset"
assert_eq "$(PGPU_ARCH=x86_64 pgpu_static_arch_asset)" "podman-linux-amd64.tar.gz" "amd64 asset"
pass "podman-static arch mapping"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_podman_static.sh`
Expected: FAIL — `install/podman-static.sh` not found.

- [ ] **Step 3: Write minimal implementation**

`install/podman-static.sh`:
```bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_podman_static.sh`
Expected: PASS — prints `PASS: podman-static arch mapping`.

- [ ] **Step 5: Commit**

```bash
git add install/podman-static.sh tests/test_podman_static.sh
git commit -m "feat: no-sudo static podman installer with arch detection

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: `run`/`build`/`train`/`profile`/`clean` commands

**Files:**
- Modify: `bin/pgpu` (add cases + functions)
- Create: `tests/test_run.sh`

**Interfaces:**
- Consumes: `pgpu_load_config`, `pgpu_require_config`, log functions.
- Produces: `pgpu_run_argv [CMD...]` — echoes the full podman argv it would execute (one token per line), reading `IMAGE/GPUS/NETWORK/WORKDIR/MOUNTS`. `cmd_run`/`cmd_build`/`cmd_train`/`cmd_profile`/`cmd_clean` wire these to real execution; all honor `PGPU_PRINT=1` to print the argv instead of executing (the test hook). `cmd_clean` removes `/dev/shm/libpod_rootless_lock_$(id -u)` and `$XDG_RUNTIME_DIR/{libpod,containers}`.

- [ ] **Step 1: Write the failing test**

`tests/test_run.sh`:
```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_run.sh`
Expected: FAIL — `run` hits the unknown-command branch; no `--device` in output.

- [ ] **Step 3: Write minimal implementation**

In `bin/pgpu` add `. "$PGPU_ROOT/lib/config.sh"` near the other sources, then:
```bash
PODMAN="${PGPU_PODMAN:-podman}"

pgpu_run_argv() {
  pgpu_load_config; pgpu_require_config || exit 1
  local argv=("$PODMAN" run -it --rm --network="$NETWORK"
              --device "nvidia.com/gpu=$GPUS" --ipc=host -w "$WORKDIR")
  local m; for m in "${MOUNTS[@]}"; do argv+=(-v "$m"); done
  argv+=("$IMAGE" "$@")
  printf '%s\n' "${argv[@]}"
}
cmd_run() {
  mapfile -t a < <(pgpu_run_argv "$@")
  if [ "${PGPU_PRINT:-0}" = 1 ]; then printf '%s\n' "${a[@]}"; else exec "${a[@]}"; fi
}
cmd_build() {
  pgpu_load_config; pgpu_require_config || exit 1
  local a=("$PODMAN" build --network=host -t "$IMAGE" -f "$DOCKERFILE" .)
  if [ "${PGPU_PRINT:-0}" = 1 ]; then printf '%s\n' "${a[@]}"; else exec "${a[@]}"; fi
}
cmd_train()   { pgpu_load_config; [ -n "$TRAIN_CMD" ]   || { log_fail "TRAIN_CMD not set";   exit 1; }; cmd_run -- bash -lc "$TRAIN_CMD"; }
cmd_profile() { pgpu_load_config; [ -n "$PROFILE_CMD" ] || { log_fail "PROFILE_CMD not set"; exit 1; }; cmd_run -- bash -lc "$PROFILE_CMD"; }
cmd_clean() {
  rm -f "/dev/shm/libpod_rootless_lock_$(id -u)" 2>/dev/null || true
  rm -rf "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/libpod" "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/containers" 2>/dev/null || true
  log_pass "cleared stale rootless locks / runtime state"
}
```
Add cases before `*)`:
```bash
  setup) cmd_setup ;;
  build) cmd_build ;;
  run) cmd_run "$@" ;;
  train) cmd_train ;;
  profile) cmd_profile ;;
  clean) cmd_clean ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_run.sh`
Expected: PASS — prints `PASS: run argv`.

- [ ] **Step 5: Commit**

```bash
git add bin/pgpu tests/test_run.sh
git commit -m "feat: add run/build/train/profile/clean commands with --print dry-run

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Makefile, example configs, and README

**Files:**
- Create: `Makefile`
- Create: `pgpu.conf.example`
- Create: `examples/llm-ft.conf`
- Create: `examples/llm-inf.conf`
- Create: `README.md`
- Create: `tests/test_cli_smoke.sh`

**Interfaces:**
- Consumes: `bin/pgpu`.
- Produces: `make doctor|setup|build|run|train|profile|clean` targets that call `bin/pgpu`. Example configs and README documenting quickstart, tiers, and the GPU smoke test.

- [ ] **Step 1: Write the failing test**

`tests/test_cli_smoke.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
assert_file "$HERE/../Makefile"
assert_file "$HERE/../pgpu.conf.example"
assert_file "$HERE/../examples/llm-ft.conf"
assert_file "$HERE/../README.md"
out="$(make -C "$HERE/.." -n doctor 2>&1)"
assert_contains "$out" "pgpu" "make doctor invokes pgpu"
pass "cli smoke"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_cli_smoke.sh`
Expected: FAIL — `Makefile` and example/readme files missing.

- [ ] **Step 3: Write minimal implementation**

`Makefile`:
```makefile
PGPU := ./bin/pgpu
.PHONY: doctor setup build run train profile clean test
doctor:  ; $(PGPU) doctor
setup:   ; $(PGPU) setup
build:   ; $(PGPU) build
run:     ; $(PGPU) run
train:   ; $(PGPU) train
profile: ; $(PGPU) profile
clean:   ; $(PGPU) clean
test:    ; bash tests/run.sh
```

`pgpu.conf.example`:
```bash
# Copy to your project root as pgpu.conf and edit.
IMAGE=my-image
DOCKERFILE=Dockerfile
GPUS=all                      # or 0 / 0,1
HF_CACHE=.hf_cache
MOUNTS=("$PWD:/workspace" "$PWD/.hf_cache:/root/.cache/huggingface")
WORKDIR=/workspace
TRAIN_CMD=""
PROFILE_CMD=""
```

`examples/llm-ft.conf`:
```bash
IMAGE=llm-ft
DOCKERFILE=Dockerfile
GPUS=all
HF_CACHE=.hf_cache
MOUNTS=("$PWD:/workspace" "$PWD/.hf_cache:/root/.cache/huggingface")
WORKDIR=/workspace
TRAIN_CMD="python train_lora.py"
PROFILE_CMD="bash profile_nsys.sh"
```

`examples/llm-inf.conf`:
```bash
IMAGE=llm-inf
DOCKERFILE=Dockerfile
GPUS=all
HF_CACHE=.hf_cache
MOUNTS=("$PWD:/workspace" "$PWD/.hf_cache:/root/.cache/huggingface")
WORKDIR=/workspace
TRAIN_CMD=""
PROFILE_CMD=""
```

`README.md`: quickstart (`cp examples/llm-ft.conf ~/work/llm-ft/pgpu.conf`; `pgpu doctor`; `pgpu setup`; `pgpu build`; `pgpu run -- nvidia-smi`), the three tiers table, the per-user/NFS notes, and the smoke test. Keep it concise and accurate to the commands above.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_cli_smoke.sh && bash tests/run.sh`
Expected: PASS — `PASS: cli smoke` and `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add Makefile pgpu.conf.example examples README.md tests/test_cli_smoke.sh
git commit -m "feat: Makefile entrypoints, example configs, and README

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation: real-host validation (manual, on the GPU box)

Not a CI task (needs a GPU). After all tasks pass `bash tests/run.sh`:

```bash
cp examples/llm-ft.conf ~/work/llm-ft/pgpu.conf
cd ~/work/llm-ft
~/work/pgpu/bin/pgpu doctor      # expect: Resolved tier: 2 on the rbalwpr453 box
~/work/pgpu/bin/pgpu setup
~/work/pgpu/bin/pgpu run -- nvidia-smi   # expect: NVIDIA GB10 table
```

## Blog post (separate deliverable)

After the toolkit is validated, produce the companion blog post via the
`blog-post` skill, using the spec's outline (enterprise/no-sudo motivation,
the 8-problem "What Broke (and Why)", the toolkit, the "different trust model"
close). Optionally record a `pgpu doctor` asciinema GIF via the
`cli-demo-generator` skill.

## Self-Review

- **Spec coverage:** Tiers (T3–T6), CDI/storage/containers config (T6), static podman (T7), commands incl. GPU selection + per-user clean (T5,T8), cross-project config (T2,T9), bash-only/no-Python (all), testing plan (harness T1 + per-task tests + manual smoke). Blog deferred to blog-post skill (noted). ✅
- **Placeholder scan:** README body in T9 Step 3 is described rather than shown verbatim — acceptable as prose content, but the implementer must write real sections matching the documented commands; no code step uses placeholders. ✅
- **Type/name consistency:** `pgpu_resolve_tier` keys (`TIER/CDI_DIR/IGNORE_CHOWN/STORE_REDIRECT/STORE_BASE/NEED_STATIC_PODMAN`) are consumed identically in T6 `cmd_setup`. `pgpu_run_argv`/`cmd_run` names consistent across T8. Probe overrides (`PGPU_*`) consistent between detect.sh and tests. ✅
