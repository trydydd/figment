# Changelog

All notable changes to Figment are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `LICENSES/` directory containing upstream MIT (llama.cpp) and Apache 2.0
  (Qwen) attributions, copied onto the target USB by `BuildYourOwn.sh`.
- `CHECKSUMS.sha256` manifest and corresponding verification in
  `BuildYourOwn.sh::download_file`. `FIGMENT_SKIP_CHECKSUMS=1` and
  `FIGMENT_CHECKSUMS_FILE=...` escape hatches for users overriding URLs.
- `RELEASE_CHECKLIST.md` — the v1.0.0 release gate, including the CUDA /
  Vulkan validation runbook.
- `.github/workflows/smoke.yml` — `bash -n`, `shellcheck`, `--help` smoke
  job for both shell scripts plus a release-artifact presence check.
- `benchmarks/kv_cache_bench.sh` plus `benchmarks/prompts/long.txt` and
  `benchmarks/README.md` — KV cache sweep harness that emits paste-ready
  Markdown tables for `.github/README.md`.
- `lib/cache_types.sh` — shared cache-type detection helpers used by the
  launcher and the benchmark harness so the parsing logic does not
  diverge.
- `dev/bootstrap-local.sh`, `dev/launch-local.sh`, `dev/bench-local.sh`
  — local development scaffold that provisions `./local-dev/.system/`
  via the production builder and runs the launcher / benchmark against
  it without a USB stick.
- Two new launcher env vars: `FIGMENT_SYSTEM_DIR` overrides the
  `.system/` location (mirrors the benchmark's existing knob), and
  `FIGMENT_MODEL_OVERRIDE` boots a specific GGUF and bypasses the
  High / Low / Thinking / Coder selection path.
- `FIGMENT_VERBOSE=1` (or `true`/`yes`/`on`) keeps llama.cpp's runtime
  logs visible. The launcher adds `--log-disable` by default for a
  clean end-user prompt; `dev/launch-local.sh` now flips this on
  automatically so contributors see the full log stream. The e2e
  smoke test (`tests/e2e/tiny_smoke.sh`) honours the same contract.

### Changed
- `LinuxLaunch.sh` GPU banner now reads `GPU acceleration via runtime-cuda/
  (Vulkan build)` to reflect that the default runtime is the upstream
  Vulkan binary even when an NVIDIA card is present.
- `.github/README.md` clarifies that `runtime-cuda/` ships the Vulkan
  build by default and documents `LLAMA_CPP_CUDA_PACKAGE_URL` overrides
  for users who want a pure CUDA build.

### Known limitations (carry-over to v1.0.0)
- Pure CUDA (non-Vulkan) builds remain untested — the bundled GPU
  runtime is Vulkan; NVIDIA hardware works through the Vulkan driver.
- ARM64 builds are produced but have not been formally validated.
- Release artifacts are not GPG-signed.
- KV cache fallback is a single retry from the requested profile to
  `f16/f16`; there is no automatic CPU-runtime fallback if the GPU
  runtime fails for non-KV reasons.

## [1.0.0] — TBD

First public release; pending completion of `RELEASE_CHECKLIST.md` on
NVIDIA hardware.

- Rebrand from `llmstick` to Figment.
- Linux-only, fully-offline launcher with no telemetry and aggressive
  history wipes (`LinuxLaunch.sh`).
- USB build pipeline pinned to `ggml-org/llama.cpp` release `b8893`,
  with optional rotorquant rebuild via
  `johndpope/llama-cpp-turboquant` branch
  `feature/planarquant-kv-cache` commit `20efe75`.
- Three KV cache profiles (`compatibility`, `memory-saver`,
  `max-compression`) plus the `FIGMENT_KV_ROTATION` knob for
  `turbo3` / `planar3` / `iso3` rotorquant families. Crash-tolerant
  fallback to `f16/f16` when the runtime does not advertise the
  requested cache type.
- `--thinking` and `--coder` model selection flags, with graceful
  fallback when the corresponding GGUF is not on disk.

[Unreleased]: https://github.com/trydydd/figment/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/trydydd/figment/releases/tag/v1.0.0
