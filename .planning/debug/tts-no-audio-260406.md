---
status: diagnosed
trigger: "TTS subtitles render correctly but no audio playback"
created: 2026-04-06
updated: 2026-04-07
---

## Current Focus

hypothesis: CONFIRMED — `~/.local/share/tts-debug-wav/` directory is missing; AfplayPlayer fails to write the WAV before spawning afplay, aborts playback, but subtitles already rendered from in-memory samples.
test: Created the missing directory, retriggered TTS, observed WAV file was successfully written (tts-2026-04-07T19-06-12Z...wav, 1.4MB).
expecting: WAV written → afplay plays → audio heard.
next_action: Return diagnosis. User decides fix.

## Symptoms

expected: tts_kokoro.sh "test" → subtitles + audio
actual: Subtitles visible, no audio
errors: "Failed to write WAV for afplay/pipelined afplay: NSCocoaErrorDomain Code=4 ... NSPOSIXErrorDomain Code=2 No such file or directory"
reproduction: Any TTS path — HTTP /tts/speak, tts_kokoro.sh, session-end notification
started: At least since 11:11 today (oldest log evidence). Likely since the running binary was last started (Fri Apr 3 17:41).

## Eliminated

- hypothesis: Recent refactor af9698be broke JSON decoding
  evidence: Running binary at /Users/terryli/.local/bin/claude-tts-companion has mtime Apr 3 17:41. Process PID 4864 started Fri Apr 3 17:41:55. Commit af9698be is Apr 6 17:12 — three days AFTER the running binary. The refactor is not in running code.
  timestamp: 2026-04-07 12:04

- hypothesis: Python Kokoro server down
  evidence: At initial test time (12:02-12:04), kokoro-tts-server was healthy, returned 36 words + 14.725s audio correctly ("[TELEMETRY] Server returned 36 words ... audioDuration=14.725s"). Synthesis succeeded; the failure was post-synthesis at WAV-write stage. (Note: server later crashed during my 12:06 test — that is a separate intermittent issue, not the reported bug.)
  timestamp: 2026-04-07 12:04

- hypothesis: Circuit breaker blocking user-initiated requests
  evidence: Logs show "TTS speak: user-initiated priority, 24 chars" → "Synthesizing USER TTS" → successful synthesis. User-initiated path is not blocked.
  timestamp: 2026-04-07 12:04

- hypothesis: Audio output device problem
  evidence: Default output = MacBook Pro Speakers, default system output = yes. No AVAudioEngine errors in stderr. Companion never reached the `afplay` subprocess spawn — aborted earlier.
  timestamp: 2026-04-07 12:04

## Evidence

- timestamp: 2026-04-07 12:02
  checked: Running binary vs refactor commit time
  found: Binary Apr 3 17:41, commit Apr 6 17:12
  implication: Refactor cannot be the cause

- timestamp: 2026-04-07 12:04
  checked: stderr log during successful test at 12:02:45
  found: "[TELEMETRY] Server returned 36 words, 36 onsets, audioDuration=14.725s" followed immediately by "error afplay-player: Failed to write WAV for pipelined afplay: ... NSFilePath=/Users/terryli/.local/share/tts-debug-wav/tts-2026-04-07T19-02-45Z_Astro_check_passed_clean_the_build.wav ... No such file or directory"
  implication: Synthesis succeeded (samples in memory), subtitles rendered, but WAV write to debug dir failed → afplay never invoked → no audio

- timestamp: 2026-04-07 12:05
  checked: Existence of /Users/terryli/.local/share/tts-debug-wav/
  found: Missing — "ls: No such file or directory". Parent /Users/terryli/.local/share/ is writable (touch probe succeeded).
  implication: `debugWavDir` init-time `try? FileManager.createDirectory(atPath:withIntermediateDirectories:true)` at AfplayPlayer.swift:46 either (a) never ran, (b) ran before `.local/share` existed, or (c) the directory was deleted after init. The `try?` swallows any error silently.

- timestamp: 2026-04-07 12:06
  checked: Created the dir manually (`mkdir /Users/terryli/.local/share/tts-debug-wav`) and retriggered TTS
  found: WAV file tts-2026-04-07T19-06-12Z_Hi_Terry_you_were_working_in.wav was written successfully (1,384,844 bytes). Confirms the missing-dir was the only blocker for the write path.
  implication: Fix is to ensure the directory exists before every write, not just once at init.

- timestamp: 2026-04-07 12:06
  checked: grep of all "Failed to write WAV" errors in stderr.log
  found: At least 25+ occurrences spanning 11:11:57 through 12:04:44 — every single TTS attempt since the process started has failed the WAV write. 100% failure rate.
  implication: This is not intermittent. The dir has been missing for the entire process lifetime.

## Resolution

root_cause: |
The running `claude-tts-companion` process has been unable to write any TTS WAV file for its entire lifetime because the target directory `/Users/terryli/.local/share/tts-debug-wav/` does not exist.

`AfplayPlayer.swift:44-48` lazy-initializes `debugWavDir` once when the first AfplayPlayer instance is created:

      private let debugWavDir: String = {
          let dir = NSHomeDirectory() + "/.local/share/tts-debug-wav"
          try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
          return dir
      }()

The `try?` silently swallows any creation error. Either the createDirectory call failed at init time, or the directory was deleted after init (e.g., user cleanup, `rm -rf`, or macOS storage optimization). There is no "ensure dir exists" guard inside `playPipelined(samples:)` / `play(samples:)` at lines ~135 and ~364 before the `writeWav(...)` call, so once the dir is gone it stays gone for the process's lifetime.

When `writeWav` fails, the code logs an error and returns early (`return false` / `return`) — it never spawns `afplay`. But synthesis already succeeded and the in-memory `samples` array was already pushed to the subtitle sync driver, so subtitles render and karaoke-highlight against wall-clock time while no audio plays.

fix: |
Diagnose-only mode — no fix applied. Immediate mitigation: `mkdir -p ~/.local/share/tts-debug-wav` (already done during investigation; verified working). Durable fix should do ALL of:

1. In AfplayPlayer.swift `playPipelined(samples:)` (~line 130) and `play(samples:)` (~line 360), call `FileManager.default.createDirectory(atPath: debugWavDir, withIntermediateDirectories: true)` (NOT `try?` — log and handle the error) BEFORE constructing `wavPath`. Idempotent and cheap.
2. Change the init-time `try?` at line 46 to `do { try ... } catch { logger.error(...) }` so silent failures become visible.
3. Consider whether retaining WAVs in `~/.local/share/` is the right design — an ephemeral location (e.g., `NSTemporaryDirectory() + "claude-tts-wav/"`) would be self-healing on reboot and not subject to user cleanup. The "debug/manual inspection" use case (mentioned in the comment at line 513) could be a separate opt-in setting.
4. Bonus: investigate WHY the dir disappeared in the first place. No code in this repo deletes it (grep confirms). Suspects: the user running `/gsd-quick` cleanup, an external sweeper, or the dir was never created because `.local/share` didn't exist at AfplayPlayer init time (on a fresh install — though this binary is from Apr 3, and `.local/share` clearly existed long before that).

verification: Not applied — diagnose-only.
files_changed: []
