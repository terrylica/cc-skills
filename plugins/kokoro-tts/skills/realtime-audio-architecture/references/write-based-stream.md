# Write-Based sounddevice.OutputStream

## Why Write-Based Over Callback-Based

The sounddevice library offers two approaches:

1. **Callback-based**: You provide a Python function that PortAudio calls on its real-time thread
2. **Write-based**: You call `stream.write(data)` which blocks in C until the device buffer has space

### The GIL Problem with Callbacks

```
Audio thread (PortAudio)     Python main thread (MLX synthesis)
─────────────────────────    ──────────────────────────────────
callback() called            model.synthesize(chunk)
  → needs GIL                  → holds GIL for 10-50ms
  → BLOCKED                    → numpy operations
  → buffer underrun!           → finally releases GIL
  → silence/glitch           callback() finally runs (too late)
```

Even though the callback is invoked from C, the Python code inside (`queue.get_nowait()`) needs the GIL. When MLX Metal inference holds the GIL (common during wrapper calls), the callback is delayed past its deadline.

### Write-Based: No GIL on Audio Thread

```
Playback thread              Python synthesis thread
──────────────────           ──────────────────────
stream.write(block)          model.synthesize(chunk)
  → enters C code              → holds GIL
  → blocks in PortAudio        → numpy operations
  → NO GIL NEEDED              → releases GIL
  → audio flows smoothly     next chunk ready
```

`stream.write()` passes the data to PortAudio's internal buffer in C and blocks until there's space. The audio thread is managed entirely by PortAudio in C — no Python code runs on it.

## Implementation

```python
import sounddevice as sd
import numpy as np

# Opened lazily per request — closed after each to follow device changes
_stream: sd.OutputStream | None = None

def open_audio_stream() -> sd.OutputStream:
    # Refresh PortAudio to discover hot-plugged devices (Bluetooth, HDMI)
    sd._terminate()
    sd._initialize()
    stream = sd.OutputStream(
        samplerate=24000,   # Kokoro outputs 24kHz
        channels=1,
        dtype="float32",    # CoreAudio native format
        blocksize=2048,     # ~85ms — good balance
        latency="high",     # large buffer = fewer underruns
    )
    stream.start()
    return stream

def write_audio(stream: sd.OutputStream, audio: np.ndarray, interrupted) -> None:
    """Write audio in ~170ms blocks for responsive interrupt checking."""
    WRITE_BLOCK = 4096
    audio_2d = audio.reshape(-1, 1)  # write() expects (frames, channels)
    for i in range(0, len(audio_2d), WRITE_BLOCK):
        if interrupted.is_set():
            return
        stream.write(audio_2d[i:i + WRITE_BLOCK])

def stop_audio(stream: sd.OutputStream) -> None:
    """Immediately stop playback. stream.abort() unblocks write()."""
    if stream and stream.active:
        stream.abort()  # raises PortAudioError in write() — catch in caller
```

## Tuning Parameters

| Parameter     | Value       | Rationale                                                                   |
| ------------- | ----------- | --------------------------------------------------------------------------- |
| `blocksize`   | 2048        | ~85ms at 24kHz. Larger = more buffer tolerance. Smaller = lower latency.    |
| `latency`     | `"high"`    | Requests largest buffer from PortAudio. We're not live, so latency is fine. |
| `WRITE_BLOCK` | 4096        | ~170ms. Balance between write granularity and interrupt responsiveness.     |
| `dtype`       | `"float32"` | CoreAudio's native format. No conversion overhead.                          |

## Stop/Resume Lifecycle

1. Normal stop: `stream.abort()` → unblocks `write()` → `PortAudioError` in caller
2. Caller catches `PortAudioError`, checks `_interrupted` flag
3. Stream closed in `finally` block after each request
4. Next request: `stream = open_audio_stream()` (fresh device scan + open)
5. Stream stays open between chunks within the same speak request

## Compared to afplay Subprocess

| Metric             | afplay subprocess            | Write-based stream       |
| ------------------ | ---------------------------- | ------------------------ |
| Audio device opens | Once per chunk               | Once per request         |
| File I/O           | WAV write + read per chunk   | None (numpy arrays)      |
| Process spawns     | fork+exec per chunk          | None                     |
| Inter-chunk gap    | 50-200ms (device re-acquire) | 0ms (continuous buffer)  |
| GIL sensitivity    | N/A (separate process)       | None (write blocks in C) |
| Stop latency       | `kill` signal propagation    | Immediate (`abort()`)    |
