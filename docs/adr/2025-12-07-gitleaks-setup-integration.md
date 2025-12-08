---
status: implemented
date: 2025-12-07
decision-maker: Terry Li
consulted: [Security-Fundamentals, Plugin-Integration, Tool-Registry]
research-method: single-agent
clarification-iterations: 2
perspectives: [DevSecOps, ToolchainIntegration, LocalFirst]
---

# ADR: Add Gitleaks Secret Scanner to ITP Setup Command

**Design Spec**: [Implementation Spec](/docs/design/2025-12-07-gitleaks-setup-integration/spec.md)

## Context and Problem Statement

The cc-skills repository uses Doppler for centralized secret management, but lacks a pre-commit mechanism to prevent accidental secret commits. Once a secret enters git history, remediation is costly (history rewriting, credential rotation, security incident response).

Gitleaks is an open-source secret scanner with 160+ built-in detection patterns that can catch secrets before they enter the repository via pre-commit hooks.

### Before/After

**Before:** Secrets can accidentally enter git history with no prevention mechanism.

```
           ⏮️ Before: No Secret Scanning

┌───────────┐     ┌────────────┐     ┌─────────────┐
│ Developer │ ──> │ git commit │ ──> │ Git History │
└───────────┘     └────────────┘     └─────────────┘
                    ∧
                    │
                    │
                  ┌────────────┐
                  │  Secrets   │
                  └────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: No Secret Scanning"; flow: east; }
[ Developer ] -> [ git commit ] -> [ Git History ]
[ Secrets ] -> [ git commit ]
```

</details>

**After:** Gitleaks intercepts secrets before they enter git history.

```
                     ⏭️ After: Gitleaks Pre-commit


  ┌────────────────────┐
  │                    ∨
  │  ┌─────────┐     ┌───────────┐     ┌────────────┐     ┌─────────────┐
  │  │ Secrets │     │ Gitleaks  │     │ git commit │     │ Git History │
  │  │         │ ──> │   Scan    │ ──> │            │ ──> │             │
  │  └─────────┘     └───────────┘     └────────────┘     └─────────────┘
  │                    │
  │                    │ BLOCKED
  │                    ∨
  │                  ┌───────────┐
  └───────────────── │ Developer │
                     └───────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Gitleaks Pre-commit"; flow: east; }
[ Developer ] -> [ Gitleaks\nScan ] -> [ git commit ] -> [ Git History ]
[ Secrets ] -> [ Gitleaks\nScan ] -- BLOCKED --> [ Developer ]
```

</details>

## Research Summary

| Agent Perspective     | Key Finding                                                                                       | Confidence |
| --------------------- | ------------------------------------------------------------------------------------------------- | ---------- |
| Security-Fundamentals | Pre-commit catches secrets BEFORE git history is tainted; CI catches AFTER (costly remediation)   | High       |
| Plugin-Integration    | Gitleaks fits Code Audit Tools category alongside ruff, semgrep, jscpd                            | High       |
| Tool-Registry         | Gitleaks available via mise aqua backend (`aqua:gitleaks/gitleaks`) - preferred over asdf plugins | High       |

## Decision Log

| Decision Area       | Options Evaluated                            | Chosen                  | Rationale                                                              |
| ------------------- | -------------------------------------------- | ----------------------- | ---------------------------------------------------------------------- |
| Integration Point   | Separate command, Add to existing /itp:setup | /itp:setup Todo 4       | Follows established pattern for Code Audit Tools                       |
| Installation Method | brew/apt only, mise-first with fallbacks     | mise-first              | Consistent with existing tools (ruff, semgrep); aqua backend is secure |
| Config File         | None, .gitleaks.toml                         | Optional .gitleaks.toml | Allows allowlisting tmp/, tests/, example patterns                     |

### Trade-offs Accepted

| Trade-off                | Choice                           | Accepted Cost                              |
| ------------------------ | -------------------------------- | ------------------------------------------ |
| Complexity vs Simplicity | Add to existing setup            | Slightly larger Todo 4 table               |
| mise dependency          | Require mise for best experience | Falls back to brew/apt if mise unavailable |

## Decision Drivers

- Local-first development philosophy (instant feedback vs CI delays)
- Existing pattern in install-dependencies.sh (mise-preferred tools)
- Security: prevent secrets from entering git history
- Gitleaks availability in mise registry via aqua backend

## Considered Options

- **Option A**: Create separate `/itp:gitleaks` command
- **Option B**: Add gitleaks to existing `/itp:setup` Todo 4 (Code Audit Tools) <- Selected
- **Option C**: Document manual installation only

## Decision Outcome

Chosen option: **Option B**, because it follows the established pattern for Code Audit Tools (ruff, semgrep, jscpd) and maintains a single source of truth for dependency management in `install-dependencies.sh`.

## Synthesis

**Convergent findings**: All research confirmed pre-commit is superior to CI-only scanning for secret detection.

**Divergent findings**: None significant - the mise aqua backend availability resolved installation concerns.

**Resolution**: User confirmed adding to existing setup command follows the established pattern.

## Consequences

### Positive

- Secrets caught before entering git history (shift-left security)
- Consistent with local-first development philosophy
- mise-first installation leverages secure aqua backend
- Optional .gitleaks.toml allows project-specific allowlisting

### Negative

- Adds another tool to the audit suite (minor complexity increase)
- Users without mise will use brew/apt fallback (less version consistency)

## Architecture

```
                     🏗️ ITP Setup Todo 4: Code Audit Tools

                             ╭─────────────────────────╮
                             │       /itp:setup        │
                             ╰─────────────────────────╯
                               │
                               │
                               ∨
┌──────────────────────┐     ┌──────────────────────────────────┐     ┌─────────┐
│         ruff         │     │             Todo 4:              │     │ semgrep │
│                      │ <── │         Code Audit Tools         │ ──> │         │
└──────────────────────┘     └──────────────────────────────────┘     └─────────┘
                               │                          │
                               │                          │
                               ∨                          ∨
                             ┏━━━━━━━━━━━━━━━━━━━━━━━━━┓┌───────┐
                             ┃      [+] gitleaks       ┃│ jscpd │
                             ┗━━━━━━━━━━━━━━━━━━━━━━━━━┛└───────┘
                               │
                               │
                               ∨
┌──────────────────────┐     ┌─────────────────────────┐
│ [1] mise (preferred) │ <── │ install-dependencies.sh │
└──────────────────────┘     └─────────────────────────┘
                               │
                               │
                               ∨
                             ┌─────────────────────────┐
                             │      [2] fallback       │
                             └─────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ ITP Setup Todo 4: Code Audit Tools"; flow: south; }
[ /itp:setup ] { shape: rounded; } -> [ Todo 4:\nCode Audit Tools ]
[ Todo 4:\nCode Audit Tools ] -> [ ruff ]
[ Todo 4:\nCode Audit Tools ] -> [ semgrep ]
[ Todo 4:\nCode Audit Tools ] -> [ jscpd ]
[ Todo 4:\nCode Audit Tools ] -> [ gitleaks ] { label: "[+] gitleaks"; border: bold; }
[ gitleaks ] -> [ install-dependencies.sh ]
[ install-dependencies.sh ] -> [ mise install gitleaks ] { label: "[1] mise (preferred)"; }
[ install-dependencies.sh ] -> [ brew/apt fallback ] { label: "[2] fallback"; }
```

</details>

## References

- [Gitleaks GitHub](https://github.com/gitleaks/gitleaks) - v8.30.0 (Nov 2025)
- [mise Registry](https://mise.jdx.dev/registry.html) - gitleaks via aqua backend
- [IBM PTC Security - Pre-commit Integration](https://medium.com/@ibm_ptc_security/securing-your-repositories-with-gitleaks-and-pre-commit-27691eca478d)
- [Plan File](/docs/design/2025-12-07-gitleaks-setup-integration/spec.md) - Implementation details
