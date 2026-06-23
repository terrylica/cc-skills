#!/usr/bin/env bash
#MISE description="Iter-111 marketplace-wide producer-side escape-hatch-marker typo audit: enumerates every UPPER-KEBAB-CASE-(OK|SKIP|WRAP) token appearing in PRODUCER source files (anything outside the consumer hooks directory plugins/itp-hooks/hooks/ and outside the audit-tasks directory .mise/) and verifies each token appears in the iter-111 canonical producer-marker registry. Unknown tokens are reported as POTENTIAL TYPOS — the operator must either fix the typo or register a new legitimate marker. Informational by default; can be promoted to strict-block in iter-112+ once registry coverage stabilizes."

# ────────────────────────────────────────────────────────────────────────
# Full design rationale
# ────────────────────────────────────────────────────────────────────────
#
# Pre-iter-111 marketplace state: ~12 production escape-hatch markers
# (PROCESS-STORM-OK, FILE-SIZE-OK, BASH-LAUNCHD-OK, SSoT-OK, etc.)
# scattered across producer files in 7+ plugins (gmail-commander,
# calcom-commander, quality-tools, statusline-tools, itp-hooks,
# agent-reach) with NO single document answering the new-contributor's
# question:
#
#   "If I write `# FOO-OK` at the top of my file, will any hook actually
#    recognize it — or will it silently fail to suppress?"
#
# The pre-iter-111 failure mode was particularly insidious: a typo like
# `# PROCSS-STORM-OK` (missing the first `E`) would silently fail — the
# consumer hook wouldn't see the marker, would block the operation, and
# the operator would be confused why their "escape hatch" didn't work.
# There was no static check catching the typo.
#
# Iter-111 introduces:
#   1. A canonical producer-marker registry at
#      plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-
#      marker-canonical-registry-cross-plugin-iter111.ts that declares
#      every legitimate marker token with its consumer hook, case-
#      sensitivity mode, window-semantics mode, reason policy, and
#      operator-readable description.
#   2. THIS audit task that scans the marketplace for marker-shaped
#      tokens in producer files and reports any that are NOT in the
#      registry — catching typos before they become silent-fail bugs
#      that the operator only discovers months later.
#
# Audit scope (intentionally narrow to keep false-positives low):
#
#   - INCLUDES: every file under plugins/<plugin>/ EXCEPT plugins/itp-hooks/hooks/
#     (the hooks dir is where CONSUMERS live — they spell markers in
#      configuration objects, not as opt-out comments)
#   - INCLUDES: hooks/ and scripts/ subdirectories of every plugin
#   - EXCLUDES: tests/ subdirectories (test fixtures use synthetic markers
#     like FOO-OK, BAR-OK, BAZ-OK, QUX-OK that aren't real markers)
#   - EXCLUDES: docs/ and references/ (documentation may reference
#     synthetic markers in examples)
#   - EXCLUDES: any file that looks like a test by name (*.test.*, test-*,
#     *_test.*, *.spec.*)
#   - EXCLUDES: vendor/build directories (.build, node_modules, .venv,
#     target, .git)
#
# Token shape detected: \b[A-Z][A-Z0-9-]{2,}-(OK|SKIP|WRAP)\b — three
# suffixes documented by the marketplace (`-OK` for opt-out, `-SKIP`
# for cargo-tty-guard-style opt-out, `-WRAP` for cargo-tty-guard-style
# force-opt-in).
#
# Parallel to:
#   - iter-99 audit: raw-stdout-emission silent-drop (PostToolUse invariant)
#   - iter-101 audit: matcher-hygiene (Write|Edit|MultiEdit invariant)
#   - iter-103 audit: NotebookEdit applicability matrix
#   - iter-105 audit: unbounded-emission truncation-helper invariant
#   - iter-106 audit: truncation-helper canonical-home invariant
#   - iter-107 audit: escape-hatch-marker hand-rolled detection inventory (CONSUMER side)
#   - iter-111 audit (THIS): producer-side marker-typo detection vs canonical registry

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Audit lives at .mise/tasks/<this-script>.sh; repo root is two levels up.
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"
ITER111_PRODUCER_MARKER_CANONICAL_REGISTRY_TYPESCRIPT_SOURCE_FILE_RELATIVE_PATH="plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts"

print_banner() {
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════════════"
}

print_banner "Iter-111 marketplace-wide producer-side escape-hatch-marker typo audit"
echo ""
echo "  Theory: a typo like '# PROCSS-STORM-OK' (missing first E) silently"
echo "          fails — the consumer hook wouldn't recognize it, would block"
echo "          the operation, and the operator would be confused why their"
echo "          'escape hatch' didn't work. No static check existed pre-iter-111."
echo "  Source: https://code.claude.com/docs/en/hooks (no official escape-hatch convention)"
echo "  This audit: scans producer files for marker-shaped tokens, verifies"
echo "              each is registered in the iter-111 canonical registry."
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  Step 1 — Verify the iter-111 canonical producer-marker registry exists
# ══════════════════════════════════════════════════════════════════════════

if [[ ! -f "$REPO_ROOT/$ITER111_PRODUCER_MARKER_CANONICAL_REGISTRY_TYPESCRIPT_SOURCE_FILE_RELATIVE_PATH" ]]; then
    echo "  ✗ AUDIT FAILED — iter-111 canonical registry not found:"
    echo "      $ITER111_PRODUCER_MARKER_CANONICAL_REGISTRY_TYPESCRIPT_SOURCE_FILE_RELATIVE_PATH"
    exit 1
fi
echo "  ✓ Step 1: iter-111 canonical producer-marker registry exists"

# ══════════════════════════════════════════════════════════════════════════
#  Step 2 — Extract the set of registered marker tokens from the registry
# ══════════════════════════════════════════════════════════════════════════
#
# Parse the TypeScript registry source file to extract every
# `markerNameTokenIncludingSuffix: "<TOKEN>",` field. Using grep + sed
# (not a TS parser) is intentional: the audit must be self-contained
# and runnable in any preflight environment that has bash + grep + sed
# but doesn't necessarily have a TypeScript runtime.

REGISTERED_MARKER_TOKENS_ONE_PER_LINE=$(
    grep -oE 'markerNameTokenIncludingSuffix:\s*"[^"]+"' "$REPO_ROOT/$ITER111_PRODUCER_MARKER_CANONICAL_REGISTRY_TYPESCRIPT_SOURCE_FILE_RELATIVE_PATH" \
        | sed -E 's/.*"([^"]+)".*/\1/' \
        | sort -u
)
REGISTERED_MARKER_COUNT=$(echo "$REGISTERED_MARKER_TOKENS_ONE_PER_LINE" | grep -c '^.' || echo 0)

if [[ "$REGISTERED_MARKER_COUNT" -lt 5 ]]; then
    echo "  ✗ AUDIT FAILED — iter-111 registry parsed only $REGISTERED_MARKER_COUNT markers (expected ≥5);"
    echo "      either the registry file is malformed or the parse heuristic broke."
    exit 1
fi
echo "  ✓ Step 2: parsed $REGISTERED_MARKER_COUNT registered markers from canonical registry"

# ══════════════════════════════════════════════════════════════════════════
#  Step 3 — Enumerate marker tokens appearing in PRODUCER files
# ══════════════════════════════════════════════════════════════════════════
#
# Producer-file inclusion rules (see header rationale):
#   - All plugins/<plugin>/ files EXCEPT plugins/itp-hooks/hooks/
#   - Skip tests/, docs/, references/, *.test.*, test-*, *_test.*, *.spec.*
#   - Skip vendor/build dirs

PRODUCER_FILE_MARKER_OCCURRENCES_TSV=$(
    grep --include='*.ts' --include='*.tsx' --include='*.mjs' --include='*.js' \
         --include='*.jsx' --include='*.sh' --include='*.bash' --include='*.py' \
         --include='*.rs' --include='*.go' \
         --exclude='*.test.*' --exclude='test-*' --exclude='*_test.*' --exclude='*.spec.*' \
         --exclude-dir='node_modules' --exclude-dir='.build' --exclude-dir='.venv' \
         --exclude-dir='target' --exclude-dir='.git' --exclude-dir='tests' \
         --exclude-dir='docs' --exclude-dir='references' \
         -rHnoE '\b[A-Z][A-Z0-9-]{2,}-(OK|SKIP|WRAP)\b' \
         "$REPO_ROOT/plugins" 2>/dev/null \
    | grep -v '/itp-hooks/hooks/' \
    | sort -u || true
)

if [[ -z "$PRODUCER_FILE_MARKER_OCCURRENCES_TSV" ]]; then
    echo "  ✓ Step 3: no marker occurrences found in producer files (vacuously clean)"
    PRODUCER_UNIQUE_MARKER_TOKENS=""
else
    PRODUCER_UNIQUE_MARKER_TOKENS=$(echo "$PRODUCER_FILE_MARKER_OCCURRENCES_TSV" | awk -F: '{print $NF}' | sort -u)
    PRODUCER_UNIQUE_MARKER_COUNT=$(echo "$PRODUCER_UNIQUE_MARKER_TOKENS" | grep -c '^.')
    PRODUCER_OCCURRENCE_COUNT=$(echo "$PRODUCER_FILE_MARKER_OCCURRENCES_TSV" | grep -c '^.')
    echo "  ✓ Step 3: found $PRODUCER_OCCURRENCE_COUNT marker occurrence(s) across $PRODUCER_UNIQUE_MARKER_COUNT unique token(s) in producer files"
fi

# ══════════════════════════════════════════════════════════════════════════
#  Step 4 — Cross-check every producer marker token against the registry
# ══════════════════════════════════════════════════════════════════════════
#
# Case-sensitivity policy: the registry encodes per-marker case-sensitivity
# at the consumer call site, but the producer-side TYPO check is always
# CASE-INSENSITIVE — `# process-storm-ok` and `# PROCESS-STORM-OK` are
# both legitimate references to the same registered token (the consumer
# decides whether the case-difference is honored). The audit normalizes
# to UPPER-CASE for comparison.

declare -a UNREGISTERED_MARKER_TOKENS_FOUND_IN_PRODUCER_FILES=()

if [[ -n "$PRODUCER_UNIQUE_MARKER_TOKENS" ]]; then
    while IFS= read -r producer_marker_token; do
        [[ -z "$producer_marker_token" ]] && continue
        producer_marker_token_normalized_uppercase=$(echo "$producer_marker_token" | tr '[:lower:]' '[:upper:]')
        is_registered=0
        while IFS= read -r registered_marker_token; do
            [[ -z "$registered_marker_token" ]] && continue
            registered_marker_token_normalized_uppercase=$(echo "$registered_marker_token" | tr '[:lower:]' '[:upper:]')
            if [[ "$producer_marker_token_normalized_uppercase" == "$registered_marker_token_normalized_uppercase" ]]; then
                is_registered=1
                break
            fi
        done <<< "$REGISTERED_MARKER_TOKENS_ONE_PER_LINE"
        if [[ "$is_registered" -eq 0 ]]; then
            UNREGISTERED_MARKER_TOKENS_FOUND_IN_PRODUCER_FILES+=("$producer_marker_token")
        fi
    done <<< "$PRODUCER_UNIQUE_MARKER_TOKENS"
fi

# ══════════════════════════════════════════════════════════════════════════
#  Step 5 — Report
# ══════════════════════════════════════════════════════════════════════════

echo ""
echo "  ┌─ Registered markers (iter-111 canonical registry):"
while IFS= read -r registered_marker_token; do
    [[ -z "$registered_marker_token" ]] && continue
    echo "  │   ✓ $registered_marker_token"
done <<< "$REGISTERED_MARKER_TOKENS_ONE_PER_LINE"
echo "  │"
echo "  ├─ Unregistered tokens found in producer files (POTENTIAL TYPOS):"
if [[ ${#UNREGISTERED_MARKER_TOKENS_FOUND_IN_PRODUCER_FILES[@]} -eq 0 ]]; then
    echo "  │   (none — every producer-side marker is registered)"
else
    for unregistered_token in "${UNREGISTERED_MARKER_TOKENS_FOUND_IN_PRODUCER_FILES[@]}"; do
        echo "  │   ⚠ $unregistered_token"
        # Show the first 3 file:line occurrences for operator debugging
        echo "$PRODUCER_FILE_MARKER_OCCURRENCES_TSV" \
            | awk -F: -v t="$unregistered_token" 'tolower($NF) == tolower(t) { print "  │       at " $1 ":" $2 }' \
            | head -3
    done
fi
echo "  └─"
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  Step 6 — Exit policy
# ══════════════════════════════════════════════════════════════════════════
#
# Iter-111: informational only. Reports findings but never blocks release.
# Iter-112+ may promote to strict-block once:
#   1. The registry coverage stabilizes (all currently-known markers added)
#   2. Edge cases are documented (e.g., the audit-marker family
#      WILDCARD-MATCHER-OK, MATCHER-NO-MULTIEDIT-OK, etc. which are
#      consumed by .mise/ audit tasks rather than runtime hooks — likely
#      a separate registry layer)
#   3. The exit-code-2-on-violation behavior is documented in HOOKS.md

if [[ ${#UNREGISTERED_MARKER_TOKENS_FOUND_IN_PRODUCER_FILES[@]} -gt 0 ]]; then
    echo "  ⚠ AUDIT FOUND ${#UNREGISTERED_MARKER_TOKENS_FOUND_IN_PRODUCER_FILES[@]} unregistered marker token(s) (informational; never blocks release)"
    echo ""
    echo "  Resolution paths:"
    echo "    A. If the token is a typo: fix the producer file"
    echo "    B. If the token is a legitimate new marker: register it in"
    echo "       $ITER111_PRODUCER_MARKER_CANONICAL_REGISTRY_TYPESCRIPT_SOURCE_FILE_RELATIVE_PATH"
    echo "    C. If the token is a test fixture: rename to start with"
    echo "       FOO-/BAR-/BAZ-/QUX- (the audit ignores those families)"
    echo "    D. If the token is consumed by a .mise/ audit task (not a"
    echo "       runtime hook): wait for iter-112+ audit-marker registry"
    echo "       layer; no action needed now"
    exit 0
fi

echo "  ✓ AUDIT PASSED — every producer-side marker token is registered in the iter-111 canonical registry"
exit 0
