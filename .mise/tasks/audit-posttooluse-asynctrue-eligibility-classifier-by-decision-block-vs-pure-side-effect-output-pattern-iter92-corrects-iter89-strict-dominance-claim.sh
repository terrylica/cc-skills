#!/usr/bin/env bash
#MISE description="Iter-92 PostToolUse async:true ELIGIBILITY audit — corrects iter-89's incorrect 'async:true is strict-dominant for PostToolUse' claim. Per Anthropic's documented timing semantics (placement next-to-tool-result requires synchronous completion before next model request), async:true is ONLY safe for PURE-SIDE-EFFECT hooks. Hooks that emit `{decision: \"block\", reason}` JSON for Claude self-correction-feedback-loop MUST remain SYNCHRONOUS — async would break the on-same-turn context injection contract. This task scans every PostToolUse hooks.json entry across the marketplace, classifies each script by output pattern (DECISION-BLOCK-EMITTING / PURE-SIDE-EFFECT / NEEDS-MANUAL-REVIEW), and produces an actionable report. Replaces iter-88's blanket '9 hooks → 1 orchestrator, ~136ms savings' projection with a per-hook safety verdict."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# ---------- Locate repo root ----------
SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"

# ---------- Output formatting ----------
print_banner() {
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════════════"
}

print_banner "Iter-92 PostToolUse async:true Eligibility Audit"
echo ""
echo "  Theory: async:true is SAFE only for PURE-SIDE-EFFECT PostToolUse hooks."
echo "  CONTEXT-INJECTING hooks (decision-block-emitting) MUST remain synchronous."
echo "  Source: code.claude.com/docs/en/hooks + claudefa.st March-2026 reference."
echo ""

# ---------- Discover PostToolUse hook scripts via every plugin's hooks.json ----------
# Iterate every plugins/*/hooks/hooks.json file. For each PostToolUse entry,
# extract the command field, resolve the ${CLAUDE_PLUGIN_ROOT} placeholder to
# the absolute plugin-root directory, strip the `bun ` / `node ` prefix to
# isolate the script path, and accumulate (de-duplicated) into the records list.
declare -a POSTTOOLUSE_HOOK_FORENSIC_RECORDS=()
while IFS= read -r hooks_json_file_absolute_path; do
    plugin_hooks_directory_containing_this_hooks_json=$(dirname "$hooks_json_file_absolute_path")
    # Use jq to extract every PostToolUse entry's command field; each entry may
    # have multiple hooks per matcher. We want the full hooks-command list.
    while IFS= read -r posttooluse_hook_command_raw_with_plugin_root_placeholder; do
        # Substitute ${CLAUDE_PLUGIN_ROOT} → the plugin's root directory
        # (the parent of hooks/ contains plugin.json — that's CLAUDE_PLUGIN_ROOT)
        plugin_root_directory_absolute_path=$(dirname "$plugin_hooks_directory_containing_this_hooks_json")
        # Substitute the placeholder
        # shellcheck disable=SC2001 # sed needed for literal pattern substitution
        posttooluse_hook_command_resolved=$(echo "$posttooluse_hook_command_raw_with_plugin_root_placeholder" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$plugin_root_directory_absolute_path#g")
        # Strip the `bun ` prefix if present
        posttooluse_hook_script_path_only=$(echo "$posttooluse_hook_command_resolved" | sed -E 's/^[[:space:]]*(bun|node)[[:space:]]+//' | awk '{print $1}')

        if [[ -f "$posttooluse_hook_script_path_only" ]]; then
            POSTTOOLUSE_HOOK_FORENSIC_RECORDS+=("$posttooluse_hook_script_path_only")
        fi
    done < <(jq -r '.hooks.PostToolUse[]?.hooks[]?.command // empty' "$hooks_json_file_absolute_path" 2>/dev/null)
done < <(find "$REPO_ROOT/plugins" -mindepth 3 -maxdepth 3 -name 'hooks.json' -type f 2>/dev/null)

# Dedupe preserving order
declare -a POSTTOOLUSE_HOOK_FORENSIC_RECORDS_DEDUPED=()
declare -A POSTTOOLUSE_HOOK_FORENSIC_SEEN_SET=()
for path in "${POSTTOOLUSE_HOOK_FORENSIC_RECORDS[@]}"; do
    if [[ -z "${POSTTOOLUSE_HOOK_FORENSIC_SEEN_SET[$path]:-}" ]]; then
        POSTTOOLUSE_HOOK_FORENSIC_RECORDS_DEDUPED+=("$path")
        POSTTOOLUSE_HOOK_FORENSIC_SEEN_SET[$path]=1
    fi
done

echo "  Total PostToolUse hook scripts discovered (after dedup): ${#POSTTOOLUSE_HOOK_FORENSIC_RECORDS_DEDUPED[@]}"
echo ""

# ---------- Iter-124 perf: pre-scan async-flag-by-hook-basename map ----------
#
# Pre-iter-124 the per-hook classifier (line ~73 below) re-ran a
# `grep -rE … --include=hooks.json` against the entire plugins/ tree
# ONCE PER HOOK to determine async-flag status. With N PostToolUse hooks
# (currently 11) that meant N redundant tree-walks of the plugins/ tree.
# Empirical iter-124 measurement: 11 sequential greps = 925ms — 40% of
# the audit's 2.4s total runtime — for a lookup whose data is invariant
# across the loop. Same iter-74 / iter-79 fork-storm anti-pattern.
#
# Iter-124 fix: single jq pass extracts (basename, async-flag) pairs from
# every hooks.json file ONCE before the classifier loop, stores in a
# basename-keyed bash associative array. Per-hook lookup becomes O(1)
# hash-lookup instead of O(M) tree-walk where M = number of marketplace
# hooks.json files.
declare -A ITER124_ASYNC_FLAG_STATUS_BY_POSTTOOLUSE_HOOK_BASENAME=()
while IFS= read -r hooks_json_path_for_async_flag_prescan; do
    # Extract each PostToolUse entry's (async, command-basename) tuple.
    # The `command` field looks like `bun ${CLAUDE_PLUGIN_ROOT}/hooks/foo.ts`
    # — split on whitespace, take the last segment, split on `/`, take
    # the basename. `async` defaults to false when absent.
    while IFS=$'\t' read -r async_flag_value command_basename; do
        [[ -z "$command_basename" ]] && continue
        if [[ "$async_flag_value" == "true" ]]; then
            ITER124_ASYNC_FLAG_STATUS_BY_POSTTOOLUSE_HOOK_BASENAME[$command_basename]="ALREADY-ASYNC"
        elif [[ -z "${ITER124_ASYNC_FLAG_STATUS_BY_POSTTOOLUSE_HOOK_BASENAME[$command_basename]:-}" ]]; then
            # First-seen-wins for the NOT-CURRENTLY-ASYNC default; if a
            # later hooks.json entry has async:true for the same basename,
            # the branch above will overwrite to ALREADY-ASYNC (treating
            # any async:true marketplace-wide as authoritative).
            ITER124_ASYNC_FLAG_STATUS_BY_POSTTOOLUSE_HOOK_BASENAME[$command_basename]="NOT-CURRENTLY-ASYNC"
        fi
    done < <(jq -r '.hooks.PostToolUse[]?.hooks[]? | "\(.async // false)\t\(.command | split("/") | .[-1] | split(" ") | .[0])"' "$hooks_json_path_for_async_flag_prescan" 2>/dev/null)
done < <(find "$REPO_ROOT/plugins" -mindepth 3 -maxdepth 3 -name 'hooks.json' -type f 2>/dev/null)

# ---------- Per-script async-eligibility classifier ----------
classify_posttooluse_hook_for_async_true_safety_by_output_pattern() {
    local hook_script_absolute_path="$1"
    local classification_verdict_letter="?"
    local human_readable_classification_rationale=""
    local existing_async_flag_status=""

    # Iter-124: O(1) hash-lookup instead of O(M) tree-walk per hook.
    # Default to NOT-CURRENTLY-ASYNC for hooks whose basename isn't in
    # the pre-scanned map (defensive — shouldn't happen since both the
    # discovery loop above and the pre-scan walk the same hooks.json
    # files, but tolerate it rather than crash on a stale entry).
    local hook_basename
    hook_basename=$(basename "$hook_script_absolute_path")
    existing_async_flag_status="${ITER124_ASYNC_FLAG_STATUS_BY_POSTTOOLUSE_HOOK_BASENAME[$hook_basename]:-NOT-CURRENTLY-ASYNC}"

    # PATTERN 1: Hook emits `{decision: "block", reason: ...}` JSON
    #   → CONTEXT-INJECTING (Claude reads the reason for self-correction)
    #   → ASYNC-UNSAFE (model advances before context arrives if async)
    if grep -qE 'decision[[:space:]]*:[[:space:]]*"block"' "$hook_script_absolute_path" 2>/dev/null; then
        classification_verdict_letter="C"
        human_readable_classification_rationale="CONTEXT-INJECTING (emits decision:block JSON for self-correction feedback loop — MUST remain SYNCHRONOUS so Claude sees the reason next-to-tool-result per Anthropic timing docs)"
    # PATTERN 2: Hook emits `additionalContext` JSON
    #   → CONTEXT-INJECTING (Claude reads the field as system reminder)
    #   → ASYNC-UNSAFE
    elif grep -qE '"additionalContext"[[:space:]]*:|additionalContext[[:space:]]*:' "$hook_script_absolute_path" 2>/dev/null; then
        classification_verdict_letter="C"
        human_readable_classification_rationale="CONTEXT-INJECTING (emits additionalContext JSON — same async-unsafe rationale as decision:block)"
    # PATTERN 3: Hook emits text to stdout that's NOT structured JSON
    #   → MAY-INJECT-CONTEXT (Claude may parse the stdout as a system reminder)
    #   → NEEDS-MANUAL-REVIEW
    elif grep -qE '^[[:space:]]*(console\.log|process\.stdout\.write|echo[[:space:]])' "$hook_script_absolute_path" 2>/dev/null; then
        classification_verdict_letter="M"
        human_readable_classification_rationale="MAY-INJECT-CONTEXT (emits unstructured stdout; manual review required — could be operator-visible only via stderr OR could be Claude-visible system reminder)"
    # PATTERN 4: No stdout output detected, only file/network side effects
    #   → PURE-SIDE-EFFECT
    #   → ASYNC-SAFE
    else
        classification_verdict_letter="S"
        human_readable_classification_rationale="PURE-SIDE-EFFECT (no detected stdout output → safe candidate for async:true)"
    fi

    echo "  [$classification_verdict_letter] [$existing_async_flag_status] $(basename "$hook_script_absolute_path")"
    echo "      $human_readable_classification_rationale"
}

# ---------- Run classifier on every discovered PostToolUse hook ----------
COUNT_VERDICT_CONTEXT_INJECTING_ASYNC_UNSAFE=0
COUNT_VERDICT_MANUAL_REVIEW_NEEDED=0
COUNT_VERDICT_PURE_SIDE_EFFECT_ASYNC_SAFE=0

for posttooluse_hook_path in "${POSTTOOLUSE_HOOK_FORENSIC_RECORDS_DEDUPED[@]}"; do
    classification_output_block=$(classify_posttooluse_hook_for_async_true_safety_by_output_pattern "$posttooluse_hook_path")
    echo "$classification_output_block"
    # Count by verdict letter on the first line
    verdict_letter_on_first_line=$(echo "$classification_output_block" | head -1 | grep -oE '\[[CMS]\]' | head -1)
    case "$verdict_letter_on_first_line" in
        '[C]') COUNT_VERDICT_CONTEXT_INJECTING_ASYNC_UNSAFE=$((COUNT_VERDICT_CONTEXT_INJECTING_ASYNC_UNSAFE + 1)) ;;
        '[M]') COUNT_VERDICT_MANUAL_REVIEW_NEEDED=$((COUNT_VERDICT_MANUAL_REVIEW_NEEDED + 1)) ;;
        '[S]') COUNT_VERDICT_PURE_SIDE_EFFECT_ASYNC_SAFE=$((COUNT_VERDICT_PURE_SIDE_EFFECT_ASYNC_SAFE + 1)) ;;
    esac
    echo ""
done

# ---------- Summary + actionable verdict ----------
print_banner "Iter-92 Audit Summary"
echo ""
echo "  Total PostToolUse hooks scanned:                                  ${#POSTTOOLUSE_HOOK_FORENSIC_RECORDS_DEDUPED[@]}"
echo "  [C] CONTEXT-INJECTING (decision:block or additionalContext):      $COUNT_VERDICT_CONTEXT_INJECTING_ASYNC_UNSAFE  → ASYNC-UNSAFE (keep synchronous)"
echo "  [M] MAY-INJECT-CONTEXT (unstructured stdout):                     $COUNT_VERDICT_MANUAL_REVIEW_NEEDED  → MANUAL-REVIEW required"
echo "  [S] PURE-SIDE-EFFECT (no stdout output):                          $COUNT_VERDICT_PURE_SIDE_EFFECT_ASYNC_SAFE  → ASYNC-SAFE candidates"
echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "  ITER-92 CORRECTION OF ITER-89 STRICT-DOMINANCE CLAIM"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Iter-89 claimed: 'async:true is strict-dominant over orchestrator inlining"
echo "  for PostToolUse because PostToolUse cannot deny per iter-66 schema'."
echo ""
echo "  Iter-92 web research (claudefa.st March 2026 + Anthropic hooks reference)"
echo "  reveals the claim was WRONG: PostToolUse can still INJECT CONTEXT via"
echo "  {decision: 'block', reason} or additionalContext, and async:true breaks"
echo "  the same-turn timing required for Claude's self-correction feedback loop."
echo ""
echo "  Per Anthropic timing semantics:"
echo "    \"An async PostToolUse hook cannot reliably inject additionalContext"
echo "     next to the tool result, since the model will have already advanced"
echo "     before the hook finishes.\""
echo ""
echo "  CORRECTED ARCHITECTURE DECISION FOR TASK #96:"
echo "    - Path A (async:true sweep): RULED OUT for $COUNT_VERDICT_CONTEXT_INJECTING_ASYNC_UNSAFE of"
echo "      ${#POSTTOOLUSE_HOOK_FORENSIC_RECORDS_DEDUPED[@]} hooks; viable for $COUNT_VERDICT_PURE_SIDE_EFFECT_ASYNC_SAFE pure-side-effect hooks ONLY"
echo "    - Path B (orchestrator inlining): viable for ALL hooks (preserves"
echo "      synchronous decision:block context injection)"
echo "    - Path C (HTTP hooks long-lived server): viable but requires server"
echo "      lifecycle management; SOTA pattern surfaced by iter-89 research"
echo ""
echo "  Iter-93+ recommendation: pursue Path B (orchestrator) for the"
echo "  $COUNT_VERDICT_CONTEXT_INJECTING_ASYNC_UNSAFE context-injecting hooks; apply Path A async:true to the"
echo "  $COUNT_VERDICT_PURE_SIDE_EFFECT_ASYNC_SAFE pure-side-effect hooks only after this audit's"
echo "  classification has been peer-reviewed."
echo "════════════════════════════════════════════════════════════════════════════════"

# Exit 0 (informational task — never blocks release pipeline)
exit 0
