# Phase 1: Foundation & Build System - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

The project compiles and runs as a macOS accessory app with all dependencies resolved. Package.swift includes swift-telegram-sdk v4.5.0 and sherpa-onnx static lib linker settings. Bridging header imports sherpa-onnx C API and ONNX Runtime C API. Release binary is a single file under 30MB.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion — pure infrastructure phase. Use ROADMAP phase goal, success criteria, and spike findings to guide decisions.

Key spike references:

- Spike 08: Package.swift design with sherpa-onnx linker flags
- Spike 10: Bridging header (`bridge.h`) for sherpa-onnx C API
- Spike 04: swift-telegram-sdk dependency setup
- Stack research: swift-telegram-sdk v4.5.0 (not v3.x from spikes)

</decisions>

<code_context>

## Existing Code Insights

### Reusable Assets

- sherpa-onnx static libraries built at `~/tmp/subtitle-spikes-7aqa/03-textream/sherpa-onnx/build-arm64-apple-darwin/install/`
- Bridging header from Spike 10: `~/tmp/subtitle-spikes-7aqa/10-e2e-flow/bridge.h`
- Package.swift skeleton from Spike 08: see SPIKE-08-INTEGRATION-ARCH.md

### Established Patterns

- cc-skills uses plugin structure: `plugins/{name}/`
- New plugin should be at `plugins/claude-tts-companion/`

### Integration Points

- Plugin must be registered in `.claude-plugin/marketplace.json`
- Plugin needs its own `CLAUDE.md`

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase. Refer to ROADMAP phase description and success criteria.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>
