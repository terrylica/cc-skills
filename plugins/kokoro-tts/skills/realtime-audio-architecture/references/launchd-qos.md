# launchd QoS for Audio Processes

## The Problem

macOS uses Quality of Service (QoS) classes to schedule process priority. A TTS server configured as `Background` gets actively throttled — macOS treats it as unimportant work that can be deferred.

## QoS Classes (Apple's Hierarchy)

| ProcessType   | QoS Class                | CPU Priority                    | I/O Priority | Audio Suitability                           |
| ------------- | ------------------------ | ------------------------------- | ------------ | ------------------------------------------- |
| `Interactive` | User Interactive         | Highest                         | Highest      | Overkill (blocks UI responsiveness metrics) |
| `Adaptive`    | User Initiated → Utility | High when active, low when idle | Normal       | **Best for audio**                          |
| `Standard`    | Default                  | Normal                          | Normal       | Acceptable                                  |
| `Background`  | Background               | Lowest                          | Lowest       | **NEVER for audio**                         |

## Correct Configuration

```xml
<key>Nice</key>
<integer>-10</integer>
<key>ProcessType</key>
<string>Adaptive</string>
```

### Nice Value

- Range: -20 (highest priority) to 20 (lowest priority)
- 0 = normal user process
- -10 = elevated priority (appropriate for audio)
- -20 = maximum priority (usually reserved for system processes)
- launchd user agents CAN use negative values (launchd runs as root)

### ProcessType: Adaptive

`Adaptive` is ideal for audio because:

1. **High priority when active**: When the process is doing work (synthesizing, playing audio), macOS boosts it to User Initiated QoS
2. **Low priority when idle**: When waiting for requests, drops to Utility QoS — doesn't waste resources
3. **No UI impact**: Unlike `Interactive`, doesn't affect macOS responsiveness metrics

## Symptoms of Wrong QoS

- Jitter that only appears during system load (other apps active)
- Inconsistent synthesis times (same text takes 500ms sometimes, 2000ms other times)
- Audio that sounds fine in isolation but glitches during normal use
- Hard to reproduce in testing (test conditions usually have low system load)

## Verification

```bash
# Check process nice value
ps -o pid,nice,pri,command -p $(pgrep -f tts_server.py)

# Check plist settings
plutil -p ~/Library/LaunchAgents/com.terryli.kokoro-tts-server.plist | grep -E 'Nice|ProcessType'

# Expected output:
#   "Nice" => -10
#   "ProcessType" => "Adaptive"
```

## SoftResourceLimits

The memory limit in the plist should accommodate model loading:

```xml
<key>SoftResourceLimits</key>
<dict>
    <key>MemoryLimit</key>
    <integer>4294967296</integer>  <!-- 4GB — Kokoro-82M needs ~150MB, but MLX allocates more -->
</dict>
```
