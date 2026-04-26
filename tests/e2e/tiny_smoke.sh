#!/usr/bin/env bash
# ==============================================================================
#  tiny_smoke.sh
#  End-to-end smoke test: download upstream llama.cpp + a small llama-arch GGUF,
#  then run real inference against a small KV-profile matrix and assert the
#  model produced output. Exercises the runtime tarball, cache-type knobs, and
#  actual model loading on the host. No GPU required.
# ==============================================================================
set -u
set -o pipefail

# ---- Configuration ----------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CACHE_DIR="${FIGMENT_E2E_CACHE_DIR:-$REPO_ROOT/.test-cache}"

RUNTIME_TAG="b8893"
RUNTIME_TARBALL_NAME="llama-${RUNTIME_TAG}-bin-ubuntu-x64.tar.gz"
RUNTIME_URL="${FIGMENT_E2E_RUNTIME_URL:-https://github.com/ggml-org/llama.cpp/releases/download/${RUNTIME_TAG}/${RUNTIME_TARBALL_NAME}}"

MODEL_NAME="${FIGMENT_E2E_MODEL_NAME:-tinyllama-1.1b-chat-v0.3.Q4_K_M.gguf}"
MODEL_URL="${FIGMENT_E2E_MODEL_URL:-https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v0.3-GGUF/resolve/main/tinyllama-1.1b-chat-v0.3.Q4_K_M.gguf}"

PROMPT="The capital of France is"
N_PREDICT=16

# Default KV-profile sweep — first entry is also the --quick case.
KV_PROFILES=(
    "f16:f16"
    "q8_0:f16"
    "q4_0:q4_0"
)

QUICK_MODE="false"
while [ $# -gt 0 ]; do
    case "$1" in
        --quick)
            QUICK_MODE="true"
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: $(basename "$0") [--quick]

Downloads upstream llama.cpp ${RUNTIME_TAG} CPU runtime and a tiny GGUF model,
then runs real inference across a small KV-profile sweep.

Options:
  --quick   Run only the f16/f16 case (fastest).

Environment:
  FIGMENT_E2E_CACHE_DIR   Override the download/extract cache (default:
                          \$REPO_ROOT/.test-cache).
  FIGMENT_E2E_RUNTIME_URL Override the llama.cpp runtime tarball URL.
  FIGMENT_E2E_MODEL_URL   Override the GGUF model URL.
  FIGMENT_E2E_MODEL_NAME  Override the on-disk model filename (must match the
                          basename you'd want under .test-cache/downloads/).
EOF
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [ "$QUICK_MODE" = "true" ]; then
    KV_PROFILES=( "f16:f16" )
fi

# ---- Helpers ----------------------------------------------------------------

log()  { printf '[tiny_smoke] %s\n' "$*" >&2; }
warn() { printf '[tiny_smoke] WARN: %s\n' "$*" >&2; }
die()  { printf '[tiny_smoke] ERROR: %s\n' "$*" >&2; exit 1; }

# Mirror LinuxLaunch.sh's runtime_library_path_for_binary so we exercise the
# same library-resolution behaviour the launcher uses in production.
runtime_library_path_for_binary() {
    local candidate="$1"
    local binary_dir=""
    local runtime_root=""
    local runtime_root_has_shared_libs="false"
    local path_candidate=""
    local library_path=""

    [ -n "$candidate" ] || return 0
    binary_dir="$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P)" || return 0
    runtime_root="$(cd "$binary_dir/.." 2>/dev/null && pwd -P)" || return 0
    if [ -n "$(find "$runtime_root" -maxdepth 1 -type f \( -name '*.so' -o -name '*.so.*' \) -print -quit)" ]; then
        runtime_root_has_shared_libs="true"
    fi

    for path_candidate in "$runtime_root/lib" "$runtime_root/lib64" "$runtime_root"; do
        if [ -d "$path_candidate" ]; then
            if [ "$path_candidate" = "$runtime_root" ] && [ "$runtime_root_has_shared_libs" != "true" ]; then
                continue
            fi
            if [ -n "$library_path" ]; then
                library_path="${library_path}:$path_candidate"
            else
                library_path="$path_candidate"
            fi
        fi
    done

    printf '%s\n' "$library_path"
}

download_if_missing() {
    local url="$1"
    local dest="$2"

    if [ -s "$dest" ]; then
        log "Cached: $(basename "$dest") ($(du -h "$dest" | awk '{print $1}'))"
        return 0
    fi

    log "Downloading: $url"
    log "       into: $dest"
    mkdir -p "$(dirname "$dest")"
    # -C - resumes partial downloads if curl was interrupted previously.
    if ! curl -fL --progress-bar -C - -o "$dest" "$url"; then
        rm -f "$dest"
        die "Download failed: $url"
    fi
    [ -s "$dest" ] || die "Downloaded file is empty: $dest"
    log "Downloaded: $(basename "$dest") ($(du -h "$dest" | awk '{print $1}'))"
}

extract_runtime_if_needed() {
    local tarball="$1"
    local out_dir="$2"

    # Sentinel: if we already have an llama-cli somewhere under out_dir, skip.
    if [ -d "$out_dir" ] && find "$out_dir" -type f -name 'llama-cli' -print -quit 2>/dev/null | grep -q .; then
        log "Runtime already extracted at: $out_dir"
        return 0
    fi

    mkdir -p "$out_dir"
    log "Extracting runtime tarball into: $out_dir"
    tar -xzf "$tarball" -C "$out_dir" || die "Failed to extract $tarball"
}

locate_llama_cli() {
    local search_root="$1"
    local found
    found="$(find "$search_root" -type f -name 'llama-cli' -print -quit 2>/dev/null || true)"
    [ -n "$found" ] || return 1
    [ -x "$found" ] || chmod +x "$found" 2>/dev/null || true
    printf '%s\n' "$found"
}

# Run inference for one (k, v) cache-type pair. Echoes a single line:
#   PASS|FAIL|FALLBACK <profile> <details>
run_one_profile() {
    local llama_cli="$1"
    local model_path="$2"
    local k="$3"
    local v="$4"
    local lib_path="$5"

    local label="${k}/${v}"
    local stdout_file stderr_file
    stdout_file="$(mktemp -t tiny_smoke.stdout.XXXXXX)"
    stderr_file="$(mktemp -t tiny_smoke.stderr.XXXXXX)"

    log "----------------------------------------------------------------"
    log "Running profile: $label"

    local -a cmd=(
        "$llama_cli"
        -m "$model_path"
        -p "$PROMPT"
        -n "$N_PREDICT"
        -no-cnv
        --cache-type-k "$k"
        --cache-type-v "$v"
        --log-disable
    )

    local exit_code=0
    if [ -n "$lib_path" ]; then
        LD_LIBRARY_PATH="${lib_path}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
            "${cmd[@]}" >"$stdout_file" 2>"$stderr_file" || exit_code=$?
    else
        "${cmd[@]}" >"$stdout_file" 2>"$stderr_file" || exit_code=$?
    fi

    local stdout_content stderr_content
    stdout_content="$(cat "$stdout_file")"
    stderr_content="$(cat "$stderr_file")"

    # Patterns that indicate the runtime declined this cache type — these are
    # the same errors LinuxLaunch.sh treats as "fall back to f16/f16".
    local kv_error_pattern='unsupported cache type|cache type .*not supported|unknown (argument|option).*(cache-type|ctk|ctv)|invalid (argument|value).*(cache-type|ctk|ctv)|unrecognized option.*(cache-type|ctk|ctv)'

    local verdict="FAIL"
    local reason=""

    if [ "$exit_code" -eq 0 ]; then
        # Check the model produced something beyond the prompt: any alphabetic
        # character in stdout that isn't merely the prompt itself.
        local generated="$stdout_content"
        # Strip the prompt occurrence from the start of stdout if present so
        # we're really asserting *new* tokens.
        local stripped="${generated#"$PROMPT"}"
        if [ -n "$generated" ] && printf '%s' "$stripped" | grep -q '[A-Za-z]'; then
            verdict="PASS"
            # Trim to a single-line preview for readability.
            local preview
            preview="$(printf '%s' "$stripped" | tr '\n' ' ' | sed 's/  */ /g' | head -c 200)"
            reason="output: ${preview}"
        else
            reason="exit 0 but stdout had no alphabetic content beyond prompt"
        fi
    else
        if printf '%s' "$stderr_content" | grep -Eiq "$kv_error_pattern"; then
            verdict="FALLBACK"
            reason="runtime rejected cache-type ${label} (documented fallback)"
        else
            reason="exit=$exit_code; stderr tail: $(printf '%s' "$stderr_content" | tail -n 5 | tr '\n' ' ' | head -c 400)"
        fi
    fi

    case "$verdict" in
        PASS)     log "  [PASS] $label — $reason" ;;
        FALLBACK) log "  [FALLBACK] $label — $reason" ;;
        FAIL)     log "  [FAIL] $label — $reason" ;;
    esac

    rm -f "$stdout_file" "$stderr_file"
    printf '%s\n' "$verdict"
}

# ---- Main -------------------------------------------------------------------

log "Cache dir: $CACHE_DIR"
mkdir -p "$CACHE_DIR/downloads" "$CACHE_DIR/runtime" || die "Cannot create cache dir"

RUNTIME_TARBALL="$CACHE_DIR/downloads/$RUNTIME_TARBALL_NAME"
MODEL_PATH="$CACHE_DIR/downloads/$MODEL_NAME"
RUNTIME_DIR="$CACHE_DIR/runtime"

download_if_missing "$RUNTIME_URL" "$RUNTIME_TARBALL"
download_if_missing "$MODEL_URL"   "$MODEL_PATH"

extract_runtime_if_needed "$RUNTIME_TARBALL" "$RUNTIME_DIR"

LLAMA_CLI="$(locate_llama_cli "$RUNTIME_DIR" || true)"
[ -n "$LLAMA_CLI" ] || die "llama-cli not found under $RUNTIME_DIR"
log "llama-cli: $LLAMA_CLI"

LIB_PATH="$(runtime_library_path_for_binary "$LLAMA_CLI")"
if [ -n "$LIB_PATH" ]; then
    log "LD_LIBRARY_PATH (runtime libs): $LIB_PATH"
else
    log "LD_LIBRARY_PATH: (none — no bundled libs detected)"
fi

# Quick smoke that the binary at least loads its libs and prints help.
if [ -n "$LIB_PATH" ]; then
    LD_LIBRARY_PATH="${LIB_PATH}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        "$LLAMA_CLI" --help >/dev/null 2>&1 \
        || die "llama-cli --help failed (libs not loadable?)"
else
    "$LLAMA_CLI" --help >/dev/null 2>&1 \
        || die "llama-cli --help failed"
fi
log "llama-cli --help: OK"

declare -a RESULTS=()
declare -A VERDICT_OF=()
overall_pass="true"
saw_any_pass="false"

for pair in "${KV_PROFILES[@]}"; do
    k="${pair%:*}"
    v="${pair#*:}"
    verdict="$(run_one_profile "$LLAMA_CLI" "$MODEL_PATH" "$k" "$v" "$LIB_PATH")"
    RESULTS+=( "$pair=$verdict" )
    VERDICT_OF["$pair"]="$verdict"
    case "$verdict" in
        PASS)     saw_any_pass="true" ;;
        FALLBACK) : ;;  # acceptable
        FAIL)     overall_pass="false" ;;
    esac
done

log "================================================================"
log "Summary:"
for pair in "${KV_PROFILES[@]}"; do
    log "  ${pair} -> ${VERDICT_OF[$pair]}"
done

# Top-level rule: at least one PASS is required, and no profile may FAIL.
# FALLBACK is acceptable on its own (documented runtime decline) but cannot
# be the *only* verdict — we need a real successful inference somewhere.
if [ "$overall_pass" != "true" ] || [ "$saw_any_pass" != "true" ]; then
    log "Result: FAIL"
    exit 1
fi

log "Result: PASS"
exit 0
