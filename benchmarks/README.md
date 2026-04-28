# Figment KV cache benchmarks

`kv_cache_bench.sh` exists so the README's KV-profile claims can be backed
with real numbers instead of bullet points. It sweeps the installed
`runtime-cpu/` and `runtime-cuda/` packages across the KV cache profiles
exposed by `LinuxLaunch.sh` and writes both a raw JSON file and a
paste-ready Markdown table into `benchmarks/results/`.

## Prerequisites

- A Figment build tree on disk — i.e. you have run `BuildYourOwn.sh` or are
  pointing at an installed USB target via `FIGMENT_SYSTEM_DIR=...`.
- `python3`, `awk`, `sha256sum`, `/usr/bin/time` (GNU), `curl`. All are
  preinstalled on every supported Linux distribution.
- A working `llama-bench` binary inside at least one runtime
  (`runtime-cpu/bin/llama-bench` or `runtime-cuda/bin/llama-bench`). The
  upstream `ggml-org/llama.cpp` Linux release tarballs ship it. If a
  runtime omits `llama-bench`, that runtime row is recorded as
  `skipped`.

## Quickstart

```bash
# Cheap smoke run: one model, two profiles, single runtime, single ctx.
./benchmarks/kv_cache_bench.sh --quick --runtime cpu

# Full release sweep: every runtime, every profile pair, both context
# sizes. Run on the same hardware that signs off RELEASE_CHECKLIST.md.
./benchmarks/kv_cache_bench.sh --full
```

Output filenames follow `<hostname>-<gpu>-<date>.{json,md}` so multiple
hardware configurations coexist in the same directory without collisions.

## What gets measured

Per (runtime × KV-k × KV-v × ctx) cell, one row containing:

- `prompt_tps` — prompt-evaluation tokens/sec (`llama-bench` JSON).
- `gen_tps` — token-generation tokens/sec.
- `peak_rss_mib` — high-water mark of RSS, parsed from `/usr/bin/time -v`.
- `kv_mib` — KV cache size in MiB, scraped from llama.cpp's startup log
  (the `KV self size` / `KV buffer` line).
- `wall_s`, `exit`, `status` — bookkeeping.

Cells whose KV pair is not advertised by the runtime's
`--cache-type-k` help are skipped before the run, with a `reason`
attached. Cells that crash mid-run are recorded with
`status: "failed"` and the sweep continues — the same crash-tolerant
contract the launcher uses.

## What gets _not_ measured

Quality. The benchmark does not score model output. The launcher's
existing crash-and-fallback path is the only quality gate; comparing
output checksums across cache types is on the post-v1.0 roadmap.

## Reproducibility

Numbers move with the host CPU, GPU, memory bandwidth, kernel
scheduler, and the exact llama.cpp build. Always commit the raw JSON
alongside the Markdown so future readers can verify provenance, and
always include the hardware footnote.

To compare two runs on the same machine, hold these constant:

- `--ctx`, `--model`, `FIGMENT_BENCH_N_PROMPT`, `FIGMENT_BENCH_N_GEN`,
  `FIGMENT_BENCH_REPS`.
- The `prompts/long.txt` file. Do not edit it casually — changes
  invalidate historical comparisons.

## Updating the README table

After running `--full` on the release-validation hardware:

1. Open the generated `benchmarks/results/<host>-<gpu>-<date>.md`.
2. Copy the Markdown table into `.github/README.md` under **Tech
   Stack**, replacing the current numberless bullet list of KV
   profiles.
3. Commit both the result file and the README change.

This is a copy step, not an authoring step. If the table needs hand-
editing, fix the script instead so v1.1 doesn't redo the work.
