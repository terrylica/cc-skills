---
adr: 2026-01-18-sred-dynamic-discovery
source: ~/.claude/plans/piped-spinning-dawn.md
implementation-status: in_progress
phase: phase-1
last-updated: 2026-01-18
---

# SR&ED Project Discovery: Forked Haiku Session via Claude Agent SDK

**ADR**: [SR&ED Dynamic Project Discovery ADR](/docs/adr/2026-01-18-sred-dynamic-discovery.md)

> Dynamic SR&ED project identifier discovery using Claude Agent SDK to spawn isolated Haiku sessions from PreToolUse hooks.

## CRA Compliance Notes

**Valid SRED-Type values** (per CRA glossary):

- `experimental-development` - Achieving technological advancement
- `applied-research` - Scientific knowledge with practical application
- `basic-research` - Scientific knowledge without practical application
- `support-work` - Programming, testing, data collection supporting above

**REMOVED (not CRA terminology)**:

- ~~systematic-investigation~~ (this is a METHOD, not a type)
- ~~technical-innovation~~ (not official CRA term)

**Project Identifier Format**: `PROJECT[-VARIANT]`

- PROJECT: Internal project name (uppercase, derived from scope)
- VARIANT: Optional sub-project identifier (e.g., `PROJECT-A-VARIANT`)
- Year/Quarter: Auto-detected from git commit timestamp at report time

Examples: `PROJECT-A`, `PROJECT-A-VARIANT`, `PROJECT-B`, `PROJECT-C`

**Year/Quarter Extraction** (at CRA report time):

```bash
# Extract Q1 2026 SR&ED commits with project identifiers
git log --since="2026-01-01" --until="2026-03-31" \
  --format='%ad|%an|%s|%(trailers:key=SRED-Type,valueonly)|%(trailers:key=SRED-Claim,valueonly)' \
  --date=short | grep -v '||$'

# Group by project (year-agnostic)
git log --format='%(trailers:key=SRED-Claim,valueonly)' | sort | uniq -c
```

## Core Principles

1. **No registry files** - Git history is the only source of truth
2. **No hardcoded project identifiers** - Discovered dynamically from git log
3. **CLI subscription only** - Uses Claude Agent SDK (not direct Anthropic API)
4. **Hook isolation** - `settingSources: []` prevents recursive hook execution
5. **Fail-open for crashes** - Hook crashes allow commit (safety); SDK errors use fallback suggestion (still blocks, but with derived project identifier)

## Official Documentation References

| Component                   | Verified Source                                                                                                        |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Hook output format          | [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)                                                   |
| `permissionDecision` values | [Hooks guide](https://platform.claude.com/docs/en/agent-sdk/hooks)                                                     |
| `settingSources` isolation  | [TypeScript SDK Reference](https://platform.claude.com/docs/en/agent-sdk/typescript)                                   |
| `query()` API               | [TypeScript SDK Reference](https://platform.claude.com/docs/en/agent-sdk/typescript)                                   |
| Model selection (`haiku`)   | [TypeScript SDK Reference - AgentDefinition](https://platform.claude.com/docs/en/agent-sdk/typescript#agentdefinition) |

## Architecture

```
MAIN SESSION (Opus/Sonnet)
│
├─ User runs: git commit -m "feat(<scope>): <description>"
│
├─ PreToolUse hook intercepts Bash tool
│
├─ Skip if: CLAUDE_HOOK_SPAWNED=1 (defense-in-depth)
│
├─ Detects: Missing SRED-Claim trailer
│
├─ Fork to Haiku session via Claude Agent SDK
│   │
│   ├─ settingSources: []     ← NO HOOKS (isolation)
│   ├─ model: "haiku"         ← Fast + cheap
│   ├─ maxTurns: 2            ← Bounded execution
│   ├─ allowedTools: ["Bash"] ← Minimal surface
│   │
│   ├─ Runs: git log (365 days, SRED-Claim trailers)
│   ├─ Analyzes commit context
│   └─ Returns: { suggested_project, confidence, reasoning }
│
├─ On success: Block commit with AI suggestion + AskUserQuestion
├─ On SDK/network error: Block with FALLBACK suggestion (scope-derived)
├─ On hook crash (unexpected): ALLOW commit (true fail-open for safety)
│
└─ Output: Always blocks missing trailers, but uses fallback on errors
```

## Cost Analysis

Uses Claude Code CLI subscription (no per-API-call charges).
Haiku model selected for speed within hook timeout budget.

## Safety Mechanisms

### Hook Recursion Prevention

- Primary: `settingSources: []` prevents hooks in spawned session
- Defense-in-depth: `CLAUDE_HOOK_SPAWNED` env var skips processing

### Offline Detection

- Quick TCP connect test to `api.anthropic.com:443` (100ms timeout)
- If offline: skip Haiku, use fallback immediately
- Prevents hanging on network issues

### Scope-Based Caching

- Cache location: `~/.cache/sred-hook/suggestions/`
- Cache key: hash of staged file paths + commit scope
- Invalidation: File hash changes OR 5-minute TTL expires
- If cache hit AND files unchanged: return cached suggestion
- Reduces redundant Haiku calls during rapid development

## Implementation

### File: `sred-discovery.ts` (NEW)

**Path:** `~/eon/cc-skills/plugins/itp-hooks/hooks/sred-discovery.ts`

**Language:** TypeScript/Bun (per lifecycle-reference.md "Hook Implementation Language Policy" - TypeScript is preferred for complex validation with business logic, educational feedback, and external API calls)

Key features:

- Spawns isolated Haiku session with `settingSources: []`
- Eight-second internal timeout (conservative vs default 60s; keeps git commit flow responsive)
- Input sanitization (4KB limit, control chars stripped)
- Offline detection (100ms TCP check before API call)
- Scope-based caching (5-minute TTL)
- Fallback suggestion on SDK errors (commit still blocked, but with derived suggestion)
- Follows lifecycle-reference.md TypeScript template pattern (pure `runHook()` + single `main()` entry)

Core logic:

- Skip immediately if `CLAUDE_HOOK_SPAWNED` is set
- Check cache first (by scope hash)
- If cache miss: check network connectivity
- If online: call `query()` with isolation options per SDK reference:

  ```typescript
  import { query } from "@anthropic-ai/claude-agent-sdk";

  for await (const msg of query({
    prompt: "Analyze git log and suggest project identifier...",
    options: {
      settingSources: [], // No filesystem settings = isolation
      model: "haiku", // Fast + cheap
      maxTurns: 2, // Bounded execution
      allowedTools: ["Bash"], // Minimal surface
    },
  })) {
    /* process messages */
  }
  ```

- Parse JSON result, cache it, return
- On ANY error: return fallback (scope-derived project identifier)

### File: `sred-commit-guard.ts` (MODIFY)

**Path:** `~/eon/cc-skills/plugins/itp-hooks/hooks/sred-commit-guard.ts`

Changes required:

- Remove `VALID_CLAIM_IDS` hardcoded array (lines 31-35)
- Remove `CONFIG.validateClaimIds` flag
- Fix `SRED_TYPES` (lines 22-28): remove `systematic-investigation`, `technical-innovation`; add `support-work`
- Import `discoverProject` from `./sred-discovery`
- Replace `validateSredClaim` to call discovery on missing trailer
- Wrap discovery call in try/catch with fail-open behavior

Logic flow:

- If SRED-Claim present: validate format only (PROJECT[-VARIANT], uppercase)
- If missing: call `discoverProject()` for AI suggestion
- Output `permissionDecisionReason` with structured text:
  - Suggested project + alternatives
  - Confidence indicator
  - Instructions for Claude to ask user
- Claude receives reason, uses AskUserQuestion to present choices
- On discovery error: block with fallback text suggestion

### Hook → Claude → AskUserQuestion Flow

Per lifecycle-reference.md, hooks CANNOT directly trigger AskUserQuestion. The correct flow is:

```
Hook blocks commit  →  Claude receives reason  →  Claude uses AskUserQuestion tool
       ↓                        ↓                           ↓
  permissionDecision: "deny"    Parses suggestions    Presents options to user
  permissionDecisionReason      Identifies choices    Collects user selection
```

**Hook Output Format** (per lifecycle-reference.md lines 561-576):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "[SRED-GUARD] Missing SRED-Claim trailer.\n\nSuggested project: <MATCHED-PROJECT>\nAlternatives: <ALT-1>, <ALT-2>\n\nPlease ask the user which project to use, then retry with:\nSRED-Claim: <selected-project>"
  }
}
```

**What Claude Sees** (from the reason):

- Hook blocking message
- Suggested project identifier
- Alternative options
- Instructions to ask user

**What Claude Does Next**:
Claude may use AskUserQuestion to present choices to the user. Example Claude behavior:

```json
{
  "question": "Which SR&ED project should this commit be tagged with?",
  "header": "SRED-Claim",
  "options": [
    {
      "label": "<MATCHED-PROJECT>",
      "description": "Matches N prior commits (recommended)"
    },
    { "label": "<ALT-1>", "description": "M prior commits" },
    { "label": "<ALT-2>", "description": "K prior commits" }
  ],
  "multiSelect": false
}
```

**Key Insight**: The hook provides information; Claude decides presentation. This is more flexible than hardcoding AskUserQuestion JSON in hook output.

### Fallback Text Examples (when AskUserQuestion unavailable)

**Example A: High Confidence Match**

```
Commit: <type>(<scope>): <description>

Haiku finds N commits with matching SRED-Claim in history.
Confidence: >= 0.8 (strong match)

Hook output:
  [SRED-GUARD] Missing SRED-Claim trailer.

  Suggested: SRED-Claim: <MATCHED-PROJECT>
  Reasoning: Scope '<scope>' matches N prior commits in <project>.

  Add this trailer to your commit message and retry.
```

**Example B: New Project (no history match)**

```
Commit: <type>(<new-scope>): <description>

Haiku finds no matching projects.
Confidence: < 0.5 (proposing new)

Hook output:
  [SRED-GUARD] Missing SRED-Claim trailer.

  No existing project matches. Options:
    1. SRED-Claim: <NEW-SCOPE>        (NEW)
    2. SRED-Claim: <existing-A>       (from history)
    3. SRED-Claim: <existing-B>       (from history)

  Reasoning: Scope '<new-scope>' has no prior SR&ED work.

  Add your chosen SRED-Claim and retry.
```

**Example C: Fallback (offline/error)**

```
Commit: <type>(<scope>): <description>

Network unavailable or timeout.

Hook output:
  [SRED-GUARD] Missing SRED-Claim trailer.

  (Discovery unavailable)
  Suggested: SRED-Claim: <SCOPE-UPPERCASE>

  Format: PROJECT[-VARIANT] (e.g., MYPROJECT, MYPROJECT-VARIANT)
  Add trailer and retry.
```

**Example D: Valid (passes through)**

```
Commit with valid trailers:
  SRED-Type: experimental-development | applied-research | basic-research | support-work
  SRED-Claim: <PROJECT[-VARIANT]>

Hook output: (none - allowed)
```

**Project Identifier Format**: `PROJECT[-VARIANT]`

- PROJECT: Derived from commit scope or Haiku suggestion (uppercase)
- VARIANT: Optional sub-identifier for related work streams
- Year/Quarter: Extracted from git commit timestamp at CRA report time

**CRA Terminology in Output**:

- Use "SR&ED project identifier" (not "claim ID")
- Use "type of SR&ED work" (not "category")
- Include non-SR&ED guidance: "Routine maintenance does NOT qualify"

This design is **universally applicable** - works with any:

- Repository (no hardcoded paths)
- Commit scope (extracted dynamically)
- Git history (learned at runtime)
- Project identifiers (`PROJECT[-VARIANT]` format, year/quarter from git)

## File Locations

**Plugin Source** (development):

```
~/eon/cc-skills/plugins/itp-hooks/hooks/
```

**ADR and Design Spec** (ITP workflow artifacts):

```
~/eon/cc-skills/docs/adr/2026-01-18-sred-dynamic-discovery.md
~/eon/cc-skills/docs/design/2026-01-18-sred-dynamic-discovery/spec.md
```

**Claude Code Config** (runtime):

```
~/.claude/settings.json  # Hooks synced here via manage-hooks.sh
```

## Files to Create/Modify

| File                                                             | Action                            |
| ---------------------------------------------------------------- | --------------------------------- |
| `~/eon/cc-skills/plugins/itp-hooks/hooks/sred-discovery.ts`      | CREATE                            |
| `~/eon/cc-skills/plugins/itp-hooks/hooks/failure-patterns.ts`    | CREATE (scripted failure outputs) |
| `~/eon/cc-skills/plugins/itp-hooks/hooks/sred-commit-guard.ts`   | MODIFY (remove invalid types)     |
| `~/eon/cc-skills/plugins/itp-hooks/tests/sred-discovery.test.ts` | CREATE (unit tests)               |
| `~/eon/cc-skills/plugins/itp-hooks/tests/sred-integration.sh`    | CREATE (integration tests)        |
| `~/eon/cc-skills/package.json`                                   | ADD SDK + Zod dependencies        |
| `~/eon/sred-analysis/SRED-REGISTRY.md`                           | UPDATE (fix category terminology) |

**SRED-REGISTRY.md Changes Required**:

- Remove `systematic-investigation` from valid types
- Remove `technical-innovation` from valid types
- Add `support-work` as valid type
- Update category descriptions to match CRA glossary

**Dependency Installation**:

```bash
cd ~/eon/cc-skills
bun add @anthropic-ai/claude-agent-sdk zod@3.24
```

Note: Zod must be version 3.x (not 4.x) due to SDK compatibility.

**Hook Sync** (after changes):

```bash
~/eon/cc-skills/plugins/itp-hooks/scripts/manage-hooks.sh install
```

## Verification

```bash
# Test A: Repo with existing SR&ED history
cd <any-repo-with-sred-commits>
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat(<scope>): test\""}}' | \
  bun ~/eon/cc-skills/plugins/itp-hooks/hooks/sred-commit-guard.ts
# Should suggest matching project from history

# Test B: New scope (no history match)
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat(<new-scope>): init\""}}' | \
  bun ~/eon/cc-skills/plugins/itp-hooks/hooks/sred-commit-guard.ts
# Should propose <NEW-SCOPE> (uppercase)

# Test C: Offline fallback
# Disconnect network, then run:
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix(<scope>): test\""}}' | \
  bun ~/eon/cc-skills/plugins/itp-hooks/hooks/sred-commit-guard.ts
# Should return fallback immediately (no hang)

# Test D: Cache hit verification
# Run same commit twice within 5 minutes
# Second run should be near-instant (cached)
ls ~/.cache/sred-hook/suggestions/

# Test E: Hook synced to Claude Code
grep -A5 "sred-commit-guard" ~/.claude/settings.json
```

## Prerequisites

**Claude Code CLI**: Must be installed and authenticated (no separate API key needed).
Uses CLI subscription for Haiku sessions.

## Success Criteria

### Core Functionality

- [ ] Zero hardcoded project identifiers
- [ ] Haiku analyzes git history via Claude Agent SDK
- [ ] Returns structured suggestion with reasoning
- [ ] Hook isolation via `settingSources: []`
- [ ] Fallback suggestion on SDK/network errors (still blocks, uses derived project ID)
- [ ] Output `permissionDecisionReason` with structured suggestions (Claude uses AskUserQuestion)

### Safety

- [ ] Offline detection skips API when disconnected
- [ ] Scope-based caching reduces redundant calls
- [ ] Bun compatible with Zod 3.x dependency

### SR&ED Maximization

- [ ] Keyword detection triggers eligibility prompts
- [ ] H-E-R-A body template suggested for eligible work
- [ ] Failed experiments recognized as positive evidence
- [ ] Routine commits auto-excluded from prompts
- [ ] Branch name auto-suggests SR&ED type
- [ ] Investigation chains detected and linked

## Fallback Behavior

When Haiku session fails (network, timeout, SDK error):

- Extract scope from commit: `feat(my-scope):` → `MY-SCOPE`
- Generate fallback project identifier: `MY-SCOPE`
- **Block commit** with fallback suggestion (still requires user to add trailer)
- Never blocks indefinitely - always provides actionable guidance

**Note**: This is NOT "fail-open" in the traditional sense. The commit is still blocked until the user adds a valid SRED-Claim trailer. The "fallback" simply provides a derived suggestion instead of an AI-analyzed one.

**Failure Notification (MANDATORY)**: All failures MUST end loudly by including structured text in `permissionDecisionReason` that instructs Claude to use `AskUserQuestion`. This ensures the user is always prompted for action, even on errors.

Example failure output:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "[SRED-GUARD] Discovery failed (network timeout).\n\nFallback suggestion: SRED-Claim: <SCOPE-DERIVED>\n\nPlease ask the user to confirm or select a different project identifier:\n- <SCOPE-DERIVED> (derived from scope)\n- Enter manually\n\nThen retry the commit with the selected SRED-Claim trailer."
  }
}
```

The `permissionDecisionReason` explicitly instructs Claude to use AskUserQuestion, ensuring failure is never silent.

**Failure Patterns (scripted)**: All failure outputs follow a consistent format for testability:

```typescript
// ~/eon/cc-skills/plugins/itp-hooks/hooks/failure-patterns.ts
export const FAILURE_PATTERNS = {
  NETWORK_TIMEOUT: {
    code: "NETWORK_TIMEOUT",
    message: "Discovery failed (network timeout)",
    instruction:
      "Please ask the user to confirm or select a different project identifier",
  },
  SDK_ERROR: {
    code: "SDK_ERROR",
    message: "Discovery failed (SDK error)",
    instruction:
      "Please ask the user to confirm the fallback suggestion or enter manually",
  },
  PARSE_ERROR: {
    code: "PARSE_ERROR",
    message: "Discovery failed (invalid response)",
    instruction: "Please ask the user which project identifier to use",
  },
} as const;

export function formatFailure(
  pattern: keyof typeof FAILURE_PATTERNS,
  fallbackProject: string,
  alternatives: string[],
): string {
  const { message, instruction } = FAILURE_PATTERNS[pattern];
  return (
    `[SRED-GUARD] ${message}.\n\n` +
    `Fallback suggestion: SRED-Claim: ${fallbackProject}\n` +
    (alternatives.length > 0
      ? `Alternatives: ${alternatives.join(", ")}\n`
      : "") +
    `\n${instruction}:\n` +
    `- ${fallbackProject} (derived from scope)\n` +
    alternatives.map((alt) => `- ${alt}`).join("\n") +
    `\n- Enter manually\n\n` +
    `Then retry the commit with the selected SRED-Claim trailer.`
  );
}
```

This module is imported by `sred-discovery.ts` and tested in `sred-discovery.test.ts`.

**Naming Convention Note**: The git trailer is `SRED-Claim` (fixed name). However, function names and variables should use "project" for clarity:

- `discoverProject()` not `discoverClaim()`
- `fallbackProject` not `fallbackClaim`
- `suggestedProject` not `suggestedClaim`

## SR&ED Maximization Features

### Keyword Detection + Prompts

HIGH confidence patterns (trigger strong suggestion):

- `experiment`, `hypothesis`, `investigate`, `prototype`, `research`
- `uncertain`, `unknown`, `novel`, `explore`, `analyze`

MEDIUM patterns (trigger soft suggestion):

- `optimize`, `algorithm`, `performance`, `ml`, `model`

ROUTINE patterns (auto-skip prompts):

- `chore:`, `docs:`, `style:`, `ci:`, `build:`, `typo`, `merge`

### H-E-R-A Commit Body Guidance

When SR&ED-eligible work detected, prompt for structured body:

```
HYPOTHESIS: <what we expected/believed>
EXPERIMENT: <methodology and approach>
RESULT: <SUCCESS/FAILED + quantified metrics>
ADVANCEMENT: <new knowledge gained>
```

### Failed Experiment Highlighting

Commits containing "FAILED", "did not achieve", "contrary to hypothesis":

- Recognize as POSITIVE CRA evidence
- Document shows genuine systematic investigation
- Prompt for detailed failure analysis

### Branch Name Intelligence

Auto-detect SR&ED type from branch prefix:

- `experiment/*`, `poc/*`, `prototype/*` → experimental-development
- `perf/*`, `optimize/*` → experimental-development (performance advancements)
- `investigate/*`, `research/*` → applied-research
- `test/*`, `qa/*` → support-work (testing supporting SR&ED)

### Investigation Chain Detection

Link related commits by:

- Same SRED-Claim within 72 hours
- Shared issue reference (EI-NNNN)
- Sequential work on same scope

Generate Investigation Cycle summary for stronger CRA evidence.

## Risk Mitigations (from critic review)

| Risk             | Mitigation                                           |
| ---------------- | ---------------------------------------------------- |
| Hook recursion   | `settingSources: []` + `CLAUDE_HOOK_SPAWNED` env     |
| Timeout exceeded | Eight-second internal timeout with abort             |
| Network failure  | Fallback suggestion (blocks with derived project ID) |
| Prompt injection | Input sanitization (4KB limit)                       |

## Testing Strategy

### Unit Tests (`sred-discovery.test.ts`)

- `sanitize()`: truncation, control char removal
- `generateFallback()`: scope extraction → uppercase PROJECT[-VARIANT]
- Cache key generation from file list
- Cache invalidation logic (TTL + file hash)

### Integration Tests (`sred-integration.sh`)

- Test A: Valid commit with existing SR&ED history
- Test B: New scope with no history (fallback path)
- Test C: Offline mode (network disconnected)
- Test D: Cache hit verification (two rapid commits)
- Test E: Cache invalidation (change staged files)
