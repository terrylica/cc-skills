---
status: accepted
date: 2025-12-05
decision-maker: Terry Li
consulted: [Claude-Planning]
research-method: single-agent
clarification-iterations: 4
perspectives: [EcosystemArtifact, ProductFeature]
---

# ADR: TodoWrite-Driven Interactive Setup Workflow for ITP

**Design Spec**: [Implementation Spec](/docs/design/2025-12-05-itp-setup-todowrite-workflow/spec.md)

## Context and Problem Statement

The current `/itp:setup` command runs dependency checks and installations without user interaction or progress visibility. Users have no control over what gets installed, no visibility into what tools are already present, and no ability to skip installation. This contrasts with the `/itp:go` workflow which uses TodoWrite for structured progress tracking and interactive gates.

The setup command should respect existing user installations and only install missing tools after explicit user confirmation.

### Before/After

**Before: Silent Auto-Install**

```
                  ⏮️ Before: Silent Auto-Install

╭────────────╮     ┌─────────────┐     ┏━━━━━━━━━━━━━┓     ╭──────╮
│ /itp:setup │ ──> │ Check Tools │ ──> ┃ Install All ┃ ──> │ Done │
╰────────────╯     └─────────────┘     ┗━━━━━━━━━━━━━┛     ╰──────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Silent Auto-Install"; flow: east; }
[ /itp:setup ] { shape: rounded; } -> [ Check Tools ] -> [ Install All ] { border: bold; } -> [ Done ] { shape: rounded; }
```

</details>

**After: TodoWrite-Driven Interactive**

```
                                        ⏭️ After: TodoWrite-Driven Interactive

╭────────────╮     ╔═══════════╗     ┌───────┐     ┌──────────┐     ┏━━━━━━┓     ┌─────────┐     ┌────────┐     ╭──────╮
│ /itp:setup │     ║ TodoWrite ║     │ Check │     │ Present  │     ┃ User ┃     │ Install │     │ Verify │     │ Done │
│            │ ──> ║   First   ║ ──> │ Tools │ ──> │ Findings │ ──> ┃ Gate ┃ ──> │ Missing │ ──> │        │ ──> │      │
╰────────────╯     ╚═══════════╝     └───────┘     └──────────┘     ┗━━━━━━┛     └─────────┘     └────────┘     ╰──────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: TodoWrite-Driven Interactive"; flow: east; }
[ /itp:setup ] { shape: rounded; } -> [ TodoWrite\nFirst ] { border: double; } -> [ Check\nTools ] -> [ Present\nFindings ] -> [ User\nGate ] { border: bold; } -> [ Install\nMissing ] -> [ Verify ] -> [ Done ] { shape: rounded; }
```

</details>

## Research Summary

| Agent Perspective | Key Finding                                                                  | Confidence |
| ----------------- | ---------------------------------------------------------------------------- | ---------- |
| Claude-Planning   | TodoWrite-first pattern from /itp:go provides structured workflow control    | High       |
| Claude-Planning   | Interactive gate pattern enables user consent before installation            | High       |
| Claude-Planning   | Version checking APIs too complex; simpler to respect existing installations | High       |

## Decision Log

| Decision Area        | Options Evaluated                      | Chosen           | Rationale                                         |
| -------------------- | -------------------------------------- | ---------------- | ------------------------------------------------- |
| Progress tracking    | Silent execution vs TodoWrite-driven   | TodoWrite-driven | Mirrors /itp:go pattern, provides visibility      |
| Installation control | Auto-install vs Interactive gate       | Interactive gate | Respects user autonomy, prevents unwanted changes |
| Version handling     | API version checks vs Respect existing | Respect existing | Simpler, avoids complexity of version APIs        |
| Flag behavior        | Visible flags vs Hidden aliases        | Hidden aliases   | Maintains backward compatibility                  |

### Trade-offs Accepted

| Trade-off                        | Choice       | Accepted Cost                                          |
| -------------------------------- | ------------ | ------------------------------------------------------ |
| Simplicity vs Version validation | Simplicity   | May miss compatibility issues with older tool versions |
| User control vs Automation       | User control | Extra step required for installation                   |

## Decision Drivers

- Consistency with `/itp:go` workflow pattern
- User autonomy over their development environment
- Transparency about what tools are installed/missing
- Simplicity over complex version checking

## Considered Options

- **Option A**: Keep current behavior (silent auto-install)
- **Option B**: Add version checking via package manager APIs
- **Option C**: TodoWrite-driven interactive workflow with gates <- Selected

## Decision Outcome

Chosen option: **Option C** (TodoWrite-driven interactive workflow), because:

1. Mirrors the successful `/itp:go` pattern for consistency
2. Provides user visibility via TodoWrite progress tracking
3. Respects existing installations without forcing upgrades
4. Includes interactive gate for user consent before changes
5. Avoids complexity of version checking APIs

## Synthesis

**Convergent findings**: The TodoWrite-first pattern is proven effective in `/itp:go` and should be adopted for setup.

**Divergent findings**: Initial exploration considered version checking APIs, but this was rejected as too complex.

**Resolution**: User explicitly requested simpler approach—respect existing installations, add disclaimer about latest versions.

## Consequences

### Positive

- Consistent workflow pattern across ITP commands
- User has full visibility into tool status
- Existing installations are respected (no forced upgrades)
- Clear disclaimer about version expectations
- Backward-compatible via hidden flag aliases

### Negative

- Extra interaction step required for installation
- Cannot guarantee tool version compatibility
- Users must manually upgrade if issues arise

## Architecture

```
🏗️ Setup Workflow Architecture

                                ╭─────────────────────╮
                                │     /itp:setup      │
                                ╰─────────────────────╯
                                  │
                                  │
                                  ∨
                                ╔═════════════════════╗
                                ║      TodoWrite      ║
                                ║     Initialize      ║
                                ╚═════════════════════╝
                                  │
                                  │
                                  ∨
                                ┌─────────────────────┐
                                │      Phase 1:       │
                                │   Preflight Check   │
                                └─────────────────────┘
                                  │
                                  │
                                  ∨
                              ┌−−−−−−−−−−−−−−−−−−−−−−−−−┐
                              ╎ Phase 1 - Check:        ╎
                              ╎                         ╎
                              ╎ ┌─────────────────────┐ ╎
                              ╎ │   Detect Platform   │ ╎
                              ╎ └─────────────────────┘ ╎
                              ╎   │                     ╎
                              ╎   │                     ╎
                              ╎   ∨                     ╎
                              ╎ ┌─────────────────────┐ ╎
                              ╎ │  Check Core Tools   │ ╎
                              ╎ └─────────────────────┘ ╎
                              ╎   │                     ╎
                              ╎   │                     ╎
                              ╎   ∨                     ╎
                              ╎ ┌─────────────────────┐ ╎
                              ╎ │   Check ADR Tools   │ ╎
                              ╎ └─────────────────────┘ ╎
                              ╎   │                     ╎
                              ╎   │                     ╎
                              ╎   ∨                     ╎
                              ╎ ┌─────────────────────┐ ╎
                              ╎ │  Check Audit Tools  │ ╎
                              ╎ └─────────────────────┘ ╎
                              ╎   │                     ╎
                              ╎   │                     ╎
                              ╎   ∨                     ╎
                              ╎ ┌─────────────────────┐ ╎
                              ╎ │ Check Release Tools │ ╎
                              ╎ └─────────────────────┘ ╎
                              ╎                         ╎
                              └−−−−−−−−−−−−−−−−−−−−−−−−−┘
                                  │
                                  │
                                  ∨
                                ┌─────────────────────┐
                                │      Phase 2:       │
                                │  Present Findings   │
                                └─────────────────────┘
                                  │
                                  │
                                  ∨
                                ┌─────────────────────┐
                                │    Show Summary     │
                                └─────────────────────┘
                                  │
                                  │
                                  ∨
                                ┌─────────────────────┐
                                │   Show Disclaimer   │
                                └─────────────────────┘
                                  │
                                  │
                                  ∨
┌─────────────┐                 ┏━━━━━━━━━━━━━━━━━━━━━┓
│ Show Manual │  user skips     ┃  Interactive Gate   ┃
│  Commands   │ <────────────   ┃                     ┃
└─────────────┘                 ┗━━━━━━━━━━━━━━━━━━━━━┛
  │                               │
  │                               │ user confirms
  │                               ∨
  │                             ┌─────────────────────┐
  │                             │      Phase 3:       │
  │                             │    Installation     │
  │                             └─────────────────────┘
  │                               │
  │                               │
  │                               ∨
  │                             ┌─────────────────────┐
  │                             │   Install Missing   │
  │                             └─────────────────────┘
  │                               │
  │                               │
  │                               ∨
  │                             ┌─────────────────────┐
  │                             │   Verify Success    │
  │                             └─────────────────────┘
  │                               │
  │                               │
  │                               ∨
  │                             ╭─────────────────────╮
  └─────────────────────────>   │      Complete       │
                                ╰─────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ Setup Workflow Architecture"; flow: south; }
[ /itp:setup ] { shape: rounded; } -> [ TodoWrite\nInitialize ]
[ TodoWrite\nInitialize ] { border: double; } -> [ Phase 1:\nPreflight Check ]
( Phase 1 - Check:
  [ Detect Platform ]
  [ Check Core Tools ]
  [ Check ADR Tools ]
  [ Check Audit Tools ]
  [ Check Release Tools ]
)
[ Phase 1:\nPreflight Check ] -> [ Detect Platform ]
[ Detect Platform ] -> [ Check Core Tools ] -> [ Check ADR Tools ] -> [ Check Audit Tools ] -> [ Check Release Tools ]
[ Check Release Tools ] -> [ Phase 2:\nPresent Findings ]
[ Phase 2:\nPresent Findings ] -> [ Show Summary ]
[ Show Summary ] -> [ Show Disclaimer ]
[ Show Disclaimer ] -> [ Interactive Gate ] { border: bold; }
[ Interactive Gate ] -- user confirms --> [ Phase 3:\nInstallation ]
[ Interactive Gate ] -- user skips --> [ Show Manual\nCommands ]
[ Phase 3:\nInstallation ] -> [ Install Missing ]
[ Install Missing ] -> [ Verify Success ]
[ Verify Success ] -> [ Complete ] { shape: rounded; }
[ Show Manual\nCommands ] -> [ Complete ]
```

</details>

## Implementation Overview

### Files Modified

1. **`/plugins/itp/commands/setup.md`** - Complete rewrite with TodoWrite template
2. **`/plugins/itp/scripts/install-dependencies.sh`** - Add `--detect-only` flag and disclaimer

### Workflow Phases

| Phase      | Description                            | Gate              |
| ---------- | -------------------------------------- | ----------------- |
| 1. Check   | Detect platform, check tool categories | None              |
| 2. Present | Show findings with disclaimer          | Interactive       |
| 3. Install | Install missing tools                  | User confirmation |
| 4. Verify  | Re-check installations                 | None              |

### Flag Handling

| Flag        | Behavior                                  |
| ----------- | ----------------------------------------- |
| (none)      | Check → Gate → Ask permission             |
| `--check`   | Same as default (hidden alias)            |
| `--install` | Check → Skip gate → Install automatically |
| `--yes`     | Alias for `--install`                     |

## References

- [ITP Command](/plugins/itp/commands/go.md) - Pattern source for TodoWrite workflow
- Global Plan: `memoized-cooking-nygaard.md` - Original design (ephemeral, local to author's machine)
