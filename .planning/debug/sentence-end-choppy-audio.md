---
status: awaiting_human_verify
trigger: "Audio sounds choppy/cut-off at the END of sentences during streaming TTS playback"
created: 2026-03-27T11:15:00-0700
updated: 2026-03-27T11:15:00-0700
---

## Current Focus

hypothesis: The choppy audio at sentence ends is caused by two compounding issues: (1) each sentence chunk's WAV ends abruptly at the last audio sample with no trailing silence for natural decay, and (2) the tick()-based chunk transition via `!currentPlayer.isPlaying` introduces a detection latency of up to 16ms where the audio hardware has nothing to play, causing a micro-gap/click between chunks
test: Add trailing silence padding (~100ms) to each WAV chunk in writeWav() and measure if choppiness disappears
expecting: If silence padding eliminates choppiness, confirms the waveform truncation is the root cause. If it persists, the issue is in AVAudioPlayer transition timing.
next_action: Implement silence padding fix in writeWav() or synthesizeStreaming()

## Symptoms

expected: Smooth continuous speech across sentence boundaries
actual: Choppy/cut-off sound at the end of some sentences before the next one starts
errors: No errors in logs
reproduction: Intermittent -- some sentence transitions are clean, others have audible chop
started: Since streaming sentence-chunked TTS pipeline

## Eliminated

## Evidence

- timestamp: 2026-03-27T11:15:00
  checked: TTSEngine.synthesizeStreaming() and SubtitleSyncDriver.tickStreaming()
  found: Each sentence is synthesized independently via generateAudio(). The raw audio samples are written directly to WAV with zero trailing silence. The TTS model naturally produces trailing energy at sentence ends (fade-out), but writeWav() writes exactly `audio.count` samples -- no padding.
  implication: When the last phoneme ends, the waveform may be cut mid-decay, producing an abrupt truncation artifact.

- timestamp: 2026-03-27T11:15:00
  checked: SubtitleSyncDriver.tickStreaming() chunk transition logic
  found: Chunk transition happens in tickStreaming() when `!currentPlayer.isPlaying` is detected. This is polled every 16ms. Between the moment the player finishes and the next tick detects it, there is silence. Then advanceToPrebuilt() calls player.play() -- even pre-buffered, there's still the poll latency gap.
  implication: Up to 16ms detection gap + any play() startup latency creates a micro-gap at every chunk boundary. Some transitions sound clean (when the sentence has natural trailing silence that masks the gap), others sound choppy (when the sentence ends abruptly on a stressed word).

- timestamp: 2026-03-27T11:15:00
  checked: Web research on SOTA solutions
  found: (1) 30-50ms crossfade eliminates clicks between chunks. (2) Silence padding of ~100ms at end preserves natural speech decay. (3) AVAudioEngine with scheduled buffers enables sample-accurate gapless playback. (4) Conservative approach: pad each chunk with ~100ms silence to let the waveform naturally decay to zero.
  implication: The simplest effective fix is to pad each synthesized chunk with trailing silence (50-100ms). This is lower-risk than crossfade (which requires overlapping audio from adjacent chunks) or AVAudioEngine migration.

## Resolution

root_cause: Each sentence chunk's audio is written to WAV with exactly the samples returned by generateAudio() -- no trailing silence. TTS models produce natural trailing energy (formant decay, breath noise) that gets truncated at the last sample. Combined with the 16ms poll-based chunk transition in tickStreaming(), this produces audible choppiness at sentence boundaries where the waveform doesn't naturally decay to zero.
fix: Added 100ms trailing silence padding (2400 zero samples at 24kHz) to each streaming chunk WAV in synthesizeStreaming(). The padding is appended after the synthesized audio samples but before writeWav(). The audioDuration reported to the subtitle system remains based on the original (unpadded) sample count, so karaoke sync is unaffected. The silence gives the waveform room for natural decay and absorbs the ~16ms poll-based chunk transition latency.
verification: Binary builds cleanly, installed to ~/.local/bin/, service restarted. Awaiting human verification of audio quality.
files_changed: [plugins/claude-tts-companion/Sources/claude-tts-companion/TTSEngine.swift]
