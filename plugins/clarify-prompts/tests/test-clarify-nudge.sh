#!/usr/bin/env bash
# Test harness for clarify-nudge.sh — verifies all five guards behave correctly.
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

# Each test case: name, stdin payload, expected outcome (allow|block).
# "allow" = empty stdout, exit 0
# "block" = JSON with {"decision":"block",...} on stdout, exit 0
run_case() {
    local name="$1" payload="$2" expected="$3"
    local out rc
    out=$("$HOOK" <<<"$payload" 2>/dev/null) || rc=$?
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

# Build a transcript JSONL with one or more assistant entries.
# Args: <path>, <variant: empty|with-aq|without-aq>
build_transcript() {
    local path="$1" variant="$2"
    : >"$path"
    case "$variant" in
        empty) ;;  # leave file empty
        without-aq)
            jq -nc '{type:"user", message:{role:"user", content:"hello"}}' >>"$path"
            jq -nc '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:"hi"}]}}' >>"$path"
            ;;
        with-aq)
            jq -nc '{type:"user", message:{role:"user", content:"do something"}}' >>"$path"
            jq -nc '{
                type:"assistant",
                message:{
                    role:"assistant",
                    content:[
                        {type:"text", text:"Let me clarify."},
                        {type:"tool_use", id:"tu_1", name:"AskUserQuestion", input:{questions:[]}}
                    ]
                }
            }' >>"$path"
            ;;
        with-aq-then-text)
            # AQ used earlier, but later assistant turn has no AQ → should nudge.
            jq -nc '{type:"user", message:{role:"user", content:"first"}}' >>"$path"
            jq -nc '{
                type:"assistant",
                message:{role:"assistant", content:[{type:"tool_use", id:"tu_1", name:"AskUserQuestion", input:{}}]}
            }' >>"$path"
            jq -nc '{type:"user", message:{role:"user", content:"answer"}}' >>"$path"
            jq -nc '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:"thanks"}]}}' >>"$path"
            ;;
    esac
}

echo "=== clarify-nudge.sh test harness ==="

# --- Guard 1: stop_hook_active loop guard ---
T1="$TMP/t1.jsonl"; build_transcript "$T1" without-aq
run_case "loop guard (stop_hook_active=true)" \
    "$(jq -nc --arg t "$T1" '{stop_hook_active:true, transcript_path:$t, session_id:"abc", cwd:"/tmp"}')" \
    allow

# --- Guard 2: subagent transcript path ---
T2="$TMP/agents/x.jsonl"; mkdir -p "$(dirname "$T2")"; build_transcript "$T2" without-aq
run_case "subagent guard (/agents/ in path)" \
    "$(jq -nc --arg t "$T2" '{transcript_path:$t, session_id:"abc", cwd:"/tmp"}')" \
    allow

# --- Guard 3: autonomous-loop session_id match ---
REG="$TMP/registry.json"
cat >"$REG" <<JSON
{
  "loops": [
    {
      "loop_id": "test1",
      "contract_path": "/tmp/some-loop/LOOP_CONTRACT.md",
      "owner_session_id": "loop-session-uuid-AAA"
    }
  ]
}
JSON
T3="$TMP/t3.jsonl"; build_transcript "$T3" without-aq
LOOP_REGISTRY_PATH="$REG" run_case "autonomous-loop guard (session_id match)" \
    "$(jq -nc --arg t "$T3" '{transcript_path:$t, session_id:"loop-session-uuid-AAA", cwd:"/elsewhere"}')" \
    allow

# --- Guard 3b: autonomous-loop cwd match (session_id mismatch) ---
T3B="$TMP/t3b.jsonl"; build_transcript "$T3B" without-aq
LOOP_REGISTRY_PATH="$REG" run_case "autonomous-loop guard (cwd matches contract dir)" \
    "$(jq -nc --arg t "$T3B" '{transcript_path:$t, session_id:"different", cwd:"/tmp/some-loop"}')" \
    allow

# --- Guard 3c: autonomous-loop with NO match → fall through ---
T3C="$TMP/t3c.jsonl"; build_transcript "$T3C" without-aq
LOOP_REGISTRY_PATH="$REG" run_case "autonomous-loop registry exists but no match (should nudge)" \
    "$(jq -nc --arg t "$T3C" '{transcript_path:$t, session_id:"unrelated", cwd:"/somewhere/else"}')" \
    block

# --- Guard 4: already-asked (last assistant has AskUserQuestion) ---
T4="$TMP/t4.jsonl"; build_transcript "$T4" with-aq
run_case "already-asked guard (AskUserQuestion in last assistant turn)" \
    "$(jq -nc --arg t "$T4" '{transcript_path:$t, session_id:"abc", cwd:"/tmp"}')" \
    allow

# --- Guard 4b: AQ in earlier turn, but later turn has none → nudge ---
T4B="$TMP/t4b.jsonl"; build_transcript "$T4B" with-aq-then-text
run_case "already-asked: stale AQ (last turn is plain text → should nudge)" \
    "$(jq -nc --arg t "$T4B" '{transcript_path:$t, session_id:"abc", cwd:"/tmp"}')" \
    block

# --- Happy path: nudge when nothing else suppresses ---
T5="$TMP/t5.jsonl"; build_transcript "$T5" without-aq
run_case "happy path (no AQ + no loop + main agent → nudge)" \
    "$(jq -nc --arg t "$T5" '{transcript_path:$t, session_id:"abc", cwd:"/tmp"}')" \
    block

# --- Robustness: empty stdin ---
run_case "robustness: empty stdin" "" allow

# --- Robustness: missing transcript_path ---
run_case "robustness: missing transcript_path" \
    "$(jq -nc '{session_id:"abc", cwd:"/tmp"}')" \
    allow

# --- Robustness: transcript file does not exist ---
run_case "robustness: transcript file missing on disk" \
    "$(jq -nc '{transcript_path:"/nonexistent/path.jsonl", session_id:"abc", cwd:"/tmp"}')" \
    allow

# --- Robustness: empty transcript file ---
T_EMPTY="$TMP/empty.jsonl"; : >"$T_EMPTY"
run_case "robustness: empty transcript file" \
    "$(jq -nc --arg t "$T_EMPTY" '{transcript_path:$t, session_id:"abc", cwd:"/tmp"}')" \
    block

# --- Verify nudge content ---
echo ""
echo "=== nudge content verification ==="
sample=$("$HOOK" <<<"$(jq -nc --arg t "$T5" '{transcript_path:$t, session_id:"abc", cwd:"/tmp"}')")
if jq -e '.decision == "block" and (.reason | contains("AskUserQuestion") and contains("layman") | not | not)' <<<"$sample" >/dev/null 2>&1; then
    if jq -e '.reason | contains("AskUserQuestion")' <<<"$sample" >/dev/null 2>&1; then
        echo "  PASS: reason mentions AskUserQuestion"
        PASSES=$((PASSES + 1))
    else
        echo "  FAIL: reason missing AskUserQuestion mention"
        FAILS=$((FAILS + 1))
    fi
fi

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
