# CLAUDE.md

Claude Code skills marketplace: **25 plugins** with skills for ADR-driven development workflows.

**Architecture**: Link Farm + Hub-and-Spoke with Progressive Disclosure

## Documentation Hierarchy

```
CLAUDE.md (this file)                  ◄── Hub: Navigation + Essentials
    │
    ├── plugins/CLAUDE.md              ◄── Spoke: Plugin development (all 24 plugins listed)
    │       ├── {plugin}/CLAUDE.md     ◄── Deep: Each of the 24 plugins has its own CLAUDE.md
    │       └── (see Navigation table below for key plugin docs)
    │
    └── docs/CLAUDE.md                 ◄── Spoke: Documentation standards
            ├── HOOKS.md               ◄── Hook development patterns
            ├── RELEASE.md             ◄── Release workflow
            ├── PLUGIN-LIFECYCLE.md    ◄── Plugin internals
            └── LESSONS.md             ◄── Lessons learned (extracted from root)
```

## Navigation

### Spokes & Docs

| Topic             | Document                                                                                                                     |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Installation      | [README.md](./README.md)                                                                                                     |
| Plugin Dev        | [plugins/CLAUDE.md](./plugins/CLAUDE.md)                                                                                     |
| Documentation     | [docs/CLAUDE.md](./docs/CLAUDE.md)                                                                                           |
| Hooks Dev         | [docs/HOOKS.md](./docs/HOOKS.md)                                                                                             |
| Lessons Learned   | [docs/LESSONS.md](./docs/LESSONS.md)                                                                                         |
| Cargo TTY Fix     | [docs/cargo-tty-suspension-prevention.md](./docs/cargo-tty-suspension-prevention.md)                                         |
| Claude Code Proxy | [devops-tools/skills/claude-code-proxy-patterns/SKILL.md](./plugins/devops-tools/skills/claude-code-proxy-patterns/SKILL.md) |
| Release           | [docs/RELEASE.md](./docs/RELEASE.md)                                                                                         |
| Plugin Lifecycle  | [docs/PLUGIN-LIFECYCLE.md](./docs/PLUGIN-LIFECYCLE.md)                                                                       |
| Troubleshooting   | [docs/troubleshooting/](./docs/troubleshooting/)                                                                             |
| ADRs              | [docs/adr/](./docs/adr/)                                                                                                     |
| Resume Context    | [docs/RESUME.md](./docs/RESUME.md)                                                                                           |

### Plugin CLAUDE.md Files (25/25)

All 25 plugins have their own CLAUDE.md with Hub+Sibling navigation links. Access via `plugins/{name}/CLAUDE.md` or browse the full table in [plugins/CLAUDE.md](./plugins/CLAUDE.md).

Key plugin docs: [itp](./plugins/itp/CLAUDE.md) | [itp-hooks](./plugins/itp-hooks/CLAUDE.md) | [gh-tools](./plugins/gh-tools/CLAUDE.md) | [devops-tools](./plugins/devops-tools/CLAUDE.md) | [gmail-commander](./plugins/gmail-commander/CLAUDE.md) | [tts-tg-sync](./plugins/tts-tg-sync/CLAUDE.md) | [calcom-commander](./plugins/calcom-commander/CLAUDE.md)

## Essential Commands

| Task             | Command                            |
| ---------------- | ---------------------------------- |
| Validate plugins | `bun scripts/validate-plugins.mjs` |
| Release (full)   | `mise run release:full`            |
| Release (dry)    | `mise run release:dry`             |
| Execute workflow | `/itp:go feature-name -b`          |
| Setup env        | `/itp:setup`                       |
| Add plugin       | `/plugin-dev:create plugin-name`   |
| Autonomous mode  | `/ru:start` / `/ru:stop`           |

## Plugin Discovery

**SSoT**: `.claude-plugin/marketplace.json`

```bash
# Validate before commit
bun scripts/validate-plugins.mjs
```

Missing marketplace.json entry = "Plugin not found". See [plugins/CLAUDE.md](./plugins/CLAUDE.md).

## Directory Structure

```
cc-skills/
├── .claude-plugin/marketplace.json  ← Plugin registry (SSoT)
├── plugins/                         ← 25 marketplace plugins (each has CLAUDE.md)
│   ├── itp/                         ← Core 4-phase workflow
│   ├── itp-hooks/                   ← Workflow enforcement + code correctness
│   ├── ru/                          ← RU autonomous loop mode
│   ├── mise/                        ← User-global mise workflow commands
│   ├── gemini-deep-research/        ← Gemini Deep Research browser automation
│   ├── gmail-commander/             ← Gmail bot + CLI (1Password OAuth)
│   └── ...                          ← 19 more plugins
├── docs/
│   ├── adr/                         ← Architecture Decision Records
│   ├── design/                      ← Implementation specs (1:1 with ADRs)
│   ├── HOOKS.md                     ← Hook development patterns
│   ├── RELEASE.md                   ← Release workflow
│   ├── PLUGIN-LIFECYCLE.md          ← Plugin internals
│   └── LESSONS.md                   ← Lessons learned
└── .mise/tasks/                     ← Release automation
```

## Key Files

| File                                   | Purpose                 |
| -------------------------------------- | ----------------------- |
| `.claude-plugin/marketplace.json`      | Plugin registry (SSoT)  |
| `.releaserc.yml`                       | semantic-release config |
| `scripts/validate-plugins.mjs`         | Plugin validation       |
| `scripts/sync-hooks-to-settings.sh`    | Hook synchronization    |
| `scripts/sync-commands-to-settings.sh` | Command synchronization |

## Link Conventions

| Context        | Format    | Example                          |
| -------------- | --------- | -------------------------------- |
| Skill-internal | Relative  | `[Guide](./references/guide.md)` |
| Repo docs      | Repo-root | `[ADR](/docs/adr/file.md)`       |
| External       | Full URL  | `[Docs](https://example.com)`    |

## Development Toolchain

**Bun-First Policy** (2025-01-12): JavaScript global packages installed via `bun add -g`.

```bash
bun add -g prettier          # Install
bun update -g                # Upgrade all
bun pm ls -g                 # List
```

**Auto-upgrade**: `com.terryli.mise_autoupgrade` runs every 2 hours.

## Lessons Learned

See [docs/LESSONS.md](./docs/LESSONS.md).

<!-- GSD:project-start source:PROJECT.md -->
## Project

**claude-tts-companion**

A single Swift binary that consolidates the Telegram session bot, Kokoro TTS engine, and a new subtitle overlay into one macOS launchd service. Replaces three separate processes (Swift runner + Bun/TypeScript bot + Python TTS server) with a unified ~27MB idle / 561MB peak binary. Includes word-level karaoke subtitles synced with TTS playback for silent-mode session consumption.

**Core Value:** **See what Claude says, anywhere** — real-time karaoke subtitles overlaid on your macOS screen, synced with TTS playback or displayed standalone when audio is off. One binary, one service, one control surface.

### Constraints

- **Platform**: macOS Apple Silicon only (Apple Silicon required for sherpa-onnx/MLX)
- **macOS version**: macOS 14+ (for swift-telegram-sdk, sherpa-onnx)
- **Python**: Not used — pure Swift + C (sherpa-onnx static libs)
- **Build**: `swift build` via SwiftPM (not Xcode) for the main binary; sherpa-onnx C++ libs pre-built
- **Model**: Kokoro int8 English at `~/.local/share/kokoro/models/kokoro-int8-en-v0_19/` (129MB on disk)
- **Display**: Default to MacBook built-in (2056x1329), configurable to external via SwiftBar
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Language & Runtime
| Technology | Version                          | Purpose          | Why                                                                                                                                                                                                                                | Confidence |
| ---------- | -------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| Swift      | 6.0+                             | Primary language | Unifies all three replaced runtimes (Swift/TypeScript/Python) into one binary. Swift 6 gives strict concurrency checking, which prevents data races in our multi-threaded architecture (main thread UI + background bot/TTS/HTTP). | HIGH       |
| SwiftPM    | swift-tools-version: 6.0         | Build system     | Spike 08 validated this. No Xcode project needed. `swift build` produces the binary directly.                                                                                                                                      | HIGH       |
| macOS 14+  | Deployment target `.macOS(.v14)` | Minimum OS       | Required by swift-telegram-sdk (Swift 6 concurrency runtime). Spike 08 confirmed macOS 14 as the correct floor. Your machine runs macOS 14+. No reason to support older.                                                           | HIGH       |
### Telegram Bot
| Technology                                                        | Version               | Purpose                  | Why                                                                                                                                                                                                                                                               | Confidence |
| ----------------------------------------------------------------- | --------------------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| [swift-telegram-sdk](https://github.com/nerzh/swift-telegram-sdk) | 4.5.0 (from: "4.5.0") | Telegram Bot API wrapper | Spike 04 validated: 4.5MB binary, 8.6MB RSS. Long polling works without Vapor/SwiftNIO. Only dependency is swift-log + swift-regular-expression. Implements Telegram Bot API 9.5. The `TGClientPrtcl` approach lets you use pure URLSession (88 lines, spike 04). | HIGH       |
### TTS Engine
| Technology                                           | Version                           | Purpose                               | Why                                                                                                                                                                                                                                               | Confidence |
| ---------------------------------------------------- | --------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | 1.12.33 (built from source)       | Kokoro TTS synthesis via ONNX Runtime | Validated across spikes 03, 09, 10, 13b, 16, 19. Int8 quantized model cuts peak RSS to 561MB. Static linking avoids dylib hell. The ~50-line C++ patch (spike 16) enables word-level timestamps from the duration model -- zero-drift, zero-cost. | HIGH       |
| ONNX Runtime                                         | Bundled with sherpa-onnx (static) | ML inference backend                  | Comes as `libonnxruntime.a` in the sherpa-onnx build. Do NOT add the separate `onnxruntime-swift-package-manager` SPM package -- it would conflict with sherpa-onnx's bundled copy.                                                               | HIGH       |
### Subtitle Overlay
| Technology         | Version                | Purpose                         | Why                                                                                                                                                                                                                                | Confidence |
| ------------------ | ---------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| AppKit NSPanel     | macOS system framework | Always-on-top subtitle window   | Spike 02: 88KB binary, 19MB RSS. NSPanel with `.floating` level + `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]` gives always-visible overlay. `sharingType = .none` auto-hides during screen sharing (spike 21). | HIGH       |
| NSAttributedString | macOS system framework | Word-level karaoke highlighting | Spike 19: gold highlighting at 6us per word update (37x headroom). NSAttributedString range-based styling is the right abstraction for karaoke.                                                                                    | HIGH       |
### HTTP Control API
| Technology                                        | Version                 | Purpose                 | Why                                                                                                                                                                                                                                    | Confidence |
| ------------------------------------------------- | ----------------------- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| [FlyingFox](https://github.com/swhitty/FlyingFox) | 0.26.2 (from: "0.26.0") | Lightweight HTTP server | Pure BSD sockets + Swift Concurrency. Zero dependencies (no SwiftNIO, no Vapor). Spike 08 designed for raw BSD sockets; FlyingFox wraps them with a clean async/await API while adding zero framework overhead. Supports macOS 10.15+. | MEDIUM     |
### File Watching
| Technology                | Version                | Purpose                                 | Why                                                                                                                                                                 | Confidence |
| ------------------------- | ---------------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| DispatchSource + FSEvents | macOS system framework | Watch notification files, JSONL tailing | Spike 15 validated offset-based JSONL tailing at 0.34ms P95. `DispatchSource.makeFileSystemObjectSource(.write)` is the correct API. No third-party library needed. | HIGH       |
### Logging
| Technology                                      | Version                | Purpose                   | Why                                                                                                                                                                                                                                                                 | Confidence |
| ----------------------------------------------- | ---------------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| [swift-log](https://github.com/apple/swift-log) | 1.10.1 (from: "1.6.0") | Structured logging facade | Already a transitive dependency of swift-telegram-sdk. Use it directly rather than adding a second logging system. Apple's standard logging API for server/CLI Swift. Configure with `StreamLogHandler.standardError` for launchd (stderr goes to ASL/Console.app). | HIGH       |
### Audio Playback
| Technology                   | Version                | Purpose      | Why                                                                                                                                                                                                 | Confidence |
| ---------------------------- | ---------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| AVFoundation (AVAudioPlayer) | macOS system framework | WAV playback | Spike 10 validated: plays 24kHz mono 16-bit WAV from sherpa-onnx output. Alternative `afplay` subprocess works but AVAudioPlayer gives programmatic control (pause, current time for karaoke sync). | HIGH       |
### AI / MiniMax API
| Technology | Version                | Purpose                              | Why                                                                                                                                              | Confidence |
| ---------- | ---------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| URLSession | macOS system framework | MiniMax API calls, session summaries | Spike 11 validated MiniMax integration from Swift. URLSession handles HTTPS, JSON encoding/decoding, async/await. No HTTP client library needed. | HIGH       |
### CLI Arguments (Optional)
| Technology                                                              | Version               | Purpose                    | Why                                                                                                                                                                                      | Confidence |
| ----------------------------------------------------------------------- | --------------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.7.1 (from: "1.5.0") | CLI flags for debug/config | Only needed if you want `claude-tts-companion --port 8780 --model-path /path`. For a launchd service that reads config from a plist or JSON file, this is optional. Add later if needed. | MEDIUM     |
## Stack NOT to Use
| Technology          | Why Not                                                                                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Vapor / Hummingbird | Pulls in SwiftNIO + massive dependency tree. The HTTP API is 4-5 endpoints, not a web application. Overkill.                                                              |
| SwiftNIO            | Adds complexity without benefit. BSD sockets (or FlyingFox) handle the load. You're serving ~1 req/sec from SwiftBar, not thousands.                                      |
| CoreML / FluidAudio | Spike 05 evaluated and rejected. CoreML models are 3.9GB vs 129MB for sherpa-onnx int8. FluidAudio has no Swift API.                                                      |
| Electron / Tauri    | Native AppKit NSPanel is 88KB vs hundreds of MB. No web runtime needed for a text overlay.                                                                                |
| SwiftUI             | No benefit for the overlay (single NSPanel + NSTextField). SwiftUI's layout system adds overhead for zero gain. AppKit is simpler here.                                   |
| Telegrammer         | Abandoned (last commit 2021). swift-telegram-sdk is the only actively maintained option.                                                                                  |
| TDLibKit            | Full Telegram client library (TDLib C++). Overkill -- you need Bot API, not client API.                                                                                   |
| os.log / OSLog      | Good for app debugging, but launchd services benefit from swift-log's StreamLogHandler which writes to stderr (captured by launchd). os.log requires Console.app to read. |
## Package.swift Structure
## Dependency Tree (Total)
## Build & Run
# Build (debug)
# Build (release, stripped)
# Run
# Install as launchd service
# Use existing plist pattern from com.terryli.telegram-bot
## Binary Size & Memory Targets
| Metric                 | Target    | Source                                                        |
| ---------------------- | --------- | ------------------------------------------------------------- |
| Binary size (stripped) | ~19-25 MB | Spike 03: 19MB for TTS alone                                  |
| Idle RSS               | ~27 MB    | Spike 02 (19MB subtitle) + spike 04 (8.6MB bot) share runtime |
| Peak RSS (synthesis)   | ~561 MB   | Spike 09: int8 quantized model                                |
| Model load time        | ~0.56s    | Spike 03 (lazy, on first TTS request)                         |
## Sources
- [sherpa-onnx v1.12.33](https://github.com/k2-fsa/sherpa-onnx/releases) -- verified March 24, 2026
- [swift-telegram-sdk v4.5.0](https://github.com/nerzh/swift-telegram-sdk/releases) -- verified March 1, 2026
- [swift-log v1.10.1](https://github.com/apple/swift-log/releases) -- verified February 16, 2025
- [swift-argument-parser v1.7.1](https://github.com/apple/swift-argument-parser/releases) -- verified March 20, 2025
- [FlyingFox v0.26.2](https://github.com/swhitty/FlyingFox) -- verified January 17, 2025
- [ONNX Runtime SPM v1.24.2](https://github.com/microsoft/onnxruntime-swift-package-manager/releases) -- NOT recommended (conflicts with sherpa-onnx bundled copy)
- Spike 08: Integration Architecture -- validated dependency conflicts, Package.swift design
- Spike 04: Swift Telegram Bot -- validated long polling without Vapor
- Spike 02: Swift Subtitle Overlay -- validated NSPanel approach
- Spike 03/09: sherpa-onnx TTS -- validated synthesis and int8 quantization
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
