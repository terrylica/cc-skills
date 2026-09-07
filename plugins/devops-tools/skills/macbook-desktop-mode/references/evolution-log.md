# macbook-desktop-mode Evolution Log

## v1.0.0 — 2026-03-18

**Origin**: A bus-powered USB 1.1 audio-class microphone repeatedly disappeared from macOS sound input after sleep/wake cycles on an Apple Silicon MacBook running permanently on AC. Root cause analysis revealed DarkWake cycling (macOS takes a partial maintenance wake roughly every 15 minutes overnight), USB 1.1 fragility (no LPM, no serial number), Chrome USB handle contention, and battery micro-cycling on an always-plugged-in Mac left with no charge limit.

**Scope**: Full-stack solution covering power configuration (`pmset`, charge limit), hardware layer (powered USB hub with uhubctl), and software layer (AudioDeviceMonitorRunner.swift v2 with state machine, wake detection, heartbeat, recovery cascade, Telegram notification).

**Key technical discoveries**:

- IOKit message constants (`kIOMessageSystemHasPoweredOn`, etc.) use `iokit_common_msg()` C macros that Swift can't import — must define hex values manually (`0xe0000300`)
- `IORegisterForSystemPower` works in headless launchd daemons; `NSWorkspace.didWakeNotification` requires AppKit
- Apple Silicon AC bypass mode at charge limit means battery is electrically disconnected — zero performance impact
- USB kernel assertions (`pmset -g assertions | grep USB`) show device enumeration timestamps — useful for pinpointing when a device was last re-enumerated vs. originally discovered at boot

**Implementation**: `AudioDeviceMonitorRunner.swift` enhanced from v1 (priority enforcer only) to v2 (device guardian). Lives in `~/own/amonic/bin/swift/`. Build requires `-framework IOKit` in addition to `-framework CoreAudio`.
