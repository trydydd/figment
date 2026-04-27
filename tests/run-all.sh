#!/bin/bash
# run-all.sh — orchestrator for the Figment test suite.
#
# Tiers:
#   unit          pure bats tests against lib/cache_types.sh (zero deps).
#   integration   bats tests against LinuxLaunch.sh using FIGMENT_DRY_RUN
#                 and a stub llama-cli (zero network, zero model load).
#   e2e           downloads the upstream runtime + a tiny GGUF, runs real
#                 inference (~700 MB cache, ~1-2 min on cache hit). Skipped
#                 by default; opt in with --e2e or FIGMENT_RUN_E2E=1.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RUN_E2E="${FIGMENT_RUN_E2E:-0}"
QUICK="false"

usage() {
    cat <<EOF
Usage: ./tests/run-all.sh [options]

Options:
  --e2e         Include the e2e tier (downloads, real inference).
  --quick       Pass --quick to the e2e script (single profile).
  --no-color    Disable color output.
  -h, --help    Show this help.

Environment:
  FIGMENT_RUN_E2E=1   Equivalent to --e2e.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --e2e)      RUN_E2E=1; shift ;;
        --quick)    QUICK="true"; shift ;;
        --no-color) NO_COLOR=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    BOLD=""; GREEN=""; RED=""; DIM=""; RESET=""
fi

if ! command -v bats >/dev/null 2>&1; then
    echo "${RED}bats not installed.${RESET} Install with: sudo ./install.sh /usr/local from https://github.com/bats-core/bats-core" >&2
    exit 127
fi

run_tier() {
    local label="$1"; shift
    printf '%s== %s ==%s\n' "$BOLD" "$label" "$RESET"
    if "$@"; then
        printf '%s  %s passed%s\n\n' "$GREEN" "$label" "$RESET"
        return 0
    else
        printf '%s  %s FAILED%s\n\n' "$RED" "$label" "$RESET"
        return 1
    fi
}

cd "$REPO_ROOT"

# --print-output-on-failure surfaces a failing test's captured stdout/stderr
# inline in the bats summary. Cheap insurance against silent failures —
# especially for the integration tier where the launcher's stderr is the
# whole story.
BATS_FLAGS=(--print-output-on-failure)

unit_status=0
run_tier "unit" bats "${BATS_FLAGS[@]}" tests/unit || unit_status=$?

integration_status=0
run_tier "integration" bats "${BATS_FLAGS[@]}" tests/integration || integration_status=$?

e2e_status=0
if [ "$RUN_E2E" = "1" ]; then
    e2e_args=()
    [ "$QUICK" = "true" ] && e2e_args+=(--quick)
    run_tier "e2e (tiny model)" tests/e2e/tiny_smoke.sh "${e2e_args[@]}" || e2e_status=$?
else
    printf '%s== e2e (skipped) ==%s\n' "$BOLD" "$RESET"
    printf '%s  pass --e2e or set FIGMENT_RUN_E2E=1 to include%s\n\n' "$DIM" "$RESET"
fi

if [ "$unit_status" -ne 0 ] || [ "$integration_status" -ne 0 ] || [ "$e2e_status" -ne 0 ]; then
    printf '%sSome tiers failed.%s\n' "$RED" "$RESET"
    exit 1
fi
printf '%sAll tiers passed.%s\n' "$GREEN" "$RESET"
