# Phase 18: CompanionCore Library & Test Infrastructure - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 18-companioncore-library-test-infrastructure
**Areas discussed:** Initial test targets, main.swift residual scope, Access control strategy

---

## Initial Test Targets

| Option                             | Description                                                                   | Selected |
| ---------------------------------- | ----------------------------------------------------------------------------- | -------- |
| LanguageDetector + SubtitleChunker | Both pure functions, no dependencies. Best bang-for-buck proof of swift test. | ✓        |
| TelegramFormatter                  | String transformation with many edge cases. High test value but more complex. | ✓        |
| TranscriptParser                   | JSONL parsing into enums. Needs fixture data but self-contained.              | ✓        |
| CircuitBreaker                     | State machine with time-based transitions. May need clock injection.          | ✓        |

**User's choice:** All four types selected for initial tests
**Notes:** More coverage than minimum success criteria ("at least one unit test"), but all are pure types so straightforward to test.

---

## main.swift Residual Scope

| Option                       | Description                                                                                                               | Selected |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------- | -------- |
| Ultra-thin: lifecycle only   | main.swift keeps ONLY NSApplication setup, SIGTERM handler, run loop (~50 lines). All wiring moves to CompanionApp class. | ✓        |
| Thin: lifecycle + wiring     | Keep app lifecycle AND component creation/wiring (~80 lines). Notification closure stays.                                 |          |
| Moderate: keep orchestration | Move types and helpers only. Keep notification watcher closure and plannedRestart in main.swift.                          |          |

**User's choice:** Ultra-thin: lifecycle only
**Notes:** CompanionApp class in CompanionCore handles all wiring and orchestration.

---

## Access Control Strategy

| Option                         | Description                                                                 | Selected |
| ------------------------------ | --------------------------------------------------------------------------- | -------- |
| Public types, internal members | Mark types as public, keep methods internal. Tests use @testable import.    | ✓        |
| Blanket public everything      | All types AND methods public. Simplest but constrains Phase 19 refactoring. |          |
| Package access level           | Swift 5.9+ `package` modifier. May be redundant with @testable.             |          |

**User's choice:** Public types, internal members
**Notes:** Clean API surface. @testable import grants test access to internals. main.swift only needs public CompanionApp facade.

---

## Claude's Discretion

- CompanionApp class vs bootstrap() function
- Test file organization (per-type vs grouped)
- CircuitBreaker clock abstraction approach

## Deferred Ideas

None — discussion stayed within phase scope
