#!/usr/bin/env bats
# Fallback-chain assertions for LinuxLaunch.sh — actually runs the stubbed
# llama-cli binary so the launcher's crash/KV-error retry logic at
# LinuxLaunch.sh:539-595 exercises end-to-end.
#
# Call sequence (no FIGMENT_DRY_RUN, default invocation, stub failing):
#   1. probe_binary --help          (during choose_runtime_binary)
#   2. detect_supported_cache_types --help
#   3. user LAUNCH_CMD                (with the requested KV profile)
#   4. PROBE_CMD (-n 1 -p ping)       (only if step 3 exits non-zero)
#   5. FALLBACK_CMD (--cache-type-k f16 --cache-type-v f16)
#                                     (only if crash signal OR KV pattern AND
#                                      not already on f16/f16)

load '../lib/test_helper.bash'

setup() {
    make_fake_system_dir
    STUB_RECORD_FILE="$FAKE_TMP/stub-record.log"
    : >"$STUB_RECORD_FILE"
    export STUB_RECORD_FILE
}

teardown() {
    cleanup_fake_system_dir
    unset STUB_RECORD_FILE
}

# Run the launcher for real (no FIGMENT_DRY_RUN). printf '\n' satisfies the
# trailing `read -p "Press Enter to exit..."` prompt. Each "$@" is passed as a
# discrete env var (so values containing spaces or quotes survive intact).
run_launcher_real() {
    run env "$@" \
        FIGMENT_SYSTEM_DIR="$FAKE_SYSTEM_DIR" \
        STUB_RECORD_FILE="$STUB_RECORD_FILE" \
        bash -c 'printf "\n" | bash "$0"' "${FAKE_LAUNCHER:-$LAUNCHER}"
}

# Count how many records on STUB_RECORD_FILE have help:false (i.e. real
# invocations vs --help discovery probes).
non_help_record_count() {
    grep -c '"help":false' "$STUB_RECORD_FILE" 2>/dev/null || true
}

@test "SIGABRT (exit 134) on first call -> retries with f16/f16" {
    run_launcher_real STUB_EXIT_CODE=134
    [[ "$output" == *"runtime crashed while loading"* ]]
    [[ "$output" == *"Compatibility [f16/f16] [automatic fallback]"* ]]

    # 2 help + 1 user + 1 probe + 1 fallback = 5 total records.
    assert_record_count 5

    # First non-help invocation must use turbo3/f16; the retry must use f16/f16.
    line3=$(record_line 3)
    [[ "$line3" == *'"ctk":"turbo3"'* ]]
    [[ "$line3" == *'"ctv":"f16"'* ]]

    line5=$(record_line 5)
    [[ "$line5" == *'"ctk":"f16"'* ]]
    [[ "$line5" == *'"ctv":"f16"'* ]]
}

@test "KV stderr pattern -> retries with f16/f16" {
    run_launcher_real STUB_EXIT_CODE=1 STUB_FAIL_ON_KV='turbo3 f16'
    [[ "$output" == *"Requested KV cache profile is not supported"* ]]
    [[ "$output" == *"Compatibility [f16/f16] [automatic fallback]"* ]]

    assert_record_count 5

    line5=$(record_line 5)
    [[ "$line5" == *'"ctk":"f16"'* ]]
    [[ "$line5" == *'"ctv":"f16"'* ]]
}

@test "exit 1 with no KV pattern -> probe runs but no retry" {
    run_launcher_real STUB_EXIT_CODE=1

    # No fallback diagnostic should appear.
    [[ "$output" != *"runtime crashed while loading"* ]]
    [[ "$output" != *"Requested KV cache profile is not supported"* ]]
    [[ "$output" != *"automatic fallback"* ]]

    # 2 help + 1 user + 1 probe = 4 records (no fifth/fallback record).
    assert_record_count 4
}

@test "qwen3 architecture stderr -> diagnostic message printed" {
    run_launcher_real STUB_EXIT_CODE=1 "STUB_STDERR=unknown model architecture: 'qwen3'"
    [[ "$output" == *"cannot load Qwen3 models"* ]]
    [[ "$output" == *"too old for this architecture"* ]]
}

@test "already on f16/f16 + KV pattern -> no retry" {
    run_launcher_real FIGMENT_KV_PROFILE=compatibility \
        STUB_EXIT_CODE=1 STUB_FAIL_ON_KV='f16 f16'

    # No fallback because we are already on f16/f16.
    [[ "$output" != *"automatic fallback"* ]]

    # 2 help + 1 user + 1 probe = 4 records, no fifth fallback record.
    assert_record_count 4

    # Both user and probe invocations must be on f16/f16.
    line3=$(record_line 3)
    [[ "$line3" == *'"ctk":"f16"'* ]]
    [[ "$line3" == *'"ctv":"f16"'* ]]

    line4=$(record_line 4)
    [[ "$line4" == *'"ctk":"f16"'* ]]
    [[ "$line4" == *'"ctv":"f16"'* ]]
}
