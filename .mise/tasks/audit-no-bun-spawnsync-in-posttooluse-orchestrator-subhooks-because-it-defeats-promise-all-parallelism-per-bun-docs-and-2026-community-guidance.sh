#!/usr/bin/env bash
#MISE description="Iter-94 preventive static audit: scans every classifier function imported by the iter-93 PostToolUse orchestrator for Bun.spawnSync( invocations. Per Bun's official documentation + 2026 community guidance (search 'Bun.spawn vs Bun.spawnSync async parallelism event loop blocking 2026'), Bun.spawnSync halts the JS event loop until the subprocess exits, so wrapping it inside the orchestrator's Promise.all yields ZERO actual parallelism — N type-checker subhooks serialize at the OS level even though they iterate 'in parallel' at the JS level. Any classifier imported by the orchestrator that uses Bun.spawnSync( is a parallelism-defeat hazard and fails this audit. Informational task; release:preflight Check 4n candidate."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"
POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"

print_banner() {
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════════════"
}

print_banner "Iter-94 Static Audit: no Bun.spawnSync in PostToolUse orchestrator subhooks"
echo ""
echo "  Theory: Bun.spawnSync inside Promise.all yields ZERO OS-level parallelism."
echo "  Source: Bun docs (bun.com/docs/api/spawn) + 2026 community guidance."
echo "  Quote:  \"With Bun.spawnSync, true parallelism is impossible from a single"
echo "           thread — each call must finish before the next line of JS runs.\""
echo ""

if [[ ! -f "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" ]]; then
    echo "  ⊘ orchestrator file not found — audit cannot run, treating as no-op"
    exit 0
fi

# Extract every classifier function imported by the orchestrator. The
# pattern is `import { classify<X>ForPostToolUseOrchestrator } from "./<file>.ts"`.
# We accumulate the relative paths of those source files for the spawnSync scan.
declare -a CLASSIFIER_SOURCE_FILE_RELATIVE_PATHS_IMPORTED_BY_ORCHESTRATOR=()

while IFS= read -r import_line; do
    # Extract the path inside the from-clause quotes
    relative_source_path=$(echo "$import_line" | sed -E 's/.*from[[:space:]]*"([^"]+)".*/\1/')
    [[ -n "$relative_source_path" ]] || continue
    # Skip imports from `./lib/` (those are the contract types, not classifiers)
    if [[ "$relative_source_path" == "./lib/"* ]]; then
        continue
    fi
    CLASSIFIER_SOURCE_FILE_RELATIVE_PATHS_IMPORTED_BY_ORCHESTRATOR+=("$relative_source_path")
done < <(grep -E '^import \{[[:space:]]*classify[A-Za-z0-9]+ForPostToolUseOrchestrator' "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH")

echo "  Classifier source files imported by orchestrator: ${#CLASSIFIER_SOURCE_FILE_RELATIVE_PATHS_IMPORTED_BY_ORCHESTRATOR[@]}"
echo ""

if [[ ${#CLASSIFIER_SOURCE_FILE_RELATIVE_PATHS_IMPORTED_BY_ORCHESTRATOR[@]} -eq 0 ]]; then
    echo "  ⊘ no classifier files discovered via import-graph parse — audit cannot run"
    exit 0
fi

# Resolve each relative path to an absolute path (relative to the orchestrator file's directory)
ORCHESTRATOR_DIR_ABSOLUTE=$(dirname "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH")
declare -a CLASSIFIER_SOURCE_FILES_ABSOLUTE_PATHS=()
for relative_path in "${CLASSIFIER_SOURCE_FILE_RELATIVE_PATHS_IMPORTED_BY_ORCHESTRATOR[@]}"; do
    absolute_path="$ORCHESTRATOR_DIR_ABSOLUTE/${relative_path#./}"
    if [[ -f "$absolute_path" ]]; then
        CLASSIFIER_SOURCE_FILES_ABSOLUTE_PATHS+=("$absolute_path")
    fi
done

# Scan each classifier source file for `Bun.spawnSync(` invocations. The
# escape hatch is a same-line comment `// SPAWN-SYNC-OK: <reason ≥ 10 chars>`
# for legitimate cases (e.g., the standalone-CLI path may use spawnSync if
# it's gated behind import.meta.main and never reached during orchestrator
# inlining — though we still prefer async).
#
# Emission-pattern grep (not prose-comment grep): we EXCLUDE lines whose
# first non-whitespace character is `*` (JSDoc continuation), or that start
# with `//` (line comment), or that contain `Bun.spawnSync(` inside a
# backtick template literal. The remaining matches are actual code
# invocations. Mirrors the iter-90 PreToolUse additionalContext audit's
# emission-pattern-vs-prose-mention distinction.
declare -a PARALLELISM_DEFEAT_HAZARD_VIOLATIONS=()
for classifier_source_absolute_path in "${CLASSIFIER_SOURCE_FILES_ABSOLUTE_PATHS[@]}"; do
    classifier_relative_to_repo=${classifier_source_absolute_path#"$REPO_ROOT/"}
    while IFS= read -r matched_line; do
        # Allow the escape hatch
        if echo "$matched_line" | grep -qE 'SPAWN-SYNC-OK:[[:space:]]+.{10,}'; then
            continue
        fi
        # Strip leading `<digits>:` from `grep -n` output to inspect the line body
        line_body_only=$(echo "$matched_line" | sed -E 's/^[0-9]+://')
        # Skip JSDoc continuation lines (first non-whitespace char is `*`)
        if echo "$line_body_only" | grep -qE '^[[:space:]]*\*'; then
            continue
        fi
        # Skip pure line comments (first non-whitespace chars are `//`)
        if echo "$line_body_only" | grep -qE '^[[:space:]]*//'; then
            continue
        fi
        # Skip lines where the spawnSync token appears inside backticks
        # (e.g., template-literal documentation strings). Use bash builtin
        # pattern matching so we don't need a single-quoted regex containing
        # literal backticks (which trips SC2016 because backticks look like
        # legacy command-substitution syntax even when single-quoted).
        if [[ "$line_body_only" == *'`'*"Bun.spawnSync("*'`'* ]]; then
            continue
        fi
        PARALLELISM_DEFEAT_HAZARD_VIOLATIONS+=("$classifier_relative_to_repo: $matched_line")
    done < <(grep -n "Bun\.spawnSync(" "$classifier_source_absolute_path" 2>/dev/null || true)
done

# Report
if [[ ${#PARALLELISM_DEFEAT_HAZARD_VIOLATIONS[@]} -eq 0 ]]; then
    echo "  ✓ AUDIT PASSED — no Bun.spawnSync invocations in any orchestrator-imported classifier"
    echo ""
    echo "  Scanned files:"
    for path in "${CLASSIFIER_SOURCE_FILES_ABSOLUTE_PATHS[@]}"; do
        echo "    - ${path#"$REPO_ROOT/"}"
    done
    exit 0
fi

echo "  ✗ AUDIT FAILED — ${#PARALLELISM_DEFEAT_HAZARD_VIOLATIONS[@]} parallelism-defeat hazard(s) found:"
echo ""
for violation in "${PARALLELISM_DEFEAT_HAZARD_VIOLATIONS[@]}"; do
    echo "    $violation"
done
echo ""
echo "  Fix: replace Bun.spawnSync(...) with Bun.spawn(...) (async). Use the"
echo "  iter-94 helper executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndStreamDrain"
echo "  in posttooluse-ty-type-check.ts / posttooluse-tsgo-type-check.ts as the"
echo "  reference template."
echo ""
echo "  If the spawnSync is genuinely safe (standalone-CLI-only, never reached"
echo "  during orchestrator inlining), add an escape-hatch same-line comment:"
echo "    // SPAWN-SYNC-OK: <reason ≥ 10 chars>"
echo ""
exit 1
