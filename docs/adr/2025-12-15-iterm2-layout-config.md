---
status: implemented
date: 2025-12-15
decision-maker: terrylica
consulted: [CurrentStateAnalysis, IndustryPatterns, RealWorldExamples, Plan]
research-method: 9-agent-parallel-dctl
clarification-iterations: 4
perspectives: [ConfigurationManagement, SeparationOfConcerns, IndustryStandards]
---

# ADR: iTerm2 Layout Configuration Separation

**Design Spec**: [Implementation Spec](/docs/design/2025-12-15-iterm2-layout-config/spec.md)

## Context and Problem Statement

The `default-layout.py` script in `~/scripts/iterm2/` creates iTerm2 workspace tabs with split panes on startup. Currently, it contains 23+ hardcoded workspace paths that expose:

- **VERY HIGH risk**: Account identifiers (`work`), personal business projects (`jobber`, `insurance`, `netstrata`), legal docs, MetaTrader paths
- **HIGH risk**: Trading/data projects (`~/eon/research-repo`, `gapless-*-clickhouse`)
- **MEDIUM risk**: Tool paths (`~/.claude/tools/bin/claude-smart-start`)

**Problem**: The script cannot be published publicly without exposing private project structure and personal information.

**Goal**: Separate private/configurable information from publishable code following industry best practices.

### Before/After

```
                              ⏮️ Before: Hardcoded Paths

┌────────────────────────┐     ┏━━━━━━━━━━━━━━━━━━━━━━━━┓     ┌────────────────────────┐
│ [x] SETTLE_TIME, RATIO │ <── ┃   default-layout.py    ┃ ──> │ [x] 23 hardcoded paths │
└────────────────────────┘     ┗━━━━━━━━━━━━━━━━━━━━━━━━┛     └────────────────────────┘
                                 │
                                 │
                                 ∨
                               ┌────────────────────────┐
                               │ [x] LEFT/RIGHT_COMMAND │
                               └────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Hardcoded Paths"; flow: south; }
[ Script ] { border: bold; label: "default-layout.py"; }
[ Paths ] { label: "[x] 23 hardcoded paths"; }
[ Commands ] { label: "[x] LEFT/RIGHT_COMMAND"; }
[ Constants ] { label: "[x] SETTLE_TIME, RATIO"; }
[ Script ] -> [ Paths ]
[ Script ] -> [ Commands ]
[ Script ] -> [ Constants ]
```

</details>

```
⏭️ After: TOML Configuration

┏━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  [+] default-layout.py  ┃
┃      (publishable)      ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━┛
  │
  │
  ∨
┌─────────────────────────┐
│    [+] load_config()    │
└─────────────────────────┘
  │
  │
  ∨
╔═════════════════════════╗
║    ~/.config/iterm2/    ║
║       layout.toml       ║
╚═════════════════════════╝
  ∧
  :
  :
┌─────────────────────────┐
│ [+] layout.example.toml │
│       (template)        │
└─────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: TOML Configuration"; flow: south; }
[ default-layout.py ] { border: bold; label: "[+] default-layout.py\n(publishable)"; }
[ layout.toml ] { border: double; label: "~/.config/iterm2/\nlayout.toml"; }
[ layout.example.toml ] { label: "[+] layout.example.toml\n(template)"; }
[ load_config() ] { label: "[+] load_config()"; }
[ default-layout.py ] -> [ load_config() ]
[ load_config() ] -> [ layout.toml ]
[ layout.example.toml ] ..> [ layout.toml ]
```

</details>

## Research Summary

| Agent Perspective    | Key Finding                                                     | Confidence |
| -------------------- | --------------------------------------------------------------- | ---------- |
| CurrentStateAnalysis | 23 hardcoded paths across 4 privacy tiers (VERY HIGH to LOW)    | High       |
| IndustryPatterns     | TOML + XDG + 12-Factor is 2025 industry standard                | High       |
| RealWorldExamples    | Poetry, pre-commit, chezmoi all use three-tier config hierarchy | High       |
| Plan                 | Native Python 3.11+ tomllib eliminates dependencies             | High       |

## Decision Log

| Decision Area   | Options Evaluated                          | Chosen                         | Rationale                            |
| --------------- | ------------------------------------------ | ------------------------------ | ------------------------------------ |
| Config location | `~/.config/iterm2/`, `~/.claude/`, in-repo | `~/.config/iterm2/layout.toml` | XDG standard, directory exists       |
| File format     | TOML, JSON, YAML                           | TOML                           | Native Python 3.11+, typed, comments |
| Error handling  | Alert, Print+return, Both                  | Print + early return           | Non-intrusive, Script Console        |
| Publication     | Standalone repo, cc-skills plugin          | cc-skills marketplace          | Unified distribution                 |

### Trade-offs Accepted

| Trade-off                 | Choice             | Accepted Cost                      |
| ------------------------- | ------------------ | ---------------------------------- |
| Simplicity vs Type Safety | TOML (no Pydantic) | No runtime type validation         |
| XDG vs .claude ecosystem  | XDG path           | Config not with other Claude tools |

## Decision Drivers

- Script must be publishable without exposing private paths
- Zero additional dependencies (use native tomllib)
- Industry-standard patterns for maintainability
- Graceful error handling for iTerm2 AutoLaunch context

## Considered Options

- **Option A**: Environment variables only (12-Factor pure)
- **Option B**: JSON config file (matches existing device_priorities.json)
- **Option C**: TOML config at XDG location <- Selected

## Decision Outcome

Chosen option: **Option C (TOML at XDG location)**, because:

1. Native Python 3.11+ support via `tomllib` (zero dependencies)
2. Human-readable with comments (unlike JSON)
3. XDG Base Directory compliance (`~/.config/iterm2/`)
4. Industry standard used by Poetry, pytest, Cargo

## Synthesis

**Convergent findings**: All perspectives agreed on three-tier config hierarchy (defaults → config file → env overrides) and TOML as modern standard.

**Divergent findings**: Location debate between XDG (`~/.config/`) and Claude ecosystem (`~/.claude/`).

**Resolution**: XDG chosen as industry standard; `.claude/` is tool-specific, not configuration-specific.

## Consequences

### Positive

- Script can be published publicly without privacy exposure
- Per-machine customization supported
- Industry-standard patterns for future maintainability
- Zero runtime dependencies

### Negative

- Requires initial config setup (copy template)
- Config file in different location from other Claude tools
- No runtime type validation (could add Pydantic later if needed)

## Architecture

```
                         🏗️ Configuration Architecture

╭────────────╮     ┏━━━━━━━━━━━━━━━━━━━┓     ╔═════════════╗     ┌─────────────┐
│   iTerm2   │     ┃ default-layout.py ┃     ║ layout.toml ║     │ Create Tabs │
│ AutoLaunch │ ──> ┃                   ┃ ──> ║             ║ ──> │             │
╰────────────╯     ┗━━━━━━━━━━━━━━━━━━━┛     ╚═════════════╝     └─────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ Configuration Architecture"; flow: east; }
[ iTerm2 ] { shape: rounded; label: "iTerm2\nAutoLaunch"; }
[ Script ] { border: bold; label: "default-layout.py"; }
[ Config ] { border: double; label: "layout.toml"; }
[ Tabs ] { label: "Create Tabs"; }
[ iTerm2 ] -> [ Script ]
[ Script ] -> [ Config ]
[ Config ] -> [ Tabs ]
```

</details>

## References

- [iTerm2 Python API Documentation](https://iterm2.com/python-api/)
- [TOML Specification](https://toml.io/)
- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)
- [Python tomllib (PEP 680)](https://peps.python.org/pep-0680/)
