<!-- # SSoT-OK -->

# Phase 27: MLX Dependency Removal - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase)

<domain>
## Phase Boundary

Remove kokoro-ios, mlx-swift, and MLXUtilsLibrary from Package.swift. Remove all MLX-related imports from CompanionCore source files. Verify `swift build` succeeds with no MLX symbols. Target binary size under 20 MB.

**Why removing MLX:** mlx-swift IOAccelerator leak is by design (+2.3GB/call, ml-explore/mlx #1086). TTS is now delegated to Python MLX server which manages memory correctly. No Swift code needs MLX anymore.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices at Claude's discretion. Key constraints:

- TTSEngine no longer imports KokoroSwift/MLX — it calls Python server via HTTP
- Some files may still have stale MLX imports that compile but are unused — remove all
- Package.swift: remove 3 dependencies (kokoro-ios, mlx-swift, MLXUtilsLibrary) and their .product references from CompanionCore target
- Package.resolved will regenerate automatically after dependency removal
- Tests may reference MLX types — update or remove those tests

</decisions>

<canonical_refs>

## Canonical References

- `plugins/claude-tts-companion/Package.swift` — Remove 3 dependencies
- `plugins/claude-tts-companion/Sources/CompanionCore/*.swift` — Remove MLX imports
- `plugins/claude-tts-companion/Tests/CompanionCoreTests/*.swift` — Update tests
- `.planning/REQUIREMENTS.md` — DEP-01 through DEP-05

</canonical_refs>

<code_context>

## Existing Code Insights

### What to Remove

- `import KokoroSwift` — was used by old TTSEngine for direct MLX synthesis
- `import MLX` — used for MLXArray types in voice embeddings
- `import MLXUtilsLibrary` — used for NpyzReader (voices.npz loading)
- Package.swift: `.package(url: "...kokoro-ios...", ...)`, `.package(url: "...mlx-swift...", ...)`, `.package(url: "...MLXUtilsLibrary...", ...)`

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

_Phase: 27-mlx-dependency-removal_
_Context gathered: 2026-03-28 via auto mode_
