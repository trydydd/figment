#!/bin/bash
# bootstrap-local.sh — provision a local .system/ tree for development.
#
# Usage: ./dev/bootstrap-local.sh [extra args forwarded to BuildYourOwn.sh]
#
# Env vars:
#   FIGMENT_LOCAL_DIR        Override the local target dir (default: ./local-dev).
#   FIGMENT_LOCAL_MODEL_URL  Override the small (Q4) model URL. Must have a
#                            CHECKSUMS.sha256 entry, or run with
#                            FIGMENT_SKIP_CHECKSUMS=1.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_DIR="${FIGMENT_LOCAL_DIR:-$REPO_ROOT/local-dev}"

usage() {
    cat <<EOF
Usage: ./dev/bootstrap-local.sh [BuildYourOwn.sh-args...]

Provisions a local .system/ tree at \$FIGMENT_LOCAL_DIR (default: ./local-dev)
without writing to a USB stick. Wraps BuildYourOwn.sh with --target ... \\
--skip-copy --force so checksum verification still runs but the repo is not
rsynced onto itself.

Env vars:
  FIGMENT_LOCAL_DIR        target dir (default: \$REPO/local-dev)
  FIGMENT_LOCAL_MODEL_URL  override Q4 model URL (must be in CHECKSUMS.sha256
                           or used with FIGMENT_SKIP_CHECKSUMS=1)
  FIGMENT_SKIP_CHECKSUMS=1 bypass checksum verification
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

mkdir -p "$LOCAL_DIR"

if [ -n "${FIGMENT_LOCAL_MODEL_URL:-}" ]; then
    export Q4_URL="$FIGMENT_LOCAL_MODEL_URL"
fi

"$REPO_ROOT/BuildYourOwn.sh" --target "$LOCAL_DIR" --skip-copy --force "$@"

echo
echo "Local Figment ready at: $LOCAL_DIR/.system"
echo
echo "To launch:"
echo "  ./dev/launch-local.sh"
echo "  # or: FIGMENT_SYSTEM_DIR='$LOCAL_DIR/.system' ./LinuxLaunch.sh"
echo
echo "To benchmark:"
echo "  ./dev/bench-local.sh"
echo "  # or: FIGMENT_SYSTEM_DIR='$LOCAL_DIR/.system' ./benchmarks/kv_cache_bench.sh --quick --runtime cpu"
