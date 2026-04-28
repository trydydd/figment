# Figment v1.0.0 Release Checklist

This checklist is the gate for tagging `v1.0.0`. The build path with an
NVIDIA GPU is the primary unknown — every other change is testable on a
single Linux host without specialised hardware. Do not apply the
`v1.0.0` tag until every box below is ticked and the runner records
their hardware and OS at the bottom.

The checklist is intentionally short. It covers the launcher's three
load-bearing decisions (which runtime to pick, which model to load,
which KV profile to apply) plus the two release artefacts that have to
match what the README promises (`LICENSES/`, `CHECKSUMS.sha256`).

---

## Required hardware

- [ ] x86_64 host with an NVIDIA GPU and `nvidia-smi` installed.
- [ ] Linux kernel new enough to load the GPU driver (any modern
      Ubuntu / Fedora / Arch is fine).
- [ ] At least 32 GB of free disk space for the build target.
- [ ] At least 16 GB of RAM (so the high-quality Q8 path is exercised).

ARM64 with GPU offload is **out of scope** for v1.0.0 — see
`CHANGELOG.md` known limitations.

## Pre-flight

- [ ] `./dev/bootstrap-local.sh` provisions `./local-dev/.system/` and
      `./dev/launch-local.sh` boots the model on this host without a
      USB. Cheap smoke before the real release run.
- [ ] Working tree is clean and on the release branch.
- [ ] `LICENSES/LLAMA_CPP_LICENSE.txt` and
      `LICENSES/MODEL LICENSES/QWEN_LICENSE.txt` exist and are
      non-empty.
- [ ] `CHECKSUMS.sha256` has real hashes for every artifact (no
      `# PENDING` lines remain). Populate by running the build once
      with `FIGMENT_SKIP_CHECKSUMS=1`, then `sha256sum` each artifact.

## Build

Run the builder against a freshly-mounted target directory:

```bash
./BuildYourOwn.sh --target /mnt/figment-release-test
```

- [ ] Build completes without errors.
- [ ] `runtime-cpu/` and `runtime-cuda/` are both populated under
      `.system/`.
- [ ] `LICENSES/` is staged on the target (the builder logs
      `Staged LICENSES/ on target`).
- [ ] No `WARNING: no recorded SHA256 for ...` lines appeared in the
      build output (this is what the pre-flight checksum step is
      guarding).
- [ ] Manually corrupt one of the cached tarballs in `$TMPDIR` and re-
      run with `--skip-copy`. Confirm the launcher discards it and
      re-downloads.

## Launcher — primary GPU path

Eject and re-mount the drive (or `cd` into the target directory) and
run:

```bash
./LinuxLaunch.sh
```

- [ ] Banner reports `runtime-cuda/` (Vulkan build) selected.
- [ ] `Loading: High Performance [Q8]` (assumes ≥16 GB RAM host).
- [ ] `KV Cache: RotorQuant Memory Saver [turbo3/f16]` —or— a clean
      fallback to `Compatibility [f16/f16] [automatic fallback]`.
- [ ] Model loads, `>` prompt appears, and a fixed prompt produces a
      coherent reply.
- [ ] Pressing Enter at the post-exit prompt cleans up without errors.

## Launcher — CPU fallback

Reproduce the no-GPU case (easiest is to temporarily move
`nvidia-smi` out of `PATH`):

```bash
PATH="$(echo "$PATH" | tr ':' '\n' | grep -v cuda | paste -sd:)" ./LinuxLaunch.sh
```

- [ ] Banner reports `Runtime: CPU` (or `CPU fallback` if a CUDA build
      is present but unusable).
- [ ] Model loads and produces a reply.

## KV profile matrix

Run each of the following and confirm either a clean load or a
documented fallback:

- [ ] `FIGMENT_KV_PROFILE=compatibility ./LinuxLaunch.sh`
- [ ] `FIGMENT_KV_PROFILE=memory-saver ./LinuxLaunch.sh`
- [ ] `FIGMENT_KV_PROFILE=max-compression ./LinuxLaunch.sh`
- [ ] `FIGMENT_KV_ROTATION=planar3 FIGMENT_KV_PROFILE=memory-saver ./LinuxLaunch.sh`
- [ ] `FIGMENT_KV_ROTATION=iso3 FIGMENT_KV_PROFILE=memory-saver ./LinuxLaunch.sh`

## Model flags

- [ ] `./LinuxLaunch.sh --thinking` reports `Thinking Mode [Q8]` (or
      `[Q4]`) in the banner and the model path remains the RAM-selected
      chat model (no separate GGUF required).
- [ ] `./LinuxLaunch.sh --coder` selects the Coder Q4_K_M model.
- [ ] `--coder` falls back gracefully when the GGUF is not on disk
      (delete it, re-run, confirm fallback message).

## Benchmarks

The benchmark harness produces the table that lands in the README.

- [ ] `./benchmarks/kv_cache_bench.sh --quick --runtime cpu` completes
      and writes a JSON + markdown pair to `benchmarks/results/`.
- [ ] `./benchmarks/kv_cache_bench.sh --full` completes on this host
      (CPU sweep + CUDA sweep, full profile matrix).
- [ ] The generated markdown table is pasted into
      `.github/README.md` (replacing the current numberless KV-profile
      bullet list under **Tech Stack**).
- [ ] The raw JSON and markdown files are committed under
      `benchmarks/results/<hostname>-<gpu>-<date>.{json,md}` with the
      hardware footnote included.

## Sign-off

After every box above is ticked:

- [ ] Commit the populated `CHECKSUMS.sha256` and benchmark results.
- [ ] Update `CHANGELOG.md` with the release date.
- [ ] Tag `v1.0.0` and create the GitHub release referencing this
      completed checklist.

### Runner record

Fill in before sign-off:

- Runner name / handle: _____________________
- Hardware: CPU _____________________ / GPU _____________________
- OS + kernel: _____________________
- Date: _____________________
