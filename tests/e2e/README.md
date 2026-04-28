# End-to-end smoke test

`tiny_smoke.sh` validates that the upstream llama.cpp CPU runtime tarball, the
launcher's cache-type knobs, and real model loading all work end-to-end on the
host. No GPU required.

## What it does

1. Downloads (and caches) two artifacts:
   - **Runtime tarball** — `ggml-org/llama.cpp` release `b8893` Linux CPU build
     (~50 MB).
   - **Tiny model** — `tinyllama-1.1b-chat-v0.3.Q4_K_M.gguf` (~640 MB,
     llama-architecture, works in every llama.cpp version).
2. Extracts the runtime tarball.
3. Locates `llama-cli` inside the extracted tree and the matching
   `LD_LIBRARY_PATH` (mirrors `LinuxLaunch.sh`'s
   `runtime_library_path_for_binary`).
4. Sweeps a small KV-profile matrix (`f16:f16`, `q8_0:f16`, `q4_0:q4_0`),
   running real inference for each and asserting the model produced output.
   Profiles the runtime declines (with the documented "unsupported cache
   type" message) are treated as `FALLBACK`, not failure — the launcher
   handles those at runtime.

## Prerequisites

- `bash`, `curl`, `tar` — that's it. No Python, no special tooling.
- ~700 MB free disk for the cache directory.
- Outbound network access to `github.com` and `huggingface.co`.

## Running

```bash
# Fast iteration: f16/f16 only.
./tests/e2e/tiny_smoke.sh --quick

# Full sweep (f16/f16, q8_0/f16, q4_0/q4_0).
./tests/e2e/tiny_smoke.sh
```

Exit code `0` means at least one profile produced real model output and no
profile failed unexpectedly. Non-zero means something is wrong with the
runtime, the model, or your host.

## Cache directory

Default: `<repo-root>/.test-cache/` (gitignored). Override with
`FIGMENT_E2E_CACHE_DIR`.

Layout:

```
.test-cache/
├── downloads/
│   ├── llama-b8893-bin-ubuntu-x64.tar.gz   # runtime tarball
│   └── tinyllama-1.1b-chat-v0.3.Q4_K_M.gguf  # tiny model
└── runtime/
    └── llama-b8893-bin-ubuntu-x64/
        └── build/bin/llama-cli              # exact nesting depends on release
```

Re-running the script reuses both downloads and the extracted runtime, so
subsequent runs take seconds rather than minutes.

## Clearing the cache

```bash
rm -rf .test-cache/
# or, if you set the override:
rm -rf "$FIGMENT_E2E_CACHE_DIR"
```
