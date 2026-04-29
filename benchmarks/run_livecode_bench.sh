#!/usr/bin/env bash
# Run LiveCodeBench against a local vLLM server (OpenAI-compatible API).
#
# Usage:
#   ./run_livecode_bench.sh [extra lcb_runner args...]
#
# Environment overrides:
#   PORT        vLLM server port          (default: 8000)
#   BENCH_DIR   where to clone the repo   (default: ./LiveCodeBench)
#   N_SAMPLES   generations per problem   (default: 1)
#   WORKERS     parallel API workers      (default: 4)
#
# Examples:
#   ./run_livecode_bench.sh
#   PORT=9000 ./run_livecode_bench.sh
#   N_SAMPLES=5 ./run_livecode_bench.sh --start_date 2025-01-01
#   ./run_livecode_bench.sh --scenario testoutputprediction

set -euo pipefail

MODEL="RedHatAI/Qwen3-Coder-Next-NVFP4"
PORT="${PORT:-8000}"
BASE_URL="http://localhost:${PORT}/v1"
BENCH_DIR="${BENCH_DIR:-$(dirname "$0")/LiveCodeBench}"
N_SAMPLES="${N_SAMPLES:-1}"
WORKERS="${WORKERS:-4}"

echo "==> Model:  $MODEL"
echo "==> Target: $BASE_URL"
echo "==> Output: $BENCH_DIR"
echo

# ── 1. Verify the server is reachable ─────────────────────────────────────────
if ! curl -sf "${BASE_URL}/models" -o /dev/null; then
    echo "ERROR: No response from $BASE_URL — is vLLM running on port $PORT?" >&2
    exit 1
fi

# ── 2. Clone LiveCodeBench ────────────────────────────────────────────────────
if [ ! -d "$BENCH_DIR" ]; then
    git clone --depth 1 https://github.com/LiveCodeBench/LiveCodeBench.git "$BENCH_DIR"
fi

cd "$BENCH_DIR"

# ── 3. Virtual environment ────────────────────────────────────────────────────
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
pip install -e . -q

# ── 4. Register model in lm_styles.py (idempotent) ───────────────────────────
# LiveCodeBench requires models to be listed in LanguageModelStore; it does not
# accept arbitrary names. This block adds the entry once and is a no-op on
# subsequent runs.
python3 - <<'PYEOF'
import sys
from pathlib import Path

path = Path("lcb_runner/lm_styles.py")
src = path.read_text()

MODEL = "RedHatAI/Qwen3-Coder-Next-NVFP4"
if MODEL in src:
    print(f"  [lm_styles] {MODEL} already registered")
    sys.exit(0)

entry = (
    "    LanguageModel(\n"
    f'        model_name="{MODEL}",\n'
    '        model_repr="Qwen3-Coder-Next-NVFP4",\n'
    "        model_style=LMStyle.OpenAIChat,\n"
    "        release_date=datetime(2025, 4, 1),\n"
    f'        link="https://huggingface.co/{MODEL}",\n'
    "    ),\n"
)

# Insert as the last entry of LanguageModelList, just before its closing ]
marker = "]\n\nLanguageModelStore"
if marker not in src:
    print(
        f"ERROR: expected marker ']{chr(10)}{chr(10)}LanguageModelStore' not found in {path}.\n"
        "The LiveCodeBench source layout may have changed; inspect lm_styles.py manually.",
        file=sys.stderr,
    )
    sys.exit(1)

src = src.replace(marker, entry + marker, 1)
path.write_text(src)
print(f"  [lm_styles] Registered {MODEL}")
PYEOF

# ── 5. Run ────────────────────────────────────────────────────────────────────
# OPENAI_BASE_URL is read automatically by the OpenAI SDK when base_url is not
# explicitly set in the client constructor (which is the case in oai_runner.py).
# OPENAI_KEY is what oai_runner.py passes as api_key; vLLM accepts any value.
export OPENAI_BASE_URL="$BASE_URL"
export OPENAI_KEY="dummy"
export OPENAI_API_KEY="dummy"

echo "==> Starting generation + evaluation..."
echo

python -m lcb_runner.runner.main \
    --model        "$MODEL" \
    --scenario     codegeneration \
    --n            "$N_SAMPLES" \
    --temperature  0.0 \
    --max_tokens   8192 \
    --multiprocess "$WORKERS" \
    --evaluate \
    --release_version release_latest \
    "$@"
