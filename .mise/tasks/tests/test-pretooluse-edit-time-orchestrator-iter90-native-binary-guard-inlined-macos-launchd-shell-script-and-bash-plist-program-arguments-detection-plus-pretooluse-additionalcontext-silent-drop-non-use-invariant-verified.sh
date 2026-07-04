#!/usr/bin/env bash
#MISE description="Iter-90 regression test extending iter-89 orchestrator coverage. Verifies (1) native-binary-guard inlined as 7th registry entry — classifyMacosLaunchdNativeBinaryRequiredGuardForOrchestrator + classifyNativeBinaryGuardForOrchestrator alias both denyable, (2) launchd .sh write → DENY (extension fastpath), (3) launchd .plist with /bin/bash ProgramArguments → DENY (plist regex), (4) launchd .plist with .sh ProgramArguments path → DENY, (5) non-launchd .sh outside LAUNCHD_DIRS → ALLOW (directory substring fastpath), (6) # BASH-LAUNCHD-OK escape-hatch in proposed content → ALLOW, (7) BASH-LAUNCHD-OK in existing on-disk file (iter-15 fix) → ALLOW even when Edit new_string omits it, (8) standalone backward-compat with raw-stdin keyword prefilter preserved, (9) subhook-contract audit task discovers ≥7 conforming subhooks, (10) PreToolUse additionalContext silent-drop NON-USE invariant verified across ALL 7 classifiers (iter-90 GitHub #15664 adversarial-audit deliverable; parallel to iter-66's Stop-hook additionalContext-drop discovery)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ORCHESTRATOR_HOOK_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts"
STANDALONE_HOOK_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-native-binary-guard.ts"
SUBHOOK_CONTRACT_AUDIT_TASK_PATH="$REPO_ROOT/.mise/tasks/audit-pretooluse-orchestrator-subhook-contract-violations-static-check-no-stdin-stdout-exit-in-classifier-functions-and-import-meta-main-guard-on-standalone-main.sh"
HOOKS_DIR="$REPO_ROOT/plugins/itp-hooks/hooks"

for required_file in "$ORCHESTRATOR_HOOK_PATH" "$STANDALONE_HOOK_PATH" "$SUBHOOK_CONTRACT_AUDIT_TASK_PATH"; do
    if [[ ! -f "$required_file" ]]; then
        echo "FAIL: required file not found: $required_file"
        exit 1
    fi
done

ASSERTION_COUNT_PASSED=0
ASSERTION_COUNT_FAILED=0
assert_passes() { ASSERTION_COUNT_PASSED=$((ASSERTION_COUNT_PASSED + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_COUNT_FAILED=$((ASSERTION_COUNT_FAILED + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-90 orchestrator: native-binary-guard inlined + additionalContext-NON-USE audit"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

PAYLOAD_TEMP_DIR=$(mktemp -d -t iter90-payloads.XXXXXX)
SCRATCH_LAUNCHD_DIR=$(mktemp -d -t iter90-launchd.XXXXXX)
trap 'rm -rf "$PAYLOAD_TEMP_DIR" "$SCRATCH_LAUNCHD_DIR"' EXIT

# Build a fake LaunchAgents directory under the scratch root for iter-15-fix coverage
# (Case 7 needs a real on-disk file containing BASH-LAUNCHD-OK to test the
# orchestrator's Bun.file().text() fallback).
FAKE_LAUNCHAGENTS_DIR="$SCRATCH_LAUNCHD_DIR/Library/LaunchAgents"
mkdir -p "$FAKE_LAUNCHAGENTS_DIR"
FAKE_EXISTING_OPTIN_SCRIPT="$FAKE_LAUNCHAGENTS_DIR/com.iter15-fix-existing-marker.sh"
cat > "$FAKE_EXISTING_OPTIN_SCRIPT" <<'EXISTING'
#!/bin/bash
# BASH-LAUNCHD-OK: legacy daemon shim — Swift port planned 2026-Q4
echo "legacy content"
sleep 1
EXISTING

# ─── Case 1: launchd .sh file → DENY (shell-script-in-launchd-dir detection) ──
case1_payload="$PAYLOAD_TEMP_DIR/case1.json"
cat > "$case1_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/Users/foo/Library/LaunchAgents/com.example.run.sh","content":"#!/bin/bash\necho hi\n"}}
PAYLOAD

set +e
case1_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case1_payload" 2>/dev/null)
case1_exit=$?
set -e

if [[ "$case1_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case1_stdout" == *'NATIVE-BINARY-GUARD'* ]]; then
    assert_passes "Case 1a: orchestrator denies .sh under LaunchAgents/"
else
    assert_fails "Case 1a: stdout missing deny; got=${case1_stdout:0:200}"
fi
if [[ "$case1_stdout" == *'native-binary-guard → DENY'* ]]; then
    assert_passes "Case 1b: deny attributed to native-binary-guard subhook"
else
    assert_fails "Case 1b: subhook attribution missing"
fi
if [[ "$case1_exit" == "2" ]]; then
    assert_passes "Case 1c: orchestrator exits 2 on shell-script-in-launchd-dir deny"
else
    assert_fails "Case 1c: exit=$case1_exit, expected 2"
fi

# ─── Case 2: launchd .plist with /bin/bash as arg0 → DENY ─────────────────────
# Now denied by the named-arg0 rule (it runs BEFORE the legacy bash-reference
# detection), so the authoritative message is the "must be a NAMED script" one.
# The legacy `plist must not reference /bin/bash` message still fires when
# /bin/bash appears as a NON-arg0 string (and the .sh-path branch is covered by Case 3).
case2_payload="$PAYLOAD_TEMP_DIR/case2.json"
cat > "$case2_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/Users/foo/Library/LaunchAgents/com.example.plist","content":"<plist><dict><key>ProgramArguments</key><array><string>/bin/bash</string><string>-c</string><string>echo hi</string></array></dict></plist>"}}
PAYLOAD

set +e
case2_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case2_payload" 2>/dev/null)
case2_exit=$?
set -e

if [[ "$case2_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case2_stdout" == *'must be a NAMED script'* ]]; then
    assert_passes "Case 2a: orchestrator denies plist with /bin/bash as arg0 (named-arg0 rule)"
else
    assert_fails "Case 2a: plist /bin/bash deny missing; got=${case2_stdout:0:200}"
fi
if [[ "$case2_exit" == "2" ]]; then
    assert_passes "Case 2b: exit 2 on plist /bin/bash deny"
else
    assert_fails "Case 2b: exit=$case2_exit, expected 2"
fi

# ─── Case 3: launchd .plist with .sh ProgramArguments path → DENY ─────────────
case3_payload="$PAYLOAD_TEMP_DIR/case3.json"
cat > "$case3_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/Users/foo/Library/LaunchAgents/com.example.plist","content":"<plist><dict><key>ProgramArguments</key><array><string>/Users/foo/scripts/runme.sh</string></array></dict></plist>"}}
PAYLOAD

set +e
case3_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case3_payload" 2>/dev/null)
case3_exit=$?
set -e

if [[ "$case3_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case3_exit" == "2" ]]; then
    assert_passes "Case 3: plist with .sh ProgramArguments path → deny + exit 2"
else
    assert_fails "Case 3: .sh ProgramArguments deny missing; exit=$case3_exit"
fi

# ─── Case 4: non-launchd .sh outside LAUNCHD_DIRS → ALLOW (substring fastpath) ─
case4_payload="$PAYLOAD_TEMP_DIR/case4.json"
cat > "$case4_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo/run.sh","content":"#!/bin/bash\necho hi\n"}}
PAYLOAD

set +e
case4_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case4_payload" 2>/dev/null)
case4_exit=$?
set -e

if [[ "$case4_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case4_exit" == "0" ]]; then
    assert_passes "Case 4: non-launchd .sh allowed (launchd-directory-substring fastpath skip)"
else
    assert_fails "Case 4: substring fastpath broken; exit=$case4_exit"
fi

# ─── Case 5: # BASH-LAUNCHD-OK escape-hatch in proposed content → ALLOW ───────
case5_payload="$PAYLOAD_TEMP_DIR/case5.json"
cat > "$case5_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/Users/foo/Library/LaunchAgents/com.example.run.sh","content":"#!/bin/bash\n# BASH-LAUNCHD-OK: Swift migration tracked in issue #42\necho hi\n"}}
PAYLOAD

set +e
case5_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case5_payload" 2>/dev/null)
case5_exit=$?
set -e

if [[ "$case5_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case5_exit" == "0" ]]; then
    assert_passes "Case 5: # BASH-LAUNCHD-OK escape-hatch in content → allow"
else
    assert_fails "Case 5: escape-hatch in content broken; exit=$case5_exit"
fi

# ─── Case 6 (iter-15-fix): BASH-LAUNCHD-OK in existing file, Edit new_string omits it → ALLOW ──
case6_payload="$PAYLOAD_TEMP_DIR/case6.json"
case6_existing_path_escaped=$(printf '%s' "$FAKE_EXISTING_OPTIN_SCRIPT" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')
printf '{"tool_name":"Edit","tool_input":{"file_path":%s,"old_string":"sleep 1","new_string":"sleep 2"}}' "$case6_existing_path_escaped" > "$case6_payload"

set +e
case6_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case6_payload" 2>/dev/null)
case6_exit=$?
set -e

if [[ "$case6_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case6_exit" == "0" ]]; then
    assert_passes "Case 6 (iter-15 fix): existing-file BASH-LAUNCHD-OK honored even when Edit new_string omits it"
else
    assert_fails "Case 6: iter-15 existing-file escape-hatch broken; exit=$case6_exit; stdout=${case6_stdout:0:200}"
fi

# ─── Case 7: standalone backward-compat (raw-stdin keyword prefilter + classifier) ────
set +e
case7_stdout=$(bun "$STANDALONE_HOOK_PATH" < "$case1_payload" 2>/dev/null)
set -e

if [[ "$case7_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case7_stdout" == *'NATIVE-BINARY-GUARD'* ]]; then
    assert_passes "Case 7a: standalone native-binary-guard.ts denies (backward-compat)"
else
    assert_fails "Case 7a: standalone broken; got=${case7_stdout:0:200}"
fi
if [[ "$case7_stdout" != *'[pretooluse-edit-time-orchestrator]'* ]]; then
    assert_passes "Case 7b: standalone reason has NO orchestrator prefix"
else
    assert_fails "Case 7b: standalone leaked orchestrator prefix"
fi

# ─── Case 8: standalone raw-stdin keyword prefilter still works (no-launchd-keyword → ALLOW) ───
case8_payload="$PAYLOAD_TEMP_DIR/case8.json"
cat > "$case8_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo/models.py","content":"class Foo:\n    pass\n"}}
PAYLOAD

set +e
case8_stdout=$(bun "$STANDALONE_HOOK_PATH" < "$case8_payload" 2>/dev/null)
set -e

if [[ "$case8_stdout" == *'"permissionDecision":"allow"'* ]]; then
    assert_passes "Case 8: standalone raw-stdin keyword prefilter still bypasses JSON.parse on non-launchd payloads"
else
    assert_fails "Case 8: keyword prefilter broken"
fi

# ─── Case 9: subhook-contract audit task discovers 7 subhooks, all clean ──────
set +e
case9_stdout=$(bash "$SUBHOOK_CONTRACT_AUDIT_TASK_PATH" 2>&1)
set -e

case9_subhook_count=$(echo "$case9_stdout" | grep -oE 'Total subhook files scanned:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1 || echo 0)
if [[ "${case9_subhook_count:-0}" -ge 7 ]]; then
    assert_passes "Case 9a: audit task discovers ≥7 inlined subhooks (found ${case9_subhook_count})"
else
    assert_fails "Case 9a: subhook count ${case9_subhook_count} < 7"
fi
if [[ "$case9_stdout" == *'subhook files conform to the PreToolUseSubhookContract'* ]]; then
    assert_passes "Case 9b: audit task reports clean state (native-binary-guard.ts conforms)"
else
    assert_fails "Case 9b: clean-contract state not reported"
fi

# ─── Case 10: PreToolUse additionalContext silent-drop NON-USE invariant ──────
# Per GitHub #15664 (Dec 2025) + iter-66 schema findings: PreToolUse hook
# stdout that includes `additionalContext` is silently dropped by Claude Code.
# This case ASSERTS that NO classifier in the orchestrator registry emits
# `additionalContext` in its decision-payload construction. We must distinguish
# code-emission (the actual hazard: `additionalContext:` as an object-literal
# key, or `"additionalContext":` in a JSON string) from prose-comments
# (acceptable: defense-in-depth documentation referencing the field name).
# Grep pattern catches object-key emission OR JSON-string emission, but NOT
# prose mentions of the word "additionalContext" in JSDoc/comments.
additional_context_emission_violations_count=0
for subhook_file in \
  "$HOOKS_DIR/pretooluse-version-guard.ts" \
  "$HOOKS_DIR/pretooluse-hoisted-deps-guard.ts" \
  "$HOOKS_DIR/pretooluse-mise-hygiene-guard.ts" \
  "$HOOKS_DIR/pretooluse-pyi-stub-guard.ts" \
  "$HOOKS_DIR/pretooluse-native-binary-guard.ts" \
  "$HOOKS_DIR/pretooluse-gpu-optimization-guard.ts" \
  "$HOOKS_DIR/pretooluse-file-size-guard.ts"; do
    # Match object-literal key form: `additionalContext:` at start of trimmed line
    # OR JSON-string form: `"additionalContext":`. Both indicate runtime emission.
    if grep -qE '(^[[:space:]]*additionalContext[[:space:]]*:|"additionalContext"[[:space:]]*:)' "$subhook_file" 2>/dev/null; then
        additional_context_emission_violations_count=$((additional_context_emission_violations_count + 1))
        echo "    ↳ violation detected: $(basename "$subhook_file")"
    fi
done

if [[ "$additional_context_emission_violations_count" == "0" ]]; then
    assert_passes "Case 10: PreToolUse additionalContext silent-drop NON-USE invariant holds across all 7 inlined subhooks (GitHub #15664 defense-in-depth — emission-pattern audit ignores prose-comment mentions)"
else
    assert_fails "Case 10: ${additional_context_emission_violations_count} PreToolUse subhook(s) emit additionalContext — silent-drop hazard!"
fi

# ─── Case 11: plist arg0=/bin/bash WITH BASH-LAUNCHD-OK marker → DENY ─────────
# Hardening: the marker waives "must be a native binary" but NOT "arg0 must be a
# NAMED script", so a bare /bin/bash as arg0 is denied even with the marker.
case11_payload="$PAYLOAD_TEMP_DIR/case11.json"
cat > "$case11_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/Users/foo/Library/LaunchAgents/com.example.plist","content":"<!-- BASH-LAUNCHD-OK --><plist><dict><key>ProgramArguments</key><array><string>/bin/bash</string><string>/Users/foo/scripts/named-tool</string></array></dict></plist>"}}
PAYLOAD

set +e
case11_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case11_payload" 2>/dev/null)
case11_exit=$?
set -e

if [[ "$case11_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case11_stdout" == *'must be a NAMED script'* ]] && [[ "$case11_exit" == "2" ]]; then
    assert_passes "Case 11: plist arg0=/bin/bash WITH BASH-LAUNCHD-OK marker → DENY (marker does not waive named-arg0 rule)"
else
    assert_fails "Case 11: bare-interpreter-arg0 not denied under marker; exit=$case11_exit; got=${case11_stdout:0:200}"
fi

# ─── Case 12: plist arg0=/opt/homebrew/bin/bun (no marker) → DENY ─────────────
# Non-bash interpreters (bun/node/python/env) were previously invisible to the
# bash/sh-only regexes; the named-arg0 rule now catches them.
case12_payload="$PAYLOAD_TEMP_DIR/case12.json"
cat > "$case12_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/Users/foo/Library/LaunchAgents/com.example.plist","content":"<plist><dict><key>ProgramArguments</key><array><string>/opt/homebrew/bin/bun</string><string>/Users/foo/daemon.ts</string></array></dict></plist>"}}
PAYLOAD

set +e
case12_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case12_payload" 2>/dev/null)
case12_exit=$?
set -e

if [[ "$case12_stdout" == *'"permissionDecision":"deny"'* ]] && [[ "$case12_stdout" == *'must be a NAMED script'* ]] && [[ "$case12_exit" == "2" ]]; then
    assert_passes "Case 12: plist arg0=bun → DENY (non-bash interpreters now caught)"
else
    assert_fails "Case 12: bun arg0 not denied; exit=$case12_exit; got=${case12_stdout:0:200}"
fi

# ─── Case 13: plist arg0=named extensionless script (+ marker) → ALLOW ────────
# The blessed fix pattern: bash kept INSIDE a named script so the Login Items
# panel shows the script's name, not "bash".
case13_payload="$PAYLOAD_TEMP_DIR/case13.json"
cat > "$case13_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/Users/foo/Library/LaunchAgents/com.example.plist","content":"<!-- BASH-LAUNCHD-OK --><plist><dict><key>ProgramArguments</key><array><string>/Users/foo/.local/bin/my-named-tool</string></array></dict></plist>"}}
PAYLOAD

set +e
case13_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case13_payload" 2>/dev/null)
case13_exit=$?
set -e

if [[ "$case13_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case13_exit" == "0" ]]; then
    assert_passes "Case 13: plist arg0=named extensionless script (+ marker) → ALLOW"
else
    assert_fails "Case 13: named-arg0 wrongly blocked; exit=$case13_exit; got=${case13_stdout:0:200}"
fi

# ─── Case 14: plist Program=named binary → ALLOW ─────────────────────────────
case14_payload="$PAYLOAD_TEMP_DIR/case14.json"
cat > "$case14_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/Users/foo/Library/LaunchAgents/com.example.plist","content":"<plist><dict><key>Program</key><string>/Users/foo/libexec/my-runner</string></dict></plist>"}}
PAYLOAD

set +e
case14_stdout=$(bun "$ORCHESTRATOR_HOOK_PATH" < "$case14_payload" 2>/dev/null)
case14_exit=$?
set -e

if [[ "$case14_stdout" == *'"permissionDecision":"allow"'* ]] && [[ "$case14_exit" == "0" ]]; then
    assert_passes "Case 14: plist Program=named binary → ALLOW"
else
    assert_fails "Case 14: named Program wrongly blocked; exit=$case14_exit; got=${case14_stdout:0:200}"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-90 native-binary inline + additionalContext-NON-USE regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED"
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_COUNT_FAILED" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED assertions passed"
