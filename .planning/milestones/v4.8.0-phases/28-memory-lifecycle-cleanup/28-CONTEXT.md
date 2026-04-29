<!-- # SSoT-OK -->

# Phase 28: Memory Lifecycle Cleanup - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase)

<domain>
## Phase Boundary

Remove all IOAccelerator leak mitigation code from the Swift companion. With MLX removed (Phase 27), there is no Metal GPU memory leak — the synthesis-count restart, exit(42), and checkMemoryLifecycleRestart() are all dead code. Swift companion should stay under 100 MB RSS indefinitely.

**Why this cleanup:** The exit(42) restart hack was a workaround for mlx-swift's IOAccelerator leak (+2.3GB/call). Now that TTS delegates to Python (which handles its own memory correctly), the Swift process never touches Metal GPU buffers. The restart code is dead weight that adds complexity and causes 2s service interruptions.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices at Claude's discretion. Key items:

- Remove `MemoryLifecycle.swift` (or reduce to no-op)
- Remove `synthesisCount`, `shouldRestartForMemory`, `maxSynthesisBeforeRestart`, `memoryDiagnostics()` from TTSEngine
- Remove `checkMemoryLifecycleRestart()` calls from CompanionApp/TelegramBot/HTTPControlServer
- Remove `exit(42)` and `plannedRestart()` from CompanionApp
- Update launchd plist if ThrottleInterval was tuned for restart speed
- Verify RSS stays under 100 MB after 50+ TTS calls via the Python delegation path

</decisions>

<canonical_refs>

## Canonical References

- `plugins/claude-tts-companion/Sources/CompanionCore/MemoryLifecycle.swift` — Delete or gut
- `plugins/claude-tts-companion/Sources/CompanionCore/TTSEngine.swift` — Remove synthesis counter + restart logic
- `plugins/claude-tts-companion/Sources/CompanionCore/CompanionApp.swift` — Remove plannedRestart(), checkMemoryLifecycleRestart()
- `plugins/claude-tts-companion/Sources/CompanionCore/TelegramBot.swift` — Remove memory check calls
- `plugins/claude-tts-companion/Sources/CompanionCore/HTTPControlServer.swift` — Remove memory check calls
- `.planning/REQUIREMENTS.md` — MEM-01, MEM-02, MEM-03

</canonical_refs>

<code_context>

## Existing Code Insights

### What to Remove

- `MemoryLifecycle.swift` — cross-module restart trigger
- `exit(42)` in CompanionApp — launchd restart signal
- `synthesisCount` / `maxSynthesisBeforeRestart` / `shouldRestartForMemory` in TTSEngine
- `checkMemoryLifecycleRestart()` calls in TelegramBot and HTTPControlServer
- `/health` endpoint fields: `tts_synthesis_count`, `tts_restart_threshold` (optional — may keep for diagnostics)

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond ROADMAP success criteria.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

_Phase: 28-memory-lifecycle-cleanup_
_Context gathered: 2026-03-28 via auto mode_
