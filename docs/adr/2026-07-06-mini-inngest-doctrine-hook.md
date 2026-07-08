# ADR: Mini-Inngest Doctrine Hook (2026-07-06)

**Date**: 2026-07-06  
**Status**: Accepted  
**Severity**: Soft nudge (non-blocking reminder via PostToolUse)

---

## Context

External/web-facing services and off-web monitors are traditionally set up locally via launchd plists, cron jobs, or manual systemd services. This leads to fragmented operational state: each machine ends up with its own bespoke configurations, logging, monitoring, and deployment procedures.

The **Mac Mini** runs the **Inngest workflow engine** — a shared, durable, centralized orchestrator for all recurring tasks and service integrations. Services deployed there are immediately visible to the team, benefit from unified logging/alerting/retry logic, and survive machine restarts and updates gracefully.

This ADR codifies a soft nudge to steer developers toward the Mac Mini standard, rather than silently accepting local deployments.

---

## Decision

Implement a **soft PostToolUse hook** (`posttooluse-mini-inngest-doctrine.ts`) that emits a non-blocking reminder when the agent (Claude) appears to be setting up an external/web-facing service or off-web monitor locally/manually, rather than delegating to the Mac Mini + Inngest.

**Key traits**:

- **Soft nudge only**: emits `{decision:"block", reason:"..."}`; does NOT block or undo the tool (per ADR 2025-12-17)
- **Non-intrusive**: fires on clear signals (launchd context + external target), not on all mentions of keywords
- **Precise heuristic**: explicit launchd/cron patterns trigger alone; other keywords require both an actionable context AND an external target
- **Escape-hatchable**: `MINI-INNGEST-OK` marker silences it (registered in the iter-111 canonical registry)
- **Documented**: spoke at `docs/mini-inngest-doctrine.md`, SSoT explanation at `~/.claude/skills/homelab/references/workflows.md`

---

## Rationale

1. **Centralized operations**: The Mac Mini + Inngest is the single, durable, team-visible place for recurring services. Each machine running its own monitors/webhooks/pollers is operationally fragile and invisible to others.

2. **Soft enforcement**: Unlike the git-worktree-guard (which denies), this nudge aims to _educate_, not _block_. Developers retain the option to set up locally (via `MINI-INNGEST-OK`) if there's a legitimate reason (testing, temporary debugging, non-standard deployments).

3. **Reuses existing infra**: The hook reuses the `isRemoteCommand()` classifier from `readonly-command-detector.ts` and the iter-107 canonical escape-hatch helper (`hasFileWideEscapeHatchMarkerInContent`). No new utility code needed.

4. **Low noise**: The trigger heuristic deliberately avoids broad keyword matching (e.g., `webhook` alone doesn't fire). It requires either:
   - Explicit launchd/cron context (strong signal), OR
   - A keyword + external target + actionable pattern (reduces false positives in documentation)

---

## Trigger Design

### Explicit Context (Fire Immediately)

These patterns are self-documenting as service setup:

- `launchctl bootstrap` / `launchctl load`
- `LaunchAgent` / `LaunchDaemons` labels/paths
- `StartInterval` plist key (periodic execution)
- `crontab` / `cron -e` commands

### Keywords + External Target (Actionable Pattern)

For other signals, require **both**:

1. **Keyword**: `webhook`, `poll`, `monitor`, `uptime`, `serve`, `forward`, `deploy`, `redirect`, `notify`, etc.
2. **Actionable context**: appears in assignment/call, not documentation:
   - `webhook_url=https://api.example.com`
   - `--poll-endpoint https://external.io`
   - `monitor-host=api.service.io`
3. **External target**: hostname like `example.com`, `api.io` (excludes `localhost`, `.local`, `.ts.net`)

This design avoids firing on `echo 'webhook example.com'` (documentation) while catching real deployments.

---

## Output Contract

When triggered, emits to stdout (Claude-visible channel per ADR 2025-12-17):

```json
{
  "decision": "block",
  "reason": "[MINI-INNGEST] External/web-facing service or off-web monitor detected.\n..."
}
```

The `reason` field includes:

- Problem statement (what was detected)
- Standard deployment path (define service → deploy via mini-deploy → access UI)
- Clarification on terminology ("Inngest" = workflow engine, not "coa ingest" CLI)
- Reference to homelab skill for how-to
- Escape-hatch syntax (`MINI-INNGEST-OK`)

---

## Escape Hatch

Marker: `MINI-INNGEST-OK` (registered in `marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts`)

**Modes**: FILE_WIDE (any comment style or bare marker in the file content)

**Use when**:

- Temporary local debugging that will be cleaned up
- Non-standard deployment with documented justification
- Development server that genuinely shouldn't run on the Mac Mini

**Example**:

```bash
# MINI-INNGEST-OK - testing webhook locally before deploying to Mini
launchctl bootstrap ~/Library/LaunchAgents test-webhook.plist
```

---

## Alternatives Considered

### A. Hard Deny (Like git-worktree-guard)

**Rejected**: The Mini + Inngest standard is an _architectural preference_, not a hard safety invariant (like protecting git branch state). Developers need the flexibility to test locally or run non-standard setups.

### B. Broad Keyword Matching Without Context

**Rejected**: Would fire on documentation (e.g., READMEs, comments), creating noise. The actionable pattern filter keeps signal-to-noise ratio high.

### C. Require External Target Only (No Explicit Context)

**Rejected**: Misses the strong signal of `crontab -e` or `launchctl bootstrap` on their own. By firing on explicit context alone, we catch the most obvious cases without waiting for additional clues.

---

## Implementation Details

**Files created**:

- `hooks/posttooluse-mini-inngest-doctrine.ts` — the hook logic
- `hooks/posttooluse-mini-inngest-doctrine.test.ts` — 24 test cases (all passing)
- `docs/mini-inngest-doctrine.md` — operator documentation (spoke)

**Files modified**:

- `hooks/hooks.json` — registered in PostToolUse matchers `Bash|Write|Edit|MultiEdit`
- `lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts` — added `MINI-INNGEST-OK` entry

**Dependencies reused**:

- `isRemoteCommand()` from `readonly-command-detector.ts` (external target classification)
- `hasFileWideEscapeHatchMarkerInContent()` from `shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts` (marker detection)
- `trackHookError()` from `hook-error-tracker.ts` (error logging)

**Fail-open semantics**: Any error in detection or regex matching exits with code 0 silently; never blocks work.

---

## Test Coverage

24 tests (all passing):

**Positive cases** (should trigger):

- LaunchAgent plist with external webhook URL
- Crontab entry
- SSH with monitor script
- Launchctl bootstrap
- Webhook/poll/monitor keywords with external target URLs

**Negative cases** (should NOT trigger):

- Localhost / 127.0.0.1 dev servers
- `.local` domain references
- Tailnet references (`.ts.net`)
- Documentation/comments (e.g., `echo 'webhook example.com'`)
- Read-only commands
- Files without trigger patterns
- Payloads with `MINI-INNGEST-OK` escape hatch

**Edge cases**:

- Empty payloads
- Unknown tool names
- Malformed JSON (fail-open)

---

## Consequences

**Positive**:

- Nudges toward centralized operations (Mac Mini + Inngest)
- Soft, non-blocking (doesn't frustrate developers)
- Reuses proven escape-hatch infrastructure
- Low false-positive rate via actionable pattern filtering

**Negative**:

- Requires users to understand the Mini + Inngest doctrine (mitigated by linked documentation)
- One more PostToolUse hook in the chain (marginal latency cost, ~20ms)

---

## Related ADRs

- **2025-12-17**: PostToolUse hook visibility (the `{decision:"block", reason}` channel)
- **2026-06-22**: Git worktree guard (related enforcement pattern, but hard deny vs. soft nudge)
- **iter-111**: Marketplace-wide escape-hatch marker canonical registry

---

## Future Directions

- Extend the homelab skill with mini-deploy and tenant-service setup playbooks
- Add metrics to `~/.claude/mini-inngest-doctrine-metrics.json` to track nudge effectiveness
- Consider promoting to a hard deny if the standard becomes universally adopted
