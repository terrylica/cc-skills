# Phase 02: Subtitle Overlay — Context

## Phase Goal

Build a floating NSPanel subtitle overlay with word-level karaoke highlighting. The panel displays text with gold highlighting for the current word, anchored at the bottom center of the MacBook screen. Includes a demo mode for testing without TTS (Phase 3).

## Prior Context

- Phase 1 delivered: Package.swift, CSherpaOnnx module, main.swift (NSApp accessory + SIGTERM), Config.swift
- Build verified: `swift build` succeeds with all dependencies resolved
- Architecture: NSApplication.shared with .accessory activation policy (no dock icon)

## Decisions Made

### Panel Geometry & Position

- **Position**: Bottom center, 80px from bottom edge
- **Width**: 70% of screen width, centered (2056px screen → ~1440px panel)
- **Font**: 28pt SF Pro Display (Medium preset). S=22pt, M=28pt, L=36pt
- **Corner radius**: 10px, padding: 16px horizontal / 12px vertical

### Text Styling & Karaoke Colors

- **Current word**: Gold (#FFD700), bold weight
- **Past words**: Silver-grey (#A0A0A0), regular weight
- **Future words**: White (#FFFFFF), regular weight
- **Background**: Black (#000000) at 30% opacity

### Utterance Transitions & Testing

- **Transition**: Instant replace (clear old text, show new)
- **Linger time**: 2 seconds after final word, then clear
- **Testing**: Demo mode with hardcoded word timings (200ms per word) via `SubtitlePanel.demo()`

### Window Behavior (from Spike 02/21)

- NSPanel with `.floating` level
- `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]`
- `sharingType = .none` (auto-hides during screen sharing)
- Click-through (ignoresMouseEvents = true)
- No focus stealing (canBecomeKey = false, canBecomeMain = false)
- Word-wrap to 2 lines maximum, no text shrinking

## Success Criteria

1. Floating panel visible on all Spaces, no dock icon, no focus stealing
2. Gold karaoke highlighting advances word-by-word with <1ms per update
3. Panel invisible during screen sharing (sharingType = .none)
4. Demo mode cycles through sample sentences with hardcoded timings
5. Click-through behavior (mouse events pass through to underlying windows)
6. Word-wrap to 2 lines without shrinking text

## Files to Create/Modify

- `Sources/claude-tts-companion/SubtitlePanel.swift` — Main overlay panel
- `Sources/claude-tts-companion/SubtitleStyle.swift` — Color/font/layout constants
- `Sources/claude-tts-companion/main.swift` — Wire up panel creation after NSApp activation
