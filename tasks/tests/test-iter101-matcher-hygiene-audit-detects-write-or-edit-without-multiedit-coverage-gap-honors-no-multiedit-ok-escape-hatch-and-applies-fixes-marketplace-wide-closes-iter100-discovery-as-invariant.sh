#!/usr/bin/env bash
#MISE description="Iter-101 regression test for the marketplace-wide matcher-hygiene audit + applied fixes. Verifies audit-task existence, live marketplace passes clean post-fixes, fixture-based detection of Write|Edit without MultiEdit catches the 3 surfaced shapes (Write|Edit, Bash|Write|Edit, Edit|Write reversed), MATCHER-NO-MULTIEDIT-OK escape hatch honored, all 6 iter-101 marketplace fixes present in actual hooks.json files (covers all 8 audit-detected violations across 3 plugins), MultiEdit-already-present fixtures correctly pass."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-pretooluse-and-posttooluse-hook-matchers-for-write-or-edit-without-multiedit-coverage-gap-surfaced-by-iter100-postooluse-orchestrator-matcher-broadening-scaled-to-marketplace-invariant.sh"

if [[ ! -f "$AUDIT_TASK_ABSOLUTE_PATH" ]]; then
    echo "FAIL: audit task not found at $AUDIT_TASK_ABSOLUTE_PATH"
    exit 1
fi

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-101 matcher-hygiene audit regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: audit task exists + is executable ───────────────────────────────
if [[ -x "$AUDIT_TASK_ABSOLUTE_PATH" ]]; then
    assert_passes "Case 1: audit task exists + is executable"
else
    assert_fails "Case 1: audit task not executable"
fi

# ─── Case 2: live marketplace passes clean post-iter-101 fixes ───────────────
set +e
live_audit_output=$(bash "$AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
live_audit_exit_code=$?
set -e
if [[ "$live_audit_exit_code" == "0" ]] && [[ "$live_audit_output" == *'AUDIT PASSED'* ]]; then
    assert_passes "Case 2: live marketplace passes clean — 0 matcher coverage gaps after iter-101 fixes"
else
    assert_fails "Case 2: live marketplace audit FAILED post-fixes (exit=$live_audit_exit_code)"
fi

# ─── Synthesize fixture hooks.json files for pattern-detection tests ─────────
FIXTURE_DIR=$(mktemp -d -t iter101-fixtures.XXXXXX)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# Helper: synthesize a fixture marketplace tree (plugins/<name>/hooks/hooks.json)
# and run the audit against it. Returns "PASS" if exit 0, "FAIL:<count>" otherwise.
run_audit_against_fixture_marketplace_tree() {
    local fixture_root="$1"
    local fixture_audit_task="$fixture_root/audit-task.sh"

    # Copy the audit task into the fixture tree and rewrite REPO_ROOT to point
    # to the fixture. This isolates the test from the live marketplace.
    sed -e "s|REPO_ROOT=\"\$(cd \"\$SCRIPT_DIR_ABSOLUTE/../..\" && pwd)\"|REPO_ROOT=\"$fixture_root\"|" \
        "$AUDIT_TASK_ABSOLUTE_PATH" > "$fixture_audit_task"
    chmod +x "$fixture_audit_task"

    set +e
    local fixture_output
    fixture_output=$(bash "$fixture_audit_task" 2>&1)
    local fixture_exit=$?
    set -e

    if [[ "$fixture_exit" == "0" ]]; then
        echo "PASS"
    else
        local count
        count=$(echo "$fixture_output" | grep -oE 'AUDIT FAILED — [0-9]+ matcher coverage gap' | grep -oE '[0-9]+' | head -1 || echo 0)
        echo "FAIL:${count:-0}"
    fi
}

# ─── Case 3: fixture with Write|Edit (no MultiEdit) → 1 violation ────────────
FIXTURE_C3_ROOT="$FIXTURE_DIR/case3"
mkdir -p "$FIXTURE_C3_ROOT/plugins/fix-c3/hooks"
cat > "$FIXTURE_C3_ROOT/plugins/fix-c3/hooks/hooks.json" <<'JSON'
{
  "description": "fixture c3",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{"type": "command", "command": "bun foo.ts"}]
      }
    ]
  }
}
JSON
case3_result=$(run_audit_against_fixture_marketplace_tree "$FIXTURE_C3_ROOT")
if [[ "$case3_result" == "FAIL:1" ]]; then
    assert_passes "Case 3: fixture with matcher='Write|Edit' detected (1 violation as expected)"
else
    assert_fails "Case 3: fixture detection wrong — expected FAIL:1, got '$case3_result'"
fi

# ─── Case 4: fixture with Bash|Write|Edit (no MultiEdit) → 1 violation ───────
FIXTURE_C4_ROOT="$FIXTURE_DIR/case4"
mkdir -p "$FIXTURE_C4_ROOT/plugins/fix-c4/hooks"
cat > "$FIXTURE_C4_ROOT/plugins/fix-c4/hooks/hooks.json" <<'JSON'
{
  "description": "fixture c4",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [{"type": "command", "command": "bun bar.ts"}]
      }
    ]
  }
}
JSON
case4_result=$(run_audit_against_fixture_marketplace_tree "$FIXTURE_C4_ROOT")
if [[ "$case4_result" == "FAIL:1" ]]; then
    assert_passes "Case 4: fixture with matcher='Bash|Write|Edit' detected (1 violation as expected)"
else
    assert_fails "Case 4: fixture detection wrong — expected FAIL:1, got '$case4_result'"
fi

# ─── Case 5: fixture with Edit|Write reversed-order (no MultiEdit) → 1 ───────
FIXTURE_C5_ROOT="$FIXTURE_DIR/case5"
mkdir -p "$FIXTURE_C5_ROOT/plugins/fix-c5/hooks"
cat > "$FIXTURE_C5_ROOT/plugins/fix-c5/hooks/hooks.json" <<'JSON'
{
  "description": "fixture c5 with reversed order",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{"type": "command", "command": "./baz.sh"}]
      }
    ]
  }
}
JSON
case5_result=$(run_audit_against_fixture_marketplace_tree "$FIXTURE_C5_ROOT")
if [[ "$case5_result" == "FAIL:1" ]]; then
    assert_passes "Case 5: token-membership detection is order-independent (Edit|Write reversed → 1 violation)"
else
    assert_fails "Case 5: fixture detection wrong — expected FAIL:1, got '$case5_result' (token-order dependence regression?)"
fi

# ─── Case 6: MATCHER-NO-MULTIEDIT-OK escape hatch honored ────────────────────
FIXTURE_C6_ROOT="$FIXTURE_DIR/case6"
mkdir -p "$FIXTURE_C6_ROOT/plugins/fix-c6/hooks"
cat > "$FIXTURE_C6_ROOT/plugins/fix-c6/hooks/hooks.json" <<'JSON'
{
  "description": "fixture c6 with escape hatch",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{
          "type": "command",
          "command": "bun explicitly-no-multiedit.ts",
          "description": "Legitimately only handles single-edit shapes; MATCHER-NO-MULTIEDIT-OK: explicit owner-attested justification for MultiEdit exclusion in this fixture"
        }]
      }
    ]
  }
}
JSON
case6_result=$(run_audit_against_fixture_marketplace_tree "$FIXTURE_C6_ROOT")
if [[ "$case6_result" == "PASS" ]]; then
    assert_passes "Case 6: MATCHER-NO-MULTIEDIT-OK escape hatch in description field honored — 0 violations"
else
    assert_fails "Case 6: escape hatch NOT honored — expected PASS, got '$case6_result'"
fi

# ─── Case 7: matcher already includes MultiEdit → 0 violations ───────────────
FIXTURE_C7_ROOT="$FIXTURE_DIR/case7"
mkdir -p "$FIXTURE_C7_ROOT/plugins/fix-c7/hooks"
cat > "$FIXTURE_C7_ROOT/plugins/fix-c7/hooks/hooks.json" <<'JSON'
{
  "description": "fixture c7 — already complete",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [{"type": "command", "command": "bun complete.ts"}]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|Write|Edit|MultiEdit",
        "hooks": [{"type": "command", "command": "bun complete-post.ts"}]
      }
    ]
  }
}
JSON
case7_result=$(run_audit_against_fixture_marketplace_tree "$FIXTURE_C7_ROOT")
if [[ "$case7_result" == "PASS" ]]; then
    assert_passes "Case 7: complete matchers (Write|Edit|MultiEdit + Bash|Write|Edit|MultiEdit) → 0 violations"
else
    assert_fails "Case 7: complete matchers wrongly flagged — expected PASS, got '$case7_result'"
fi

# ─── Case 8: hooks with NO file-edit-token (Bash-only, Read-only, etc) ───────
# Should never trigger because they have no Write/Edit to begin with.
FIXTURE_C8_ROOT="$FIXTURE_DIR/case8"
mkdir -p "$FIXTURE_C8_ROOT/plugins/fix-c8/hooks"
cat > "$FIXTURE_C8_ROOT/plugins/fix-c8/hooks/hooks.json" <<'JSON'
{
  "description": "fixture c8 — Bash-only, Read-only, no file-edit",
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "bun a.ts"}]},
      {"matcher": "Read", "hooks": [{"type": "command", "command": "bun b.ts"}]},
      {"matcher": "WebFetch|WebSearch", "hooks": [{"type": "command", "command": "bun c.ts"}]}
    ]
  }
}
JSON
case8_result=$(run_audit_against_fixture_marketplace_tree "$FIXTURE_C8_ROOT")
if [[ "$case8_result" == "PASS" ]]; then
    assert_passes "Case 8: hooks without Write/Edit tokens (Bash, Read, WebFetch|WebSearch) → 0 violations"
else
    assert_fails "Case 8: non-edit matchers wrongly flagged — expected PASS, got '$case8_result'"
fi

# ─── Case 9: multi-hook entry with mix → escape hatch per-hook resolution ────
# Single matcher with TWO inner hooks: one has escape hatch, the other doesn't.
# Audit must report 1 violation (the one WITHOUT escape hatch), not 0 or 2.
FIXTURE_C9_ROOT="$FIXTURE_DIR/case9"
mkdir -p "$FIXTURE_C9_ROOT/plugins/fix-c9/hooks"
cat > "$FIXTURE_C9_ROOT/plugins/fix-c9/hooks/hooks.json" <<'JSON'
{
  "description": "fixture c9 — mixed inner hooks",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bun has-no-escape-hatch.ts"
          },
          {
            "type": "command",
            "command": "bun has-escape-hatch.ts",
            "description": "MATCHER-NO-MULTIEDIT-OK: documented exception for this specific inner hook only"
          }
        ]
      }
    ]
  }
}
JSON
case9_result=$(run_audit_against_fixture_marketplace_tree "$FIXTURE_C9_ROOT")
if [[ "$case9_result" == "FAIL:1" ]]; then
    assert_passes "Case 9: per-inner-hook escape-hatch resolution — 1 violation (only the inner hook without escape hatch)"
else
    assert_fails "Case 9: per-inner-hook resolution wrong — expected FAIL:1, got '$case9_result'"
fi

# ─── Case 10: verify all 6 iter-101 marketplace fixes are present ────────────
# Iter-101 broadened 6 matcher strings across 3 hooks.json files.
ITP_HOOKS_JSON="$REPO_ROOT/plugins/itp-hooks/hooks/hooks.json"
DOTFILES_HOOKS_JSON="$REPO_ROOT/plugins/dotfiles-tools/hooks/hooks.json"
RUST_TOOLS_HOOKS_JSON="$REPO_ROOT/plugins/rust-tools/hooks/hooks.json"

# Expected post-iter-101 state: 6 matcher strings broadened to include MultiEdit.
# Direct jq-existence queries against each target file verify the broadenings
# (no intermediate array needed — keeps the check loose-coupled and idempotent).
case10_broadenings_present=0
if jq -e '.hooks.PostToolUse[] | select(.matcher == "Edit|Write|MultiEdit")' "$DOTFILES_HOOKS_JSON" >/dev/null 2>&1; then
    case10_broadenings_present=$((case10_broadenings_present + 1))
fi
if jq -e '.hooks.PostToolUse[] | select(.matcher == "Read|Glob|Grep|Bash|Edit|Write|MultiEdit")' "$RUST_TOOLS_HOOKS_JSON" >/dev/null 2>&1; then
    case10_broadenings_present=$((case10_broadenings_present + 1))
fi
# itp-hooks has 4 broadenings: PreToolUse `Write|Edit` (orchestrator), PreToolUse `Bash|Write|Edit` (process-storm), PostToolUse `Bash|Write|Edit` (reminder+code-correctness shared matcher), PostToolUse `Write|Edit` (glossary-sync+terminology-sync shared matcher). After iter-101 they all have MultiEdit appended. Verify by counting that no remaining Write|Edit-without-MultiEdit matchers exist in itp-hooks.
itp_hooks_remaining_gaps=$(jq -r '
    .hooks
    | to_entries[]
    | select(.key == "PreToolUse" or .key == "PostToolUse")
    | .value[]
    | .matcher
    | select(. != null)
    | (split("|")) as $tokens
    | select(($tokens | index("Write")) or ($tokens | index("Edit")))
    | select(($tokens | index("MultiEdit")) | not)
    | .
' "$ITP_HOOKS_JSON" | wc -l | tr -d ' ')
if [[ "$case10_broadenings_present" == "2" ]] && [[ "$itp_hooks_remaining_gaps" == "0" ]]; then
    assert_passes "Case 10: all 6 iter-101 marketplace broadenings present (2 standalone + 4 itp-hooks; 0 residual itp-hooks gaps)"
else
    assert_fails "Case 10: marketplace broadenings incomplete (standalone-present=$case10_broadenings_present/2, itp-hooks-remaining-gaps=$itp_hooks_remaining_gaps; expected 2 + 0)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-101 regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_PASSED_COUNT"
echo "  Assertions failed: $ASSERTION_FAILED_COUNT"
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_FAILED_COUNT" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_FAILED_COUNT assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_PASSED_COUNT assertions passed"
echo ""
echo "  🚀 Iter-101 marketplace-wide preventive audit for matcher-hygiene"
echo "     (Write|Edit without MultiEdit) — preventive gate parallel to iter-94"
echo "     spawnSync audit + iter-99 silent-context-drop audit + iter-65"
echo "     wildcard-matcher audit. Scales iter-100 single-orchestrator fix to a"
echo "     marketplace invariant; would have caught the iter-100 discovery"
echo "     preventively had it existed pre-iter-100."
