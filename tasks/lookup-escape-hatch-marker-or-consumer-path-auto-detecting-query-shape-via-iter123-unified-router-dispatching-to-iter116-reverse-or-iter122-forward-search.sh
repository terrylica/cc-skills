#!/usr/bin/env bash
#MISE description="Iter-123 unified operator-facing lookup CLI auto-detecting query shape and dispatching to iter-116 reverse-search (consumer-path -> marker) or iter-122 forward-search (marker -> consumer-path) without forcing the operator to choose direction. Classification rules: (1) query contains '/' -> CONFIDENT path-shape, route to iter-116; (2) query matches canonical UPPER-KEBAB-CASE-with-OK/SKIP/WRAP-suffix regex OR is the grandfathered SSoT-OK mixed-case token -> CONFIDENT marker-shape, route to iter-122; (3) otherwise AMBIGUOUS, try forward first and fall back to reverse if no hit. Operator can override the heuristic via --direction=forward|reverse|auto (default auto). Iter-119-parallel --json mode emits classifierRationale + routingDecision + dispatched-backend-payload so downstream consumers see both the dispatch and the resolution. Exits 0 when any backend found, 2 when both backends exhausted, 1 on usage error."

# ────────────────────────────────────────────────────────────────────────
# Iter-123 design rationale (operator-facing CLI side)
# ────────────────────────────────────────────────────────────────────────
#
# Pre-iter-123 the marketplace shipped two separate operator CLIs:
#
#   - iter-116: lookup-escape-hatch-marker-by-consumer-source-file-...
#   - iter-122: lookup-escape-hatch-marker-explanation-by-marker-name-...
#
# Operators had to remember which task name corresponds to which lookup
# direction. The two task names are >130 characters each and differ only
# by the words "reverse-search-accessor" vs "forward-search-accessor"
# plus the noun ordering — error-prone in shell completion + tab-history.
#
# Iter-123 introduces a unified entry point that auto-detects the query
# shape (via the iter-123 classifier lib) and dispatches to the right
# backend. The existing iter-116 and iter-122 CLIs are NOT removed — they
# remain as explicit-direction escape hatches for operators who want
# to bypass auto-detection.
#
# Auto-detection rules (see iter-123 classifier lib for details):
#
#   1. Query contains '/' -> CONFIDENT path -> iter-116 reverse
#   2. Query matches strict UPPER-KEBAB-CASE marker regex -> CONFIDENT
#      marker -> iter-122 forward
#   3. Grandfathered SSoT-OK mixed-case token -> CONFIDENT marker -> iter-122
#   4. AMBIGUOUS (no '/', not canonical UPPER-KEBAB-CASE shape) ->
#      try forward first; if forward returns no hits, fall back to reverse
#
# The classifier's rationale string is printed in the operator's terminal
# output BEFORE the dispatched-backend's result, making the routing
# decision transparent rather than magic.
#
# Exit codes:
#
#   0 : dispatched backend found a hit (any layer of either fallback chain)
#   1 : usage error (missing arg, --help, bad --direction value)
#   2 : both backends exhausted (forward + reverse both not-found, or the
#       explicit-direction dispatch returned not-found)

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

ITER123_SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITER123_REPO_ROOT="$(cd "$ITER123_SCRIPT_DIR_ABSOLUTE/../.." && pwd)"
ITER123_CLASSIFIER_LIBRARY_TYPESCRIPT_ABSOLUTE_PATH="$ITER123_REPO_ROOT/plugins/itp-hooks/hooks/lib/iter123-unified-lookup-query-shape-auto-detection-router-dispatching-to-iter116-reverse-or-iter122-forward-search-direction-based-on-slash-and-upper-kebab-case-marker-shape-heuristics.ts"
ITER116_REVERSE_CLI_ABSOLUTE_PATH="$ITER123_REPO_ROOT/.mise/tasks/lookup-escape-hatch-marker-by-consumer-source-file-relative-path-via-iter116-reverse-search-accessor-spanning-iter111-and-iter114-canonical-registries.sh"
ITER122_FORWARD_CLI_ABSOLUTE_PATH="$ITER123_REPO_ROOT/.mise/tasks/lookup-escape-hatch-marker-explanation-by-marker-name-token-via-iter122-forward-search-accessor-spanning-iter111-and-iter114-canonical-registries.sh"

print_usage_and_exit_one() {
    echo "Usage: mise run $(basename "$0" .sh) [--json] [--direction=forward|reverse|auto] <query>"
    echo ""
    echo "  Unified escape-hatch-marker lookup CLI. Auto-detects whether the"
    echo "  query is a marker name token (UPPER-KEBAB-CASE) or a consumer"
    echo "  source file path (contains '/'), and dispatches to the iter-116"
    echo "  reverse-search OR iter-122 forward-search backend accordingly."
    echo ""
    echo "Arguments:"
    echo "  query     Either a marker name token (e.g., FILE-SIZE-OK) OR a"
    echo "            consumer source file relative path (e.g.,"
    echo "            plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts)."
    echo "            Partial queries (basename fragments, marker substrings,"
    echo "            typos) also work via the iter-116/iter-122 fuzzy-fallback"
    echo "            chains."
    echo ""
    echo "Flags:"
    echo "  --json"
    echo "      Emit machine-readable JSON to stdout. Shape includes the"
    echo "      iter-123 classifierRationale + routingDecision + the full"
    echo "      dispatched-backend JSON payload."
    echo ""
    echo "  --direction=forward|reverse|auto   (default: auto)"
    echo "      Override the auto-detect classifier. 'forward' forces the"
    echo "      iter-122 marker -> consumer dispatch; 'reverse' forces the"
    echo "      iter-116 consumer -> marker dispatch."
    echo ""
    echo "Examples:"
    echo "  # Auto-detect: marker shape -> iter-122 forward"
    echo "  mise run lookup-...-iter123-... FILE-SIZE-OK"
    echo ""
    echo "  # Auto-detect: path shape -> iter-116 reverse"
    echo "  mise run lookup-...-iter123-... plugins/itp-hooks/hooks/pretooluse-file-size-guard.ts"
    echo ""
    echo "  # Auto-detect: ambiguous basename -> try forward first, fall back to reverse"
    echo "  mise run lookup-...-iter123-... file-size-guard"
    echo ""
    echo "  # Explicit direction override:"
    echo "  mise run lookup-...-iter123-... --direction=reverse file-size-guard"
    echo ""
    echo "Exit codes:"
    echo "  0 : dispatched backend found a hit at any fallback layer"
    echo "  1 : usage error (missing arg, --help, bad --direction value)"
    echo "  2 : all dispatched backends exhausted (both forward + reverse,"
    echo "      or the explicit --direction dispatch, returned not-found)"
    exit 1
}

# Parse optional flags. Both --json and --direction may appear in either
# order, both must appear BEFORE the positional query argument.
ITER123_JSON_OUTPUT_MODE_FLAG_REQUESTED_BY_OPERATOR=false
ITER123_DIRECTION_OVERRIDE_VALUE="auto"
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --json)
            ITER123_JSON_OUTPUT_MODE_FLAG_REQUESTED_BY_OPERATOR=true
            shift
            ;;
        --direction=*)
            ITER123_DIRECTION_OVERRIDE_VALUE="${1#--direction=}"
            case "$ITER123_DIRECTION_OVERRIDE_VALUE" in
                forward|reverse|auto) shift ;;
                *)
                    echo "ERROR: invalid --direction value: $ITER123_DIRECTION_OVERRIDE_VALUE (expected forward|reverse|auto)" >&2
                    print_usage_and_exit_one
                    ;;
            esac
            ;;
        --help|-h)
            print_usage_and_exit_one
            ;;
        --*)
            echo "ERROR: unknown flag: $1" >&2
            print_usage_and_exit_one
            ;;
        *)
            break
            ;;
    esac
done

if [[ "$#" -ne 1 ]]; then
    print_usage_and_exit_one
fi

ITER123_OPERATOR_SUPPLIED_QUERY_STRING="$1"

# ════════════════════════════════════════════════════════════════════════
# Run the iter-123 classifier (TypeScript pure function) via bun and
# capture the routing decision + rationale.
# ════════════════════════════════════════════════════════════════════════

ITER123_CLASSIFIER_TEMP_SCRIPT_DIRECTORY=$(mktemp -d -t iter123-classifier-XXXXXX)
trap 'rm -rf "$ITER123_CLASSIFIER_TEMP_SCRIPT_DIRECTORY"' EXIT

cat > "$ITER123_CLASSIFIER_TEMP_SCRIPT_DIRECTORY/iter123-classify-and-emit-routing-decision.ts" <<EOF
import {
  classifyOperatorQueryShapeForUnifiedLookupDispatchRouting,
} from "$ITER123_CLASSIFIER_LIBRARY_TYPESCRIPT_ABSOLUTE_PATH";

const classification =
  classifyOperatorQueryShapeForUnifiedLookupDispatchRouting(
    "$ITER123_OPERATOR_SUPPLIED_QUERY_STRING",
  );
console.log(
  \`ITER123_CLASSIFIED_DISPATCH_DIRECTION_TAG=\${classification.classifiedDispatchDirectionTag}\`,
);
console.log(
  \`ITER123_CLASSIFIER_RATIONALE_FOR_OPERATOR=\${classification.classifierRationaleForOperatorTerminalOutput}\`,
);
EOF

set +e
ITER123_CLASSIFIER_OUTPUT=$(cd "$ITER123_REPO_ROOT" && bun "$ITER123_CLASSIFIER_TEMP_SCRIPT_DIRECTORY/iter123-classify-and-emit-routing-decision.ts" 2>&1)
ITER123_CLASSIFIER_EXIT_CODE=$?
set -e

if [[ "$ITER123_CLASSIFIER_EXIT_CODE" -ne 0 ]]; then
    echo "ERROR: iter-123 classifier subprocess failed (exit $ITER123_CLASSIFIER_EXIT_CODE):" >&2
    echo "$ITER123_CLASSIFIER_OUTPUT" | awk '{print "  " $0}' >&2
    exit 1
fi

ITER123_AUTO_DETECTED_DISPATCH_DIRECTION_TAG=$(echo "$ITER123_CLASSIFIER_OUTPUT" | awk -F= '/^ITER123_CLASSIFIED_DISPATCH_DIRECTION_TAG=/ {print $2; exit}')
ITER123_AUTO_DETECT_CLASSIFIER_RATIONALE=$(echo "$ITER123_CLASSIFIER_OUTPUT" | awk -F= '/^ITER123_CLASSIFIER_RATIONALE_FOR_OPERATOR=/ {sub(/^ITER123_CLASSIFIER_RATIONALE_FOR_OPERATOR=/, ""); print; exit}')

# ════════════════════════════════════════════════════════════════════════
# Apply the operator's --direction override (or honor the auto-detect).
# ════════════════════════════════════════════════════════════════════════

ITER123_EFFECTIVE_DISPATCH_DIRECTION="auto"
ITER123_EFFECTIVE_ROUTING_RATIONALE=""

case "$ITER123_DIRECTION_OVERRIDE_VALUE" in
    forward)
        ITER123_EFFECTIVE_DISPATCH_DIRECTION="forward"
        ITER123_EFFECTIVE_ROUTING_RATIONALE="operator --direction=forward override (bypassing auto-detect; classifier would have suggested: $ITER123_AUTO_DETECTED_DISPATCH_DIRECTION_TAG)"
        ;;
    reverse)
        ITER123_EFFECTIVE_DISPATCH_DIRECTION="reverse"
        ITER123_EFFECTIVE_ROUTING_RATIONALE="operator --direction=reverse override (bypassing auto-detect; classifier would have suggested: $ITER123_AUTO_DETECTED_DISPATCH_DIRECTION_TAG)"
        ;;
    auto)
        case "$ITER123_AUTO_DETECTED_DISPATCH_DIRECTION_TAG" in
            REVERSE_SEARCH_ITER116_CONFIDENT)
                ITER123_EFFECTIVE_DISPATCH_DIRECTION="reverse"
                ;;
            FORWARD_SEARCH_ITER122_CONFIDENT)
                ITER123_EFFECTIVE_DISPATCH_DIRECTION="forward"
                ;;
            AMBIGUOUS_TRY_FORWARD_THEN_FALLBACK_REVERSE)
                ITER123_EFFECTIVE_DISPATCH_DIRECTION="ambiguous-forward-then-reverse"
                ;;
            *)
                echo "ERROR: classifier returned unknown direction tag: $ITER123_AUTO_DETECTED_DISPATCH_DIRECTION_TAG" >&2
                exit 1
                ;;
        esac
        ITER123_EFFECTIVE_ROUTING_RATIONALE="auto-detect classifier: $ITER123_AUTO_DETECT_CLASSIFIER_RATIONALE"
        ;;
esac

# ════════════════════════════════════════════════════════════════════════
# Dispatch to the chosen backend(s).
#
# For human-readable mode, print the routing rationale BEFORE the
# dispatched-backend output so the operator sees the routing decision.
#
# For JSON mode, wrap the backend's JSON payload in an iter-123 envelope
# that includes the classifier rationale + routing decision.
# ════════════════════════════════════════════════════════════════════════

# Wrap an arbitrary backend-JSON payload in the iter-123 envelope using
# jq. Pure JSON manipulation — no fragile cross-language interpolation
# (the prior bun-heredoc attempt failed because `\$VAR` inside a double-
# quoted `bun -e "..."` block is escaped to literal `$VAR` rather than
# bash-interpolated — surfaced by shellcheck SC2034 on the temp vars).
emit_iter123_json_envelope_wrapping_backend_response() {
    local backend_json_payload="$1"
    local dispatched_backend_name="$2"
    local effective_routing_rationale_for_envelope="$3"
    echo "$backend_json_payload" | jq \
        --arg query "$ITER123_OPERATOR_SUPPLIED_QUERY_STRING" \
        --arg classifiedTag "$ITER123_AUTO_DETECTED_DISPATCH_DIRECTION_TAG" \
        --arg classifierRationale "$ITER123_AUTO_DETECT_CLASSIFIER_RATIONALE" \
        --arg effectiveDirection "$ITER123_EFFECTIVE_DISPATCH_DIRECTION" \
        --arg effectiveRationale "$effective_routing_rationale_for_envelope" \
        --arg dispatchedBackend "$dispatched_backend_name" \
        '{
            iter123UnifiedLookupEnvelope: {
                operatorSuppliedQuery: $query,
                classifiedDispatchDirectionTag: $classifiedTag,
                classifierRationale: $classifierRationale,
                effectiveDispatchDirection: $effectiveDirection,
                effectiveRoutingRationale: $effectiveRationale,
                dispatchedBackend: $dispatchedBackend
            },
            dispatchedBackendResponse: .
        }'
}

dispatch_to_reverse_search_iter116_and_pass_through_exit_code() {
    if [[ "$ITER123_JSON_OUTPUT_MODE_FLAG_REQUESTED_BY_OPERATOR" == "true" ]]; then
        local reverse_backend_json_payload
        set +e
        reverse_backend_json_payload=$(bash "$ITER116_REVERSE_CLI_ABSOLUTE_PATH" --json "$ITER123_OPERATOR_SUPPLIED_QUERY_STRING" 2>/dev/null)
        local reverse_backend_exit_code=$?
        set -e
        emit_iter123_json_envelope_wrapping_backend_response \
            "$reverse_backend_json_payload" \
            "iter116-reverse-search" \
            "$ITER123_EFFECTIVE_ROUTING_RATIONALE"
        return "$reverse_backend_exit_code"
    fi
    echo "ⓘ Routing: $ITER123_EFFECTIVE_ROUTING_RATIONALE"
    echo ""
    bash "$ITER116_REVERSE_CLI_ABSOLUTE_PATH" "$ITER123_OPERATOR_SUPPLIED_QUERY_STRING"
    return $?
}

dispatch_to_forward_search_iter122_and_pass_through_exit_code() {
    if [[ "$ITER123_JSON_OUTPUT_MODE_FLAG_REQUESTED_BY_OPERATOR" == "true" ]]; then
        local forward_backend_json_payload
        set +e
        forward_backend_json_payload=$(bash "$ITER122_FORWARD_CLI_ABSOLUTE_PATH" --json "$ITER123_OPERATOR_SUPPLIED_QUERY_STRING" 2>/dev/null)
        local forward_backend_exit_code=$?
        set -e
        emit_iter123_json_envelope_wrapping_backend_response \
            "$forward_backend_json_payload" \
            "iter122-forward-search" \
            "$ITER123_EFFECTIVE_ROUTING_RATIONALE"
        return "$forward_backend_exit_code"
    fi
    echo "ⓘ Routing: $ITER123_EFFECTIVE_ROUTING_RATIONALE"
    echo ""
    bash "$ITER122_FORWARD_CLI_ABSOLUTE_PATH" "$ITER123_OPERATOR_SUPPLIED_QUERY_STRING"
    return $?
}

case "$ITER123_EFFECTIVE_DISPATCH_DIRECTION" in
    reverse)
        set +e
        dispatch_to_reverse_search_iter116_and_pass_through_exit_code
        exit $?
        ;;
    forward)
        set +e
        dispatch_to_forward_search_iter122_and_pass_through_exit_code
        exit $?
        ;;
    ambiguous-forward-then-reverse)
        # Try forward first; if it returned not-found (exit 2), fall back
        # to reverse. If forward found a hit (exit 0), stop there.
        if [[ "$ITER123_JSON_OUTPUT_MODE_FLAG_REQUESTED_BY_OPERATOR" == "true" ]]; then
            # JSON mode: try forward silently; if not-found, try reverse;
            # emit envelope reflecting whichever backend produced the hit
            # (or the reverse's not-found if both exhausted).
            # NOTE: this branch lives at script-level inside a case
            # statement, NOT a function — so `local` is invalid here
            # (shellcheck SC2168). Use bare globals.
            set +e
            forward_attempt_json_payload=$(bash "$ITER122_FORWARD_CLI_ABSOLUTE_PATH" --json "$ITER123_OPERATOR_SUPPLIED_QUERY_STRING" 2>/dev/null)
            forward_attempt_exit_code=$?
            set -e
            forward_attempt_status_field=$(echo "$forward_attempt_json_payload" | jq -r '.status // ""' 2>/dev/null || echo "")
            if [[ "$forward_attempt_exit_code" -eq 0 ]] && [[ "$forward_attempt_status_field" == "found" ]]; then
                emit_iter123_json_envelope_wrapping_backend_response \
                    "$forward_attempt_json_payload" \
                    "iter122-forward-search" \
                    "ambiguous classification; forward search found a hit on first attempt (reverse fallback not exercised)"
                exit 0
            fi
            # Forward returned not-found — fall back to reverse.
            set +e
            reverse_fallback_json_payload=$(bash "$ITER116_REVERSE_CLI_ABSOLUTE_PATH" --json "$ITER123_OPERATOR_SUPPLIED_QUERY_STRING" 2>/dev/null)
            reverse_fallback_exit_code=$?
            set -e
            reverse_fallback_status_field=$(echo "$reverse_fallback_json_payload" | jq -r '.status // ""' 2>/dev/null || echo "")
            if [[ "$reverse_fallback_status_field" == "found" ]]; then
                fallback_dispatched_backend_label="iter116-reverse-search"
            else
                fallback_dispatched_backend_label="both-exhausted"
            fi
            emit_iter123_json_envelope_wrapping_backend_response \
                "$reverse_fallback_json_payload" \
                "$fallback_dispatched_backend_label" \
                "ambiguous classification; forward search returned no hits; fell back to reverse search"
            exit "$reverse_fallback_exit_code"
        fi
        # Human-readable mode: try forward, on not-found fall back to reverse.
        echo "ⓘ Routing: $ITER123_EFFECTIVE_ROUTING_RATIONALE"
        echo ""
        echo "→ Attempting forward search first (iter-122) ..."
        echo ""
        set +e
        bash "$ITER122_FORWARD_CLI_ABSOLUTE_PATH" "$ITER123_OPERATOR_SUPPLIED_QUERY_STRING"
        ITER123_FORWARD_EXIT_CODE=$?
        set -e
        if [[ "$ITER123_FORWARD_EXIT_CODE" -eq 0 ]]; then
            exit 0
        fi
        echo ""
        echo "ⓘ Forward search returned no hits; falling back to reverse search (iter-116) ..."
        echo ""
        set +e
        bash "$ITER116_REVERSE_CLI_ABSOLUTE_PATH" "$ITER123_OPERATOR_SUPPLIED_QUERY_STRING"
        exit $?
        ;;
    *)
        echo "ERROR: unexpected effective dispatch direction: $ITER123_EFFECTIVE_DISPATCH_DIRECTION" >&2
        exit 1
        ;;
esac
