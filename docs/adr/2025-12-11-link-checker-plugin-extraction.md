---
status: accepted
date: 2025-12-11
decision-maker: [Terry Li]
consulted:
  [
    Explore-Architecture,
    Explore-itp-hooks-Pattern,
    Explore-Python-Utilities,
    Plan-LinkChecker,
    Plan-NotificationTools,
    Plan-SQLiteMigration,
  ]
research-method: 9-agent-parallel-dctl
clarification-iterations: 4
perspectives: [ProviderToOtherComponents, EcosystemArtifact]
---

# ADR: Link Checker Plugin Extraction from Claude-Orchestrator

**Design Spec**: [Implementation Spec](/docs/design/2025-12-11-link-checker-plugin-extraction/spec.md)

## Context and Problem Statement

The `claude-orchestrator` system (~9,000 lines) contains a powerful link validation hook (`check-links-hybrid.sh`, 1,041 lines) that runs lychee on markdown files at session end. This capability is tightly coupled to the orchestrator's Telegram bot, workflow menus, and state management infrastructure.

**Problem**: Users cannot benefit from link validation without installing the entire orchestrator system with its 40+ files, Python dependencies, and Telegram integration.

**Goal**: Extract a standalone, portable link-checker plugin for the cc-skills marketplace that:

1. Works independently of claude-orchestrator
2. Provides JSON output consumable by other tools
3. Follows cc-skills plugin conventions (`${CLAUDE_PLUGIN_ROOT}`, hooks.json)
4. Maintains lychee validation + path policy checking capabilities

### Before/After

**Before: Tightly Coupled**

```
⏮️ Before: Tightly Coupled

┌─────────────────────┐     ┌───────────────────────┐     ┌──────────────┐     ┌──────┐
│ claude-orchestrator │     │ check-links-hybrid.sh │     │ Telegram Bot │     │ User │
│                     │ ──> │     (1,041 lines)     │ ──> │              │ ──> │      │
└─────────────────────┘     └───────────────────────┘     └──────────────┘     └──────┘
                              │
                              │
                              ∨
                            ┌───────────────────────┐
                            │    SessionSummary     │
                            └───────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Tightly Coupled"; flow: east; }
[ claude-orchestrator ] -> [ check-links-hybrid.sh\n(1,041 lines) ] -> [ Telegram Bot ] -> [ User ]
[ check-links-hybrid.sh\n(1,041 lines) ] -> [ SessionSummary ]
```

</details>

**After: Decoupled Plugin**

```
⏭️ After: Decoupled Plugin

┌─────────────────────┐     ╭─────────────────────╮     ┌─────────────┐     ┌──────────────┐
│ claude-orchestrator │     │ link-checker plugin │     │ JSON Output │     │ Any Consumer │
│                     │ ··> │    (~300 lines)     │ ──> │             │ ──> │              │
└─────────────────────┘     ╰─────────────────────╯     └─────────────┘     └──────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Decoupled Plugin"; flow: east; }
[ link-checker plugin\n(~300 lines) ] { shape: rounded; } -> [ JSON Output ] -> [ Any Consumer ]
[ claude-orchestrator ] ..> [ link-checker plugin\n(~300 lines) ]
```

</details>

## Research Summary

| Agent Perspective         | Key Finding                                                     | Confidence |
| ------------------------- | --------------------------------------------------------------- | ---------- |
| Explore-Architecture      | Orchestrator is 3-tier: Hook → Bot → Orchestrator (~9,000 LOC)  | High       |
| Explore-itp-hooks-Pattern | itp-hooks proves minimal plugin pattern works (~226 lines bash) | High       |
| Explore-Python-Utilities  | 32 Python files (5,141 lines), 5 have PEP 723 headers           | High       |
| Plan-LinkChecker          | Python hook (PEP 723) better than 1,041-line bash               | High       |
| Plan-NotificationTools    | Bot should consume hook output via files (decoupled)            | High       |
| Plan-SQLiteMigration      | Callbacks migration is independent concern                      | Medium     |

## Decision Log

| Decision Area     | Options Evaluated                     | Chosen            | Rationale                                           |
| ----------------- | ------------------------------------- | ----------------- | --------------------------------------------------- |
| Hook language     | Bash (current), Python (PEP 723)      | Python (PEP 723)  | Cleaner than 1,041-line bash, lychee is slow anyway |
| Output format     | JSON stdout, file only, dual          | JSON + files      | Consumable by other systems                         |
| Config resolution | Single config, cascade                | Cascade           | Repo → workspace → plugin default flexibility       |
| Integration point | Stop only, Stop + PostToolUse         | Stop only         | Full validation at session end, avoid per-edit cost |
| Dependencies      | Pure bash, minimal Python, full stack | Full Python stack | User preference, enables PEP 723 tracing utilities  |

### Trade-offs Accepted

| Trade-off                    | Choice        | Accepted Cost                        |
| ---------------------------- | ------------- | ------------------------------------ |
| Simplicity vs Features       | Features      | More code than minimal bash approach |
| Startup time vs Capability   | Capability    | ~100ms Python startup vs ~5ms bash   |
| Portability vs Observability | Observability | Requires Python 3.11+ and uv         |

## Decision Drivers

- User wants universal link validation without orchestrator dependency
- Plugin must work in cc-skills marketplace ecosystem
- JSON output enables future integrations (Telegram, GitHub Issues, etc.)
- Existing orchestrator must continue functioning during transition

## Considered Options

- **Option A**: Pure bash minimal hook (~150 lines)
  - Pro: Fast startup, no Python dependency
  - Con: Complex JSON handling, limited tracing

- **Option B**: Python hook with PEP 723 (full stack) <- Selected
  - Pro: Clean code, ULID tracing, event logging
  - Con: Requires Python 3.11+ and uv

- **Option C**: Keep tightly coupled in orchestrator
  - Pro: No extraction work needed
  - Con: Users must install entire orchestrator for link checking

## Decision Outcome

Chosen option: **Option B (Python hook with PEP 723)**, because:

1. User explicitly chose "Keep full Python stack" during planning
2. Python enables clean lychee subprocess management
3. PEP 723 inline deps provide self-contained execution (`uv run`)
4. ULID tracing enables correlation across system components
5. Lychee is inherently slow (seconds), so Python's ~100ms overhead is negligible

## Synthesis

**Convergent findings**: All perspectives agreed that:

- Link validation should be extractable as standalone plugin
- Output must be JSON for programmatic consumption
- Orchestrator's Telegram integration is separate concern

**Divergent findings**:

- Plan-LinkChecker suggested bash might be simpler
- User preference overrode this for full Python stack

**Resolution**: User decided on Python (PEP 723) with full tracing capabilities.

## Consequences

### Positive

- Universal link validation available to all cc-skills users
- JSON output enables new integrations without code changes
- Clear separation of concerns (validation vs notification)
- Orchestrator can eventually consume plugin output

### Negative

- Requires Python 3.11+ and uv (not just bash)
- Two link check implementations during transition period
- Users must install lychee separately

## Architecture

```
🏗️ Link-Checker Plugin Architecture

                                                 ╭───────────────────────╮
                                                 │ Claude Code Stop Hook │
                                                 ╰───────────────────────╯
                                                   │
                                                   ∨
┌────────────────┐     ┌────────────────┐     ┌───────────────────────┐     ┌─────────────┐
│ Markdown Files │     │ path_linter.py │     │  stop-link-check.py   │     │ ulid_gen.py │
│                │ <── │                │ <── │       (PEP 723)       │ ──> │             │
└────────────────┘     └────────────────┘     └───────────────────────┘     └─────────────┘
                         │                      │
                         │                      ∨
                         │                    ┌───────────────────────┐     ┌─────────────┐
                         │                    │   lychee_runner.py    │ ──> │ lychee CLI  │
                         │                    └───────────────────────┘     └─────────────┘
                         │                      │
                         │                      ∨
                         │                    ╔═══════════════════════╗
                         └──────────────────> ║     JSON Results      ║
                                              ╚═══════════════════════╝
                                                │
                                                ∨
                                              ┌───────────────────────┐
                                              │    stdout / files     │
                                              └───────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ Link-Checker Plugin Architecture"; flow: south; }
[ Claude Code Stop Hook ] { shape: rounded; } -> [ stop-link-check.py\n(PEP 723) ]
[ stop-link-check.py\n(PEP 723) ] -> [ path_linter.py ] -> [ Markdown Files ]
[ stop-link-check.py\n(PEP 723) ] -> [ lychee_runner.py ] -> [ lychee CLI ]
[ stop-link-check.py\n(PEP 723) ] -> [ ulid_gen.py ]
[ path_linter.py ] -> [ JSON Results ] { shape: dblframe; }
[ lychee_runner.py ] -> [ JSON Results ]
[ JSON Results ] -> [ stdout / files ]
```

</details>

## References

- [Global Plan](/docs/design/2025-12-11-link-checker-plugin-extraction/spec.md) - Full implementation specification
- [claude-orchestrator](https://github.com/terrylica/claude-orchestrator) - Source system
- [cc-skills](https://github.com/terrylica/cc-skills) - Target marketplace
- [itp-hooks pattern](/plugins/itp-hooks/) - Reference plugin architecture
