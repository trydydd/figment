#!/bin/bash
# launch-local.sh — run LinuxLaunch.sh against the dev local-dev/ tree.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_DIR="${FIGMENT_LOCAL_DIR:-$REPO_ROOT/local-dev}"
exec env FIGMENT_SYSTEM_DIR="$LOCAL_DIR/.system" "$REPO_ROOT/LinuxLaunch.sh" "$@"
