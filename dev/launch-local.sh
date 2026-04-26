#!/bin/bash
# launch-local.sh — run LinuxLaunch.sh against the dev local-dev/ tree.
# Defaults FIGMENT_VERBOSE=1 so contributors see llama.cpp's runtime logs;
# set FIGMENT_VERBOSE=0 to mirror the production-quiet UX.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_DIR="${FIGMENT_LOCAL_DIR:-$REPO_ROOT/local-dev}"
exec env \
    FIGMENT_SYSTEM_DIR="$LOCAL_DIR/.system" \
    FIGMENT_VERBOSE="${FIGMENT_VERBOSE:-1}" \
    "$REPO_ROOT/LinuxLaunch.sh" "$@"
