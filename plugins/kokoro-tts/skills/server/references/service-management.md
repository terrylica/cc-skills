# Service Management Reference

Managing the Kokoro TTS server as a macOS launchd service.

## Launchd Policy

Per the macOS launchd policy, **all launchd services must use compiled Swift binaries** — no bash scripts. This applies to the Kokoro TTS server.

## Swift Launcher Binary

The launcher is a minimal Swift program that executes the Python server:

```swift
import Foundation

let python = ProcessInfo.processInfo.environment["KOKORO_PYTHON"]
    ?? "\(NSHomeDirectory())/.local/share/kokoro/.venv/bin/python"
let script = "\(NSHomeDirectory())/.local/share/kokoro/tts_server.py"

let process = Process()
process.executableURL = URL(fileURLWithPath: python)
process.arguments = [script]
process.environment = ProcessInfo.processInfo.environment

try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
```

Compile: `swiftc -O -o kokoro-tts-server KokoroTTSServer.swift`

## Plist Template

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.kokoro-tts-server</string>
    <key>Program</key>
    <string>/path/to/compiled/kokoro-tts-server</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>30</integer>
    <key>EnvironmentVariables</key>
    <dict>
        <key>KOKORO_SERVER_PORT</key>
        <string>8779</string>
        <key>KOKORO_SERVER_HOST</key>
        <string>127.0.0.1</string>
        <key>KOKORO_DEFAULT_VOICE</key>
        <string>af_heart</string>
    </dict>
</dict>
</plist>
```

## Lifecycle Commands

```bash
# Start
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.kokoro-tts-server.plist

# Stop
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.example.kokoro-tts-server.plist

# Restart
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.example.kokoro-tts-server.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.kokoro-tts-server.plist

# Status
launchctl print gui/$(id -u)/com.example.kokoro-tts-server
```
