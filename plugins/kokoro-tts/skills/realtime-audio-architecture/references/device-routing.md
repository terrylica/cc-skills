# Audio Device Routing and Hot-Switching

## The Problem

A TTS server running as a launchd daemon opens its audio stream at startup. The stream binds to whatever output device was default at that moment (typically MacBook Pro Speakers at login). When the user later switches to an external monitor (HDMI) or Bluetooth headphones (AirPods), audio keeps going to the old device.

Two independent issues:

1. **PortAudio device cache**: `Pa_Initialize()` scans devices once. Bluetooth devices connecting later are invisible.
2. **Stream device binding**: `sd.OutputStream` binds to a specific device at creation. Changing the system default has no effect on an already-open stream.

## Solution: Two-Layer Device Detection

### Layer 1: Between Requests (Full Refresh)

Before each speak request, re-initialize PortAudio to discover new devices:

```python
def _refresh_audio_devices():
    """Re-init PortAudio to pick up hot-plugged devices (~1ms)."""
    sd._terminate()
    sd._initialize()

def _open_audio_stream():
    _refresh_audio_devices()
    device = _get_output_device()  # None = system default, or env override
    stream = sd.OutputStream(
        samplerate=24000, channels=1, dtype="float32",
        blocksize=2048, latency="high", device=device,
    )
    stream.start()
    dev_info = sd.query_devices(stream.device, kind='output')
    print(f"Audio stream opened → {dev_info['name']}")
    return stream
```

The stream is closed after each request completes:

```python
finally:
    if _stream is not None:
        _stream.close()
        _stream = None
```

This guarantees the next request opens a fresh stream on the current default device, with a fresh PortAudio device scan that sees newly-connected Bluetooth devices.

### Layer 2: Between Chunks (Cached Check)

For long multi-chunk playback, check between chunks if the default device changed among already-known devices:

```python
def _maybe_reopen_stream(stream):
    """Check if default output changed. Uses cached device list only."""
    try:
        current_default = sd.query_devices(kind='output')['index']
    except sd.PortAudioError:
        return stream
    if stream.device != current_default:
        stream.close()
        return _open_audio_stream()  # refresh + open on new device
    return stream
```

**CRITICAL**: Do NOT call `_refresh_audio_devices()` inside `_maybe_reopen_stream()`. The `sd._terminate()` call invalidates all active PortAudio stream pointers, causing `PaErrorCode -9988` (invalid stream pointer) on the next `stream.write()`.

## What Each Layer Handles

| Scenario                         | Layer            | Example                                    |
| -------------------------------- | ---------------- | ------------------------------------------ |
| AirPods connected before TTS     | Between requests | `_refresh_audio_devices()` sees AirPods    |
| Switch LG ↔ MacBook mid-playback | Between chunks   | Both known to PortAudio, index check works |
| AirPods connect mid-playback     | Next request     | Current playback finishes on old device    |
| HDMI monitor plugged in          | Between requests | `_refresh_audio_devices()` sees new HDMI   |

## Explicit Device Override

For cases where the system default isn't what you want:

```python
# In tts_server.py
def _get_output_device():
    """KOKORO_AUDIO_DEVICE env: integer index or device name substring."""
    env_dev = os.environ.get("KOKORO_AUDIO_DEVICE", "").strip()
    if env_dev:
        try:
            return int(env_dev)
        except ValueError:
            return env_dev  # name substring, e.g., "AirPods"
    return None  # system default
```

When an explicit device is set, `_maybe_reopen_stream()` skips the default-device check (the user chose a specific device).

## Why Not CoreAudio Directly?

Using CoreAudio's `AudioObjectGetPropertyData` via ctypes would give real-time device change notifications without PortAudio re-initialization. However:

1. **Complexity**: Requires ctypes structs, callback registration, run loop integration
2. **Sufficient**: The two-layer approach covers all practical scenarios
3. **PortAudio compatibility**: Mixing CoreAudio and PortAudio device IDs is error-prone (different numbering)

## Diagnostic

```bash
# Check which device the server is using
grep "Audio stream opened" ~/.local/state/launchd-logs/kokoro-tts-server/stdout.log | tail -3

# Check for device switch events
grep "Output device changed" ~/.local/state/launchd-logs/kokoro-tts-server/stdout.log | tail -5

# Check for PortAudio errors (stream pointer invalidation)
grep "PaErrorCode" ~/.local/state/launchd-logs/kokoro-tts-server/stdout.log | tail -5

# Query current default from server's venv
~/.local/share/kokoro/.venv/bin/python3 -c "import sounddevice as sd; print(sd.query_devices(kind='output'))"
```
