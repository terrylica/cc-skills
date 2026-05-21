#!/usr/bin/env bash
#MISE description="Iter-77 preventive audit gate scanning every hook source file for references to plugin-root-level subtrees NOT in the iter-76 cache-populator allowlist (hooks, skills, commands, agents, plugin.json) which silently fail at L3 runtime. Default scans all hooks; --verbose shows per-violation context; --escape-hatch-marker shows the LAYER3-STRIPPED-PATH-OK marker syntax."

# Iter-77 preventive audit gate for the iter-76 cache-populator-filter
# forensic finding. Documented in docs/HOOKS.md "Iter-76 Cache-Populator-
# Filter Forensic Finding" section, this audit prevents the same kind
# of silent-runtime-failure bug that iter-77 fixed in link-tools/hooks/
# stop-link-check.py from being reintroduced in future hook source code.
#
# Bug class detected:
#
#   ${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh   ← stripped from L3, silent fail
#   ${CLAUDE_PLUGIN_ROOT}/docs/bar.md      ← stripped from L3, silent fail
#   ${CLAUDE_PLUGIN_ROOT}/tests/baz.py     ← stripped from L3, silent fail
#   ${CLAUDE_PLUGIN_ROOT}/config/qux.toml  ← stripped from L3, silent fail
#   ${CLAUDE_PLUGIN_ROOT}/templates/x.tpl  ← stripped from L3, silent fail
#   ${CLAUDE_PLUGIN_ROOT}/schemas/y.json   ← stripped from L3, silent fail
#   ${CLAUDE_PLUGIN_ROOT}/README.md        ← stripped from L3, silent fail
#   ${CLAUDE_PLUGIN_ROOT}/CLAUDE.md        ← stripped from L3, silent fail
#
# The Claude Code plugin cache populator (L2 → L3) keeps ONLY these
# subtrees at the plugin root:
#
#   - plugin.json
#   - hooks/**
#   - skills/**
#   - commands/**
#   - agents/**
#
# Any other plugin-root-level path referenced from hook source code
# resolves to a non-existent file path at hook fire time and the hook
# fails silently (returns None / null / undefined / error swallowed).
#
# Iter-77 forensic evidence: link-tools/hooks/stop-link-check.py had
# the L3-stripped-path bug for ~6 months before iter-76 discovered the
# cache-populator filter rules during the drift-detector build. The bug
# was operator-invisible because the FIRST THREE fallback paths in the
# config-resolution chain typically resolved before reaching the
# stripped path.
#
# Escape hatch (LAYER3-STRIPPED-PATH-OK marker):
#
# Genuine intentional references to L2 (not L3) paths can be allowed
# by adding a marker comment on the SAME LINE or within 3 lines of the
# offending reference:
#
#   # LAYER3-STRIPPED-PATH-OK: <reason ≥ 10 chars>
#   // LAYER3-STRIPPED-PATH-OK: <reason ≥ 10 chars>
#
# Examples of legitimate use (none currently exist in the marketplace):
#   - Hook that intentionally probes the L2 marketplace-mirror for a
#     dev-only artifact (using $HOME/.claude/plugins/marketplaces/...
#     resolved via env var instead of CLAUDE_PLUGIN_ROOT)
#   - Hook documenting the L3-stripped path in a code comment for
#     forensic clarity (already comment-only — won't trigger anyway)

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense:
shopt -u patsub_replacement 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ ! -d "$REPO_ROOT/plugins" ]]; then
    echo "✗ Expected plugins/ directory at $REPO_ROOT (script location-resolution failure)"
    exit 2
fi
cd "$REPO_ROOT"

# Parse argv
EMIT_VERBOSE_PER_VIOLATION_LINE_CONTEXT=0
EMIT_ESCAPE_HATCH_MARKER_REFERENCE_AND_EXIT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose)
            EMIT_VERBOSE_PER_VIOLATION_LINE_CONTEXT=1
            shift
            ;;
        --escape-hatch-marker)
            EMIT_ESCAPE_HATCH_MARKER_REFERENCE_AND_EXIT=1
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--verbose] [--escape-hatch-marker]"
            exit 2
            ;;
    esac
done

if [[ "$EMIT_ESCAPE_HATCH_MARKER_REFERENCE_AND_EXIT" == "1" ]]; then
    cat <<'EOF_ESCAPE_HATCH_MARKER_REFERENCE_BLOCK'
═══════════════════════════════════════════════════════════
  Iter-77 L3-Stripped-Path Audit — Escape Hatch Reference
═══════════════════════════════════════════════════════════

If a hook genuinely needs to reference an L3-stripped path (e.g., to
intentionally probe the marketplace mirror for a dev-only artifact),
mark the reference with a same-line or within-3-lines comment:

  Python:
    foo = f"{plugin_root}/scripts/x.sh"  # LAYER3-STRIPPED-PATH-OK: probes L2 mirror only
  Shell:
    ref="${CLAUDE_PLUGIN_ROOT}/docs/x"  # LAYER3-STRIPPED-PATH-OK: dev-time CLI invocation
  TypeScript/JS:
    const p = `${pluginRoot}/templates/x`;  // LAYER3-STRIPPED-PATH-OK: template-rendering at install time
  JSON (hooks.json — escape hatch via adjacent line in a "comment" field is NOT supported; relocate the asset under hooks/ instead)

Marker validation:
  - Reason must be at least 10 characters
  - Must appear on the SAME LINE as the reference, OR within the
    PRECEDING 3 LINES (to support multi-line string concatenation)
EOF_ESCAPE_HATCH_MARKER_REFERENCE_BLOCK
    exit 0
fi

# Allowlist of plugin-root subdirectories that the Claude Code cache
# populator preserves into Layer 3. Any reference like
# ${CLAUDE_PLUGIN_ROOT}/<segment>/ where <segment> is NOT in this list
# (or is not the bare "plugin.json" file) triggers a violation.
#
# Forensic evidence: iter-76 docs/HOOKS.md "Iter-76 Cache-Populator-
# Filter Forensic Finding" table.
declare -a LAYER_3_CACHE_POPULATOR_PRESERVED_PLUGIN_ROOT_SUBTREES=(
    "hooks"
    "skills"
    "commands"
    "agents"
)
LAYER_3_CACHE_POPULATOR_PRESERVED_ROOT_FILES=(
    "plugin.json"
)

is_segment_in_layer_3_preserved_allowlist() {
    local segment_under_test="$1"
    for allowlisted_subtree in "${LAYER_3_CACHE_POPULATOR_PRESERVED_PLUGIN_ROOT_SUBTREES[@]}"; do
        if [[ "$segment_under_test" == "$allowlisted_subtree" ]]; then
            return 0
        fi
    done
    for allowlisted_root_file in "${LAYER_3_CACHE_POPULATOR_PRESERVED_ROOT_FILES[@]}"; do
        if [[ "$segment_under_test" == "$allowlisted_root_file" ]]; then
            return 0
        fi
    done
    return 1
}

# Check whether a violation has a valid escape-hatch marker. Looks at
# the current line + 3 preceding lines for a "LAYER3-STRIPPED-PATH-OK:
# <reason>" comment with reason ≥ 10 chars.
has_valid_escape_hatch_marker_in_context() {
    local source_file_path="$1"
    local violation_line_number="$2"
    local search_start_line=$((violation_line_number - 3))
    if [[ "$search_start_line" -lt 1 ]]; then
        search_start_line=1
    fi
    # awk extracts the 4-line window, then grep checks for the marker
    # with a ≥10-char reason. The marker is recognized in any comment
    # style (#, //, /* */, --).
    local context_window
    context_window=$(awk -v start="$search_start_line" -v end="$violation_line_number" \
        'NR >= start && NR <= end' "$source_file_path")
    if echo "$context_window" | grep -qE 'LAYER3-STRIPPED-PATH-OK:[[:space:]]*[^[:space:]].{9,}'; then
        return 0
    fi
    return 1
}

total_hook_source_files_scanned=0
total_layer_3_stripped_path_violations_found=0
total_violations_with_valid_escape_hatch=0
declare -a violations_without_escape_hatch_for_release_gate_blocking=()

echo "═══════════════════════════════════════════════════════════"
echo "  Iter-77 L3-Stripped-Path Audit (Hook Source Code)"
echo "═══════════════════════════════════════════════════════════"
echo "  Scope: plugins/*/hooks/{*.json,*.sh,*.mjs,*.ts,*.py,*.js}"
echo "  Allowlist: \${CLAUDE_PLUGIN_ROOT}/{hooks,skills,commands,agents,plugin.json}/"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Build the file list. Filenames are stable (lowercase, hyphens, dots),
# so word-splitting is safe. Use a process-substitution + while loop
# pattern that handles "no matches" gracefully (find vs. shell glob).
#
# Iter-129 perf-win: -mindepth 3 -maxdepth 4 confines descent to exactly
# the two legitimate hook-source-file depths:
#   depth 3: plugins/<plugin>/hooks/<file>            (most hooks)
#   depth 4: plugins/<plugin>/hooks/{lib,tests}/<file> (shared helpers + tests)
# This skips descent into every plugin's skills/, scripts/, references/,
# node_modules/, .ruff_cache/, .git/, etc. before the predicate prunes.
# Empirically measured: 0.39s -> 0.02s (~20x speedup, identical 122-file
# count). Saves ~370ms per Check 4k invocation. Same iter-125/iter-127
# bounded-depth pattern; this audit's find was the last unbounded
# -path '*/hooks/...' walker in the preflight family.
hook_source_files_for_audit=()
while IFS= read -r candidate_hook_source_file_path; do
    [[ -f "$candidate_hook_source_file_path" ]] && hook_source_files_for_audit+=("$candidate_hook_source_file_path")
done < <(find "$REPO_ROOT/plugins" -mindepth 3 -maxdepth 4 \
    -path '*/hooks/*' \
    \( -name '*.json' -o -name '*.sh' -o -name '*.mjs' -o -name '*.ts' -o -name '*.py' -o -name '*.js' \) \
    -type f \
    -not -path '*/node_modules/*' \
    -not -path '*/.ruff_cache/*' \
    2>/dev/null | sort)

for hook_source_file in "${hook_source_files_for_audit[@]}"; do
    total_hook_source_files_scanned=$((total_hook_source_files_scanned + 1))
    relative_hook_source_path="${hook_source_file#"$REPO_ROOT"/}"

    # grep for `${CLAUDE_PLUGIN_ROOT}/<segment>` references. The regex
    # captures the path-component immediately after the variable. Both
    # ${CLAUDE_PLUGIN_ROOT} and $CLAUDE_PLUGIN_ROOT spellings are
    # accepted. Multiple references per line are caught via grep -oE.
    matched_reference_lines_with_numbers=$(grep -nE '\$\{?CLAUDE_PLUGIN_ROOT\}?/[A-Za-z0-9_.-]+' "$hook_source_file" 2>/dev/null || true)
    if [[ -z "$matched_reference_lines_with_numbers" ]]; then
        continue
    fi

    while IFS= read -r single_match_with_line_number; do
        # Format: "<line_number>:<line_content>"
        violation_line_number="${single_match_with_line_number%%:*}"
        line_content="${single_match_with_line_number#*:}"
        # Extract the first segment after CLAUDE_PLUGIN_ROOT/. There
        # may be multiple references per line — loop through them.
        # POSIX bash regex match in a loop:
        remaining_to_scan="$line_content"
        while [[ "$remaining_to_scan" =~ \$\{?CLAUDE_PLUGIN_ROOT\}?/([A-Za-z0-9_.-]+) ]]; do
            extracted_first_path_segment="${BASH_REMATCH[1]}"
            # Trim everything up to and including this match for the
            # next iteration. The regex match length isn't directly
            # available so we use a parameter-expansion trim.
            remaining_to_scan="${remaining_to_scan#*"${BASH_REMATCH[0]}"}"

            if is_segment_in_layer_3_preserved_allowlist "$extracted_first_path_segment"; then
                continue  # allowlisted — not a violation
            fi

            # Found a non-allowlisted reference. Check for escape hatch.
            total_layer_3_stripped_path_violations_found=$((total_layer_3_stripped_path_violations_found + 1))
            if has_valid_escape_hatch_marker_in_context "$hook_source_file" "$violation_line_number"; then
                total_violations_with_valid_escape_hatch=$((total_violations_with_valid_escape_hatch + 1))
                if [[ "$EMIT_VERBOSE_PER_VIOLATION_LINE_CONTEXT" == "1" ]]; then
                    echo "  ⊘ ESCAPE-HATCH-OK at $relative_hook_source_path:$violation_line_number (segment: $extracted_first_path_segment)"
                fi
                continue
            fi

            # Unjustified violation — record for release-gate blocking
            violation_record="$relative_hook_source_path:$violation_line_number: \${CLAUDE_PLUGIN_ROOT}/$extracted_first_path_segment/... (segment NOT in cache-populator allowlist)"
            violations_without_escape_hatch_for_release_gate_blocking+=("$violation_record")

            if [[ "$EMIT_VERBOSE_PER_VIOLATION_LINE_CONTEXT" == "1" ]]; then
                echo "  ✗ $violation_record"
                echo "      Line content: $line_content"
            else
                echo "  ✗ $violation_record"
            fi
        done
    done <<< "$matched_reference_lines_with_numbers"
done

total_unjustified_violations=${#violations_without_escape_hatch_for_release_gate_blocking[@]}

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════════════════════════"
echo "  Hook source files scanned:                    $total_hook_source_files_scanned"
echo "  L3-stripped-path references found:            $total_layer_3_stripped_path_violations_found"
echo "  With LAYER3-STRIPPED-PATH-OK escape hatch:    $total_violations_with_valid_escape_hatch"
echo "  Unjustified violations (silent-fail risk):    $total_unjustified_violations"

if [[ "$total_unjustified_violations" -gt 0 ]]; then
    echo ""
    echo "  ⚠  Each unjustified violation will silently fail at L3 runtime."
    echo "     Remediation options:"
    echo "       (a) Move the asset under hooks/ (which IS cached at L3) and update the reference"
    echo "       (b) Add a LAYER3-STRIPPED-PATH-OK: <reason ≥ 10 chars> comment if the reference is intentional"
    echo "       (c) See \`$0 --escape-hatch-marker\` for marker syntax"
    echo ""
    echo "  Forensic source: iter-76 docs/HOOKS.md cache-populator-filter section"
    echo "  Live confirmation tool: mise run audit-marketplace-mirror-layer2-vs-versioned-operator-cache-layer3-per-plugin-content-hash-drift-detector-for-iter42-three-layer-cache-lifecycle-operator-self-diagnosis"
    exit 1
fi

echo ""
echo "  ✓ All hook source references resolve to L3-cached paths"
echo "═══════════════════════════════════════════════════════════"
