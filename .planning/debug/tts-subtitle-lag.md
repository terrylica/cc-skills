---
status: awaiting_human_verify
trigger: "TTS speech lags behind subtitle gold word highlighting"
created: 2026-03-26T00:00:00Z
updated: 2026-03-26T00:00:00Z
---

## Current Focus

hypothesis: showPages() captures scheduleStart = DispatchTime.now() immediately, but play() dispatches to serial TTS queue -> forks afplay -> fills audio buffer, adding ~200-300ms before sound output. Subtitles run ahead.
test: Add audioLaunchDelay constant to SubtitleStyle, apply as offset to scheduleStart in showPages()
expecting: Last word fire time + delay approximates audioDuration (within 0.5s)
next_action: Add constant to SubtitleStyle, apply offset in showPages scheduling

## Symptoms

expected: Gold word highlighting advances exactly in sync with spoken audio
actual: Subtitles run ahead of audio -- gold words flash before the word is spoken
errors: None -- timing offset, not a crash
reproduction: Any TTS playback. Telemetry shows last subtitle word at +65.0s, audio duration 65.7s
started: Since timing race fix that moved play() after showPages() in same DispatchQueue.main.async block

## Eliminated

## Evidence

- timestamp: 2026-03-26T00:00:00Z
  checked: SubtitlePanel.swift showPages() line 170
  found: scheduleStart = DispatchTime.now() captured immediately, all word timers scheduled relative to this instant
  implication: Any delay between this capture and actual audio output = subtitle-leads-audio desync

- timestamp: 2026-03-26T00:00:00Z
  checked: TTSEngine.swift play() method line 133-158
  found: play() dispatches to serial queue.async, creates Process, runs afplay, calls waitUntilExit. The queue.async + Process fork + afplay buffer fill adds ~200-300ms before sound comes out
  implication: Confirmed root cause -- subtitle schedule anchors at now() but audio starts ~200-300ms later

- timestamp: 2026-03-26T00:00:00Z
  checked: TelegramBot.swift dispatchTTS() lines 228-235
  found: DispatchQueue.main.async calls showPages() then play() sequentially. showPages() captures DispatchTime.now(), play() dispatches to background serial queue. The queue hop + process launch = the lag.
  implication: Fix should offset scheduleStart forward by estimated launch delay

## Resolution

root_cause: showPages() anchors subtitle schedule at DispatchTime.now(), but play() dispatches to a serial background queue and forks afplay subprocess. The ~200-300ms between schedule anchor and actual audio output causes subtitles to run ahead of speech.
fix: Add SubtitleStyle.audioLaunchDelay (0.3s) and apply as offset to scheduleStart in showPages()
verification: Build passes. Service restarted. Awaiting human verify on next TTS playback.
files_changed: [SubtitleStyle.swift, SubtitlePanel.swift]
