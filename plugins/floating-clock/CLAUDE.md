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

Binary at `build/floating-clock` (~50KB), app bundle at `build/FloatingClock.app`. App bundle includes `Contents/Resources/Icon.icns` (generated at build time from `Sources/gen-icon.m` via Core Graphics — no external image dependencies). Spotlight/Launchpad/Finder index the app with this icon after first install.

## Design

- **NSPanel (not NSWindow)**: Borderless, non-activating, always floating
- **All Spaces**: `collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary`
- **Timer**: `dispatch_source_t` aligned to second boundary, 1-second interval
- **No Dock icon**: `LSUIElement=YES` in Info.plist
- **Font resolution** (in priority order):
  1. User override via NSUserDefaults key `FontName` (PostScript name)
  2. iTerm2 default profile's `Normal Font` (extracted from `com.googlecode.iterm2.plist`)
  3. System monospaced fallback: SF Mono (macOS 10.15+) or Menlo (older)
  4. Displays at fixed 24pt size (independent of iTerm2's size preference)
- **Default position** (first launch, no saved state): bottom-center of main screen's `visibleFrame` (respects menu bar and Dock)
- **Multi-monitor position persistence**:
  - Saves both window frame and screen ID on every move (`windowDidMove:`)
  - On launch: restores only if saved screen still connected AND frame intersects that screen
  - If saved screen disconnected: falls back to bottom-center of main screen
  - At runtime: monitors `NSApplicationDidChangeScreenParametersNotification`; if clock's screen unplugged, relocates to bottom-center of main screen with animation
- **Defensive parsing**: All plist dictionary lookups verify `isKindOfClass:` before use — malformed iTerm2 plist cannot crash the clock
- **Self-generated icon**: `gen-icon` helper draws a 1024×1024 clock glyph (dark rounded square + white face + 10:10 hands) using only Core Graphics. `iconutil` bundles into ICNS at build time. Zero external image assets.

## Implementation

**Single-file source**: `Sources/clock.m` (232 LoC)

- `@autoreleasepool` for memory hygiene
- Self-contained: no separate header files, no external dependencies beyond Cocoa
- No SwiftUI, no Swift runtime tax
- Automatic Reference Counting (ARC) for safety
- `resolveClockFont()`: static helper for multi-fallback font resolution
- `defaultFrame()`: computes bottom-center position on main screen
- `screensChanged:` runtime observer for monitor hot-unplug detection

## Future Enhancements

- Configurable font size via NSUserDefaults key `FontSize`
- Configurable font override via NSUserDefaults key `FontName` (already partially implemented — accepts PostScript name)
- 12h/24h format toggle (requires simple pref UI)
- Seconds toggle
- Menu bar integration (future plugin: `statusline-tools` could consume this)
- Launchd autostart option
- Settings UI (PreferencesWindowController)
