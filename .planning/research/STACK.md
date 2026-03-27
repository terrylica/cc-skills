# Technology Stack — v4.7.0 Additions <!-- # SSoT-OK -->

**Project:** claude-tts-companion
**Researched:** 2026-03-27
**Scope:** NEW capabilities only. See CLAUDE.md for the validated base stack.

## New Stack Additions <!-- # SSoT-OK -->

### 1. Actor-Based Concurrency (No New Dependencies)

| Technology              | Version                     | Purpose                                          | Why                                                                                                                                                                                                                                                                                    | Confidence |
| ----------------------- | --------------------------- | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| Swift Actors (built-in) | Swift 6.0+ (already in use) | Replace @unchecked Sendable + NSLock             | Actors suspend tasks instead of blocking threads. NSLock blocks the calling thread; actors yield to the cooperative thread pool. For a launchd daemon doing TTS + bot + HTTP + UI, blocking threads is wasteful. Actors also get compile-time data race safety in Swift 6 strict mode. | HIGH       |
| @MainActor (built-in)   | Swift 6.0+                  | UI-bound state (subtitle panel, caption history) | NSPanel and NSAttributedString manipulation must happen on the main thread. @MainActor enforces this at compile time instead of relying on DispatchQueue.main.async sprinkled manually.                                                                                                | HIGH       |

**Migration pattern:** Extract mutable state into actor types. The TTSEngine decomposition (PlaybackManager, WordTimingAligner, PronunciationProcessor) naturally maps to actors with isolated state. Synchronous state mutations stay synchronous within the actor; only cross-actor calls become async.

**Key reentrancy rule:** Actor-isolated state can change across any `await`. Never assume invariants hold after a suspension point. Perform state mutations in synchronous blocks, restore consistency before any `await`.

**Swift 6.2 note:** Swift 6.2 (WWDC 2025) introduced `defaultIsolation: MainActor` and the `@concurrent` attribute. Consider adopting when the project moves to Swift 6.2 toolchain -- it simplifies by making MainActor the default and requiring explicit `@concurrent` for background work. Not required for the current milestone since Swift 6.0 strict mode already provides data race safety.

### 2. Testing Infrastructure (No New Dependencies)

| Technology    | Version                         | Purpose                    | Why                                                                                                                                                                                                            | Confidence |
| ------------- | ------------------------------- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| Swift Testing | Built into Swift 6.0+ toolchain | Unit and integration tests | Macro-based (`@Test`, `#expect`), parallel by default, native async/await. Replaces XCTest's 40+ assertion functions with one `#expect` macro. Ships with the Swift 6.0 toolchain -- no SPM dependency needed. | HIGH       |
| XCTest        | Built into Swift toolchain      | Performance tests only     | Swift Testing cannot do performance testing yet. Use XCTest only for `measure {}` blocks if needed. Both frameworks coexist in the same test target.                                                           | HIGH       |

**Critical Package.swift pattern -- extract a library target:**

Executable targets CANNOT be imported with `@testable import`. You must split the code:

```swift
// Package.swift
let package = Package(
    name: "claude-tts-companion",
    targets: [
        // Library with all testable logic
        .target(
            name: "CompanionCore",
            dependencies: [/* sherpa-onnx, swift-telegram-sdk, FlyingFox, swift-log */]
        ),
        // Thin executable -- just calls CompanionCore.main()
        .executableTarget(
            name: "claude-tts-companion",
            dependencies: ["CompanionCore"]
        ),
        // Tests import the library
        .testTarget(
            name: "CompanionCoreTests",
            dependencies: ["CompanionCore"]
        ),
    ]
)
```

The executable's `main.swift` becomes ~5 lines that call into `CompanionCore`. All business logic, actors, managers live in `CompanionCore`. Tests use `@testable import CompanionCore`.

**Run tests:** `swift test` (runs both Swift Testing and XCTest targets in one pass).

### 3. Chinese TTS Fallback (sherpa-onnx, Already Linked)

| Technology                   | Version                          | Purpose               | Why                                                                                                                                                                                                                                                                       | Confidence |
| ---------------------------- | -------------------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| kokoro-multi-lang-v1_0 model | Via sherpa-onnx (already linked) | Chinese/Mandarin TTS  | 53 speakers, 8 Chinese voices (4F/4M). ~310MB ONNX model. Uses the same sherpa-onnx C API already in the binary -- no new library dependency. Chinese voices: zf_xiaobei, zf_xiaoni, zf_xiaoxiao, zf_xiaoyi (female); zm_yunjian, zm_yunxi, zm_yunxia, zm_yunyang (male). | HIGH       |
| espeak-ng data (bundled)     | Bundled with model download      | Chinese phonemization | The multilingual model requires `espeak-ng-data/` directory and `lexicon-zh.txt` for Chinese text processing. Already part of the model download.                                                                                                                         | HIGH       |

**Integration approach:** The existing sherpa-onnx C API supports Kokoro multilingual models with the same function signatures. The difference is configuration:

```
--kokoro-model=kokoro-multi-lang-v1_0/model.onnx
--kokoro-voices=kokoro-multi-lang-v1_0/voices.bin
--kokoro-tokens=kokoro-multi-lang-v1_0/tokens.txt
--kokoro-data-dir=kokoro-multi-lang-v1_0/espeak-ng-data
--kokoro-lexicon=kokoro-multi-lang-v1_0/lexicon-zh.txt
--sid=45  (zf_xiaobei, for example)
```

Sample rate is 24000 Hz (same as English Kokoro). Audio pipeline needs zero changes.

**Model location:** `~/.local/share/kokoro/models/kokoro-multi-lang-v1_0/` (parallel to existing English model).

**Do NOT use kokoro-multi-lang-v1_1** (103 speakers) unless testing shows v1_0 quality is insufficient. v1_1 is larger and the additional speakers are unnecessary for a fallback engine.

### 4. Bionic Reading Mode (No New Dependencies)

| Technology                             | Version                | Purpose                  | Why                                                                                                                                                                                                                                                                              | Confidence |
| -------------------------------------- | ---------------------- | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| NSAttributedString + NSFont (built-in) | macOS system framework | Bold first-half of words | The bionic reading effect is: bold the first ceil(len/2) characters of each word, regular-weight the rest. NSAttributedString range-based font attribute changes are already used for karaoke highlighting (spike 19: 6us per word update). Same technique, different attribute. | HIGH       |

**Algorithm (no external library needed):**

```swift
func bionicReading(_ text: String) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for word in text.split(separator: " ") {
        let fixation = Int(ceil(Double(word.count) / 2.0))
        let boldPart = NSAttributedString(string: String(word.prefix(fixation)),
                                          attributes: [.font: NSFont.boldSystemFont(ofSize: size)])
        let regularPart = NSAttributedString(string: String(word.dropFirst(fixation)),
                                             attributes: [.font: NSFont.systemFont(ofSize: size)])
        result.append(boldPart)
        result.append(regularPart)
        result.append(NSAttributedString(string: " "))
    }
    return result
}
```

**Do NOT use the Bionic Reading commercial API/SDK.** It requires an API key, adds a network dependency, and the algorithm is trivially implementable in ~15 lines. The open-source `text-vide` JS library confirms the algorithm is just "bold first half of word."

**Interaction with karaoke:** Bionic reading and karaoke highlighting are mutually exclusive display modes. Karaoke uses gold color highlighting on the current word; bionic uses bold/regular weight across all words. Let the user toggle between them.

### 5. Caption History Panel (No New Dependencies)

| Technology                | Version                | Purpose                    | Why                                                                                                                                                                                                                                                                                            | Confidence |
| ------------------------- | ---------------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| NSScrollView + NSTextView | macOS system framework | Scrollable caption history | NSScrollView is the standard AppKit container for scrollable content. Wrapping an NSTextView inside it gives: vertical scrolling, text selection, copy-to-clipboard. The existing subtitle panel uses NSTextField (non-scrollable). Caption history is a separate panel with accumulated text. | HIGH       |

**Implementation pattern:**

```swift
let scrollView = NSScrollView(frame: panelBounds)
scrollView.hasVerticalScroller = true
scrollView.autohidesScrollers = true

let textView = NSTextView(frame: scrollView.contentView.bounds)
textView.isEditable = false
textView.isSelectable = true  // Enable copy
textView.textContainerInset = NSSize(width: 8, height: 8)
textView.isVerticallyResizable = true
textView.autoresizingMask = [.width]
textView.textContainer?.heightTracksTextView = false

scrollView.documentView = textView
```

Key configuration: `heightTracksTextView = false` is critical -- without it, the text view matches the scroll view height and never scrolls. `autoresizingMask = [.width]` makes text wrap to panel width.

**Panel design:** Use a second NSPanel (same `.floating` level as subtitle panel) or embed in the existing panel with a toggle. Second panel is cleaner -- caption history stays visible alongside the current subtitle.

### 6. Focus/DND Awareness (No New Dependencies, Private File Read)

| Technology                         | Version   | Purpose                  | Why                                                                                                                                                                                                                                                                                                                                                          | Confidence |
| ---------------------------------- | --------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| File monitoring of DoNotDisturb DB | macOS 12+ | Detect active Focus mode | **There is no public Apple API to read Focus/DND status on macOS.** Apple's AppIntents Focus framework lets apps define Focus Filters (respond to Focus changes) but requires the app to be a proper AppIntents-registered app with an Info.plist -- not viable for a CLI/daemon. The reliable workaround: read `~/Library/DoNotDisturb/DB/Assertions.json`. | MEDIUM     |

**How it works:**

1. **`~/Library/DoNotDisturb/DB/Assertions.json`** -- contains the currently active Focus mode (if manually set)
2. **`~/Library/DoNotDisturb/DB/ModeConfigurations.json`** -- contains all configured Focus modes with scheduled triggers

Parse `Assertions.json` for active assertions. If none, check `ModeConfigurations.json` for time-based triggers matching the current time.

**File watching integration:** Use the existing `DispatchSource.makeFileSystemObjectSource(.write)` pattern (already validated in spike 15 for JSONL tailing) to watch `Assertions.json` for changes. When Focus activates/deactivates, the file is rewritten.

**Risk:** This is an undocumented file path. Apple could change the location or format in future macOS versions. Wrap in a `FocusDetector` protocol so the implementation can be swapped if Apple provides a public API or changes the file location.

**Fallback behavior:** If the file doesn't exist or can't be parsed, assume Focus is OFF (audio plays normally). Never crash on Focus detection failure.

## Alternatives Considered

| Category        | Recommended                        | Alternative                                       | Why Not                                                                                                                                                                               |
| --------------- | ---------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Concurrency     | Swift Actors                       | Continue with NSLock + @unchecked Sendable        | NSLock blocks threads; actors suspend. Swift 6 strict mode catches data races at compile time only with proper actor isolation, not with manual locks wrapped in @unchecked Sendable. |
| Testing         | Swift Testing + library extraction | XCTest only                                       | Swift Testing has better async support, parameterized tests via `@Test(arguments:)`, and parallel-by-default. XCTest works but is legacy.                                             |
| Chinese TTS     | sherpa-onnx kokoro-multi-lang-v1_0 | Separate Chinese TTS library (e.g., PaddleSpeech) | Already have sherpa-onnx linked. Adding another TTS runtime doubles complexity. Kokoro multilingual uses the same C API.                                                              |
| Bionic Reading  | Custom 15-line implementation      | Bionic Reading commercial SDK                     | SDK requires API key + network. Algorithm is trivial. No reason to add a dependency.                                                                                                  |
| Caption History | NSScrollView + NSTextView          | SwiftUI ScrollView                                | Adding SwiftUI to an AppKit app introduces NSHostingView bridging complexity. NSScrollView is the native AppKit solution and integrates cleanly with existing NSPanel architecture.   |
| Focus Detection | DoNotDisturb DB file monitoring    | AppIntents FocusFilter                            | FocusFilter requires Info.plist + AppIntents registration. Not viable for a CLI/daemon binary. The file monitoring approach works for any process.                                    |

## What NOT to Add

| Technology                        | Why Not                                                                                                                    |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| swift-testing SPM package         | Swift Testing ships with Swift 6.0+ toolchain. Do NOT add `swift-testing` as an SPM dependency -- it is already available. |
| Bionic Reading SDK                | Commercial, requires API key, trivially reimplementable                                                                    |
| SwiftUI                           | Adds NSHostingView bridging for zero benefit. Existing AppKit NSPanel + NSTextField/NSTextView architecture is simpler.    |
| onnxruntime-swift-package-manager | Still conflicts with sherpa-onnx's bundled copy. Same warning as before.                                                   |
| Any Focus/DND third-party library | sindresorhus/do-not-disturb is abandoned (macOS 11 only). The file-read approach is ~30 lines.                             |

## Installation Changes

```bash
# No new SPM dependencies. All new features use:
# - Built-in Swift language features (actors, Swift Testing)
# - Built-in macOS frameworks (NSScrollView, NSTextView, NSFont)
# - Already-linked sherpa-onnx (Chinese model is a data file, not a code dependency)

# New model download for Chinese TTS:
wget -O kokoro-multi-lang-v1_0.tar.bz2 \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2
tar xf kokoro-multi-lang-v1_0.tar.bz2
mv kokoro-multi-lang-v1_0 ~/.local/share/kokoro/models/

# Package.swift change: split executable into CompanionCore library + thin executable
# No new `dependencies:` entries in Package.swift
```

## Sources

- [Swift Actor Proposal (SE-0306)](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md) -- canonical actor semantics reference
- [Approachable Concurrency in Swift 6.2](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/) -- future direction for default MainActor isolation
- [Actor Reentrancy Discussion](https://forums.swift.org/t/actor-reentrancy/59484) -- reentrancy pitfalls and patterns
- [SwiftPM Executable Target Testability Issue #7596](https://github.com/swiftlang/swift-package-manager/issues/7596) -- confirms executable targets cannot be @testable imported
- [Swift Testing vs XCTest](https://blog.micoach.itj.com/swift-testing-vs-xctest) -- comparison and migration guidance
- [sherpa-onnx Kokoro Multilingual Models](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html) -- Chinese model details, speaker IDs, configuration
- [text-vide (Bionic Reading OSS)](https://github.com/Gumball12/text-vide) -- confirms algorithm is "bold first half of word"
- [NSScrollView Documentation](https://developer.apple.com/documentation/appkit/nsscrollview) -- Apple official
- [macOS Focus Mode Detection (JXA gist)](https://gist.github.com/drewkerr/0f2b61ce34e2b9e3ce0ec6a92ab05c18) -- Assertions.json + ModeConfigurations.json approach
- [Apple Developer Forums: DND Detection](https://developer.apple.com/forums/thread/100511) -- confirms no public API, bug closed as "won't fix"
