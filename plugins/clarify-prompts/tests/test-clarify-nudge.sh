#!/usr/bin/env bash
# Test harness for clarify-nudge.sh — verifies all five guards + the
# two-layer ambiguity classifier (qmark + LLM force-override).
#
# Run: bash plugins/clarify-prompts/tests/test-clarify-nudge.sh
# Exits 0 on all-pass, non-zero on any failure (with a summary at the end).
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/clarify-nudge.sh"
[[ -x "$HOOK" ]] || { echo "FAIL: hook not executable at $HOOK" >&2; exit 2; }

PASSES=0
FAILS=0
FAILED_CASES=()
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Each test case: name, env, payload, expected outcome (allow|block).
run_case() {
    local name="$1" env_str="$2" payload="$3" expected="$4"
    local out rc
    # shellcheck disable=SC2086
    out=$(env $env_str "$HOOK" <<<"$payload" 2>/dev/null) || rc=$?
    rc=${rc:-0}

    local actual="allow"
    if [[ -n "$out" ]] && jq -e '.decision == "block"' <<<"$out" >/dev/null 2>&1; then
        actual="block"
    fi

    if [[ "$rc" -eq 0 && "$actual" == "$expected" ]]; then
        echo "  PASS: $name"
        PASSES=$((PASSES + 1))
    else
        echo "  FAIL: $name (expected=$expected actual=$actual rc=$rc)"
        echo "        stdout: $out"
        FAILS=$((FAILS + 1))
        FAILED_CASES+=("$name")
    fi
}

# Build a transcript with the named variant. text param controls the last
# assistant message text content.
build_transcript() {
    local path="$1" variant="$2" text="${3:-}"
    : >"$path"
    case "$variant" in
        empty) ;;  # leave empty
        plain-text)
            # Last assistant turn is plain text; content from $text.
            jq -nc '{type:"user", message:{role:"user", content:"hello"}}' >>"$path"
            jq -nc --arg t "$text" '{
                type:"assistant",
                message:{role:"assistant", content:[{type:"text", text:$t}]}
            }' >>"$path"
            ;;
        with-aq)
            jq -nc '{type:"user", message:{role:"user", content:"do something"}}' >>"$path"
            jq -nc '{
                type:"assistant",
                message:{role:"assistant", content:[
                    {type:"text", text:"Let me clarify."},
                    {type:"tool_use", id:"tu_1", name:"AskUserQuestion", input:{questions:[]}}
                ]}
            }' >>"$path"
            ;;
        tool-only)
            # Assistant turn with NO text content (only a non-AQ tool_use).
            jq -nc '{type:"user", message:{role:"user", content:"x"}}' >>"$path"
            jq -nc '{
                type:"assistant",
                message:{role:"assistant", content:[
                    {type:"tool_use", id:"tu_1", name:"Bash", input:{command:"ls"}}
                ]}
            }' >>"$path"
            ;;
    esac
}

mk_payload() {
    local transcript="$1" session="${2:-abc}" cwd="${3:-/tmp}"
    jq -nc --arg t "$transcript" --arg s "$session" --arg c "$cwd" \
        '{transcript_path:$t, session_id:$s, cwd:$c}'
}

echo "=== clarify-nudge.sh test harness ==="
echo "(LLM disabled in tests via CLARIFY_NUDGE_LLM_FORCE — real MiniMax not called)"
echo ""
echo "--- Guard layer ---"

# Guard 1: stop_hook_active loop guard
T1="$TMP/t1.jsonl"; build_transcript "$T1" plain-text "Done. Nothing left."
run_case "loop guard (stop_hook_active=true)" \
    "CLARIFY_NUDGE_LLM_FORCE=GO" \
    "$(jq -nc --arg t "$T1" '{stop_hook_active:true, transcript_path:$t, session_id:"abc", cwd:"/tmp"}')" \
    allow

# Guard 2: subagent path
T2="$TMP/agents/x.jsonl"; mkdir -p "$(dirname "$T2")"
build_transcript "$T2" plain-text "Could you clarify?"
run_case "subagent guard (/agents/ in path)" \
    "CLARIFY_NUDGE_LLM_FORCE=GO" \
    "$(mk_payload "$T2")" \
    allow

# Guard 3: autonomous-loop session_id match
REG="$TMP/registry.json"
cat >"$REG" <<JSON
{
  "loops": [
    {
      "loop_id": "test1",
      "contract_path": "/tmp/some-loop/LOOP_CONTRACT.md",
      "owner_session_id": "loop-uuid-AAA"
    }
  ]
}
JSON
T3="$TMP/t3.jsonl"; build_transcript "$T3" plain-text "Need a decision?"
run_case "autonomous-loop guard (session_id match)" \
    "LOOP_REGISTRY_PATH=$REG CLARIFY_NUDGE_LLM_FORCE=GO" \
    "$(mk_payload "$T3" loop-uuid-AAA /elsewhere)" \
    allow

# Guard 3b: autonomous-loop cwd match
T3B="$TMP/t3b.jsonl"; build_transcript "$T3B" plain-text "Need a decision?"
run_case "autonomous-loop guard (cwd matches contract dir)" \
    "LOOP_REGISTRY_PATH=$REG CLARIFY_NUDGE_LLM_FORCE=GO" \
    "$(mk_payload "$T3B" different /tmp/some-loop)" \
    allow

# Guard 4: already-asked
T4="$TMP/t4.jsonl"; build_transcript "$T4" with-aq
run_case "already-asked guard (AQ in last turn)" \
    "CLARIFY_NUDGE_LLM_FORCE=GO" \
    "$(mk_payload "$T4")" \
    allow

# Guard 5: empty-text turn (tool_use only) → silent stop
T5="$TMP/t5.jsonl"; build_transcript "$T5" tool-only
run_case "empty-text guard (tool-only assistant turn)" \
    "CLARIFY_NUDGE_LLM_FORCE=GO" \
    "$(mk_payload "$T5")" \
    allow

echo ""
echo "--- Layer 1: question-mark detection ---"

# Latin question mark
T_Q="$TMP/q.jsonl"; build_transcript "$T_Q" plain-text "Should we use option A or B?"
run_case "qmark Latin '?' → nudge (no LLM call)" \
    "CLARIFY_NUDGE_LLM_FORCE=NOGO" \
    "$(mk_payload "$T_Q")" \
    block
# Note: even with LLM_FORCE=NOGO, qmark wins (Layer 1 short-circuits).

# CJK question mark
T_CJK="$TMP/cjk.jsonl"; build_transcript "$T_CJK" plain-text "需要選擇哪一個方案？"
run_case "qmark CJK '？' → nudge (no LLM call)" \
    "CLARIFY_NUDGE_LLM_FORCE=NOGO" \
    "$(mk_payload "$T_CJK")" \
    block

# No question mark in last 1500 chars
T_NQ="$TMP/nq.jsonl"; build_transcript "$T_NQ" plain-text "Released v16.12.1. After your next session restart it should look much cleaner."
# This will fall through to Layer 2 — force NOGO to test that path.

echo ""
echo "--- Layer 1: structural strip (quotes / code / tables) ---"

# `?` inside double-quoted string → strip → no qmark → fall to Layer 2
T_QUOTE="$TMP/quote.jsonl"; build_transcript "$T_QUOTE" plain-text 'A SQL query walks into a bar and asks: "Mind if I join you?"'
run_case "qmark inside double quotes → stripped (Layer 2 NOGO → silent)" \
    "CLARIFY_NUDGE_LLM_FORCE=NOGO" \
    "$(mk_payload "$T_QUOTE")" \
    allow

# `?` inside fenced code → stripped
T_FENCE="$TMP/fence.jsonl"
build_transcript "$T_FENCE" plain-text $'Here is the example:\n```\nshould we use ?\n```\nDone.'
run_case "qmark inside fenced code → stripped" \
    "CLARIFY_NUDGE_LLM_FORCE=NOGO" \
    "$(mk_payload "$T_FENCE")" \
    allow

# `?` inside inline code → stripped
T_INLINE="$TMP/inline.jsonl"
# shellcheck disable=SC2016  # backticks here are literal markdown, not command sub
build_transcript "$T_INLINE" plain-text 'The `regex/?/` pattern is fine. Done.'
run_case "qmark inside inline code → stripped" \
    "CLARIFY_NUDGE_LLM_FORCE=NOGO" \
    "$(mk_payload "$T_INLINE")" \
    allow

# `?` inside markdown table row → stripped
T_TABLE="$TMP/table.jsonl"
build_transcript "$T_TABLE" plain-text $'| Q | A |\n| - | - |\n| Should we use A? | maybe |\n\nReleased it.'
run_case "qmark inside markdown table → stripped" \
    "CLARIFY_NUDGE_LLM_FORCE=NOGO" \
    "$(mk_payload "$T_TABLE")" \
    allow

# Real question OUTSIDE any quotes/code/tables → still nudges
T_REAL="$TMP/real.jsonl"
build_transcript "$T_REAL" plain-text 'I see two paths. Should we go with option A or option B?'
run_case "real qmark (not in quote/code) → nudge" \
    "CLARIFY_NUDGE_LLM_FORCE=NOGO" \
    "$(mk_payload "$T_REAL")" \
    block

# Mixed: fake `?` inside quote AND real `?` outside → nudge wins
T_MIX="$TMP/mix.jsonl"
build_transcript "$T_MIX" plain-text 'He asked "What now?" and walked away. Should we follow him?'
run_case "mixed (quoted ? + real ?) → real one still triggers nudge" \
    "CLARIFY_NUDGE_LLM_FORCE=NOGO" \
    "$(mk_payload "$T_MIX")" \
    block

echo ""
echo "--- Layer 2: LLM classifier (forced) ---"

run_case "Layer 2 forced GO → nudge" \
    "CLARIFY_NUDGE_LLM_FORCE=GO" \
    "$(mk_payload "$T_NQ")" \
    block

run_case "Layer 2 forced NOGO → silent stop" \
    "CLARIFY_NUDGE_LLM_FORCE=NOGO" \
    "$(mk_payload "$T_NQ")" \
    allow

run_case "Layer 2 forced FAIL (degraded) → silent stop" \
    "CLARIFY_NUDGE_LLM_FORCE=FAIL" \
    "$(mk_payload "$T_NQ")" \
    allow

run_case "Layer 2 forced EMPTY → silent stop" \
    "CLARIFY_NUDGE_LLM_FORCE=EMPTY" \
    "$(mk_payload "$T_NQ")" \
    allow

run_case "Layer 2 disabled (CLARIFY_NUDGE_NO_LLM=1) → silent stop on no-qmark" \
    "CLARIFY_NUDGE_NO_LLM=1" \
    "$(mk_payload "$T_NQ")" \
    allow

# Confirm the disable still nudges on qmark-present.
run_case "Layer 2 disabled but qmark present → nudge" \
    "CLARIFY_NUDGE_NO_LLM=1" \
    "$(mk_payload "$T_Q")" \
    block

echo ""
echo "--- Robustness ---"

run_case "robustness: empty stdin" \
    "CLARIFY_NUDGE_LLM_FORCE=GO" \
    "" \
    allow

run_case "robustness: missing transcript_path" \
    "CLARIFY_NUDGE_LLM_FORCE=GO" \
    "$(jq -nc '{session_id:"abc", cwd:"/tmp"}')" \
    allow

run_case "robustness: transcript file missing on disk" \
    "CLARIFY_NUDGE_LLM_FORCE=GO" \
    "$(jq -nc '{transcript_path:"/nonexistent/path.jsonl", session_id:"abc", cwd:"/tmp"}')" \
    allow

T_EMPTY="$TMP/empty.jsonl"; : >"$T_EMPTY"
run_case "robustness: empty transcript file" \
    "CLARIFY_NUDGE_LLM_FORCE=GO" \
    "$(mk_payload "$T_EMPTY")" \
    allow

run_case "robustness: recursion guard (CLARIFY_NUDGE_LLM_CALL=1)" \
    "CLARIFY_NUDGE_LLM_CALL=1 CLARIFY_NUDGE_LLM_FORCE=GO" \
    "$(mk_payload "$T_NQ")" \
    allow

echo ""
echo "=== summary ==="
echo "  Passes: $PASSES"
echo "  Fails:  $FAILS"
if [[ "$FAILS" -gt 0 ]]; then
    echo "  Failed cases:"
    for c in "${FAILED_CASES[@]}"; do
        echo "    - $c"
    done
    exit 1
fi
echo "  ✓ All tests passed"
