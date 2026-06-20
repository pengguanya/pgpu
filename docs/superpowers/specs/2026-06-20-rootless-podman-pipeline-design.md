# Design: `pgpu` — Rootless GPU Container Pipeline (no sudo required)

**Date:** 2026-06-20
**Status:** Approved (design phase)
**Author:** Guanya Peng

## Summary

`pgpu` ("podman GPU") is a small, bash-only toolkit that makes **rootless,
daemonless GPU containers work on any machine with one command** — including
locked-down enterprise hosts where the user has no `sudo`, no `/etc/` write
access, and no subuid provisioning.

It is a **standalone, project-agnostic toolkit**: it sets up the rootless
podman + NVIDIA CDI environment and provides thin `build`/`run`/`train`/
`profile` wrappers. Any training or inference image (e.g. `llm-ft`, `llm-inf`)
plugs in via a per-project `pgpu.conf`. The toolkit hard-codes no project paths.

The design encodes, as automated checks and fixes, every problem encountered
while bringing up rootless GPU training on an aarch64 DGX-class box on
2026-06-20 (NFS `$HOME`, no subuid, podman 4.9.3 lacking `cdi_spec_dirs`,
AppArmor unprivileged-userns restriction, stale SHM locks).

## Goals

1. **Across machines/collaborators (primary):** anyone clones the repo, runs
   `pgpu doctor && pgpu setup`, and gets working rootless GPU containers
   regardless of sudo availability, podman version, subuid state, or `$HOME`
   filesystem.
2. **Across projects/images (primary):** the same toolkit drives any image via
   `pgpu.conf` — no hard-coded paths or model assumptions.
3. **GPU selection (cheap add):** a `GPUS` config var passes
   `nvidia.com/gpu=all|0|0,1` through. No launch orchestration.
4. **Per-user isolation (cheap+robust add):** overlay store and lock dirs are
   keyed by `$UID` so collaborators sharing one box never collide.

## Non-Goals (YAGNI)

- Multi-GPU / multi-node **launch orchestration** (torchrun, accelerate
  launch) — belongs to the training image's entrypoint, not the infra layer.
- Multi-user **management** (quotas, scheduling, user provisioning).
- A Python CLI — reintroduces the host-Python packaging trap the toolkit
  exists to avoid (no aarch64 wheels, rustls SSL, PEP 668).
- Rewriting or replacing `llm-ft`/`llm-inf` — they remain independent repos.

## Why bash-only

The host is exactly where Python packaging breaks on aarch64 DGX systems:
no CUDA wheels on PyPI, `uv`'s rustls rejects NVIDIA cert chains, and Debian
12's PEP 668 blocks `pip install` into the system Python. Infrastructure that
*sets up* the environment therefore cannot itself depend on a Python
environment. `pgpu` depends only on `bash`, coreutils, and `podman`.

## Architecture

```
pgpu/
├── README.md
├── Makefile                  # thin: make doctor|setup|run|train|profile → bin/pgpu …
├── bin/pgpu                  # entrypoint; argument parse + subcommand dispatch
├── lib/
│   ├── detect.sh             # read-only tiered probes; emits a resolved tier + plan
│   ├── setup.sh              # idempotently applies the chosen tier
│   ├── config.sh             # loads pgpu.conf, applies defaults, validates
│   └── log.sh                # PASS/WARN/FAIL formatting, colour, --quiet
├── install/podman-static.sh  # no-sudo podman 5.x bootstrap into $HOME (Tier 2 only)
├── pgpu.conf.example
└── examples/
    ├── llm-ft.conf
    └── llm-inf.conf
```

Each unit has one purpose and a clear interface:
- `detect.sh` → pure probing; outputs a tier id + structured findings, mutates
  nothing.
- `setup.sh` → consumes the tier and writes config / installs podman;
  idempotent (safe to re-run).
- `config.sh` → resolves effective settings from `pgpu.conf` + defaults.
- `bin/pgpu` → orchestrates; no detection logic of its own.

## Component: `pgpu doctor` (detection engine)

Read-only probes, each mapped to a real failure mode, then a computed tier.

| Probe | Lesson encoded |
|---|---|
| podman present + version | podman 4.9.3 lacks `cdi_spec_dirs` |
| `cdi_spec_dirs` support (podman ≥ 5.0) | `unresolvable CDI devices` dead-end |
| GPU device nodes + `nvidia-ctk` present | CDI generation prerequisite |
| `/etc/cdi` writable / sudo available | system CDI path needs root |
| subuid/subgid ranges for `$USER` | single-uid fallback needed |
| AppArmor `apparmor_restrict_unprivileged_userns` + cgroups version | userns/reexec viability |
| `$HOME` backing filesystem == NFS | overlay cannot back on NFS |
| local-disk candidate for overlay store | `/tmp` (or detected) redirect target |

**Resolved tiers:**

- **Tier 0 — native:** new system podman + (`/etc/cdi` writable or sudo) +
  subuid present → minimal config; CDI spec to `/etc/cdi`.
- **Tier 1 — user-CDI:** system podman ≥ 5 (reads `cdi_spec_dirs`), no sudo →
  CDI spec in `~/.config/cdi`, `cdi_spec_dirs` in `containers.conf`, storage
  redirect if `$HOME` is NFS.
- **Tier 2 — static-podman:** system podman missing or too old →
  `install/podman-static.sh` fetches podman 5.x into `$HOME`; then behaves like
  Tier 1. *(This is the path the 2026-06-20 box landed on.)*

**Cross-cutting fixes layered on any tier:**
- subuid absent → `ignore_chown_errors=true` + single-uid mapping in
  `storage.conf`.
- `$HOME` on NFS → user-scoped overlay store on local disk
  (`/tmp/$USER-pgpu/storage`, `…/run`).
- `pgpu clean` clears stale SHM locks (`/dev/shm/libpod_rootless_lock_$UID`)
  and `$XDG_RUNTIME_DIR/{libpod,containers}` to recover from version-mismatch
  `failed to reexec` errors.

`pgpu doctor` prints the resolved tier and the exact actions `pgpu setup` will
take. `pgpu setup` applies them idempotently.

## Component: commands

| Command | Behaviour |
|---|---|
| `pgpu doctor` | Probe, print tier + planned actions. Read-only. |
| `pgpu setup` | Apply tier: generate CDI spec, write `~/.config/containers/{storage,containers}.conf`, install static podman if Tier 2. Idempotent. |
| `pgpu build` | `podman build --network=host -t $IMAGE -f $DOCKERFILE .` |
| `pgpu run [-- cmd]` | Run with `--device nvidia.com/gpu=$GPUS --ipc=host --network=host` + config mounts; interactive shell if no cmd. |
| `pgpu train` | Run `$TRAIN_CMD` inside the container. |
| `pgpu profile` | Run `$PROFILE_CMD` inside the container. |
| `pgpu clean` | Clear stale SHM locks + rootless runtime state. |

## Component: configuration (`pgpu.conf`)

The cross-project mechanism. Each project drops a `pgpu.conf` in its root:

```bash
IMAGE=llm-ft
DOCKERFILE=Dockerfile
GPUS=all                      # or 0 / 0,1
HF_CACHE=.hf_cache
MOUNTS=("$PWD:/workspace" "$PWD/.hf_cache:/root/.cache/huggingface")
WORKDIR=/workspace
TRAIN_CMD="python train_lora.py"
PROFILE_CMD="bash profile_nsys.sh"
```

Defaults in `config.sh` fill anything omitted. `examples/llm-ft.conf` and
`examples/llm-inf.conf` ship as ready drop-ins for the existing repos.

## Error handling

- `detect.sh` never mutates state; safe to run anywhere, anytime.
- `setup.sh` is idempotent: re-running re-derives and rewrites config without
  duplication; existing user config is backed up (`*.pgpu.bak`) before
  overwrite.
- Every probe failure yields a specific remediation line, not a generic error
  (e.g. "subuid missing → using single-uid mapping; ask an admin to run
  `usermod --add-subuids …` to silence the warning").
- `pgpu run` fails fast with a pointer to `pgpu doctor` if CDI is unresolved.

## Testing

- **Probe unit tests:** `lib/detect.sh` functions are individually callable and
  asserted against faked inputs (e.g. a stub `podman --version`, a temp dir
  standing in for `/etc/cdi`) using a bash test harness (bats or a minimal
  assert script).
- **Idempotency test:** run `setup` twice; assert config files are identical
  and backups created once.
- **Smoke test (manual, GPU host):** `pgpu doctor && pgpu setup && pgpu run --
  nvidia-smi` prints the GPU. Documented in README; not run in CI (needs a
  GPU).

## Blog post (companion deliverable)

Third post in the DGX Spark series (setup → profiling → rootless). Same
frontmatter style (`author: peng`, `categories: [DevOps & Computing]`, tags
`dgx-spark, podman, rootless, cdi, aarch64, troubleshooting`).

- **Title:** "Rootless LLM Fine-Tuning on DGX Spark: GPU Containers Without Root"
- **Motivation (enterprise framing):** root is the default blocker in
  enterprise settings — shared DGX appliances, corporate-managed hosts, client
  environments, and locked-down compute for stakeholders routinely deny sudo,
  `/etc/` writes, and subuid provisioning, stopping teams before they start.
  `pgpu` turns that wall into a one-command bootstrap so collaborators, clients,
  and stakeholders stand up GPU training without waiting on IT or root grants —
  making enterprise-level collaboration and scale-out painless and reproducible
  across machines.
- **Why Podman over Docker** (daemonless, rootless, CDI).
- **"What Broke (and Why)"** — problem → cause → fix, mirroring the setup post:
  1. `--gpus all` → CDI `--device nvidia.com/gpu=all`
  2. No CDI spec (rootless has no root hook) → `nvidia-ctk cdi generate`
  3. `$HOME` on NFS → overlay can't back on NFS → `storage.conf` to local disk
  4. No subuid ranges → single-uid mapping + `ignore_chown_errors`
  5. podman 4.9.3 lacks `cdi_spec_dirs` → `unresolvable CDI` → static podman 5.x in `$HOME`
  6. AppArmor userns + stale SHM lock → `failed to reexec` → clean locks
  7. vLLM pulling a torch upgrade → CUDA forward-compat & image hygiene
  8. `prefetch.py` bootstrap bug → host-Python lesson, revisited
- **The toolkit:** how `pgpu doctor`/`setup`/`run` automate all eight, and why
  bash.
- **Closing:** "Rootless Is a Different Trust Model" — mirrors the prior post's
  "different environment" closer.
- Repo link + optional `pgpu doctor` asciinema GIF.

## Open questions / future work

- CI for probe unit tests (no GPU needed) via GitHub Actions.
- Optional `pgpu doctor --json` for machine-readable output.
- A `pgpu.conf` discovery rule (walk up from `$PWD`) if useful later.
