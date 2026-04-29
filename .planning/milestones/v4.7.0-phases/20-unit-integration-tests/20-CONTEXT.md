# Phase 20: Unit & Integration Tests - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Full test coverage for the decomposed components from Phase 19. Unit tests for SubtitleChunker (page splitting, line breaks, font sizes), WordTimingAligner (MToken alignment, onset resolution, hyphenated words), PronunciationProcessor (override matching, regex boundaries). Integration test for the streaming pipeline (mock synthesis, verify chunk sequencing).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — pure test-writing phase. Use ROADMAP success criteria and existing test patterns from Phase 18 (Swift Testing framework, @testable import CompanionCore) to guide decisions.

Key constraints from prior phases:

- Swift Testing framework (not XCTest) — established in Phase 18
- `@testable import CompanionCore` pattern for accessing internals
- `@MainActor @Suite(.serialized)` for types that touch AppKit (SubtitleChunker)
- Phase 19 decomposed TTSEngine into pure structs — WordTimingAligner, PronunciationProcessor, SentenceSplitter are all testable without mocking

</decisions>

<canonical_refs>

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Source Code

- `plugins/claude-tts-companion/Sources/CompanionCore/WordTimingAligner.swift` — Pure struct to test (ARCH-03)
- `plugins/claude-tts-companion/Sources/CompanionCore/PronunciationProcessor.swift` — Pure struct to test (ARCH-04)
- `plugins/claude-tts-companion/Sources/CompanionCore/SubtitleChunker.swift` — @MainActor type to test
- `plugins/claude-tts-companion/Sources/CompanionCore/SentenceSplitter.swift` — Pure struct to test
- `plugins/claude-tts-companion/Tests/CompanionCoreTests/` — Existing test files from Phase 18

### Project Context

- `.planning/ROADMAP.md` — Phase 20 success criteria (TEST-02, TEST-03, TEST-04, TEST-05)
- `.planning/REQUIREMENTS.md` — Test requirement definitions

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- 5 test files from Phase 18: LanguageDetectorTests, SubtitleChunkerTests, TelegramFormatterTests, TranscriptParserTests, CircuitBreakerTests
- Swift Testing framework already configured in Package.swift
- `@MainActor @Suite(.serialized)` pattern established for SubtitleChunker

### Established Patterns

- One test file per type
- `@testable import CompanionCore`
- Pure struct tests need no special isolation
- AppKit-dependent tests need `@MainActor @Suite(.serialized)`

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase. Follow ROADMAP success criteria exactly.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>

---

_Phase: 20-unit-integration-tests_
_Context gathered: 2026-03-28 via auto mode (infrastructure phase)_
