#!/usr/bin/env bash
#MISE description="Iter-103 marketplace-wide NotebookEdit applicability audit. Per 2026 Anthropic canonical recommendation the file-edit tool quadruple is Edit|MultiEdit|Write|NotebookEdit. NotebookEdit has DIFFERENT payload shape (notebook_path + cell_id + new_source + edit_mode) operating on Jupyter .ipynb cells. This audit produces a per-classifier applicability matrix + surfaces hooks that SHOULD honor NotebookEdit because their content patterns apply to notebook cell source (e.g., hardcoded versions, PyTorch GPU patterns). Informational only — community-validated 2026 NotebookEdit bugs (insert-positioning bug + git diff noise + Jupyter MCP server recommendation) mean per-hook broadening is conditional, not universal."

# ────────────────────────────────────────────────────────────────────────
# Full design rationale
# ────────────────────────────────────────────────────────────────────────
#
# Iter-102 surfaced via 2026 Anthropic + community best-practice web
# research that the canonical "any file modification" hook matcher per
# the official docs is `Edit|MultiEdit|Write|NotebookEdit` (4 tools, not
# the 3-tool `Edit|MultiEdit|Write` iter-101 enforced). Iter-101's
# matcher-hygiene audit therefore was also incomplete — it forced
# MultiEdit but did not surface the NotebookEdit gap.
#
# However, NotebookEdit has a fundamentally different payload shape:
#
#   {
#     "notebook_path": "/abs/path/notebook.ipynb",  # NOT file_path
#     "cell_id": "76f7be6b",                         # Jupyter cell UUID
#     "new_source": "...",                           # cell content
#     "cell_type": "code" | "markdown",
#     "edit_mode": "replace" | "insert" | "delete"
#   }
#
# Naive broadening (just adding NotebookEdit to matchers) would cause:
#   - Classifiers reading `tool_input.file_path` to silently get undefined
#   - Edit-branch content extraction logic to corrupt or fail
#   - False-positive denies if extracted content is empty/undefined
#
# Therefore NotebookEdit support is CONDITIONAL on per-hook applicability:
#   - File-path-suffix-specific hooks (CLAUDE.md, pyproject.toml, mise.toml,
#     __init__.py, launchd plists, GLOSSARY.md, README.md) → NOT applicable
#     because notebooks are .ipynb (different file type entirely)
#   - Content-pattern-specific hooks (version-guard regex, gpu-optimization-
#     guard PyTorch detection, ssot-principles, code-correctness-guard,
#     file-size-guard) → POTENTIALLY applicable — patterns can occur in
#     notebook cell source just as in .py/.ts/.rs files
#
# Community-validated 2026 NotebookEdit cautions surfaced by iter-103 web
# research:
#   1. NotebookEdit insert-positioning bug (cells inserted at position 0
#      instead of after cell_id) — anthropics/claude-code issue #18538
#   2. NotebookEdit writes cell source as single JSON string causing git
#      diff noise + format-revert war with JupyterLab — ReviewNB blog
#   3. Community recommendation: use Jupyter MCP server (kernel-aware)
#      instead of NotebookEdit for serious notebook workflows
#
# Per these cautions, this audit is INFORMATIONAL (does not force broadening).
# It surfaces the per-classifier applicability matrix + flags hooks where
# NotebookEdit support would add correctness value if/when the upstream tool
# stabilizes. Per-hook payload-shape adaptation is iter-104+ scope.
#
# Parallel to:
#   - iter-94 audit: no-spawnSync-in-PostToolUse-orchestrator (perf invariant)
#   - iter-99 audit: no-raw-stdout-emission-in-PostToolUse (silent-drop invariant)
#   - iter-101 audit: matcher Write|Edit must include MultiEdit (universal invariant)
#   - iter-103 audit (THIS): NotebookEdit applicability per-hook (conditional)
#
# Sources for iter-103 web research:
#   - https://code.claude.com/docs/en/tools-reference (NotebookEdit payload spec)
#   - https://www.reviewnb.com/claude-code-with-jupyter-notebooks (workarounds)
#   - https://github.com/anthropics/claude-code/issues/18538 (insert bug)
#   - https://github.com/anthropics/claude-code/issues/46013 (cell_id IDE context)

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"

print_banner() {
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════════════"
}

print_banner "Iter-103 Marketplace-Wide NotebookEdit Applicability Audit (Informational)"
echo ""
echo "  Theory: Per 2026 Anthropic canonical recommendation, the file-edit tool"
echo "          quadruple is Edit|MultiEdit|Write|NotebookEdit. NotebookEdit has a"
echo "          DIFFERENT payload shape (notebook_path + cell_id + new_source +"
echo "          edit_mode) operating on Jupyter .ipynb cells, not file content."
echo ""
echo "  Source: 2026 web research surfaced during iter-102 adversarial audit:"
echo "    - https://code.claude.com/docs/en/tools-reference (payload spec)"
echo "    - https://www.reviewnb.com/claude-code-with-jupyter-notebooks (workarounds)"
echo "    - https://github.com/anthropics/claude-code/issues/18538 (insert bug)"
echo ""
echo "  Iter-103 invariant: surface the per-classifier applicability matrix +"
echo "          INFORMATIONAL recommendations. No forced broadening because"
echo "          NotebookEdit has community-validated bugs (insert-positioning,"
echo "          git diff noise, Jupyter MCP server recommendation)."
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  Step 1 — Per-classifier applicability matrix (manually curated SSoT)
# ══════════════════════════════════════════════════════════════════════════
#
# Each classifier's NotebookEdit applicability is determined by what its
# logic actually inspects:
#
#   - file_path suffix matching (CLAUDE.md, pyproject.toml, __init__.py,
#     mise.toml, plist, GLOSSARY.md, README.md) → NOT APPLICABLE
#     (notebooks are .ipynb — entirely different file type)
#
#   - content pattern matching (regex, ast-grep, lint, AST scan,
#     line-count) → POTENTIALLY APPLICABLE
#     (patterns can occur in notebook cell source just like .py/.ts files)
#
# Format: hook_name|category|applicability|rationale

declare -a NOTEBOOKEDIT_APPLICABILITY_MATRIX=(
    "pretooluse-file-size-guard.ts|content-pattern|POTENTIALLY-APPLICABLE|per-cell new_source line count could exceed threshold; cell-level enforcement may not match file-level intent"
    "pretooluse-vale-claude-md-guard.ts|file-path-suffix|NOT-APPLICABLE|CLAUDE.md is markdown text; Jupyter notebooks (.ipynb) are JSON-encoded and would never be CLAUDE.md"
    "pretooluse-version-guard.ts|content-pattern|APPLICABLE|hardcoded version regex matches notebook cell source identically to .py/.ts files; high-value coverage gap"
    "pretooluse-hoisted-deps-guard.ts|file-path-suffix|NOT-APPLICABLE|operates on pyproject.toml only; notebooks are not pyproject.toml"
    "pretooluse-mise-hygiene-guard.ts|file-path-suffix|NOT-APPLICABLE|operates on mise.toml/.mise.toml only"
    "pretooluse-pyi-stub-guard.ts|file-path-suffix|NOT-APPLICABLE|operates on __init__.py/__init__.pyi only"
    "pretooluse-native-binary-guard.ts|file-path-suffix|NOT-APPLICABLE|operates on launchd .plist + .sh in automation dirs only"
    "pretooluse-gpu-optimization-guard.ts|content-pattern|APPLICABLE|PyTorch/GPU patterns commonly written in notebook cells; data science is primary notebook use case; high-value coverage gap"
    "pretooluse-inline-ignore-guard.ts|content-pattern|POTENTIALLY-APPLICABLE|inline ignore comments (# noqa, # type: ignore) can appear in notebook cell source"
    "pretooluse-fake-data-guard.mjs|content-pattern|POTENTIALLY-APPLICABLE|fake/placeholder data patterns can appear in notebook cells"
    "pretooluse-iter78-layer3-stripped-path-edit-time-guard.ts|content-pattern|POTENTIALLY-APPLICABLE|CLAUDE_PLUGIN_ROOT path references unlikely in notebooks but possible"
    "posttooluse-ty-type-check.ts|content-pattern|NOT-APPLICABLE-VIA-NOTEBOOKEDIT|ty operates on .py files; notebooks are .ipynb. Notebook code is checkable via nbqa but that is a separate tool integration"
    "posttooluse-tsgo-type-check.ts|content-pattern|NOT-APPLICABLE-VIA-NOTEBOOKEDIT|tsgo operates on .ts/.tsx files; notebooks rarely contain TypeScript"
    "posttooluse-oxlint-check.ts|content-pattern|NOT-APPLICABLE-VIA-NOTEBOOKEDIT|oxlint operates on .js/.ts files only"
    "posttooluse-biome-lint.ts|content-pattern|NOT-APPLICABLE-VIA-NOTEBOOKEDIT|biome operates on .js/.ts files only"
    "posttooluse-vale-claude-md.ts|file-path-suffix|NOT-APPLICABLE|CLAUDE.md only"
    "posttooluse-ssot-principles.ts|content-pattern|APPLICABLE|ast-grep SSoT/DI anti-pattern detection in .py/.ts/.rs cells is high-value for data-science notebook hygiene"
    "posttooluse-memory-efficiency-reminder.ts|content-pattern|APPLICABLE|once-per-session reminder fires on any code file; notebook cells qualify if treated as code edits"
    "posttooluse-glossary-sync.ts|file-path-suffix|NOT-APPLICABLE|GLOSSARY.md only"
    "posttooluse-terminology-sync.ts|file-path-suffix|NOT-APPLICABLE|CLAUDE.md only"
    "posttooluse-readme-pypi-links.ts|file-path-suffix|NOT-APPLICABLE|README.md only"
    "posttooluse-rust-sota-reminder.ts|file-path-suffix|NOT-APPLICABLE|.rs files only"
    "chezmoi-sync-reminder.sh|file-path-suffix|NOT-APPLICABLE|dotfiles in chezmoi-managed paths only"
)

echo "  NotebookEdit Applicability Matrix (per-classifier curated SSoT):"
echo ""
printf "  %-50s %-22s %-32s\n" "Classifier" "Category" "NotebookEdit Applicability"
printf "  %-50s %-22s %-32s\n" "----------" "--------" "-------------------------"

applicable_count=0
potentially_applicable_count=0
not_applicable_count=0

for matrix_entry in "${NOTEBOOKEDIT_APPLICABILITY_MATRIX[@]}"; do
    IFS='|' read -r hook_name category applicability rationale <<< "$matrix_entry"
    printf "  %-50s %-22s %-32s\n" "$hook_name" "$category" "$applicability"

    case "$applicability" in
        APPLICABLE)                         applicable_count=$((applicable_count + 1)) ;;
        POTENTIALLY-APPLICABLE)             potentially_applicable_count=$((potentially_applicable_count + 1)) ;;
        NOT-APPLICABLE|NOT-APPLICABLE-VIA-NOTEBOOKEDIT) not_applicable_count=$((not_applicable_count + 1)) ;;
    esac
done

echo ""
echo "  Summary:"
echo "    APPLICABLE (high-value coverage gap):        $applicable_count classifiers"
echo "    POTENTIALLY-APPLICABLE (conditional value):  $potentially_applicable_count classifiers"
echo "    NOT-APPLICABLE (file-type mismatch):         $not_applicable_count classifiers"
echo "    Total scanned:                                ${#NOTEBOOKEDIT_APPLICABILITY_MATRIX[@]} classifiers"
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  Step 2 — Detailed rationale for APPLICABLE classifiers
# ══════════════════════════════════════════════════════════════════════════

echo "  APPLICABLE classifiers (high-value coverage gaps) — detailed rationale:"
echo ""
for matrix_entry in "${NOTEBOOKEDIT_APPLICABILITY_MATRIX[@]}"; do
    IFS='|' read -r hook_name category applicability rationale <<< "$matrix_entry"
    if [[ "$applicability" == "APPLICABLE" ]]; then
        echo "  ◆ $hook_name"
        echo "    Category:    $category"
        echo "    Rationale:   $rationale"
        echo ""
    fi
done

# ══════════════════════════════════════════════════════════════════════════
#  Step 3 — Audit live marketplace for NotebookEdit presence in matchers
# ══════════════════════════════════════════════════════════════════════════
#
# Count how many marketplace matchers currently honor NotebookEdit (none
# expected as of iter-103 pre-broadening state).

echo "  Live marketplace NotebookEdit-honoring matcher count:"
NOTEBOOKEDIT_HONORING_MATCHER_COUNT=0
for hooks_json_absolute_path in $(find "$REPO_ROOT/plugins" -mindepth 3 -maxdepth 3 -type f -name 'hooks.json' 2>/dev/null | sort -u); do  # iter-125: bounded depth, 65ms -> 7ms
    count=$(jq -r '
        .hooks
        | to_entries[]
        | select(.key == "PreToolUse" or .key == "PostToolUse")
        | .value[]
        | select(.matcher | test("NotebookEdit"))
        | .matcher
    ' "$hooks_json_absolute_path" 2>/dev/null | wc -l | tr -d ' ')
    NOTEBOOKEDIT_HONORING_MATCHER_COUNT=$((NOTEBOOKEDIT_HONORING_MATCHER_COUNT + count))
done
echo "    $NOTEBOOKEDIT_HONORING_MATCHER_COUNT matchers currently include NotebookEdit"
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  Step 4 — Community-validated 2026 NotebookEdit cautions
# ══════════════════════════════════════════════════════════════════════════

echo "  Community-validated 2026 NotebookEdit cautions (informational):"
echo "    1. Insert-positioning bug (cells inserted at position 0 instead of after"
echo "       cell_id) — anthropics/claude-code issue #18538"
echo "    2. NotebookEdit writes cell source as single JSON string causing git diff"
echo "       noise + format-revert war with JupyterLab — ReviewNB blog"
echo "    3. Community recommendation: use Jupyter MCP server (kernel-aware) instead"
echo "       of NotebookEdit for serious notebook workflows"
echo ""
echo "  Iter-103 deliberately defers per-hook NotebookEdit broadening to iter-104+"
echo "  because:"
echo "    - APPLICABLE classifiers need PAYLOAD-SHAPE adaptation (tool_input.notebook_path"
echo "      + new_source + cell_id, NOT tool_input.file_path + content/edits[])"
echo "    - Upstream NotebookEdit bugs may make support premature"
echo "    - Each APPLICABLE classifier needs per-cell vs per-file enforcement decision"
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  Report (informational — always exits 0)
# ══════════════════════════════════════════════════════════════════════════

echo "  ✓ AUDIT INFORMATIONAL — applicability matrix surfaced for $applicable_count APPLICABLE +"
echo "    $potentially_applicable_count POTENTIALLY-APPLICABLE classifiers across the marketplace."
echo ""
echo "  Iter-104+ candidate work (in priority order, per applicability):"
echo "    1. pretooluse-version-guard (APPLICABLE)        — hardcoded versions in cells"
echo "    2. pretooluse-gpu-optimization-guard (APPLICABLE) — PyTorch GPU patterns in cells"
echo "    3. posttooluse-ssot-principles (APPLICABLE)     — ast-grep DI anti-patterns in cells"
echo "    4. posttooluse-memory-efficiency-reminder (APPLICABLE) — reminder fires on notebook code"
echo ""
echo "  Iter-104 scope DECISION pattern: per-classifier evaluation of:"
echo "    (a) is per-cell enforcement semantically meaningful vs per-file? (e.g.,"
echo "        file-size-guard's threshold applies to FILE size, not cell size)"
echo "    (b) is the upstream NotebookEdit stability sufficient? (insert-bug,"
echo "        diff noise still open as of 2026-05)"
echo "    (c) is the canonical Jupyter MCP server path preferable? (kernel-aware,"
echo "        community-recommended workaround for production notebook workflows)"
echo ""

exit 0
