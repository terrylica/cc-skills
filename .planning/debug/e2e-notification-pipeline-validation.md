---
status: awaiting_human_verify
trigger: "e2e-notification-pipeline-validation: TranscriptParser 0 turns, AutoContinue thinking-only parsing, full pipeline validation"
created: 2026-03-26T00:00:00Z
updated: 2026-03-26T19:03:00Z
---

## Current Focus

hypothesis: CONFIRMED — Three root causes identified and fixed, pipeline validated end-to-end
test: Deploy binary, trigger test notification, verify all 9 pipeline steps in logs
expecting: All steps pass with zero errors
next_action: Await human verification that real session-end notifications work

## Symptoms

expected: Full notification pipeline — detect notification, parse JSONL transcript into turns, call MiniMax for summaries, send Telegram, dispatch TTS with karaoke
actual: TranscriptParser returns 0 turns from 7684-line transcript. AutoContinue decision parsing fails on thinking-only responses. Pipeline stalls.
errors: entriesToTurns() produces 0 turns; decision parser can't extract DECISION|reason from thinking blocks; SummaryEngine returns fallback
reproduction: End any Claude Code session, check stderr.log
started: Since deployment of unified binary

## Eliminated

## Evidence

- timestamp: 2026-03-26T18:45:00Z
  checked: Real JSONL format via python3 analysis of 7684-line transcript
  found: Top-level types are "user" (512), "assistant" (763), "progress" (6401), never "human" or top-level "tool_use"/"tool_result". Tool use/result are content blocks WITHIN assistant/user entries.
  implication: Swift parser used type:"human" (wrong) and expected top-level tool_use/tool_result (wrong)

- timestamp: 2026-03-26T18:46:00Z
  checked: Legacy TypeScript transcript-parser.ts comparison
  found: TS parser correctly checks e.type === "user" and e.type === "assistant", scans message.content blocks for tool_use/tool_result within turns
  implication: Confirmed the correct parsing approach

- timestamp: 2026-03-26T18:47:00Z
  checked: MiniMaxClient thinking block handling
  found: MiniMaxClient already falls back to thinking block content (lines 131-138). parseDecision scans for DECISION keywords but only at line starts — misses unstructured thinking content
  implication: Added fallback word-boundary search for decision keywords in full text

- timestamp: 2026-03-26T18:48:00Z
  checked: Config.swift model filename
  found: kokoroModelFile hardcoded to "model.onnx" but launchd plist sets KOKORO_MODEL_PATH to int8 dir which has "model.int8.onnx"
  implication: Added auto-detection: prefers model.onnx, falls back to model.int8.onnx

- timestamp: 2026-03-26T18:52:00Z
  checked: First deployment test with real 7684-line transcript
  found: "turns=38" in auto-continue log (was 0 before fix). TTS failed on model path mismatch.
  implication: TranscriptParser fix confirmed working. Model path fix needed.

- timestamp: 2026-03-26T18:59:00Z
  checked: Second deployment test after all fixes
  found: Complete pipeline success — 38 turns parsed, MiniMax CONTINUE, Tail Brief 1199 chars, Arc Summary 3363 chars, TTS 72.33s audio synthesized and played back. Zero errors.
  implication: All three root causes fixed, pipeline end-to-end validated

## Resolution

root_cause: Three root causes:

1. TranscriptParser.parseEntry() used type:"human" for user messages but Claude Code JSONL uses type:"user". Also expected top-level type:"tool_use" and type:"tool_result" but these are content blocks within user/assistant entries, not separate entries. Result: 0 turns from any transcript.
2. AutoContinue.parseDecision() only matched decision keywords at line starts — when MiniMax thinking-only responses were used as fallback, unstructured reasoning didn't have DECISION at line starts.
3. Config.kokoroModelFile was hardcoded to "model.onnx" but launchd env pointed to int8 model dir with "model.int8.onnx".

fix:

1. Rewrote TranscriptParser.parseEntry() to return [TranscriptEntry] array. Added parseUserEntry() and parseAssistantEntry() that correctly handle type:"user" and type:"assistant", scan content blocks for text/tool_use/tool_result within each entry.
2. Added fallback pass in parseDecision() that scans for decision keywords (CONTINUE, SWEEP, REDIRECT, DONE) at word boundaries anywhere in the text, after the existing line-start matching fails.
3. Changed kokoroModelFile to auto-detect: checks for model.onnx first, falls back to model.int8.onnx.

verification: Deployed binary, triggered test notification with real 7684-line transcript. Full pipeline validated:

- Notification detected (log: "Session notification: test-e2e-validation-74d1ca4a")
- Transcript parsed to 38 turns (log: "turns=38")
- MiniMax auto-continue: CONTINUE decision with reason
- MiniMax Tail Brief: 1199 chars in 11.4s
- MiniMax Arc Summary: 3363 chars in 25s
- TTS dispatched: 1240 chars, en-us
- Model loaded: 2.85s
- Synthesis: 72.33s audio in 153.89s
- Playback: complete
  Zero errors in logs.

files_changed:

- plugins/claude-tts-companion/Sources/claude-tts-companion/TranscriptParser.swift
- plugins/claude-tts-companion/Sources/claude-tts-companion/AutoContinue.swift
- plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift
