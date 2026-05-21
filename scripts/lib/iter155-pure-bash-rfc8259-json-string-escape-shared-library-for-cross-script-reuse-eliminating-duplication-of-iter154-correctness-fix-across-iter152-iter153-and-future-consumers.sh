#!/usr/bin/env bash
# iter-155 shared library: pure-bash RFC 8259 JSON string escape.
#
# WHY THIS EXISTS:
#
#   Iter-154 fixed an iter-153 correctness bug by replacing a python3-
#   dependent JSON escape (with a silent-degrade fallback that emitted
#   broken JSON for any subject containing the 7 RFC 8259 § 7 special
#   chars: ", \, \b, \f, \n, \r, \t) with a pure-bash function. That
#   function was embedded inside the iter-153 advisor script.
#
#   Iter-155 extracts the function to this shared library because:
#
#     (a) ARCHITECTURAL DEBT — the JSON escape is genuinely reusable
#         by any bash tool wanting --json output. Locking it inside a
#         single consumer was an SSoT violation forming.
#
#     (b) FILE-SIZE PRESSURE — iter-153 advisor reached 513 lines after
#         iter-154 (with FILE-SIZE-OK suppression). Future feature
#         additions risked the 1000-line hard block. Extracting the
#         ~75-line escape function relieves the pressure preventively.
#
#     (c) AI-AGENT SURFACE EXTENSION — iter-152 commits:health dashboard
#         had no --json mode (parallel gap to iter-153 pre-iter-154).
#         The extraction enables iter-152 to source this lib and gain
#         --json mode for AI-agent automation, closing the symmetrical
#         gap.
#
# WHAT IT EXPORTS:
#
#   iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars
#
#     - Argument 1: raw input string
#     - Returns (via stdout): the input wrapped in double quotes with
#       all RFC 8259 § 7 escapes applied
#     - No external dependencies (pure bash 3.2+)
#     - Verified round-trip via python3 json.loads in iter-154 + iter-155
#       regression tests
#
# CONSUMERS (sorted by integration order):
#
#   iter-153 advisor — original site; iter-155 refactors to source
#   iter-152 dashboard — added in iter-155 with --json mode
#   future iters — any bash tool wanting RFC 8259-compliant JSON output
#
# RFC 8259 § 7 STRING SPECIFICATION:
#
#   https://datatracker.ietf.org/doc/html/rfc8259#section-7
#
#   Mandatory escapes:
#     \"   quotation mark (U+0022)
#     \\   reverse solidus / backslash (U+005C)
#     \b   backspace      (U+0008)
#     \f   form feed      (U+000C)
#     \n   line feed      (U+000A)
#     \r   carriage return (U+000D)
#     \t   tab            (U+0009)
#
#   Other control chars (U+0000-U+001F not in the named list) MUST be
#   emitted as \uXXXX six-character sequences.
#
#   Non-ASCII bytes (≥ 0x80) pass through verbatim — JSON allows raw
#   UTF-8 in strings, and bash parameter expansion handles UTF-8 byte
#   sequences correctly when LC_ALL/LANG is set appropriately.
#
# USAGE:
#
#   # In a consumer bash script:
#
#   # shellcheck source=/dev/null
#   source "$(git rev-parse --show-toplevel)/scripts/lib/iter155-...sh"
#
#   escaped=$(iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars "$raw_input")
#   printf '{"key": %s}\n' "$escaped"
#
# shellcheck disable=SC1003
# (false-positive on the literal-backslash case pattern below; bash
#  correctly matches a single backslash via "\\" or $'\\' but shellcheck
#  misreads the surrounding context as an attempted single-quote escape.)

iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars() {
    local raw_string_input_to_be_safely_json_escaped="$1"
    local accumulated_escaped_output_string_buffer=""
    local single_character_at_current_walker_position
    local single_character_decimal_codepoint_for_control_char_check
    local current_walker_position_index_into_input_string=0
    local length_of_raw_string_input_in_characters="${#raw_string_input_to_be_safely_json_escaped}"

    while (( current_walker_position_index_into_input_string < length_of_raw_string_input_in_characters )); do
        single_character_at_current_walker_position="${raw_string_input_to_be_safely_json_escaped:$current_walker_position_index_into_input_string:1}"
        case "$single_character_at_current_walker_position" in
            '"')  accumulated_escaped_output_string_buffer+='\"' ;;
            "\\") accumulated_escaped_output_string_buffer+='\\' ;;
            $'\b') accumulated_escaped_output_string_buffer+='\b' ;;
            $'\f') accumulated_escaped_output_string_buffer+='\f' ;;
            $'\n') accumulated_escaped_output_string_buffer+='\n' ;;
            $'\r') accumulated_escaped_output_string_buffer+='\r' ;;
            $'\t') accumulated_escaped_output_string_buffer+='\t' ;;
            *)
                # Check for remaining control chars (U+0000-U+001F) and
                # emit as \uXXXX. printf's %d converts the char to its
                # decimal codepoint via the `'C` literal-char trick.
                printf -v single_character_decimal_codepoint_for_control_char_check '%d' "'$single_character_at_current_walker_position"
                if (( single_character_decimal_codepoint_for_control_char_check < 32 )); then
                    accumulated_escaped_output_string_buffer+=$(printf '\\u%04x' "$single_character_decimal_codepoint_for_control_char_check")
                else
                    accumulated_escaped_output_string_buffer+="$single_character_at_current_walker_position"
                fi
                ;;
        esac
        current_walker_position_index_into_input_string=$((current_walker_position_index_into_input_string + 1))
    done

    printf '"%s"' "$accumulated_escaped_output_string_buffer"
}

# Module-load verification (no-op when sourced; consumers can grep this
# sentinel to confirm successful library load):
#
#   ITER155_PURE_BASH_RFC8259_JSON_ESCAPE_LIBRARY_LOADED_SENTINEL=1
#
# Setting an exported sentinel signals downstream consumers via env-var
# inheritance that the lib was sourced successfully.
export ITER155_PURE_BASH_RFC8259_JSON_ESCAPE_LIBRARY_LOADED_SENTINEL=1
