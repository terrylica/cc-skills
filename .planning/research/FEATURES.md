# Feature Landscape <!-- # SSoT-OK -->

**Domain:** macOS TTS companion -- architecture hardening + feature expansion
**Researched:** 2026-03-27
**Scope:** NEW features for the current milestone only

## Table Stakes for This Milestone

Features that must ship for the milestone to be considered complete.

| Feature                             | Why Expected                                                                                  | Complexity | Notes                                                              |
| ----------------------------------- | --------------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------ |
| Actor-based concurrency             | Replaces fragile NSLock/@unchecked Sendable. Data race safety must be compile-time verified.  | High       | Touches every component; requires TTSEngine decomposition          |
| XCTest/Swift Testing infrastructure | No tests = no confidence in decomposition correctness. Testing must exist before refactoring. | Medium     | One-time Package.swift restructure, then incremental test addition |
| TTSEngine decomposition             | PlaybackManager, WordTimingAligner, PronunciationProcessor must be separate testable units    | High       | Prerequisite for actor migration; defines the actor boundaries     |

## Differentiators

Features that add value but are not blocking.

### Bionic Reading Mode

| Feature                                   | Why Expected / Value                                                                        | Complexity | Dependencies                                     | Notes                                                                    |
| ----------------------------------------- | ------------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------ | ------------------------------------------------------------------------ |
| Bold first N characters per word          | Core mechanic of bionic reading; creates artificial fixation points that guide eye movement | Low        | SubtitlePanel, SubtitleStyle, NSAttributedString | ~15 lines of attributed string manipulation                              |
| Coexistence with karaoke highlighting     | Both features modify NSAttributedString; must compose cleanly                               | Medium     | SubtitlePanel.highlightWord()                    | Bionic bold + karaoke color stack: bold first N chars in gold/white/grey |
| Toggle on/off via HTTP API + Telegram     | Users must control this; some find it distracting (2025 research shows mixed results)       | Low        | SettingsStore, HTTPControlServer, TelegramBot    | Add `bionicReading: Bool` to SubtitleSettings                            |
| Adjustable intensity (light/medium/heavy) | Power users can tune fixation point density                                                 | Low        | SettingsStore                                    | Light=ceil(len*0.3), Medium=ceil(len*0.4), Heavy=ceil(len\*0.6)          |

**Algorithm:** `boldCount = max(1, ceil(Double(wordLength) * ratio))` where ratio varies by intensity preset. In SubtitlePanel.highlightWord(), split each word into bold prefix + regular suffix, layered over existing karaoke color scheme. Example: "Reading" at medium -> "**Rea**ding" (bold first 3 of 7 chars).

**Research caveat (MEDIUM confidence):** Peer-reviewed 2025 eye-tracking studies (PMC, SAGE Journals) found bionic reading does NOT significantly change eye movement patterns or reading speed. However, ADHD-specific benefits (27% reading speed improvement per Myndset Therapeutics) and subjective preference are consistently reported. Position as optional preference, not scientifically proven speed enhancement.

### Scrollable Caption History Panel

| Feature                               | Why Expected / Value                                                                | Complexity | Dependencies                                                     | Notes                                                         |
| ------------------------------------- | ----------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------- | ------------------------------------------------------------- |
| Scrollable list of past captions      | Google Meet (Feb 2025) and Teams (July 2025) made this table stakes for caption UIs | Medium     | CaptionHistory (exists as ring buffer), new NSPanel/NSScrollView | CaptionHistory.getAll() already returns chronological entries |
| Timestamps on each entry              | Users need temporal context to find what they missed                                | Low        | CaptionEntry already has `timestamp: String` (ISO 8601)          | Display as HH:MM or relative time                             |
| "Jump to bottom" / auto-scroll        | Google Meet's pattern: auto-scroll to latest, manual scroll-up pauses auto-scroll   | Medium     | NSScrollView scroll position tracking                            | Button to resume auto-scroll when user scrolls up             |
| Copy individual caption or all        | Spike 17 identified as Tier 1 must-have; CaptionHistory.copyToClipboard() exists    | Low        | CaptionHistory.copyToClipboard(), NSPasteboard                   | Click-to-copy per line                                        |
| Non-activating panel (no focus steal) | Same as subtitle panel -- must not interrupt user's active app                      | Low        | NSPanel, .nonactivatingPanel, canBecomeKey=false                 | Follow SubtitlePanel pattern                                  |

**Design pattern (from Google Meet):** Default auto-scroll to bottom. When user scrolls up, pause auto-scroll and show "Jump to bottom" button. New captions still append but don't force scroll. Panel: NSPanel, floating, non-activating, sharingType=.none, right side of screen, ~400px wide.

### Focus/DND Awareness

| Feature                              | Why Expected / Value                           | Complexity | Dependencies                                              | Notes                                                      |
| ------------------------------------ | ---------------------------------------------- | ---------- | --------------------------------------------------------- | ---------------------------------------------------------- |
| Suppress TTS audio when Focus active | Don't interrupt during meetings/focus time     | Medium     | Assertions.json polling, TTSEngine/PlaybackManager gating | Poll ~/Library/DoNotDisturb/DB/Assertions.json every 5-10s |
| Continue showing subtitles silently  | Subtitles are visual-only and non-intrusive    | Low        | Decouple audio playback from subtitle display             | SubtitleSyncDriver already supports subtitle-only mode     |
| Indicate Focus state in HTTP /status | User/SwiftBar needs to know Focus was detected | Low        | HTTP API status endpoint                                  | Add `focusMode: "work" / null` to response                 |
| Graceful degradation if API breaks   | Assertions.json is private/undocumented        | Low        | Try/catch, default to "not in focus"                      | Never crash on read failure; fail-open for audio           |

**Detection approach:** Read `~/Library/DoNotDisturb/DB/Assertions.json`, check for `data[0].storeAssertionRecords` (exists = Focus active). Cross-reference mode ID with `ModeConfigurations.json` for name. File may take 1-2 min to update after toggle. Non-sandboxed launchd service should have access. Undocumented; may break across macOS versions.

### Chinese TTS Fallback

| Feature                             | Why Expected / Value                                      | Complexity | Dependencies                                                      | Notes                                                        |
| ----------------------------------- | --------------------------------------------------------- | ---------- | ----------------------------------------------------------------- | ------------------------------------------------------------ |
| Route CJK text to Chinese voice     | CJK text currently produces silence or garbled English    | Medium     | LanguageDetector (exists), sherpa-onnx kokoro-multi-lang model    | LanguageDetector.detect() already flags CJK at 20% threshold |
| Intelligible Chinese pronunciation  | English voice reading Chinese chars is useless            | High       | Chinese model with phonemization (lexicon-zh.txt, espeak-ng-data) | sherpa-onnx kokoro-multi-lang-v1_1 has 8 Chinese voices      |
| Seamless fallback -- no user action | Language detection runs automatically per-utterance       | Low        | LanguageDetector.detect() already runs per synthesis call         | Gate behind SettingsStore flag for gradual rollout           |
| Same 24kHz sample rate output       | Mixed audio must play through same AVAudioPlayer pipeline | Low        | Both kokoro-ios and sherpa-onnx kokoro output 24kHz               | No sample rate conversion needed                             |

**Recommended model:** sherpa-onnx kokoro-multi-lang-v1_1 (int8, ~165MB estimated). Uses C API already linked via CSherpaOnnx module. Avoids loading second MLX model (GPU memory concern). Chinese voices: zf_xiaobei (female, sid=45), zm_yunxi (male). Requires lexicon-zh.txt + espeak-ng-data for phonemization.

**Skip for v4.7.0:** Chinese karaoke word timing (CJK has no word boundaries; needs tokenizer), mixed Chinese/English per-sentence routing (complex, defer to v4.8.0).

## Anti-Features

Features to explicitly NOT build in this milestone.

| Anti-Feature                           | Why Avoid                                                                                                      | What to Do Instead                                                                             |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| SwiftUI migration                      | NSHostingView bridging adds complexity for zero UI benefit. The overlay is a text panel, not a complex layout. | Stay with AppKit NSPanel + NSTextField/NSTextView.                                             |
| Multi-language TTS beyond Chinese      | Scope creep. English + Chinese covers the actual use case.                                                     | Add languages later if requested. The multilingual model supports it but don't wire up the UI. |
| Caption search/filtering               | Over-engineering for a history panel. Copy-to-clipboard is sufficient.                                         | Let users cmd+F in the history panel (NSTextView supports this natively).                      |
| Real-time Focus mode name display      | Knowing "Work Focus" vs "Personal Focus" adds no value. Only need on/off.                                      | Just suppress/allow audio. Don't display which Focus mode.                                     |
| Performance benchmarking framework     | XCTest `measure {}` is sufficient for the few perf-sensitive paths (TTS synthesis, word timing).               | Use XCTest measure blocks, not a custom framework.                                             |
| Chinese karaoke word timing            | CJK has no word boundaries; tokenization is a separate research problem                                        | Show Chinese text as plain subtitles without per-word karaoke; add later                       |
| Mixed CJK/English per-sentence routing | Sentence splitting + per-sentence engine routing + audio concatenation is complex                              | Detect dominant language per utterance (whole text block); defer sentence-level to v4.8.0      |
| Animated bionic text transitions       | Spike 17: animations fatigue users in long-form content                                                        | Instant style application, no transitions                                                      |
| Caption history disk persistence       | Ring buffer in memory is sufficient; disk persistence adds privacy concerns                                    | Clear on restart; offer export-before-clear via HTTP API                                       |
| Bionic reading exposed as API          | Scope creep; this is a subtitle overlay, not a reading tool platform                                           | Keep as rendering mode within SubtitlePanel only                                               |

## Feature Dependencies

```
Package.swift restructure (CompanionCore library)
    --> All testing
    --> Actor migration
        --> TTSEngine decomposition (PlaybackManager, WordTimingAligner, PronunciationProcessor)
            --> Chinese TTS fallback (needs PronunciationProcessor for CJK detection routing)
            --> Focus/DND awareness (needs PlaybackManager for audio suppression)
    --> Bionic reading (independent, just needs CompanionCore to exist)
    --> Caption history panel (independent, just needs CompanionCore to exist)

Existing components used by new features:
    CaptionHistory (ring buffer, exists) --> Caption History Panel (new NSPanel)
    LanguageDetector (exists) --> Chinese TTS Fallback (model loading + routing)
    SubtitleStyle (exists) --> Bionic Reading (attributed string builder)
    SettingsStore (exists) --> All new feature toggles
    SubtitleSyncDriver (exists) --> Subtitle-only mode during Focus
```

## MVP Recommendation

Prioritize:

1. Package.swift restructure + basic test infrastructure (unblocks everything)
2. Actor migration + TTSEngine decomposition (core architecture)
3. Bionic reading (lowest complexity, independent, ships fast for user feedback)
4. Caption history panel (medium complexity, CaptionHistory already exists, table stakes since 2025)
5. Chinese TTS fallback (fills a real gap -- CJK text is currently silent; depends on TTSEngine decomposition)

Defer if needed:

- Focus/DND: Highest risk (undocumented API), lowest urgency -- users can manually pause via SwiftBar. Build defensively with graceful degradation when attempted.

## Sources

- [SwiftPM Executable Target Testability](https://github.com/swiftlang/swift-package-manager/issues/7596)
- [Swift Testing vs XCTest comparison](https://blog.micoach.itj.com/swift-testing-vs-xctest)
- [sherpa-onnx Kokoro multilingual models](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html) -- kokoro-multi-lang-v1_1, 103 speakers, 8 Chinese
- [sherpa-onnx VITS Chinese models](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/vits.html) -- vits-melo-tts-zh_en bilingual
- [sherpa-onnx PR #1795: Kokoro 1.0 multilingual API](https://github.com/k2-fsa/sherpa-onnx/pull/1795)
- [text-vide bionic reading OSS](https://github.com/Gumball12/text-vide)
- [Bionic Reading Official Method](https://bionic-reading.com/br-method/)
- [PMC: How Bionic Reading Influences Eye Movements (2025)](https://pmc.ncbi.nlm.nih.gov/articles/PMC12565662/) -- peer-reviewed, mixed results
- [SAGE: Usability of Bionic Reading on Different Mediums (2025)](https://journals.sagepub.com/doi/10.1177/21582440251376158)
- [Readima: Bionic Reading and ADHD](https://readima.com/blog/bionic-reading-read-faster-with-science-backed-typography) -- 27% ADHD improvement claim
- [Google Workspace: Scrollable Live Captions in Meet (Feb 2025)](https://workspaceupdates.googleblog.com/2025/02/google-meet-caption-history.html)
- [Drew Kerr: Read Focus Mode via JXA](https://gist.github.com/drewkerr/0f2b61ce34e2b9e3ce0ec6a92ab05c18) -- Assertions.json parsing
- [Apple Developer Forums: No public DND API](https://developer.apple.com/forums/thread/100511) -- confirmed by Apple
- [Brunerd: Respecting Focus and Meeting Status](https://www.brunerd.com/blog/2022/03/07/respecting-focus-and-meeting-status-in-your-mac-scripts-aka-dont-be-a-jerk/)
- [kokoro-ios (mlalma)](https://github.com/mlalma/kokoro-ios) -- MLX Swift port with Chinese voices
- Spike 17 Goal Refinement -- caption history table stakes, bionic reading findings
- Spike 21 Screen Sharing Privacy Report -- Focus mode API investigation
