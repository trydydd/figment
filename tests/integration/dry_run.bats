#!/usr/bin/env bats
# Argv-composition assertions for LinuxLaunch.sh via FIGMENT_DRY_RUN=1.

load '../lib/test_helper.bash'

setup() {
    make_fake_system_dir
}

teardown() {
    cleanup_fake_system_dir
}

@test "default invocation -> turbo3/f16 + Q4 model + runtime-cpu binary" {
    run_launcher_dryrun
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN: CACHE_TYPE_K=turbo3"* ]]
    [[ "$output" == *"DRY-RUN: CACHE_TYPE_V=f16"* ]]
    [[ "$output" == *"DRY-RUN: SELECTED_MODEL=$FAKE_MODEL_LOW"* ]]
    [[ "$output" == *"runtime-cpu/bin/llama-cli"* ]]
    [[ "$output" == *"DRY-RUN: BINARY=$FAKE_BIN"* ]]
}

@test "FIGMENT_KV_PROFILE=compatibility -> f16/f16" {
    run_launcher_dryrun FIGMENT_KV_PROFILE=compatibility
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN: CACHE_TYPE_K=f16"* ]]
    [[ "$output" == *"DRY-RUN: CACHE_TYPE_V=f16"* ]]
    [[ "$output" == *"CACHE_PROFILE_NAME=Compatibility"* ]]
}

@test "FIGMENT_KV_PROFILE=max-compression -> turbo3/turbo3" {
    run_launcher_dryrun FIGMENT_KV_PROFILE=max-compression
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN: CACHE_TYPE_K=turbo3"* ]]
    [[ "$output" == *"DRY-RUN: CACHE_TYPE_V=turbo3"* ]]
    [[ "$output" == *"Max Compression"* ]]
}

@test "FIGMENT_KV_ROTATION=planar3 + memory-saver -> planar3/f16" {
    run_launcher_dryrun FIGMENT_KV_ROTATION=planar3 FIGMENT_KV_PROFILE=memory-saver
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN: CACHE_TYPE_K=planar3"* ]]
    [[ "$output" == *"DRY-RUN: CACHE_TYPE_V=f16"* ]]
}

@test "FIGMENT_KV_ROTATION=iso3 + max-compression -> iso3/iso3" {
    run_launcher_dryrun FIGMENT_KV_ROTATION=iso3 FIGMENT_KV_PROFILE=max-compression
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN: CACHE_TYPE_K=iso3"* ]]
    [[ "$output" == *"DRY-RUN: CACHE_TYPE_V=iso3"* ]]
}

@test "invalid profile name -> falls back to f16/f16 with warning string" {
    run_launcher_dryrun FIGMENT_KV_PROFILE=invalid_profile_name
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN: CACHE_TYPE_K=f16"* ]]
    [[ "$output" == *"DRY-RUN: CACHE_TYPE_V=f16"* ]]
    [[ "$output" == *"invalid profile 'invalid_profile_name' ignored"* ]]
}

@test "FIGMENT_MODEL_OVERRIDE present -> SELECTED_MODEL is override, MODE_NAME=Override [...]" {
    OVERRIDE_PATH="$FAKE_TMP/custom.gguf"
    : >"$OVERRIDE_PATH"
    run_launcher_dryrun FIGMENT_MODEL_OVERRIDE="$OVERRIDE_PATH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN: SELECTED_MODEL=$OVERRIDE_PATH"* ]]
    [[ "$output" == *"DRY-RUN: MODE_NAME=Override [custom.gguf]"* ]]
}

@test "FIGMENT_MODEL_OVERRIDE missing -> warning, falls through to Q4" {
    MISSING="/nonexistent-figment-test-path/$$.gguf"
    run_launcher_dryrun FIGMENT_MODEL_OVERRIDE="$MISSING"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FIGMENT_MODEL_OVERRIDE points at $MISSING"* ]]
    [[ "$output" == *"DRY-RUN: SELECTED_MODEL=$FAKE_MODEL_LOW"* ]]
    [[ "$output" != *"DRY-RUN: SELECTED_MODEL=$MISSING"* ]]
}

@test "FIGMENT_SYSTEM_DIR override -> DRY-RUN: SYSTEM_DIR matches" {
    run_launcher_dryrun
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN: SYSTEM_DIR=$FAKE_SYSTEM_DIR"* ]]
}

@test "old-style help without turbo3 -> memory-saver runtime fallback" {
    OLD_HELP=$(cat <<'EOF'
usage: llama-cli [options]

options:
      --cache-type-k TYPE    KV cache type for K
                             allowed values: f16, q8_0
      --cache-type-v TYPE    KV cache type for V
                             allowed values: f16, q8_0
EOF
)
    run_launcher_dryrun STUB_HELP_OUTPUT="$OLD_HELP" FIGMENT_KV_PROFILE=memory-saver
    [ "$status" -eq 0 ]
    # CACHE_TYPE_K must NOT be turbo3 — runtime didn't advertise it.
    [[ "$output" != *"DRY-RUN: CACHE_TYPE_K=turbo3"* ]]
    # CACHE_PROFILE_NAME must end in "[runtime fallback]".
    [[ "$output" == *"[runtime fallback]"* ]]
}
