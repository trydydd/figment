#!/bin/bash
# Shared KV cache-type detection helpers.
# Sourced by LinuxLaunch.sh and benchmarks/kv_cache_bench.sh so the parser
# logic stays in one place.
#
# Globals owned by the sourcing script (may be referenced after calling
# figment_detect_supported_cache_types):
#   RUNTIME_HELP_OUTPUT      raw `--help` output of the resolved binary
#   SUPPORTED_CACHE_TYPES    space-separated list of cache-type tokens
#   KV_ROTATION              preferred rotorquant family (turbo3|planar3|iso3)

# Parse cache-type tokens out of a llama.cpp `--help` text on stdin.
# Recognises float (f16/f32/bf16), standard quantized (qN_*, iqN_*) and
# rotorquant (planar/turbo/iso N) types from the --cache-type-k / -v block.
figment_extract_cache_types_from_help() {
    awk '
        BEGIN {
            cache_type_pattern = "^(f16|f32|bf16|q[0-9]+(_[a-z0-9]+)*|iq[0-9]+(_[a-z0-9]+)*|(planar|turbo|iso)[0-9]+)$"
        }

        # Extract cache-type tokens from one help-output line, stripping
        # punctuation and deduplicating matches.
        function emit_tokens(line, normalized, count, i, token) {
            normalized = line
            gsub(/[][()]/, " ", normalized)
            gsub(/,/, " ", normalized)
            gsub(/[[:space:]]+/, " ", normalized)
            count = split(normalized, parts, " ")
            for (i = 1; i <= count; i++) {
                token = parts[i]
                if (token ~ cache_type_pattern && !seen[token]++) {
                    supported_types = supported_types (supported_types ? " " : "") token
                }
            }
        }

        /^[[:space:]]*--cache-type-(k|v)([[:space:]]|$)/ { in_block=1; collecting=0; next }
        in_block && /^[[:space:]]*--/ { in_block=0; collecting=0; next }
        in_block && /allowed values:/ {
            collecting=1
            line=$0
            sub(/^.*allowed values:[[:space:]]*/, "", line)
            emit_tokens(line)
            next
        }
        in_block && collecting {
            emit_tokens($0)
        }

        END {
            print supported_types
        }
    '
}

# Run a llama-cli/llama-bench binary with --help and populate
# RUNTIME_HELP_OUTPUT and SUPPORTED_CACHE_TYPES globals.
# Argument: $1 = path to executable. The caller is responsible for setting
# LD_LIBRARY_PATH (or wrapping via run_command_with_binary_libs).
figment_detect_supported_cache_types() {
    local candidate="$1"
    RUNTIME_HELP_OUTPUT="$("$candidate" --help 2>&1 || true)"
    SUPPORTED_CACHE_TYPES="$(printf '%s\n' "$RUNTIME_HELP_OUTPUT" | figment_extract_cache_types_from_help)"
}

# Return 0 if $1 appears in $SUPPORTED_CACHE_TYPES, else 1.
figment_cache_type_supported() {
    local candidate="$1"
    case " $SUPPORTED_CACHE_TYPES " in
        *" $candidate "*) return 0 ;;
        *) return 1 ;;
    esac
}

# Pick the best quantized cache type. Preference order:
#   1. $KV_ROTATION (if set), then turbo3, planar3, iso3
#   2. any other rotorquant family (planar*, turbo*, iso*) advertised
#   3. standard quantized fallback (q8_0, q5_1, q5_0, iq4_nl, q4_1, q4_0)
# Prints the chosen type to stdout; returns non-zero if nothing matches.
figment_best_quantized_cache_type() {
    local candidate=""
    local checked_cache_types=" "
    local -a rotorquant_candidates=()

    [ -n "${KV_ROTATION:-}" ] && rotorquant_candidates+=("$KV_ROTATION")
    rotorquant_candidates+=(turbo3 planar3 iso3)

    for candidate in "${rotorquant_candidates[@]}"; do
        case "$checked_cache_types" in
            *" $candidate "*) continue ;;
        esac
        checked_cache_types="${checked_cache_types}${candidate} "
        if figment_cache_type_supported "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    for candidate in $SUPPORTED_CACHE_TYPES; do
        case "$candidate" in
            planar*|turbo*|iso*)
                case "$checked_cache_types" in
                    *" $candidate "*) continue ;;
                esac
                checked_cache_types="${checked_cache_types}${candidate} "
                if figment_cache_type_supported "$candidate"; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
                ;;
        esac
    done

    for candidate in q8_0 q5_1 q5_0 iq4_nl q4_1 q4_0; do
        if figment_cache_type_supported "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}
