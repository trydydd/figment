#!/bin/bash
# kv_cache_bench.sh
# Sweep KV cache profiles across the installed llama.cpp runtimes and emit
# paste-ready JSON + Markdown into benchmarks/results/.
#
# Usage:
#   ./benchmarks/kv_cache_bench.sh [--quick|--full]
#                                  [--runtime cpu|cuda|all]
#                                  [--model MODEL_FILE]
#                                  [--ctx N]
#                                  [--output-dir PATH]
#                                  [--prompt FILE]
#
# Defaults: --quick --runtime all, model auto-picked from .system/, ctx 4096.
# Designed to be safe to run on a host that lacks GPU/CUDA — unavailable
# runtimes and unsupported KV pairs are recorded and skipped.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SYSTEM_DIR="${FIGMENT_SYSTEM_DIR:-$REPO_ROOT/.system}"

# shellcheck source=../lib/cache_types.sh
. "$REPO_ROOT/lib/cache_types.sh"

MODE="quick"
RUNTIME_FILTER="all"
MODEL_OVERRIDE=""
CTX_OVERRIDE=""
OUTPUT_DIR="$SCRIPT_DIR/results"
PROMPT_FILE="$SCRIPT_DIR/prompts/long.txt"
N_GEN="${FIGMENT_BENCH_N_GEN:-128}"
N_PROMPT="${FIGMENT_BENCH_N_PROMPT:-512}"
N_REPS="${FIGMENT_BENCH_REPS:-2}"

usage() {
    cat <<'EOF'
Usage: ./benchmarks/kv_cache_bench.sh [options]

  --quick                One model, two profiles (default).
  --full                 Whole matrix (all installed runtimes, all profile pairs).
  --runtime cpu|cuda|all Restrict to one runtime (default: all).
  --model PATH           Override model file (defaults to first GGUF found).
  --ctx N                Override context size (default: 4096).
  --output-dir PATH      Override results directory.
  --prompt FILE          Override the fixed prompt file.
  -h, --help             Show this help.

Environment overrides:
  FIGMENT_SYSTEM_DIR     Path to .system/ (default: <repo>/.system).
  FIGMENT_BENCH_N_GEN    Tokens generated per run (default: 128).
  FIGMENT_BENCH_N_PROMPT Prompt-eval tokens per run (default: 512).
  FIGMENT_BENCH_REPS     Repetitions per configuration (default: 2).
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --quick)        MODE="quick"; shift ;;
        --full)         MODE="full"; shift ;;
        --runtime)      RUNTIME_FILTER="$2"; shift 2 ;;
        --model)        MODEL_OVERRIDE="$2"; shift 2 ;;
        --ctx)          CTX_OVERRIDE="$2"; shift 2 ;;
        --output-dir)   OUTPUT_DIR="$2"; shift 2 ;;
        --prompt)       PROMPT_FILE="$2"; shift 2 ;;
        -h|--help)      usage; exit 0 ;;
        *)              echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

case "$RUNTIME_FILTER" in
    cpu|cuda|all) ;;
    *) echo "Invalid --runtime: $RUNTIME_FILTER" >&2; exit 1 ;;
esac

if [ ! -d "$SYSTEM_DIR" ]; then
    echo "ERROR: .system/ not found at $SYSTEM_DIR" >&2
    echo "Run BuildYourOwn.sh first, or set FIGMENT_SYSTEM_DIR=..." >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

resolve_binary() {
    local root="$1"
    local name="$2"
    local search_root candidate
    local -a search_roots=()
    shopt -s nullglob
    search_roots=( "$root"/ "$root"/*/ "$root"/*/*/ )
    shopt -u nullglob
    for search_root in "${search_roots[@]}"; do
        candidate="${search_root%/}/bin/$name"
        if [ -x "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
        candidate="${search_root%/}/$name"
        if [ -x "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
    done
    return 1
}

runtime_lib_path() {
    local candidate="$1"
    local binary_dir runtime_root path library_path=""
    [ -n "$candidate" ] || return 0
    binary_dir="$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P)" || return 0
    runtime_root="$(cd "$binary_dir/.." 2>/dev/null && pwd -P)" || return 0
    for path in "$runtime_root/lib" "$runtime_root/lib64" "$runtime_root"; do
        if [ -d "$path" ]; then
            library_path="${library_path:+$library_path:}$path"
        fi
    done
    printf '%s\n' "$library_path"
}

run_with_libs() {
    local candidate="$1"; shift
    local lp
    lp="$(runtime_lib_path "$candidate")"
    if [ -n "$lp" ]; then
        LD_LIBRARY_PATH="${lp}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$candidate" "$@"
    else
        "$candidate" "$@"
    fi
}

pick_default_model() {
    local f
    for f in \
        "$SYSTEM_DIR/Qwen3-4B-Instruct-2507-abliterated.Q8_0.gguf" \
        "$SYSTEM_DIR/Qwen3-4B-Instruct-2507-abliterated.Q4_K_M.gguf" \
        "$SYSTEM_DIR/Qwen3-4B-Thinking-2507-abliterated.Q8_0.gguf" \
        "$SYSTEM_DIR/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf"
    do
        if [ -f "$f" ]; then printf '%s\n' "$f"; return 0; fi
    done
    return 1
}

if [ -n "$MODEL_OVERRIDE" ]; then
    MODEL_FILE="$MODEL_OVERRIDE"
else
    MODEL_FILE="$(pick_default_model 2>/dev/null || true)"
fi

if [ -z "$MODEL_FILE" ] || [ ! -f "$MODEL_FILE" ]; then
    echo "ERROR: no model GGUF found under $SYSTEM_DIR (use --model PATH)" >&2
    exit 1
fi

CTX_LIST=("${CTX_OVERRIDE:-4096}")
if [ -z "$CTX_OVERRIDE" ] && [ "$MODE" = "full" ]; then
    CTX_LIST=(4096 8192)
fi

if [ "$MODE" = "quick" ]; then
    PROFILE_PAIRS=( "f16:f16" "turbo3:f16" )
else
    PROFILE_PAIRS=(
        "f16:f16"
        "turbo3:f16" "turbo3:turbo3"
        "planar3:f16" "planar3:planar3"
        "iso3:f16" "iso3:iso3"
    )
fi

RUNTIMES=()
case "$RUNTIME_FILTER" in
    cpu)  RUNTIMES=(cpu) ;;
    cuda) RUNTIMES=(cuda) ;;
    all)  RUNTIMES=(cpu cuda) ;;
esac

HOST="$(hostname -s 2>/dev/null || echo host)"
GPU_TAG="$(command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | tr -c 'A-Za-z0-9' '_' | sed 's/__*/_/g; s/^_//; s/_$//')"
[ -n "$GPU_TAG" ] || GPU_TAG="nogpu"
DATE_TAG="$(date -u +%Y%m%d)"
RESULT_BASE="$OUTPUT_DIR/${HOST}-${GPU_TAG}-${DATE_TAG}"
JSON_OUT="$RESULT_BASE.json"
MD_OUT="$RESULT_BASE.md"

declare -a ROWS_JSON=()
declare -a ROWS_MD=()

emit_skip_row() {
    local runtime="$1" ctk="$2" ctv="$3" ctx="$4" reason="$5"
    ROWS_JSON+=( "$(printf '{"runtime":"%s","ctk":"%s","ctv":"%s","ctx":%d,"status":"skipped","reason":"%s"}' \
        "$runtime" "$ctk" "$ctv" "$ctx" "$reason")" )
    ROWS_MD+=( "| $runtime | $ctk/$ctv | $ctx | _skipped_ | _skipped_ | _skipped_ | _skipped_ | $reason |" )
}

emit_result_row() {
    local runtime="$1" ctk="$2" ctv="$3" ctx="$4" status="$5"
    local prompt_tps="$6" gen_tps="$7" peak_rss_mib="$8" kv_mib="$9" wall="${10}" exitcode="${11}" log_excerpt="${12}"
    ROWS_JSON+=( "$(printf '{"runtime":"%s","ctk":"%s","ctv":"%s","ctx":%d,"status":"%s","prompt_tps":%s,"gen_tps":%s,"peak_rss_mib":%s,"kv_mib":%s,"wall_s":%s,"exit":%d}' \
        "$runtime" "$ctk" "$ctv" "$ctx" "$status" \
        "${prompt_tps:-null}" "${gen_tps:-null}" "${peak_rss_mib:-null}" "${kv_mib:-null}" "${wall:-null}" "${exitcode:-0}")" )
    ROWS_MD+=( "| $runtime | $ctk/$ctv | $ctx | ${prompt_tps:-—} | ${gen_tps:-—} | ${peak_rss_mib:-—} | ${kv_mib:-—} | $status |" )
    if [ -n "$log_excerpt" ]; then
        printf '%s\n' "$log_excerpt" >&2
    fi
}

run_llama_bench() {
    local binary="$1" ctk="$2" ctv="$3" ctx="$4" log="$5"
    /usr/bin/time -v -o "$log.time" \
        $(command -v setsid 2>/dev/null) \
        bash -c "$(declare -f run_with_libs runtime_lib_path); run_with_libs '$binary' \
            -m '$MODEL_FILE' -p '$N_PROMPT' -n '$N_GEN' -r '$N_REPS' \
            -ctk '$ctk' -ctv '$ctv' -c '$ctx' -o json" \
        >"$log" 2>"$log.stderr"
}

parse_metric() {
    local json="$1" key="$2"
    python3 - "$json" "$key" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
key = sys.argv[2]
rows = data if isinstance(data, list) else data.get("results", data.get("rows", []))
vals = []
for row in rows:
    v = row.get(key)
    if isinstance(v, (int, float)):
        vals.append(v)
if vals:
    print(f"{sum(vals)/len(vals):.2f}")
PY
}

parse_kv_mib() {
    local stderr="$1"
    grep -Eio 'KV[ _]?(self|buffer)[^0-9]*([0-9]+\.[0-9]+|[0-9]+)[[:space:]]*MiB' "$stderr" \
        | grep -Eo '[0-9]+\.[0-9]+|[0-9]+' \
        | sort -n -r \
        | head -1
}

parse_peak_rss_mib() {
    local time_log="$1"
    awk '/Maximum resident set size/ { printf "%.1f\n", $NF/1024; exit }' "$time_log" 2>/dev/null
}

run_one() {
    local runtime="$1" ctk="$2" ctv="$3" ctx="$4"
    local runtime_dir="$SYSTEM_DIR/runtime-$runtime"
    [ -d "$runtime_dir" ] || { emit_skip_row "$runtime" "$ctk" "$ctv" "$ctx" "runtime-$runtime not installed"; return; }

    local bench
    bench="$(resolve_binary "$runtime_dir" "llama-bench" 2>/dev/null || true)"
    if [ -z "$bench" ]; then
        emit_skip_row "$runtime" "$ctk" "$ctv" "$ctx" "llama-bench missing in runtime-$runtime"
        return
    fi

    local cli
    cli="$(resolve_binary "$runtime_dir" "llama-cli" 2>/dev/null || true)"
    if [ -n "$cli" ]; then
        figment_detect_supported_cache_types "$cli"
        if ! figment_cache_type_supported "$ctk" || ! figment_cache_type_supported "$ctv"; then
            emit_skip_row "$runtime" "$ctk" "$ctv" "$ctx" "cache type unsupported by runtime"
            return
        fi
    fi

    local log
    log="$(mktemp -t figment-bench.XXXXXX.json)"
    local start end wall exit_code=0
    start="$(date +%s)"
    if ! run_llama_bench "$bench" "$ctk" "$ctv" "$ctx" "$log"; then
        exit_code=$?
    fi
    end="$(date +%s)"
    wall=$((end - start))

    local prompt_tps gen_tps peak_rss kv_mib status="ok"
    prompt_tps="$(parse_metric "$log" "avg_ts" 2>/dev/null || true)"
    [ -z "$prompt_tps" ] && prompt_tps="$(parse_metric "$log" "prompt_token_per_sec" 2>/dev/null || true)"
    gen_tps="$(parse_metric "$log" "gen_token_per_sec" 2>/dev/null || true)"
    [ -z "$gen_tps" ] && gen_tps="$prompt_tps"
    peak_rss="$(parse_peak_rss_mib "$log.time" 2>/dev/null || true)"
    kv_mib="$(parse_kv_mib "$log.stderr" 2>/dev/null || true)"

    if [ "$exit_code" -ne 0 ]; then
        status="failed"
    fi

    emit_result_row "$runtime" "$ctk" "$ctv" "$ctx" "$status" \
        "$prompt_tps" "$gen_tps" "$peak_rss" "$kv_mib" "$wall" "$exit_code" ""

    rm -f "$log" "$log.time" "$log.stderr"
}

echo "Figment KV cache benchmark"
echo "  mode:      $MODE"
echo "  model:     $MODEL_FILE"
echo "  prompt:    $PROMPT_FILE"
echo "  output:    $RESULT_BASE.{json,md}"
echo "  runtimes:  ${RUNTIMES[*]}"
echo "  ctx:       ${CTX_LIST[*]}"
echo "  profiles:  ${PROFILE_PAIRS[*]}"
echo

for runtime in "${RUNTIMES[@]}"; do
    for ctx in "${CTX_LIST[@]}"; do
        for pair in "${PROFILE_PAIRS[@]}"; do
            ctk="${pair%%:*}"
            ctv="${pair##*:}"
            echo "  -> $runtime  $ctk/$ctv  ctx=$ctx"
            run_one "$runtime" "$ctk" "$ctv" "$ctx"
        done
    done
done

{
    printf '{\n'
    printf '  "host": "%s",\n' "$HOST"
    printf '  "gpu": "%s",\n' "$GPU_TAG"
    printf '  "date_utc": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "model": "%s",\n' "$(basename -- "$MODEL_FILE")"
    printf '  "mode": "%s",\n' "$MODE"
    printf '  "n_prompt": %d,\n' "$N_PROMPT"
    printf '  "n_gen": %d,\n' "$N_GEN"
    printf '  "rows": [\n'
    n=${#ROWS_JSON[@]}
    for ((i=0; i<n; i++)); do
        if (( i + 1 < n )); then
            printf '    %s,\n' "${ROWS_JSON[i]}"
        else
            printf '    %s\n'  "${ROWS_JSON[i]}"
        fi
    done
    printf '  ]\n}\n'
} > "$JSON_OUT"

{
    printf '# KV cache benchmark — %s (%s)\n\n' "$HOST" "$GPU_TAG"
    printf '- Date: %s\n' "$(date -u +%Y-%m-%d)"
    printf '- Model: `%s`\n' "$(basename -- "$MODEL_FILE")"
    printf '- Mode: `%s` (n_prompt=%d, n_gen=%d, reps=%d)\n\n' "$MODE" "$N_PROMPT" "$N_GEN" "$N_REPS"
    printf '| Runtime | KV (k/v) | ctx | prompt tok/s | gen tok/s | peak RSS (MiB) | KV cache (MiB) | status |\n'
    printf '|---------|----------|-----|--------------|-----------|----------------|----------------|--------|\n'
    for row in "${ROWS_MD[@]}"; do
        printf '%s\n' "$row"
    done
    printf '\nGenerated by `benchmarks/kv_cache_bench.sh`. Numbers are hardware-specific; do not extrapolate.\n'
} > "$MD_OUT"

echo
echo "Wrote:"
echo "  $JSON_OUT"
echo "  $MD_OUT"
