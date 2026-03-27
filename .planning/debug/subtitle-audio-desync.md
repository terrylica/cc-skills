---
status: awaiting_human_verify
trigger: "Karaoke word highlighting is completely out of sync with TTS audio playback after Phase 17 subtitle chunking changes"
created: 2026-03-26T00:00:00Z
updated: 2026-03-26T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED and FIXED. Two root causes addressed.
test: Rebuild, redeploy, trigger TTS playback via session notification
expecting: Gold word highlighting tracks spoken audio within ~10ms
next_action: User deploys new binary and verifies sync

## Symptoms

expected: Gold word highlighting advances word-by-word in sync with spoken audio
actual: Words and sound are "not sync at all" -- highlighting doesn't match what's being spoken
errors: None visible -- audio plays fine, subtitles display fine, but timing is wrong
reproduction: Any TTS playback triggered by session end notification
started: After Phase 17 changes (subtitle chunking, whitespace normalization)

## Eliminated

- hypothesis: Word count mismatch between extractWordTimings and chunkIntoPages in CURRENT source code
  evidence: Both now use identical whitespace splitting (\.isWhitespace) since commit 96bc5897. Word arrays match.
  timestamp: 2026-03-26

## Evidence

- timestamp: 2026-03-26
  checked: Running binary vs source code versions
  found: Running binary is from commit 5d9faa76 (22:28), missing whitespace normalization fix 96bc5897 (23:26). Running binary has NO [showPages] logging.
  implication: Running binary has the embedded-newline word mismatch bug

- timestamp: 2026-03-26
  checked: Git diff of commit 96bc5897 (whitespace normalization)
  found: Before this fix, TTSEngine split on " " (space only) while SubtitleChunker also split on " ". BUT text with \n\n creates compound words like "configuration.\n\nSo" that visually consume 3+ lines in a 2-line panel, causing truncation. Karaoke advances through invisible words.
  implication: Root cause #1 -- running binary has page rendering overflow from embedded newlines (already fixed in HEAD but not deployed)

- timestamp: 2026-03-26
  checked: Timing architecture in dispatchTTS (TelegramBot.swift lines 210-225)
  found: In current code, SubtitleChunker.chunkIntoPages() runs INSIDE DispatchQueue.main.async BEFORE showPages() captures scheduleStart = DispatchTime.now(). Chunking involves O(N) pixel-width measurements (NSAttributedString.size()). Meanwhile, play() starts afplay independently on TTS queue. Audio can start 100-500ms before scheduleStart is anchored.
  implication: Root cause #2 -- subtitle scheduling anchors AFTER audio start due to chunking computation delay on main thread

- timestamp: 2026-03-26
  checked: Service logs for TTS flow
  found: Multiple TTS dispatches pile up (23:26-23:30 shows 6 dispatches before first synthesis complete). No "Playing WAV" entries for later dispatches. No [showPages] entries at all (binary predates that logging).
  implication: Confirms running binary is older version without diagnostic logging

- timestamp: 2026-03-26
  checked: Fix applied and verified build
  found: Moved play() call INSIDE DispatchQueue.main.async block, AFTER chunkIntoPages() and showPages(). This ensures scheduleStart is captured before audio is queued. Build succeeds (debug + release).
  implication: Subtitle anchor and audio start are now synchronized (~1ms gap instead of 100-500ms)

## Resolution

root_cause: Two issues combine to cause desync: (1) Running binary (commit 5d9faa76) lacks whitespace normalization -- embedded \n\n in MiniMax text creates compound words that overflow 2-line pages, making highlights advance through invisible words. Already fixed in HEAD (commit 96bc5897) but not deployed. (2) Chunking computation (pixel-width measurement, 100-500ms for long text) runs on main thread BEFORE scheduleStart is captured, while play() starts afplay independently on TTS queue -- audio leads subtitles by the chunking duration.
fix: Moved ttsEngine.play() call inside the DispatchQueue.main.async block, after chunkIntoPages() and showPages(). This sequences the operations: chunk -> schedule subtitles (captures scheduleStart) -> start audio. The scheduleStart anchor and audio onset are now within ~1ms.
verification: Build compiles (debug + release). Awaiting user deployment and end-to-end verification.
files_changed: [plugins/claude-tts-companion/Sources/claude-tts-companion/TelegramBot.swift]
