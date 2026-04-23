# floating-clock

Always-on-top floating desktop clock for macOS. Single-file Objective-C implementation (~50KB binary, ~10–12 MB RSS) using NSPanel with persistent positioning and sub-0.1% idle CPU.

**Hub:** [CLAUDE.md](../../CLAUDE.md) | **Sibling:** [plugins/CLAUDE.md](../CLAUDE.md)

## Build

From the plugin directory:

```bash
cd plugins/floating-clock
make all          # build + bundle + sign
make run          # build + bundle + sign + open app
make install      # install to /Applications
make clean        # remove build/ artifacts
```

Binary at `build/floating-clock` (~50KB), app bundle at `build/FloatingClock.app`.

## Design

- **NSPanel (not NSWindow)**: Borderless, non-activating, always floating
- **All Spaces**: `collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary`
- **Timer**: `dispatch_source_t` aligned to second boundary, 1-second interval
- **Position persistence**: NSUserDefaults key `FloatingClockWindowFrame`, restored on launch
- **No Dock icon**: `LSUIElement=YES` in Info.plist
- **Monospaced digits**: `monospacedDigitSystemFontOfSize:weight:` (stable-width for clean display)

## Implementation

**Single-file source**: `Sources/clock.m` (~115 LoC)

- `@autoreleasepool` for memory hygiene
- Self-contained: no separate header files, no external dependencies beyond Cocoa
- No SwiftUI, no Swift runtime tax
- Automatic Reference Counting (ARC) for safety

## Future Enhancements

- 12h/24h format toggle (requires simple pref UI)
- Seconds toggle
- Menu bar integration (future plugin: `statusline-tools` could consume this)
- Launchd autostart option
- Settings UI (PreferencesWindowController)
