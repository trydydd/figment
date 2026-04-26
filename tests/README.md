# Figment test suite

Three tiers, ordered cheap → expensive.

## Tiers

| Tier | What it tests | Deps | Wall time |
|------|---------------|------|-----------|
| `unit` | `lib/cache_types.sh` parser + selection logic | `bats` | <1 s |
| `integration` | `LinuxLaunch.sh` argv composition (via `FIGMENT_DRY_RUN=1`) and the crash/KV-error retry chain (via a stub `llama-cli`). | `bats` | ~5 s |
| `e2e` | Download upstream `llama.cpp` runtime + a tiny GGUF, run real inference across a small KV-profile sweep. | `curl`, `tar`, ~700 MB free disk | ~1-2 min on cache hit, ~3-5 min cold |

## Running

```bash
# unit + integration only (default)
./tests/run-all.sh

# include e2e
./tests/run-all.sh --e2e
./tests/run-all.sh --e2e --quick   # single KV profile

# or invoke a tier directly
bats tests/unit
bats tests/integration
./tests/e2e/tiny_smoke.sh --quick
```

## Installing `bats`

The unit and integration tiers require `bats` ≥1.10. If `apt install bats` is unavailable, install from source:

```bash
git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats-core
sudo /tmp/bats-core/install.sh /usr/local
```

## Layout

```
tests/
├── README.md
├── run-all.sh                  orchestrator
├── lib/
│   ├── stub-llama-cli          fake llama-cli for fallback tests
│   └── test_helper.bash        bats helpers (fake .system/, dry-run runner)
├── unit/
│   └── cache_types.bats        28 cases — parser + selection
├── integration/
│   ├── dry_run.bats            10 cases — argv composition under dry-run
│   └── fallback.bats           5 cases  — crash/KV-error retry chain
└── e2e/
    ├── README.md
    └── tiny_smoke.sh           runs real inference with TinyLlama Q4
```

## Test isolation

- The integration helper copies `LinuxLaunch.sh` and `lib/cache_types.sh` into a per-test tempdir before invoking the launcher. This prevents the launcher's privacy wipe (`rm -f $ROOT_DIR/main.log` and friends) from touching the real repo.
- The e2e cache lives at `.test-cache/` in the repo root; it is gitignored. Override with `FIGMENT_E2E_CACHE_DIR`.
- Both runtime and model URLs in the e2e tier are env-overridable (`FIGMENT_E2E_RUNTIME_URL`, `FIGMENT_E2E_MODEL_URL`, `FIGMENT_E2E_MODEL_NAME`) so air-gapped or sandboxed environments can mirror the artifacts.

## What's NOT covered

- GPU / Vulkan / CUDA paths. Those are gated by `RELEASE_CHECKLIST.md` and a maintainer's hardware.
- The actual interactive `-cnv` UX of the launcher. The e2e tier exercises real inference but invokes `llama-cli` directly, not via `LinuxLaunch.sh`'s interactive loop.
- `BuildYourOwn.sh` end-to-end (full USB provision). Smoke is limited to `--help`.
