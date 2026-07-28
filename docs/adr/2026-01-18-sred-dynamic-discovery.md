---
status: superseded
date: 2026-01-18
decision-maker: [Terry Li]
consulted:
  [SDK-Integration-Agent, CRA-Compliance-Agent, Hook-Architecture-Agent]
research-method: single-agent
clarification-iterations: 8
perspectives:
  [UpstreamIntegration, EcosystemArtifact, ProviderToOtherComponents]
superseded-date: 2026-07-27
superseded-reason: SR&ED commit tracking was abandoned by operator decision — the guard was removed as unused dead code (never registered in hooks.json since January 2026).
---

# ADR: SR&ED Dynamic Project Discovery via Claude Agent SDK

**Design Spec**: [Implementation Spec](/docs/design/2026-01-18-sred-dynamic-discovery/spec.md)

> **🔴 SUPERSEDED (2026-07-27)**: This ADR and its implementation are obsolete. The `sred-commit-guard` hook
> was deleted as unused dead code, and SR&ED commit tracking was abandoned. This document is retained for historical
> reference only.

## Context and Problem Statement

The current `sred-commit-guard.ts` PreToolUse hook enforces SR&ED (Scientific Research & Experimental Development) commit trailers for CRA tax credit compliance. However, it relies on hardcoded project identifiers (`VALID_CLAIM_IDS`) that must be manually maintained in the hook source code.

This creates several problems:

1. **Maintenance burden**: Adding new SR&ED projects requires code changes to the hook
2. **Registry drift**: Hardcoded IDs can become stale or inconsistent with actual git history
3. **Poor discoverability**: Users must know valid project IDs upfront; no guidance for new projects
4. **CRA terminology errors**: Current implementation uses invalid SR&ED types (`systematic-investigation`, `technical-innovation`) not recognized by CRA

The solution is to dynamically discover project identifiers from git history using an isolated Claude Haiku session spawned via the Claude Agent SDK.

### Before/After

**Before: Hardcoded Registry**

```
 ⏮️ Before: Hardcoded Registry

    ╭──────────────────────╮
    │        Commit        │
    │ (missing SRED-Claim) │
    ╰──────────────────────╯
      │
      │
      ∨
    ┌──────────────────────┐
    │ sred-commit-guard.ts │
    └──────────────────────┘
      │
      │
      ∨
    ╔══════════════════════╗
    ║   VALID_CLAIM_IDS    ║
    ║  (hardcoded array)   ║
    ╚══════════════════════╝
      │
      │ lookup
      ∨
    ┌──────────────────────┐
    │      Validation      │
    └──────────────────────┘
      │
      │ fail
      ∨
    ╭──────────────────────╮
    │        BLOCK         │
    │  (invalid claim ID)  │
    ╰──────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Hardcoded Registry"; flow: south; }
[ Commit\n(missing SRED-Claim) ] { shape: rounded; }
[ sred-commit-guard.ts ]
[ VALID_CLAIM_IDS\n(hardcoded array) ] { border: double; }
[ Validation ]
[ BLOCK\n(invalid claim ID) ] { shape: rounded; }

[ Commit\n(missing SRED-Claim) ] -> [ sred-commit-guard.ts ]
[ sred-commit-guard.ts ] -> [ VALID_CLAIM_IDS\n(hardcoded array) ]
[ VALID_CLAIM_IDS\n(hardcoded array) ] -- lookup --> [ Validation ]
[ Validation ] -- fail --> [ BLOCK\n(invalid claim ID) ]
```

</details>

**After: Dynamic Discovery**

```
 ⏭️ After: Dynamic Discovery

   ╭──────────────────────╮
   │        Commit        │
   │ (missing SRED-Claim) │
   ╰──────────────────────╯
     │
     │
     ∨
   ┌──────────────────────┐
   │ sred-commit-guard.ts │
   └──────────────────────┘
     │
     │
     ∨
   ╔══════════════════════╗
   ║  sred-discovery.ts   ║
   ╚══════════════════════╝
     │
     │ SDK query
     ∨
   ┌──────────────────────┐
   │     Claude Haiku     │
   │  (isolated session)  │
   └──────────────────────┘
     │
     │
     ∨
   ┌──────────────────────┐
   │     Git History      │
   │       Analysis       │
   └──────────────────────┘
     │
     │
     ∨
   ┌──────────────────────┐
   │    AI Suggestion     │
   │  + AskUserQuestion   │
   └──────────────────────┘
     │
     │
     ∨
   ┌──────────────────────┐
   │     User Selects     │
   │      Project ID      │
   └──────────────────────┘
     │
     │
     ∨
   ╭──────────────────────╮
   │      Retry with      │
   │      SRED-Claim      │
   ╰──────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Dynamic Discovery"; flow: south; }
[ Commit\n(missing SRED-Claim) ] { shape: rounded; }
[ sred-commit-guard.ts ]
[ sred-discovery.ts ] { border: double; }
[ Claude Haiku\n(isolated session) ]
[ Git History\nAnalysis ]
[ AI Suggestion\n+ AskUserQuestion ]
[ User Selects\nProject ID ]
[ Retry with\nSRED-Claim ] { shape: rounded; }

[ Commit\n(missing SRED-Claim) ] -> [ sred-commit-guard.ts ]
[ sred-commit-guard.ts ] -> [ sred-discovery.ts ]
[ sred-discovery.ts ] -- SDK query --> [ Claude Haiku\n(isolated session) ]
[ Claude Haiku\n(isolated session) ] -> [ Git History\nAnalysis ]
[ Git History\nAnalysis ] -> [ AI Suggestion\n+ AskUserQuestion ]
[ AI Suggestion\n+ AskUserQuestion ] -> [ User Selects\nProject ID ]
[ User Selects\nProject ID ] -> [ Retry with\nSRED-Claim ]
```

</details>

## Research Summary

| Agent Perspective       | Key Finding                                                                    | Confidence |
| ----------------------- | ------------------------------------------------------------------------------ | ---------- |
| SDK-Integration-Agent   | Claude Agent SDK `query()` with `settingSources: []` provides hook isolation   | High       |
| CRA-Compliance-Agent    | Only 4 valid SRED-Types per CRA glossary; must remove invalid categories       | High       |
| Hook-Architecture-Agent | PreToolUse hooks block BEFORE execution; output via `permissionDecisionReason` | High       |

## Decision Log

| Decision Area             | Options Evaluated                       | Chosen                  | Rationale                                      |
| ------------------------- | --------------------------------------- | ----------------------- | ---------------------------------------------- |
| SDK vs Direct API         | Anthropic API, Claude Agent SDK         | Claude Agent SDK        | CLI subscription only, no API key needed       |
| Hook Recursion Prevention | Env var only, settingSources only, Both | Both (defense-in-depth) | `settingSources: []` + `CLAUDE_HOOK_SPAWNED`   |
| Failure Behavior          | Fail-open (allow), Fail-closed (block)  | Fail-closed + fallback  | SDK errors block with derived suggestion       |
| Model Selection           | Opus, Sonnet, Haiku                     | Haiku                   | Fast + cheap, within hook timeout budget       |
| Project ID Format         | YYYY-QN-PROJECT, PROJECT[-VARIANT]      | PROJECT[-VARIANT]       | Year/quarter from git timestamp at report time |
| Caching Strategy          | No cache, Time-only, Scope+File hash    | Scope+File hash         | Reduces redundant Haiku calls; 5-min TTL       |

### Trade-offs Accepted

| Trade-off                    | Choice            | Accepted Cost                                   |
| ---------------------------- | ----------------- | ----------------------------------------------- |
| AI suggestion vs manual only | AI suggestion     | Network dependency; SDK/timeout errors possible |
| Blocking vs permissive       | Block on error    | May slow commits; requires user action on error |
| Cache complexity vs fresh    | Scope-based cache | Cache invalidation complexity                   |

## Decision Drivers

- CRA compliance requires consistent SR&ED documentation in git history
- No hardcoded project identifiers for universal applicability across repositories
- Must work with Claude Code subscription (no separate Anthropic API key)
- Hook timeout budget (~8 seconds) constrains model choice
- Fail-closed ensures all SR&ED commits are properly tagged

## Considered Options

- **Option A**: Keep hardcoded registry - Rejected: maintenance burden, poor discoverability
- **Option B**: External registry file - Rejected: still requires manual maintenance
- **Option C**: Dynamic discovery via Claude Agent SDK - Selected

## Decision Outcome

Chosen option: **Option C (Dynamic Discovery via Claude Agent SDK)**, because it eliminates hardcoded identifiers, leverages git history as single source of truth, and provides intelligent project suggestions to users.

The implementation spawns an isolated Haiku session that:

1. Analyzes recent git history for existing SR&ED project patterns
2. Suggests the most likely project based on commit scope and history
3. Returns structured output for Claude to present via `AskUserQuestion`
4. Falls back to scope-derived suggestion on SDK/network errors

## Synthesis

**Convergent findings**: All perspectives agreed on Claude Agent SDK as the integration path, PreToolUse as the correct hook lifecycle, and the need to fix invalid CRA terminology.

**Divergent findings**: Initial confusion about fail-open vs fail-closed behavior; AskUserQuestion invocation from hooks.

**Resolution**: Clarified that hooks output `permissionDecisionReason` and Claude decides presentation. SDK errors block with fallback suggestion (not true fail-open); only unexpected crashes allow commits through for safety.

## Consequences

### Positive

- Zero hardcoded project identifiers across all repositories
- Git history becomes single source of truth for project discovery
- Intelligent suggestions reduce user friction for SR&ED tagging
- Fixes CRA terminology (removes invalid types, adds `support-work`)
- Universal applicability: works with any repository

### Negative

- Network dependency for AI suggestions (mitigated by fallback)
- SDK/timeout errors require user action (mitigated by clear messaging)
- Cache management complexity (mitigated by simple TTL + file hash)
- Additional dependency on `@anthropic-ai/claude-agent-sdk`

## Architecture

```
          🏗️ SR&ED Discovery Architecture

                        ╭──────────────────────────╮
                        │      Commit Command      │
                        ╰──────────────────────────╯
                          │
                          │
                          ∨
                        ┌──────────────────────────┐
                        │     PreToolUse Hook      │
                        └──────────────────────────┘
                          │
                          │
                          ∨
                        ┌──────────────────────────┐
                        │   sred-commit-guard.ts   │
                        └──────────────────────────┘
                          │
                          │
                          ∨
                        ┌──────────────────────────┐
                        │      Check Trailers      │
                        └──────────────────────────┘
                          │
                          │ missing
                          ∨
                        ╔══════════════════════════╗
                        ║    sred-discovery.ts     ║
                        ╚══════════════════════════╝
                          │
                          │
                          ∨
                        ┌──────────────────────────┐
                        │       Cache Check        │
                        └──────────────────────────┘
                          │
                          │ miss
                          ∨
┌──────────┐  offline   ┌──────────────────────────┐
│ Fallback │ <───────── │      Network Check       │
└──────────┘            └──────────────────────────┘
  │                       │
  │                       │ online
  │                       ∨
  │                     ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
  │                     ┃       Claude Haiku       ┃
  │                     ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛
  │                       │
  │                       │
  │                       ∨
  │                     ┌──────────────────────────┐
  │                     │         git log          │
  │                     └──────────────────────────┘
  │                       │
  │                       │
  │                       ∨
  │                     ┌──────────────────────────┐
  └───────────────────> │      Format Output       │
                        └──────────────────────────┘
                          │
                          │
                          ∨
                        ╭──────────────────────────╮
                        │ permissionDecisionReason │
                        ╰──────────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "🏗️ SR&ED Discovery Architecture"; flow: south; }

[ Commit Command ] { shape: rounded; }
[ PreToolUse Hook ]
[ sred-commit-guard.ts ]
[ Check Trailers ]
[ sred-discovery.ts ] { border: double; }
[ Cache Check ]
[ Network Check ]
[ Claude Haiku ] { border: bold; }
[ git log ]
[ Fallback ]
[ Format Output ]
[ permissionDecisionReason ] { shape: rounded; }

[ Commit Command ] -> [ PreToolUse Hook ]
[ PreToolUse Hook ] -> [ sred-commit-guard.ts ]
[ sred-commit-guard.ts ] -> [ Check Trailers ]
[ Check Trailers ] -- missing --> [ sred-discovery.ts ]
[ sred-discovery.ts ] -> [ Cache Check ]
[ Cache Check ] -- miss --> [ Network Check ]
[ Network Check ] -- online --> [ Claude Haiku ]
[ Network Check ] -- offline --> [ Fallback ]
[ Claude Haiku ] -> [ git log ]
[ git log ] -> [ Format Output ]
[ Fallback ] -> [ Format Output ]
[ Format Output ] -> [ permissionDecisionReason ]
```

</details>

## References

- [Claude Agent SDK TypeScript Reference](https://platform.claude.com/docs/en/agent-sdk/typescript)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [CRA SR&ED Glossary](https://www.canada.ca/en/revenue-agency/services/scientific-research-experimental-development-tax-incentive-program/glossary.html)
- [Existing Hook: sred-commit-guard.ts](/plugins/itp-hooks/hooks/sred-commit-guard.ts)
