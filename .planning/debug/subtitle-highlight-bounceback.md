---
status: awaiting_human_verify
trigger: "subtitle-highlight-bounceback: After TTS finishes speaking the last word, the gold karaoke highlight bounces back to highlight the first word of the page/chunk before the subtitle hides"
created: 2026-03-26T00:00:00Z
updated: 2026-03-26T00:00:00Z
---

## Current Focus

hypothesis: When AVAudioPlayer finishes, currentTime resets to 0. tick() reads 0, maps to globalIdx=0 (first word), highlights it. Next tick detects !isPlaying and calls finishPlayback().
test: Code review of tickSingleShot() and tickStreaming() confirms the check order
expecting: Moving !isPlaying check BEFORE highlight computation fixes the bounceback
next_action: Apply fix to both tickSingleShot() and tickStreaming()

## Symptoms

expected: After last word is spoken, subtitle lingers showing last word highlighted in gold for 2s, then hides
actual: After last word, highlight bounces back to first word (gold flashes on word 0) before subtitle hides
errors: No errors -- visual glitch in the highlight
reproduction: Any TTS playback, observe final moments before subtitle hides
started: After AVAudioPlayer + CADisplayLink refactor (SubtitleSyncDriver)

## Eliminated

## Evidence

- timestamp: 2026-03-26T00:00:00Z
  checked: tickSingleShot() lines 285-325
  found: Lines 288-320 compute globalIdx from player.currentTime and update highlight BEFORE lines 322-324 check !player.isPlaying. When player finishes, currentTime=0 causes globalIdx=0 highlight before finishPlayback() fires.
  implication: Confirms hypothesis -- check order is the root cause

- timestamp: 2026-03-26T00:00:00Z
  checked: tickStreaming() lines 327-372
  found: Same pattern -- lines 333-365 compute and highlight before line 368 checks !currentPlayer.isPlaying
  implication: Same bug exists in streaming mode

## Resolution

root_cause: In both tickSingleShot() and tickStreaming(), the player.currentTime is read and used to update the highlight BEFORE checking !player.isPlaying. When AVAudioPlayer finishes, currentTime resets to 0, causing one frame of highlight on word 0 before the next tick detects playback ended.
fix: Move the !isPlaying check to the top of both tick methods, before reading currentTime or updating highlights.
verification: []
files_changed:

- plugins/claude-tts-companion/Sources/claude-tts-companion/SubtitleSyncDriver.swift
