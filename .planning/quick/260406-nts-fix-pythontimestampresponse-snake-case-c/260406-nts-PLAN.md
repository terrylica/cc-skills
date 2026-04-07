---
phase: 260406-nts
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift
autonomous: true
requirements:
  - NTS-01
must_haves:
  truths:
    - "PythonTimestampResponse uses camelCase Swift property names (audioB64, audioDuration, sampleRate)"
    - "JSON keys from Python server (snake_case) still decode correctly via CodingKeys"
    - "swift build succeeds with zero errors"
  artifacts:
    - path: "plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift"
      provides: "PythonTimestampResponse with explicit CodingKeys mapping"
      contains: "enum CodingKeys"
  key_links:
    - from: "PythonTimestampResponse Swift properties"
      to: "Python server JSON keys"
      via: "CodingKeys enum string raw values"
      pattern: 'case audioB64 = "audio_b64"'
---

<objective>
Eliminate the snake_case/camelCase duplicate-naming collision flagged by the telemetry similarity audit: `PythonTimestampResponse` in TTSEngine.swift uses snake_case Swift properties (`audio_b64`, `audio_duration`, `sample_rate`) that are immediately re-mapped to camelCase downstream, creating two names for the same concept.

Purpose: Single canonical Swift naming convention (camelCase) across the codebase. Removes the only real duplicate-naming offender from the audit.

Output: Renamed properties + explicit CodingKeys mapping; updated call sites; clean swift build.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift

<interfaces>
Current state (lines 426-438) — `PythonTimestampWord` is already camelCase (text/onset/duration), no changes needed:

```swift
private struct PythonTimestampWord: Codable {
    let text: String
    let onset: Double
    let duration: Double
}

private struct PythonTimestampResponse: Codable {
    let audio_b64: String          // ← rename
    let words: [PythonTimestampWord]
    let audio_duration: Double     // ← rename
    let sample_rate: Int           // ← rename
}
```

Call sites that read the snake_case properties (must update):

- Line 493: `tsResponse.audio_b64` → `tsResponse.audioB64`
- Line 506: `tsResponse.audio_duration` → `tsResponse.audioDuration`
- `sample_rate` is declared but never read — keep it (matches server contract) but rename for consistency.

Decoder (line 491) is `JSONDecoder()` constructed locally. Per task brief, prefer Option A (explicit CodingKeys) over Option B (`.convertFromSnakeCase`) for self-documentation and zero accidental scope creep.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Rename PythonTimestampResponse properties to camelCase + add CodingKeys</name>
  <files>plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift</files>
  <action>
Edit `PythonTimestampResponse` struct (lines 433-438) to use camelCase Swift property names with an explicit `CodingKeys` enum mapping to the Python server's snake_case JSON keys:

```swift
private struct PythonTimestampResponse: Codable {
    let audioB64: String
    let words: [PythonTimestampWord]
    let audioDuration: Double
    let sampleRate: Int

    enum CodingKeys: String, CodingKey {
        case audioB64 = "audio_b64"
        case words
        case audioDuration = "audio_duration"
        case sampleRate = "sample_rate"
    }
}
```

Then update the two call sites that read the renamed properties:

- Line 493: `tsResponse.audio_b64` → `tsResponse.audioB64`
- Line 506: `tsResponse.audio_duration` → `tsResponse.audioDuration`

Do NOT touch:

- `PythonTimestampWord` (already camelCase: text/onset/duration)
- The Python server source
- The HTTP request body dictionary at line 460-466 (those are JSON keys sent TO the server, not Swift property names)
- Any sherpa-onnx C API references to `sample_rate` (that's C code in CSherpaOnnx, out of scope)

Rationale for CodingKeys (Option A) over `decoder.keyDecodingStrategy = .convertFromSnakeCase` (Option B): explicit, self-documenting, scoped to this one struct, cannot accidentally affect other Codable types if more are added later.
</action>
<verify>
<automated>cd plugins/claude-tts-companion && swift build 2>&1 | tee /tmp/nts-build.log && ! grep -E "error:" /tmp/nts-build.log</automated>
</verify>
<done>

- `PythonTimestampResponse` declares `audioB64`, `audioDuration`, `sampleRate` (camelCase)
- `CodingKeys` enum maps each to its snake_case JSON key
- All references to `tsResponse.audio_b64` / `tsResponse.audio_duration` updated to camelCase
- `swift build` exits 0 with no errors
- `grep -n "audio_b64\|audio_duration\|sample_rate" Sources/CompanionCore/TTSEngine.swift` returns only the comment on line 67 and the CodingKeys raw-value strings
  </done>
  </task>

</tasks>

<verification>
1. `cd plugins/claude-tts-companion && swift build` — must compile cleanly (zero errors).
2. `grep -n "tsResponse\.\(audio_b64\|audio_duration\|sample_rate\)" Sources/CompanionCore/TTSEngine.swift` — must return zero matches (all call sites updated).
3. `grep -n "let audio_b64\|let audio_duration\|let sample_rate" Sources/CompanionCore/TTSEngine.swift` — must return zero matches (struct fields renamed).
4. `grep -n "case audioB64 = \"audio_b64\"" Sources/CompanionCore/TTSEngine.swift` — must match (CodingKeys present).
</verification>

<success_criteria>

- swift build succeeds with zero errors and zero new warnings
- PythonTimestampResponse uses camelCase Swift property names exclusively
- Python server JSON contract preserved via CodingKeys (no behavioral change at the wire)
- Telemetry audit's single real duplicate-naming finding resolved
- No changes outside `plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift`
  </success_criteria>

<output>
After completion, create `.planning/quick/260406-nts-fix-pythontimestampresponse-snake-case-c/260406-nts-01-SUMMARY.md` documenting:
- Properties renamed (before → after)
- Call sites updated (line numbers)
- Build verification result
- Confirmation that PythonTimestampWord required no changes
</output>
