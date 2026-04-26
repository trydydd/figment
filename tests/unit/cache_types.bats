#!/usr/bin/env bats
#
# Unit tests for lib/cache_types.sh.
#
# Covers:
#   * figment_extract_cache_types_from_help (stdin parser)
#   * figment_cache_type_supported          (membership check)
#   * figment_best_quantized_cache_type     (selection logic)

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    # shellcheck disable=SC1091
    . "$REPO_ROOT/lib/cache_types.sh"
    # Make sure no stray globals leak between tests.
    unset KV_ROTATION
    SUPPORTED_CACHE_TYPES=""
}

# ---------------------------------------------------------------------------
# figment_extract_cache_types_from_help
# ---------------------------------------------------------------------------

@test "extract: empty input produces empty output" {
    run bash -c '. "$REPO_ROOT/lib/cache_types.sh"; printf "" | figment_extract_cache_types_from_help'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "extract: help text without cache-type block produces empty output" {
    run bash -c '. "$REPO_ROOT/lib/cache_types.sh"; figment_extract_cache_types_from_help <<EOF
usage: llama-cli [options]
  --foo BAR    do nothing useful
  -h, --help   show this help
EOF'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "extract: standard llama.cpp --cache-type-k block emits all eight tokens" {
    run bash -c '. "$REPO_ROOT/lib/cache_types.sh"; figment_extract_cache_types_from_help <<EOF
  --cache-type-k TYPE
                        allowed values: f16, f32, q8_0, q5_1, q5_0, iq4_nl, q4_1, q4_0
  --next-option FOO
EOF'
    [ "$status" -eq 0 ]
    [ "$output" = "f16 f32 q8_0 q5_1 q5_0 iq4_nl q4_1 q4_0" ]
}

@test "extract: tokens wrapped in square brackets are still parsed" {
    run bash -c '. "$REPO_ROOT/lib/cache_types.sh"; figment_extract_cache_types_from_help <<EOF
  --cache-type-k TYPE
                        allowed values: [f16, f32, q8_0, q4_0]
  --next-option FOO
EOF'
    [ "$status" -eq 0 ]
    [ "$output" = "f16 f32 q8_0 q4_0" ]
}

@test "extract: tokens wrapped in parentheses are still parsed" {
    run bash -c '. "$REPO_ROOT/lib/cache_types.sh"; figment_extract_cache_types_from_help <<EOF
  --cache-type-k TYPE
                        allowed values: (f16, f32, q8_0)
  --next-option FOO
EOF'
    [ "$status" -eq 0 ]
    [ "$output" = "f16 f32 q8_0" ]
}

@test "extract: allowed values continuing on indented next line are parsed" {
    run bash -c '. "$REPO_ROOT/lib/cache_types.sh"; figment_extract_cache_types_from_help <<EOF
  --cache-type-k TYPE
                        allowed values:
                          f16, f32, q8_0, q4_0
  --next-option FOO
EOF'
    [ "$status" -eq 0 ]
    [ "$output" = "f16 f32 q8_0 q4_0" ]
}

@test "extract: rotorquant fork help yields rotorquant tokens" {
    run bash -c '. "$REPO_ROOT/lib/cache_types.sh"; figment_extract_cache_types_from_help <<EOF
  --cache-type-k TYPE
                        allowed values: f16, f32, q8_0, q5_1, q5_0, iq4_nl, q4_1, q4_0, turbo3, planar3, iso3
  --next-option FOO
EOF'
    [ "$status" -eq 0 ]
    [ "$output" = "f16 f32 q8_0 q5_1 q5_0 iq4_nl q4_1 q4_0 turbo3 planar3 iso3" ]
    # Verify each rotorquant token appears explicitly.
    [[ "$output" =~ (^|\ )turbo3(\ |$) ]]
    [[ "$output" =~ (^|\ )planar3(\ |$) ]]
    [[ "$output" =~ (^|\ )iso3(\ |$) ]]
}

@test "extract: case is preserved; uppercase tokens are not matched (lowercase regex)" {
    # The current parser regex is strictly lowercase. Uppercase F16/F32 should
    # NOT match. We assert the surviving lowercase tokens come through verbatim
    # (not lowercased on top of the uppercase ones).
    run bash -c '. "$REPO_ROOT/lib/cache_types.sh"; figment_extract_cache_types_from_help <<EOF
  --cache-type-k TYPE
                        allowed values: F16, f32, Q8_0, q5_0
  --next-option FOO
EOF'
    [ "$status" -eq 0 ]
    [ "$output" = "f32 q5_0" ]
}

@test "extract: --cache-type-v block alone is parsed" {
    run bash -c '. "$REPO_ROOT/lib/cache_types.sh"; figment_extract_cache_types_from_help <<EOF
  --cache-type-v TYPE
                        allowed values: f16, q8_0, q4_0
  --next-option FOO
EOF'
    [ "$status" -eq 0 ]
    [ "$output" = "f16 q8_0 q4_0" ]
}

@test "extract: garbage tokens (--something-else, words) are not emitted" {
    run bash -c '. "$REPO_ROOT/lib/cache_types.sh"; figment_extract_cache_types_from_help <<EOF
  --cache-type-k TYPE
                        allowed values: f16, --something-else, q8_0, garbage_token, ROTOR
  --next-option FOO
EOF'
    [ "$status" -eq 0 ]
    [ "$output" = "f16 q8_0" ]
}

@test "extract: a token appearing in both -k and -v blocks is emitted only once" {
    run bash -c '. "$REPO_ROOT/lib/cache_types.sh"; figment_extract_cache_types_from_help <<EOF
  --cache-type-k TYPE
                        allowed values: f16, f32, q8_0, q5_1
  --cache-type-v TYPE
                        allowed values: f16, q8_0, q4_0
  --next-option FOO
EOF'
    [ "$status" -eq 0 ]
    [ "$output" = "f16 f32 q8_0 q5_1 q4_0" ]
}

@test "extract: another --option after the allowed values list ends collection" {
    # The parser exits the block on the next line beginning with --, so any
    # tokens after that should NOT be picked up even if they look valid.
    run bash -c '. "$REPO_ROOT/lib/cache_types.sh"; figment_extract_cache_types_from_help <<EOF
  --cache-type-k TYPE
                        allowed values: f16, q8_0
  --unrelated TYPE
                        allowed values: q4_0, q5_0
EOF'
    [ "$status" -eq 0 ]
    [ "$output" = "f16 q8_0" ]
}

# ---------------------------------------------------------------------------
# figment_cache_type_supported
# ---------------------------------------------------------------------------

@test "supported: returns 0 when type is in SUPPORTED_CACHE_TYPES" {
    SUPPORTED_CACHE_TYPES="f16 f32 q8_0 q4_0"
    run figment_cache_type_supported "q8_0"
    [ "$status" -eq 0 ]
}

@test "supported: returns 1 when type is missing" {
    SUPPORTED_CACHE_TYPES="f16 f32 q8_0"
    run figment_cache_type_supported "iq4_nl"
    [ "$status" -eq 1 ]
}

@test "supported: empty SUPPORTED_CACHE_TYPES returns 1" {
    SUPPORTED_CACHE_TYPES=""
    run figment_cache_type_supported "f16"
    [ "$status" -eq 1 ]
}

@test "supported: substring match does not yield false positive" {
    SUPPORTED_CACHE_TYPES="q8_0 q5_1 q5_0"
    # "q8" is a prefix of "q8_0" but should not match.
    run figment_cache_type_supported "q8"
    [ "$status" -eq 1 ]
    # And "5_0" is a suffix of "q5_0" but should not match either.
    run figment_cache_type_supported "5_0"
    [ "$status" -eq 1 ]
}

@test "supported: rotorquant token lookup works" {
    SUPPORTED_CACHE_TYPES="f16 turbo3 planar3 iso3"
    run figment_cache_type_supported "planar3"
    [ "$status" -eq 0 ]
    run figment_cache_type_supported "turbo3"
    [ "$status" -eq 0 ]
    run figment_cache_type_supported "iso3"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# figment_best_quantized_cache_type
# ---------------------------------------------------------------------------

@test "best: KV_ROTATION=turbo3 with turbo3 supported prints turbo3" {
    SUPPORTED_CACHE_TYPES="f16 q8_0 turbo3 planar3 iso3"
    KV_ROTATION="turbo3"
    run figment_best_quantized_cache_type
    [ "$status" -eq 0 ]
    [ "$output" = "turbo3" ]
}

@test "best: KV_ROTATION=planar3 with planar3 supported prints planar3" {
    SUPPORTED_CACHE_TYPES="f16 q8_0 turbo3 planar3 iso3"
    KV_ROTATION="planar3"
    run figment_best_quantized_cache_type
    [ "$status" -eq 0 ]
    [ "$output" = "planar3" ]
}

@test "best: KV_ROTATION=iso3 with iso3 supported prints iso3" {
    SUPPORTED_CACHE_TYPES="f16 q8_0 turbo3 planar3 iso3"
    KV_ROTATION="iso3"
    run figment_best_quantized_cache_type
    [ "$status" -eq 0 ]
    [ "$output" = "iso3" ]
}

@test "best: KV_ROTATION=turbo3 falls through to planar3 when turbo3 is missing" {
    SUPPORTED_CACHE_TYPES="f16 q8_0 planar3"
    KV_ROTATION="turbo3"
    run figment_best_quantized_cache_type
    [ "$status" -eq 0 ]
    [ "$output" = "planar3" ]
}

@test "best: no rotorquant types — chooses q8_0 (highest quality fallback)" {
    SUPPORTED_CACHE_TYPES="f16 f32 q8_0 q5_1 q5_0 iq4_nl q4_1 q4_0"
    unset KV_ROTATION
    run figment_best_quantized_cache_type
    [ "$status" -eq 0 ]
    [ "$output" = "q8_0" ]
}

@test "best: KV_ROTATION unset, all rotorquant types present — prefers turbo3" {
    SUPPORTED_CACHE_TYPES="f16 f32 q8_0 turbo3 planar3 iso3"
    unset KV_ROTATION
    run figment_best_quantized_cache_type
    [ "$status" -eq 0 ]
    [ "$output" = "turbo3" ]
}

@test "best: only q4_0 available — prints q4_0" {
    SUPPORTED_CACHE_TYPES="q4_0"
    unset KV_ROTATION
    run figment_best_quantized_cache_type
    [ "$status" -eq 0 ]
    [ "$output" = "q4_0" ]
}

@test "best: nothing supported — returns non-zero" {
    SUPPORTED_CACHE_TYPES=""
    unset KV_ROTATION
    run figment_best_quantized_cache_type
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "best: only float types (f16/f32) — returns non-zero (no quantized fallback)" {
    SUPPORTED_CACHE_TYPES="f16 f32 bf16"
    unset KV_ROTATION
    run figment_best_quantized_cache_type
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "best: non-default rotorquant (planar5) is chosen via second pass" {
    # No turbo3/planar3/iso3, but planar5 is advertised. The second loop
    # over $SUPPORTED_CACHE_TYPES should pick it up before the q8_0 fallback.
    SUPPORTED_CACHE_TYPES="f16 q8_0 planar5"
    unset KV_ROTATION
    run figment_best_quantized_cache_type
    [ "$status" -eq 0 ]
    [ "$output" = "planar5" ]
}

@test "best: KV_ROTATION pointing at unsupported rotorquant falls through to default order" {
    # KV_ROTATION=turbo7 is not advertised; default rotorquant order should kick in.
    SUPPORTED_CACHE_TYPES="f16 q8_0 planar3 iso3"
    KV_ROTATION="turbo7"
    run figment_best_quantized_cache_type
    [ "$status" -eq 0 ]
    [ "$output" = "planar3" ]
}
