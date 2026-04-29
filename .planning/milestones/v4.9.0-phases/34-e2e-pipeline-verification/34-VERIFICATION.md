# E2E Pipeline Verification

**Phase:** 34-e2e-pipeline-verification
**Date:** 2026-03-28
**Requirements:** E2E-01, E2E-02, E2E-03

## E2E-01: Full Session-End-to-Telegram Chain

**Status:** PASS

**Evidence:**

The full pipeline is wired end-to-end through these files:

1. **NotificationWatcher detects session-end files:**
   - `NotificationWatcher.swift:50-58` -- `start()` creates a 2-second polling timer via `DispatchSource.makeTimerSource`
   - `NotificationWatcher.swift:73-105` -- `scanForNewFiles()` scans directory for `.json` files, compares modification dates against `knownFiles` map, fires `callback(fullPath)` for new/modified files

2. **CompanionApp wires notification callback to processing pipeline:**
   - `CompanionApp.swift:127-129` -- `NotificationWatcher` created with `handleNotification(filePath:)` callback
   - `CompanionApp.swift:160-288` -- `handleNotification()` reads JSON, extracts `sessionId`, `transcriptPath`, `cwd`, dispatches to auto-continue evaluator and session notification

3. **SummaryEngine generates Arc Summary and Tail Brief via MiniMax:**
   - `SummaryEngine.swift:209-339` -- `arcSummary(turns:cwd:)` builds chronological narrative with transition words via MiniMax API query
   - `SummaryEngine.swift:347-448` -- `tailBrief(turns:cwd:)` generates end-weighted narrative (20% context, 80% final turn) via MiniMax API query

4. **TelegramBotNotifications sends summaries and dispatches TTS:**
   - `TelegramBotNotifications.swift:10-122` -- `sendSessionNotification()` concurrently generates both summaries (`async let arcResult`, `async let tailResult`), renders rich HTML via `TelegramFormatter.renderSessionNotification()`, sends Arc Summary as main Telegram message (line 93), sends Tail Brief as silent message (line 109), then dispatches TTS for Tail Brief text (line 119)
   - `TelegramBotNotifications.swift:142-152` -- `dispatchTTS()` enqueues text on `ttsQueue` with priority `.automated`

5. **TTSPipelineCoordinator orchestrates synthesis -> playback -> subtitles:**
   - `TTSPipelineCoordinator.swift:143-236` -- `startBatchPipeline(chunks:)` cancels any in-progress session, creates a `SubtitleSyncDriver`, adds chunks with word onsets, and calls `driver.startBatchPlayback()` for gapless karaoke playback

6. **TTSEngine delegates to Python server:**
   - `TTSEngine.swift:392-446` -- `callPythonServerWithTimestamps()` sends POST to `Config.pythonTTSServerURL + "/v1/audio/speech-with-timestamps"` with JSON body `{input, voice, language, speed, response_format}`, decodes `PythonTimestampResponse` with `audio_b64`, `words` array (onset/duration per word), `audio_duration`

7. **Chain fully wired:** NotificationWatcher callback (CompanionApp:127) -> handleNotification (CompanionApp:160) -> sendSessionNotification (CompanionApp:269-279 via TelegramBot) -> arcSummary + tailBrief (SummaryEngine) -> Telegram message delivery + dispatchTTS (TelegramBotNotifications:119) -> ttsQueue.enqueue -> TTSEngine.synthesizeStreaming -> Python server -> SubtitleSyncDriver karaoke

## E2E-02: Native Word-Level Karaoke (Python MToken Onsets)

**Status:** PASS

**Evidence:**

1. **TTSEngine calls Python server's timestamp endpoint:**
   - `TTSEngine.swift:393` -- URL constructed as `Config.pythonTTSServerURL + "/v1/audio/speech-with-timestamps"`
   - `TTSEngine.swift:364-368` -- `PythonTimestampWord` struct: `{text: String, onset: Double, duration: Double}` -- per-word onset and duration from Kokoro duration model
   - `TTSEngine.swift:372-376` -- `PythonTimestampResponse` struct: `{audio_b64, words: [PythonTimestampWord], audio_duration, sample_rate}`

2. **Response parsing extracts native word-level onset/duration arrays:**
   - `TTSEngine.swift:435-437` -- `wordOnsets = tsResponse.words.map { TimeInterval($0.onset) }`, `wordDurations = tsResponse.words.map { TimeInterval($0.duration) }`, `wordTexts = tsResponse.words.map { $0.text }`
   - These are NOT character-weighted approximations -- they are native values from the Kokoro duration model via the Python server

3. **SubtitleSyncDriver receives and uses native word onsets:**
   - `SubtitleSyncDriver.swift:120-142` -- `resolveOnsets()` static method: if `nativeOnsets.count == totalWords`, uses native onsets directly (line 129); only falls back to duration-derived onsets if count mismatches (line 135-141)
   - `SubtitleSyncDriver.swift:225` -- `addChunk()` receives `nativeOnsets` parameter, passes to `resolveOnsets()` (line 232)
   - `SubtitleSyncDriver.swift:529-537` -- `updateHighlight(for:)` uses `wordOnsets` array to find active word via linear scan, driving gold karaoke highlighting

4. **Flow: Python response -> TTSEngine -> SubtitleSyncDriver (no character-weighted approximation):**
   - `TTSEngine.swift:281-287` -- `synthesizeStreaming()` passes `allWordOnsets` directly into `ChunkResult.wordOnsets`
   - `TTSPipelineCoordinator.swift:185-186` -- `startBatchPipeline()` passes `chunk.wordOnsets` as `nativeOnsets` parameter to `driver.addChunk()`
   - The `nativeOnsets` parameter bypasses the duration-derived fallback entirely when counts match

## E2E-03: tts_kokoro.sh CLI Regression

**Status:** PASS

**Evidence:**

1. **Script exists:**
   - Path: `~/.local/bin/tts_kokoro.sh` (symlink -> `/Users/terryli/eon/cc-skills/plugins/tts-tg-sync/scripts/tts_kokoro.sh`)

2. **Script calls Swift companion HTTP API:**
   - Line 20: `TTS_SERVICE="http://localhost:8780"` -- targets the Swift companion HTTP control API
   - Line 41: Health check via `curl -s --max-time 2 "${TTS_SERVICE}/health"`
   - Line 49-53: `POST "${TTS_SERVICE}/tts/speak"` with `Content-Type: application/json`, body `{"text": "..."}`, header `X-TTS-Priority: user-initiated`
   - This calls the Swift companion's HTTP endpoint which triggers synthesis + karaoke subtitles + audio playback

3. **Script accepts text as argument and plays audio end-to-end:**
   - Lines 26-32: Three input modes: stdin (`-` flag), CLI arguments (`$*`), or clipboard (`pbpaste`)
   - The `/tts/speak` endpoint handles synthesis and playback server-side; the script blocks until the HTTP response (30s max-time)

4. **Script is executable:**
   - `ls -la` output: `lrwxr-xr-x` -- symlink is readable/executable
   - Symlink target is the repo-tracked script at `plugins/tts-tg-sync/scripts/tts_kokoro.sh`
   - Line 1: `#!/bin/bash` shebang present

## Summary

| Requirement | Status | Key Evidence                                                                                                                                                                                                                                                             |
| ----------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| E2E-01      | PASS   | Full chain traced: NotificationWatcher(polling) -> CompanionApp.handleNotification -> SummaryEngine(arcSummary+tailBrief via MiniMax) -> TelegramBotNotifications(send+dispatchTTS) -> TTSEngine(Python /v1/audio/speech-with-timestamps) -> SubtitleSyncDriver(karaoke) |
| E2E-02      | PASS   | TTSEngine.callPythonServerWithTimestamps() extracts native PythonTimestampWord onset/duration arrays; SubtitleSyncDriver.resolveOnsets() uses native onsets directly when count matches; no character-weighted approximation in the path                                 |
| E2E-03      | PASS   | tts_kokoro.sh exists at ~/.local/bin/ (symlink), calls POST localhost:8780/tts/speak with JSON body, accepts text via args/stdin/clipboard, is executable                                                                                                                |
