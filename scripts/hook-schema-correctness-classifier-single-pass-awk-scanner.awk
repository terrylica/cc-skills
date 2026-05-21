#!/usr/bin/env awk -f
# hook-schema-correctness-classifier-single-pass-awk-scanner.awk
#
# Iter-79 single-pass cross-file scanner that replaces the fork-exec
# storm in `.mise/tasks/release/preflight` Check 4f (iter-60 PreToolUse
# schema audit, 842ms) and Check 4h (iter-62 inverse PreToolUse schema
# audit, 787ms). Reads every hook source file passed in argv, emits one
# TSV record per file with the audit facts needed by the downstream
# bash post-processor in either audit task:
#
#   <filepath>\t<has_permissionDecision_pretooluse_only_field:0|1>\
#   t<has_hookSpecificOutput_wrapper:0|1>\
#   t<has_deprecated_top_level_decision_block_or_deny:0|1>\
#   t<has_modern_pretooluse_helper_function_call:0|1>\
#   t<has_additionalContext_informational_field:0|1>\
#   t<has_posttooluse_helpers_module_import:0|1>
#
# Iter-79 perf-win rationale: each audit currently issues 3-4
# `grep -qE` forks per hook source file (29 PreToolUse + 24 non-
# PreToolUse = 53 files × ~3.5 forks = ~186 fork-exec invocations
# per preflight). Replaces those ~186 forks with TWO awk process
# invocations (one per audit). Estimated combined drop from ~1629ms
# to ~150-300ms (~1300-1500ms saved per preflight run, ~24% of the
# total ~6.1s preflight). See docs/RELEASE.md "Opt-In Per-Phase
# Wall-Clock Timing Instrumentation (iter-73)" for baseline.
#
# Audit semantics preserved bit-for-bit from the iter-60 and iter-62
# baselines. Both audits read the SAME set of TSV flags but interpret
# them OPPOSITELY:
#
#   Check 4f (PreToolUse hooks) — tier order:
#     1. modern (has_permissionDecision_field OR has_hookSpecificOutput_wrapper)
#        → MODERN-CORRECT
#     2. else has_deprecated_top_level_decision_block_or_deny
#        → DEPRECATED-WARNING (silent-fail on Claude Code v2.0.10+)
#     3. else has_modern_pretooluse_helper_function_call
#        → HELPER-WRAPPED
#     4. else → NO-DECISION-EMITTED
#
#   Check 4h (non-PreToolUse hooks) — tier order:
#     1. has_permissionDecision_pretooluse_only_field
#        → WRONG-FIELD-SILENT-FAIL (PreToolUse-only field on wrong event)
#     2. else has_deprecated_top_level_decision_block_or_deny
#        → SCHEMA-CORRECT-FOR-EVENT (top-level decision IS canonical
#          for these events)
#     3. else has_additionalContext_informational_field
#        → SCHEMA-CORRECT-FOR-EVENT (valid informational pattern)
#     4. else has_posttooluse_helpers_module_import
#        → HELPER-WRAPPED
#     5. else → NO-BLOCKING-EMITTED
#
# The asymmetry — permissionDecision is GOOD in 4f, BAD in 4h — is the
# whole reason these audits exist as a sister pair. The Claude Code
# v2.0.10+ schema reads permissionDecision ONLY for PreToolUse; on any
# other event it's read by no field consumer and silently dropped.
# This single-pass classifier preserves the asymmetric interpretation
# by emitting raw flags and letting each post-processor apply its own
# tier rules.
#
# Portability: POSIX-portable awk syntax — no gawk-specific extensions
# (no ENDFILE, no asort, no length(array)). Verified against macOS
# BWK awk version 20200816 (/usr/bin/awk).
#
# Comment-line filtering: this scanner intentionally does NOT skip
# comment lines, matching the iter-60/iter-62 baseline behavior. Both
# audits use `grep -qE` which scans the entire file including comments.
# A hook source file with a comment like
#     // emit hookSpecificOutput.permissionDecision: "deny"
# WILL match the iter-60 MODERN-CORRECT tier just as before.

# File-boundary detection: at the FIRST line of each new input file,
# flush results for the PREVIOUS file (if any) and reset per-file state.
# This pattern is the portable alternative to gawk's ENDFILE.
FNR == 1 {
    if (filepath_of_previously_scanned_hook_source_file != "") {
        emit_tsv_classification_flags_for_completed_hook_source_file()
    }
    # Reset per-file accumulator state for the new hook source file.
    filepath_of_previously_scanned_hook_source_file = FILENAME
    has_permissionDecision_pretooluse_only_field = 0
    has_hookSpecificOutput_wrapper = 0
    has_deprecated_top_level_decision_block_or_deny = 0
    has_modern_pretooluse_helper_function_call = 0
    has_additionalContext_informational_field = 0
    has_posttooluse_helpers_module_import = 0
}

# Per-line pattern matchers — once a flag is set for a file, no need
# to re-check, but the cost of `index() > 0` short-circuiting on
# already-set flags is negligible and keeps the awk logic simple.

# Match: permissionDecision (the PreToolUse-only blocking decision field).
# Iter-60 tier 1 / iter-62 tier 1.
index($0, "permissionDecision") > 0 {
    has_permissionDecision_pretooluse_only_field = 1
}

# Match: hookSpecificOutput (the modern PreToolUse wrapper object).
# Iter-60 tier 1 (paired with permissionDecision in the canonical
# v2.0.10+ schema).
index($0, "hookSpecificOutput") > 0 {
    has_hookSpecificOutput_wrapper = 1
}

# Match: deprecated top-level `decision: "block"` or `decision: "deny"`
# Iter-60 tier 2 / iter-62 tier 2.
# Bash-escaped variant of the original regex with single AND double
# quote support. Both single-quoted and double-quoted forms occur in
# the wild because hooks are written in TypeScript (double) and Python
# (mixed) and shell (mixed).
$0 ~ /"decision"[[:space:]]*:[[:space:]]*"(block|deny)"/ {
    has_deprecated_top_level_decision_block_or_deny = 1
}
$0 ~ /decision:[[:space:]]*['"'"'"](block|deny)['"'"'"]/ {
    has_deprecated_top_level_decision_block_or_deny = 1
}

# Match: a call to one of the cc-skills PreToolUse helper functions
# (deny, block, ask, allow, allowWithInput) at the source level. The
# `\b` word boundary anchors prevent partial matches like `myBlock(`.
# Iter-60 tier 3.
$0 ~ /[^A-Za-z_](deny|block|ask|allow|allowWithInput)\(/ {
    has_modern_pretooluse_helper_function_call = 1
}
# Also catch the case where the helper call starts the line.
$0 ~ /^(deny|block|ask|allow|allowWithInput)\(/ {
    has_modern_pretooluse_helper_function_call = 1
}

# Match: additionalContext field (the informational, non-blocking
# pattern valid on PostToolUse / UserPromptSubmit / SessionStart).
# Iter-62 tier 3.
index($0, "additionalContext") > 0 {
    has_additionalContext_informational_field = 1
}

# Match: import statement pulling from a posttooluse-helpers module.
# Iter-62 tier 4 — currently no such module exists, but the audit
# pattern is reserved for the future. The same regex as the original.
$0 ~ /from[[:space:]]+["'"'"'][^"'"'"']*posttooluse-helpers/ {
    has_posttooluse_helpers_module_import = 1
}

# Flush the LAST file's classification — END fires once after all input
# is consumed. Without this, the final file in argv would be silently
# omitted from the TSV output (FNR==1 only fires at the START of files).
END {
    if (filepath_of_previously_scanned_hook_source_file != "") {
        emit_tsv_classification_flags_for_completed_hook_source_file()
    }
}

# TSV-emission helper. Tab-separated for safe parsing by the downstream
# bash `while IFS=$'\t' read` loop in each audit. Filenames in the
# cc-skills marketplace are constrained to
# `plugins/<slug>/hooks/<prefix>-<rest>.<ext>` with slug = [a-z0-9-]+
# — no tabs, no newlines, no special chars in the filepath column.
# The other six columns are integers (0 or 1).
function emit_tsv_classification_flags_for_completed_hook_source_file() {
    printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\n", \
        filepath_of_previously_scanned_hook_source_file, \
        has_permissionDecision_pretooluse_only_field, \
        has_hookSpecificOutput_wrapper, \
        has_deprecated_top_level_decision_block_or_deny, \
        has_modern_pretooluse_helper_function_call, \
        has_additionalContext_informational_field, \
        has_posttooluse_helpers_module_import
}
