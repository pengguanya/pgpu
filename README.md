# pgpu — rootless GPU containers, no sudo required

`pgpu` is a bash-only toolkit that makes rootless, no-sudo NVIDIA GPU containers
work on any machine via tiered auto-detection. It wraps `podman` with the minimal
configuration needed to pass GPU devices into containers without root access.

---

## Quickstart

```bash
# Copy an example config into your project
cp examples/llm-ft.conf ~/work/llm-ft/pgpu.conf

cd ~/work/llm-ft

# Probe the host and see which tier will be used
~/work/pgpu/bin/pgpu doctor

# Write CDI spec, storage.conf, and containers.conf (one-time per machine)
~/work/pgpu/bin/pgpu setup

# Build your project image
~/work/pgpu/bin/pgpu build

# Run a container with GPU access
~/work/pgpu/bin/pgpu run -- nvidia-smi
```

`pgpu` looks for `pgpu.conf` in the current directory. All commands except
`doctor` and `clean` require a `pgpu.conf`.

---

## Commands

| Command | Description |
|---------|-------------|
| `pgpu doctor` | Probe host, print all capability checks, and show the resolved tier |
| `pgpu setup` | Apply the resolved tier: generate CDI spec, write `~/.config/containers/{storage,containers}.conf`, install static podman if needed |
| `pgpu build` | Build the project container image (`DOCKERFILE` → `IMAGE`) |
| `pgpu run [-- CMD]` | Run a GPU container (interactive shell if no `CMD`) |
| `pgpu train` | Run `TRAIN_CMD` in a container |
| `pgpu profile` | Run `PROFILE_CMD` in a container |
| `pgpu clean` | Clear stale rootless locks and runtime state |

---

## Three-Tier Auto-Detection

`pgpu doctor` and `pgpu setup` automatically select the best available approach:

| Tier | Conditions | CDI spec location | Notes |
|------|-----------|-------------------|-------|
| **0 — native** | System podman ≥ 5, sudo/writable `/etc/cdi`, subuid ranges present | `/etc/cdi` | Full rootless with user namespace mapping |
| **1 — user-CDI** | Podman ≥ 5 (no sudo), or subuid missing | `~/.config/cdi` | CDI spec in user home, no system write needed |
| **2 — static podman** | No podman, or podman < 5 | `~/.config/cdi` | Installs a static podman 5.x binary into `$HOME` |

Run `pgpu doctor` to see which tier your host resolves to and why.

---

## Config File (`pgpu.conf`)

Place a `pgpu.conf` in your project root. All keys:

```bash
IMAGE=my-image               # Container image name (build target / run source)
DOCKERFILE=Dockerfile        # Path to Dockerfile for pgpu build
GPUS=all                     # GPU selection: all / 0 / 0,1
HF_CACHE=.hf_cache           # Local HuggingFace cache directory
MOUNTS=("$PWD:/workspace" "$PWD/.hf_cache:/root/.cache/huggingface")
WORKDIR=/workspace           # Container working directory
TRAIN_CMD=""                 # Command for pgpu train (blank = error)
PROFILE_CMD=""               # Command for pgpu profile (blank = error)
```

See `pgpu.conf.example` for a template and `examples/` for ready-to-use configs.

---

## Per-User and NFS Notes

- **No subuid ranges** (`/etc/subuid` has no entry for `$USER`): `pgpu setup`
  sets `ignore_chown_errors = "true"` in `storage.conf` so single-uid containers
  still work without failing on ownership errors.

- **`$HOME` on NFS**: overlay mounts fail on NFS. `pgpu setup` redirects the
  container store (`graphroot` and `runroot`) to `/tmp/$USER-pgpu/` on local disk,
  keeping your home directory for config files only.

- **Stale locks after crashes**: run `pgpu clean` to remove
  `/dev/shm/libpod_rootless_lock_<uid>` and the XDG runtime libpod directories.

All paths and locks are per-user (`/tmp/$USER-pgpu`, `~/.config/containers`),
so multiple users on the same machine do not interfere.

---

## Makefile Targets

A thin `Makefile` delegates every command to `bin/pgpu`:

```bash
make doctor      # pgpu doctor
make setup       # pgpu setup
make build       # pgpu build
make run         # pgpu run (interactive)
make train       # pgpu train
make profile     # pgpu profile
make clean       # pgpu clean
make test        # bash tests/run.sh
```

---

## Testing

```bash
# Run full test suite
bash tests/run.sh

# Or via make
make test
```

The test suite is bash-only (no Python, no external framework). It covers config
loading, tier detection, setup config writers, doctor output, run command
construction, and static podman install stubs.

---

## Installation

`pgpu` is designed to live in a fixed location (e.g., `~/work/pgpu`) and be
invoked by absolute path or via the `Makefile`. No system-wide install is needed.

```bash
git clone https://github.com/PengGuanya/pgpu.git ~/work/pgpu
~/work/pgpu/bin/pgpu doctor
```
