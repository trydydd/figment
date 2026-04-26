#!/bin/bash
# bench-local.sh — run kv_cache_bench.sh against the dev local-dev/ tree.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_DIR="${FIGMENT_LOCAL_DIR:-$REPO_ROOT/local-dev}"
if [ "$#" -eq 0 ]; then
    set -- --quick --runtime cpu
fi
exec env FIGMENT_SYSTEM_DIR="$LOCAL_DIR/.system" "$REPO_ROOT/benchmarks/kv_cache_bench.sh" "$@"
