#!/usr/bin/env bash
# Common bats helpers for LinuxLaunch.sh integration tests.

# Resolve once — bats runs each test in a clean shell but tests source this.
TEST_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_HELPER_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/LinuxLaunch.sh"
STUB_PATH="$TEST_HELPER_DIR/stub-llama-cli"

# Build a fake $SYSTEM_DIR layout that mimics what BuildYourOwn.sh produces:
#   $TMPDIR/.system/runtime-cpu/bin/llama-cli  (copy of stub)
#   $TMPDIR/.system/mlabonne_Qwen3-4B-abliterated-Q4_K_M.gguf  (touched)
#
# Sets:
#   FAKE_TMP        unique tempdir for this test (callers may add files)
#   FAKE_SYSTEM_DIR path to .system inside FAKE_TMP
#   FAKE_MODEL_LOW  path to the Q4 model file
#   FAKE_BIN        path to the stub-as-llama-cli
make_fake_system_dir() {
    FAKE_TMP="$(mktemp -d -t figment-bats.XXXXXX)"
    FAKE_SYSTEM_DIR="$FAKE_TMP/.system"
    mkdir -p "$FAKE_SYSTEM_DIR/runtime-cpu/bin"
    cp "$STUB_PATH" "$FAKE_SYSTEM_DIR/runtime-cpu/bin/llama-cli"
    chmod +x "$FAKE_SYSTEM_DIR/runtime-cpu/bin/llama-cli"

    FAKE_MODEL_LOW="$FAKE_SYSTEM_DIR/mlabonne_Qwen3-4B-abliterated-Q4_K_M.gguf"
    : >"$FAKE_MODEL_LOW"

    FAKE_BIN="$FAKE_SYSTEM_DIR/runtime-cpu/bin/llama-cli"

    # Copy the launcher and its lib/ helper into FAKE_TMP so $ROOT_DIR resolves
    # there, not at the repo root. The launcher's privacy wipe (rm -f
    # $ROOT_DIR/main.log etc.) would otherwise nuke files in the repo every
    # test run.
    mkdir -p "$FAKE_TMP/lib"
    cp "$REPO_ROOT/LinuxLaunch.sh" "$FAKE_TMP/LinuxLaunch.sh"
    cp "$REPO_ROOT/lib/cache_types.sh" "$FAKE_TMP/lib/cache_types.sh"
    chmod +x "$FAKE_TMP/LinuxLaunch.sh"
    FAKE_LAUNCHER="$FAKE_TMP/LinuxLaunch.sh"
}

cleanup_fake_system_dir() {
    if [ -n "${FAKE_TMP:-}" ] && [ -d "$FAKE_TMP" ]; then
        rm -rf "$FAKE_TMP"
    fi
    unset FAKE_TMP FAKE_SYSTEM_DIR FAKE_MODEL_LOW FAKE_BIN FAKE_LAUNCHER
}

# Run the launcher in dry-run mode against the fake system dir.
# Captures `output` and `status` for bats `run` semantics.
# Usage: run_launcher_dryrun [extra env=val ...] [-- argv]
run_launcher_dryrun() {
    # Force a known-low RAM so the launcher selects MODEL_LOW (Q4) by default.
    # `free -g` will still be used; we instead override AVAIL/RAM via the
    # launcher's own variables — but those aren't exposed. We rely on the
    # default-Q4 path being deterministic on test machines with <16GB.
    # Fortunately the Q4 path is also the default when MODEL_HIGH is missing.
    run env \
        FIGMENT_DRY_RUN=1 \
        FIGMENT_SYSTEM_DIR="$FAKE_SYSTEM_DIR" \
        "$@" \
        bash "${FAKE_LAUNCHER:-$LAUNCHER}"
}

# Assert STUB_RECORD_FILE has exactly $1 invocation lines.
# Usage: assert_record_count <expected>
assert_record_count() {
    local expected="$1"
    local actual
    actual=$(wc -l <"${STUB_RECORD_FILE}" 2>/dev/null || echo 0)
    actual="${actual// /}"
    if [ "$actual" != "$expected" ]; then
        echo "expected $expected stub invocation(s), saw $actual" >&2
        echo "--- record file ($STUB_RECORD_FILE) ---" >&2
        cat "$STUB_RECORD_FILE" >&2 || true
        return 1
    fi
}

# Read the Nth (1-indexed) invocation line from STUB_RECORD_FILE.
record_line() {
    local n="$1"
    sed -n "${n}p" "$STUB_RECORD_FILE"
}
