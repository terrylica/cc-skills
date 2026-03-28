# Benchmark: Python MLX Kokoro TTS (Baseline)

## Model

- ID: mlx-community/Kokoro-82M-bf16
- Framework: mlx-audio (Python MLX)
- Server: localhost:8779
- Voice: af_heart, speed: 1.2

## Latency

| Text   | Words | Audio Duration | Synthesis Time | RTF   |
| ------ | ----- | -------------- | -------------- | ----- |
| Short  | 2     | 1.375s         | 0.195s         | 0.142 |
| Medium | 16    | 5.100s         | 0.836s         | 0.164 |
| Long   | 45    | 14.800s        | 1.520s         | 0.103 |

RTF (Real-Time Factor) = synthesis_time / audio_duration. Lower is faster.
All three well under RTF 0.2 — comfortably real-time on Apple Silicon.

## RAM

- Before first synthesis: 552.5 MB physical, 468 IOAccelerator regions
- After 3 syntheses: 562.6 MB physical, 469 IOAccelerator regions
- Delta: +10.1 MB physical, +1 IOAccelerator region
- Peak (historical): 6.6 GB physical (likely model warm-up on first ever load)

Memory is stable across repeated synthesis — no leak detected across 3 calls.

## Word Timing

- Available in HTTP response: **No** (returns raw WAV bytes only, no JSON envelope)
- Available in Python API: Yes (via mlx-audio `generate()` tokens — MToken objects have `start_ts`/`end_ts`)
- Would need: custom `/v1/audio/speech/with-timing` endpoint, or a separate timing extraction pass
- Impact for karaoke subtitles: Swift client cannot get word timestamps from this server as-is

## Audio Reference

- Medium WAV: /tmp/benchmark-python-mlx-medium.wav
- Duration: 5.100s
- File size: 239 KB (244,844 bytes)
- Format: 1ch, 24000 Hz, Int16 PCM WAV

## Verdict

Stable baseline. RTF 0.10–0.16 across all text lengths — real-time synthesis well within margin.
Memory stable after warm-up. Main limitation: no word timestamps in HTTP API, which blocks
karaoke subtitle sync without a server-side patch. Quality reference at /tmp/benchmark-python-mlx-medium.wav.
