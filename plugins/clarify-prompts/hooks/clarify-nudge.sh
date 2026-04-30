#!/usr/bin/env bash
# Stop hook: nudge the main agent to invoke AskUserQuestion when the
# just-finished turn left a genuine decision unresolved. Two-layer
# detection so most stops pass through silently.
#
#   Layer 1  Question-mark scan in the last assistant text. ~0ms.
#   Layer 2  MiniMax-M2.7 binary classifier when no `?` was found.
#            ~1.5s end-to-end. Returns GO (nudge) or NOGO (silent stop).
#
# Why MiniMax over `claude --print`:
#   * `claude --print` cold-starts a full Claude Code session — ~10s
#     even for Haiku, and recurses through our own Stop hook.
#   * MiniMax is a single OpenAI-compatible POST to api.minimax.io —
#     ~1.5s round-trip, no startup overhead, no recursion.
#   * Plain MiniMax-M2.7 (not -highspeed) is documented as 2.5× faster
#     than -highspeed for short outputs <150 tokens. A GO/NOGO is ~3.
#
# Five guards run before classification:
#   0. CLARIFY_NUDGE_LLM_CALL recursion guard (defensive — not actually
#      reachable via MiniMax HTTP, kept for safety).
#   1. stop_hook_active loop guard.
#   2. /agents/ subagent guard.
#   3. Autonomous-loop guard (session_id OR cwd match in registry).
#   4. Already-asked guard (last assistant turn used AskUserQuestion).
#
# Failure mode: any error path exits 0 (allow stop). A wedged main agent
# is worse than a missed nudge.
#
# Env knobs:
#   MINIMAX_API_KEY            required for Layer 2 — without it we fall
#                              back to Layer 1 (qmark) + degraded no-nudge.
#   CLARIFY_NUDGE_NO_LLM       set to 1 to skip Layer 2 entirely.
#   CLARIFY_NUDGE_MODEL        model id (default: "MiniMax-M2.7").
#   CLARIFY_NUDGE_TIMEOUT      curl total timeout in seconds (default 10).
#   CLARIFY_NUDGE_API_URL      override endpoint for tests.
#   CLARIFY_NUDGE_LLM_FORCE    test override — set to GO|NOGO|FAIL|EMPTY
#                              to skip the real call and return a fixed
#                              classification (used by the test harness).
#   LOOP_REGISTRY_PATH         override registry path (tests use this).
set -uo pipefail

# 0. Recursion guard.
[[ -n "${CLARIFY_NUDGE_LLM_CALL:-}" ]] && exit 0

input=$(cat 2>/dev/null || true)
[[ -z "$input" ]] && exit 0

# 1. Loop guard.
if jq -e '.stop_hook_active // false' <<<"$input" >/dev/null 2>&1; then
    exit 0
fi

# 2. Subagent guard.
transcript_path=$(jq -r '.transcript_path // ""' <<<"$input" 2>/dev/null || echo "")
if [[ -z "$transcript_path" || ! -f "$transcript_path" ]]; then
    exit 0
fi
case "$transcript_path" in
    */agents/*) exit 0 ;;
esac

# 3. Autonomous-loop guard.
session_id=$(jq -r '.session_id // ""' <<<"$input" 2>/dev/null || echo "")
cwd=$(jq -r '.cwd // ""' <<<"$input" 2>/dev/null || echo "")
registry_path="${LOOP_REGISTRY_PATH:-$HOME/.claude/loops/registry.json}"

if [[ -f "$registry_path" ]]; then
    if [[ -n "$session_id" ]]; then
        if jq -e --arg sid "$session_id" '
            .loops // [] | map(select(.owner_session_id == $sid)) | length > 0
        ' "$registry_path" >/dev/null 2>&1; then
            exit 0
        fi
    fi
    if [[ -n "$cwd" ]]; then
        if jq -e --arg cwd "$cwd" '
            .loops // []
            | map(select((.contract_path | sub("/LOOP_CONTRACT\\.md$"; "")) == $cwd))
            | length > 0
        ' "$registry_path" >/dev/null 2>&1; then
            exit 0
        fi
    fi
fi

# 4. Already-asked guard.
last_assistant=$(jq -sc 'map(select(.type == "assistant")) | last // empty' \
    "$transcript_path" 2>/dev/null || echo "")

if [[ -n "$last_assistant" ]]; then
    if jq -e '
        .message.content // []
        | map(select(.type == "tool_use" and .name == "AskUserQuestion"))
        | length > 0
    ' <<<"$last_assistant" >/dev/null 2>&1; then
        exit 0
    fi
fi

# 5. Two-layer ambiguity detection.

last_text=$(jq -r '
    .message.content // []
    | map(select(.type == "text"))
    | map(.text)
    | join("\n")
' <<<"$last_assistant" 2>/dev/null || echo "")

# Trim to last 1500 chars — closing posture is what matters.
if [[ ${#last_text} -gt 1500 ]]; then
    last_text="${last_text: -1500}"
fi

# Empty text → nothing to classify (likely a tool-only turn) → silent stop.
if [[ -z "$last_text" ]]; then
    exit 0
fi

nudge=false

# Layer 1: question-mark scan with structural strip — `?` inside
# quoted/illustrative content shouldn't fire. We strip these regions
# BEFORE scanning so a punchline like `"Mind if I join you?"` or a
# table row like `| Should we use A? |` doesn't trigger a false-positive
# nudge. What's stripped:
#
#   * Fenced code blocks  (```…```)
#   * Inline code         (`…`)
#   * Double-quoted strs  ("…")
#   * Markdown table rows (lines starting with `|`)
#
# Single-quoted strings are NOT stripped — apostrophes in contractions
# (`I'd`, `don't`) make any `'…'` regex unsafe. Rare false positive.
sanitized=$(printf '%s' "$last_text" | perl -0777 -pe '
    s/```.*?```//gs;
    s/`[^`]*`//g;
    s/"[^"]*"//g;
    s/^\s*\|.*$//mg;
' 2>/dev/null || echo "$last_text")

if [[ "$sanitized" == *"?"* || "$sanitized" == *"？"* ]]; then
    nudge=true
elif [[ "${CLARIFY_NUDGE_NO_LLM:-0}" != "1" ]]; then
    # Layer 2: MiniMax binary classifier.

    # Test-harness short-circuit.
    case "${CLARIFY_NUDGE_LLM_FORCE:-}" in
        GO)    nudge=true;  ;;
        NOGO)  nudge=false; ;;
        FAIL|EMPTY) nudge=false; ;;
        "")    # No override — call MiniMax for real.
            api_key="${MINIMAX_API_KEY:-}"
            api_url="${CLARIFY_NUDGE_API_URL:-https://api.minimax.io/v1/chat/completions}"
            model="${CLARIFY_NUDGE_MODEL:-MiniMax-M2.7}"
            timeout_secs="${CLARIFY_NUDGE_TIMEOUT:-10}"

            if [[ -z "$api_key" ]]; then
                # No auth → degraded mode (no nudge). User can set
                # MINIMAX_API_KEY to enable Layer 2.
                nudge=false
            else
                # Build request via jq to handle escaping safely.
                # Few-shot prompt: bare classifier instructions miss
                # genre context (e.g., a `?` in a joke punchline gets
                # classified GO when it's clearly NOGO). Six examples
                # cover the calibration: jokes/code/quotes/statements
                # → NOGO; direct questions / implicit decisions → GO.
                user_prompt='Classify the assistant message below. Reply with EXACTLY one word: GO or NOGO.

GO  = the message has a real unresolved decision the user could weigh in on (a question to the user, a choice between options, a "need to pick" statement, or "want me to X?").
NOGO = the message is complete (statement, report, joke, code example, narrative). Question marks inside quoted speech, jokes, dialogue, code blocks, or hypothetical examples DO NOT count as real decisions.

EXAMPLES:
MSG: A SQL query walks into a bar and asks: "Mind if I join you?"
ANSWER: NOGO

MSG: Want me to schedule a cleanup PR for next week?
ANSWER: GO

MSG: Released v16.12.1. Restart to pick it up.
ANSWER: NOGO

MSG: I could go with either approach A or B. Both work. Need to pick one to start.
ANSWER: GO

MSG: Should we use option A or option B?
ANSWER: GO

MSG: The pattern /foo?/ matches a literal question mark. Done.
ANSWER: NOGO

MESSAGE TO CLASSIFY:'
                req=$(jq -nc \
                    --arg model "$model" \
                    --arg prompt "$user_prompt" \
                    --arg msg "$last_text" \
                    '{
                        model: $model,
                        max_tokens: 300,
                        messages: [
                            {role: "system", content: "You are a binary classifier. Your output is parsed by a script. Respond with ONLY one word: GO or NOGO."},
                            {role: "user", content: ($prompt + "\n<<<\n" + $msg + "\n>>>\n\nAnswer:")}
                        ]
                    }')

                response=$(curl -sS -X POST "$api_url" \
                    --max-time "$timeout_secs" \
                    -H "Authorization: Bearer $api_key" \
                    -H "Content-Type: application/json" \
                    --data-raw "$req" 2>/dev/null || echo "")

                # Extract assistant content, then strip <think>...</think>
                # block (MiniMax-M2.7 is a reasoning model). The remainder
                # holds the GO/NOGO answer.
                content=$(jq -r '.choices[0].message.content // empty' <<<"$response" 2>/dev/null || echo "")
                # Strip <think>...</think> (multiline; perl handles cleanly).
                stripped=$(printf '%s' "$content" | perl -0777 -pe 's{<think>.*?</think>}{}gs' 2>/dev/null || echo "")
                # First non-empty token, uppercased.
                first_word=$(echo "$stripped" | awk 'NF{print $1; exit}' | tr '[:lower:]' '[:upper:]' | tr -d '[:punct:]')

                case "$first_word" in
                    GO|YES)         nudge=true  ;;
                    NOGO|NO|NOGO.) nudge=false ;;
                    *) nudge=false ;;  # degraded: empty/unparseable
                esac
            fi
            ;;
        *) nudge=false ;;  # unknown force value → safe default
    esac
fi

# 6. Decision.
if [[ "$nudge" == true ]]; then
    jq -nc '{
        decision: "block",
        reason: "If user'"'"'s request had ambiguity, invoke AskUserQuestion (plain language, ≤12-char headers, 2-4 options); else stop next pass."
    }'
fi
