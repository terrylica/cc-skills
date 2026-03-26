---
phase: "06"
plan: "01"
subsystem: telegram-bot-commands
tags: [cli-subprocess, jsonl-parser, model-selection, ndjson-streaming]
dependency_graph:
  requires: [01-01, 01-02]
  provides: [transcript-parsing, claude-cli-subprocess, model-selection]
  affects: [telegram-bot, session-notifications]
tech_stack:
  added: []
  patterns: [ndjson-streaming, process-pipe, sendable-concurrency]
key_files:
  created:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/TranscriptParser.swift
    - plugins/claude-tts-companion/Sources/claude-tts-companion/ClaudeProcess.swift
  modified:
    - plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift
decisions:
  - "NSLock + class-level stderrBuffer for Swift 6 Sendable compliance in Process termination handler"
  - "Character-weighted word timing fallback when raw duration tensor unavailable"
metrics:
  duration: 4min
  completed: 2026-03-26
---

# Phase 6 Plan 1: CLI Subprocess + JSONL Parser + Model Selection Summary

JSONL transcript parser, Claude CLI subprocess with NDJSON streaming, and model selection enum -- the data and process layers for Telegram bot commands.

## What Was Built

### Task 1: JSONL Transcript Parser (TranscriptParser.swift)

Parses Claude Code session transcripts (JSONL format) into typed `TranscriptEntry` enum values. Supports four entry types: prompt, response, tool_use, and tool_result. Extracts text from nested `message.content` structures including array-of-blocks format. The `summarize()` function computes prompt/response/tool counts and captures first prompt + last response for notifications. Malformed lines are logged at debug level and skipped.

### Task 2: Claude CLI Subprocess (ClaudeProcess.swift)

Spawns the `claude` CLI as a Foundation Process with Pipe-based I/O. Key features:

- **Model selection (BOT-05):** `ClaudeModel` enum maps haiku/sonnet/opus to `--model` CLI flags
- **Environment isolation (CLI-03):** Unsets `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT` env vars before spawning
- **NDJSON streaming (CLI-02):** Reads stdout via `readabilityHandler`, buffers partial lines, parses each complete line into `ClaudeOutputChunk` (text, toolUse, toolResult, done, error)
- **Swift 6 concurrency safety:** NSLock protects shared state; stderr buffer stored as class property to avoid captured-var Sendable violations

### Task 3: Config Additions

Added `claudeCLIPath` (with `CLAUDE_CLI_PATH` env override, default `/usr/local/bin/claude`) and `defaultModel` to Config.swift.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 Sendable violation in stderr capture**

- **Found during:** Task 2
- **Issue:** Local `var stderrBuffer` captured in `@Sendable` closures (readabilityHandler, terminationHandler) violates Swift 6 strict concurrency
- **Fix:** Moved stderrBuffer to class property, protected reads/writes with NSLock
- **Files modified:** ClaudeProcess.swift
- **Commit:** d7d047dd

## Commits

| Task | Description                             | Hash     |
| ---- | --------------------------------------- | -------- |
| 1    | JSONL transcript parser                 | 492b38bf |
| 2    | Claude CLI subprocess + model selection | d7d047dd |
| 3    | Config additions                        | 1d4cf513 |

## Known Stubs

None. All components are fully implemented with no placeholder data or TODO markers.

## Self-Check: PASSED
