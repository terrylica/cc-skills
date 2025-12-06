---
status: implemented
date: 2025-12-06
decision-maker: Terry Li
consulted: [claude-code-guide, Explore-Agent]
research-method: multi-agent
clarification-iterations: 3
perspectives:
  [DeveloperExperience, CrossPlatformCompatibility, DocumentationStandard]
---

# ADR: Shell Command Portability for Zsh Compatibility

**Design Spec**: [Implementation Spec](/docs/design/2025-12-06-shell-command-portability-zsh/spec.md)

## Context and Problem Statement

When Claude Code's Bash tool runs commands with `$(...)` substitution on macOS (zsh default shell), it fails with:

```
(eval):1: parse error near `('
```

**Root Cause**: Zsh parses `VAR=$(cmd) another-cmd` differently than bash. This is a zsh FEATURE, not a bug. Commands like `GITHUB_TOKEN=$(gh auth token) npx semantic-release` work in bash but fail in zsh's eval.

This affects all documentation in the cc-skills repository that shows shell commands with inline variable assignment or command substitution patterns.

### Before/After

**Before**: Documentation shows commands that fail on macOS zsh

```
                     ⏮️ Before: Shell Commands Fail on macOS

┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐
╎                                                                                       ╎
╎ ┌─────────────────────┐     ┌─────────────────────────────┐     ┌───────────────────┐ ╎
╎ │   User copies cmd   │     │     Claude Code Bash Tool   │     │       ❌ FAIL     │ ╎
╎ │    from docs/md     │ ──> │     (runs through zsh)      │ ──> │ parse error near  │ ╎
╎ │ GITHUB_TOKEN=$(...)  │     │                             │     │       `('         │ ╎
╎ └─────────────────────┘     └─────────────────────────────┘     └───────────────────┘ ╎
╎                                                                                       ╎
└−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Shell Commands Fail on macOS"; flow: east; }

[user] { label: "User copies cmd\nfrom docs/md\nGITHUB_TOKEN=$(...)"; }
[bash] { label: "Claude Code Bash Tool\n(runs through zsh)"; }
[fail] { label: "❌ FAIL\nparse error near\n`('"; }

[user] -> [bash] -> [fail]
```

</details>

**After**: Documentation shows portable commands that work everywhere

```
                       ⏭️ After: Shell Commands Work Everywhere

┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐
╎                                                                                                     ╎
╎ ┌───────────────────────────┐     ┌─────────────────────────────┐     ┌───────────────────────────┐ ╎
╎ │     User copies cmd       │     │     Claude Code Bash Tool   │     │        ✅ SUCCESS         │ ╎
╎ │      from docs/md         │ ──> │   (zsh runs bash wrapper)   │ ──> │ Command executes properly │ ╎
╎ │ /usr/bin/env bash -c '...' │     │                             │     │                           │ ╎
╎ └───────────────────────────┘     └─────────────────────────────┘     └───────────────────────────┘ ╎
╎                                                                                                     ╎
└−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Shell Commands Work Everywhere"; flow: east; }

[user] { label: "User copies cmd\nfrom docs/md\n/usr/bin/env bash -c '...'"; }
[bash] { label: "Claude Code Bash Tool\n(zsh runs bash wrapper)"; }
[ok] { label: "✅ SUCCESS\nCommand executes properly"; }

[user] -> [bash] -> [ok]
```

</details>

## Research Summary

| Agent Perspective       | Key Finding                                                      | Confidence |
| ----------------------- | ---------------------------------------------------------------- | ---------- |
| claude-code-guide       | Claude Code has no shell configuration option (Issue #7490 OPEN) | High       |
| claude-code-guide       | PreToolUse hooks can modify commands but escaping is unsolvable  | High       |
| Explore-Agent           | 97 instances across 35 files need modification                   | High       |
| Cross-Platform Research | `/usr/bin/env bash` works on macOS, Linux, FreeBSD, OpenBSD      | High       |

## Decision Log

| Decision Area     | Options Evaluated                             | Chosen                 | Rationale                                              |
| ----------------- | --------------------------------------------- | ---------------------- | ------------------------------------------------------ |
| Solution Approach | Hook-based wrapping, Documentation fix        | Documentation fix      | Hook escaping is unsolvable; docs are the real problem |
| Wrapper Syntax    | `/bin/bash -c`, `/usr/bin/env bash -c`        | `/usr/bin/env bash -c` | Works on FreeBSD, OpenBSD, Alpine Linux                |
| Scope             | Critical only (12), All occurrences (97)      | All occurrences (97)   | Consistent documentation across repo                   |
| User Memory       | Project CLAUDE.md, Global ~/.claude/CLAUDE.md | Global user memory     | Standard applies to all projects                       |

### Trade-offs Accepted

| Trade-off                      | Choice            | Accepted Cost                         |
| ------------------------------ | ----------------- | ------------------------------------- |
| Effort vs Reliability          | Modify 97 files   | Higher effort, but reliable solution  |
| Implicit vs Explicit           | Explicit wrappers | More verbose commands in docs         |
| Hook automation vs Manual docs | Manual docs       | No magic, users see exactly what runs |

## Decision Drivers

- macOS uses zsh as default shell since Catalina (2019)
- Claude Code's Bash tool runs through system shell, not bash
- Documentation must show commands that work on both macOS and Linux
- Users copy-paste commands directly from skill documentation

## Considered Options

- **Option A**: PreToolUse hook to auto-wrap all commands with bash
- **Option B**: Modify documentation to use portable `/usr/bin/env bash -c` wrapper
- **Option C**: Wait for Claude Code to add shell configuration (GitHub Issue #7490)

## Decision Outcome

Chosen option: **Option B (Documentation fix)**, because:

1. The problem is DOCUMENTATION, not execution - users copy commands from docs
2. Hook-based escaping is mathematically unsolvable for arbitrary commands
3. `/usr/bin/env bash -c` is the most portable wrapper (macOS, Linux, BSD)
4. Explicit commands in docs are transparent - no hidden magic

## Synthesis

**Convergent findings**: All research agents agreed that Claude Code cannot be configured to use bash, and that hook-based wrapping fails on commands containing quotes.

**Divergent findings**: Initial assumption was that a PreToolUse hook could solve this automatically. Research proved this impossible due to shell escaping limitations.

**Resolution**: Accept that documentation must show the correct, portable commands explicitly.

## Consequences

### Positive

- All shell commands in docs work on macOS zsh and Linux bash
- Users see exactly what will be executed (no hidden wrapping)
- Standard documented in user memory prevents future issues
- Cross-platform compatibility (macOS, Linux, FreeBSD, OpenBSD)

### Negative

- 97 file edits required (one-time cost)
- Commands in docs are more verbose
- Users must remember the wrapper pattern for new commands

## Architecture

```
                        🏗️ Shell Command Portability Solution

                   ┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐
                   ╎ Global Standard:                                   ╎
                   ╎                                                    ╎
                   ╎                 ┌────────────────────────────────┐ ╎
                   ╎                 │    ~/.claude/CLAUDE.md         │ ╎
                   ╎                 │ (Shell Portability Standard)   │ ╎
                   ╎                 └────────────────────────────────┘ ╎
                   ╎                   │                                ╎
                   ╎                   │ references                     ╎
                   ╎                   ∨                                ╎
                   ╎                 ╔════════════════════════════════╗ ╎
                   ╎                 ║   /usr/bin/env bash -c '...'   ║ ╎
                   ╎                 ║      (Portable Wrapper)        ║ ╎
                   ╎                 ╚════════════════════════════════╝ ╎
                   ╎                                                    ╎
                   └−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘
                                       │
                                       │ applies to
                                       ∨
┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐
╎ Documentation Files (97 instances):                                                                 ╎
╎                                                                                                     ╎
╎ ┌───────────────────────┐  ┌───────────────────────┐  ┌───────────────────────┐  ┌───────────────┐ ╎
╎ │   CRITICAL (12)       │  │      HIGH (15)        │  │     MEDIUM (40+)      │  │   LOW (20+)   │ ╎
╎ │ semantic-release      │  │   export patterns     │  │  command substitution │  │  ITP commands │ ╎
╎ │ inline var assignment │  │   doppler secrets     │  │    in arguments       │  │  shell docs   │ ╎
╎ └───────────────────────┘  └───────────────────────┘  └───────────────────────┘  └───────────────┘ ╎
╎                                                                                                     ╎
└−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ Shell Command Portability Solution"; flow: south; }

( Global Standard:
  [memory] { label: "~/.claude/CLAUDE.md\n(Shell Portability Standard)"; }
  [wrapper] { label: "/usr/bin/env bash -c '...'\n(Portable Wrapper)"; border: bold; }
)

( Documentation Files (97 instances):
  [critical] { label: "CRITICAL (12)\nsemantic-release\ninline var assignment"; }
  [high] { label: "HIGH (15)\nexport patterns\ndoppler secrets"; }
  [medium] { label: "MEDIUM (40+)\ncommand substitution\nin arguments"; }
  [low] { label: "LOW (20+)\nITP commands\nshell docs"; }
)

[memory] -- references --> [wrapper]
[wrapper] -- applies to --> [critical]
[wrapper] -- applies to --> [high]
[wrapper] -- applies to --> [medium]
[wrapper] -- applies to --> [low]
```

</details>

## References

- [Claude Code GitHub Issue #7490](https://github.com/anthropics/claude-code/issues/7490) - Shell configuration feature request
- [Zsh Command Substitution](https://zsh.sourceforge.io/Doc/Release/Expansion.html) - Zsh expansion documentation
- [semantic-release skill](/plugins/itp/skills/semantic-release/SKILL.md) - Primary affected skill
