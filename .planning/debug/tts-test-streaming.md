---
status: fixing
trigger: "Fix /tts/test to use streaming synthesis + AVAudioEngine instead of single-shot AVAudioPlayer"
created: 2026-03-27T00:00:00Z
updated: 2026-03-27T00:00:00Z
---

## Current Focus

hypothesis: /tts/test uses synthesizeWithTimestamps (single-shot) which hits tooManyTokens for >400 chars
test: Replace with synthesizeStreaming path mirroring TelegramBot.dispatchStreamingTTS
expecting: Long texts synthesize without token limit errors
next_action: Implement the streaming path in HTTPControlServer /tts/test handler

## Symptoms

expected: POST /tts/test with long text should synthesize and play with karaoke subtitles
actual: Hits tooManyTokens error for texts >~400 chars because kokoro-ios has per-call token limit
errors: tooManyTokens from kokoro-ios generateAudio
reproduction: POST /tts/test with >400 char text
started: Always (endpoint was built with single-shot path)

## Eliminated

(none)

## Evidence

- timestamp: 2026-03-27
  checked: HTTPControlServer.swift lines 176-217
  found: /tts/test uses synthesizeWithTimestamps -> single generateAudio call -> token limit
  implication: Must switch to synthesizeStreaming which splits into sentences

- timestamp: 2026-03-27
  checked: TelegramBot.dispatchStreamingTTS (lines 264-355)
  found: Production path uses synthesizeStreaming with SubtitleSyncDriver streaming mode + AudioStreamPlayer
  implication: Exact pattern to replicate for /tts/test

## Resolution

root_cause: /tts/test endpoint calls synthesizeWithTimestamps() which makes a single generateAudio() call with the full text, exceeding kokoro-ios per-call token limit for long texts
fix: Replace with synthesizeStreaming() + SubtitleSyncDriver streaming mode + AudioStreamPlayer (same path as TelegramBot)
verification: (pending)
files_changed:

- plugins/claude-tts-companion/Sources/claude-tts-companion/HTTPControlServer.swift
