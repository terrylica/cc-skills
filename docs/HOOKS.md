# Hooks Development Guide

Comprehensive guide for developing Claude Code hooks in the cc-skills marketplace.

## Hook Lifecycle

Claude Code hooks intercept tool calls at three lifecycle points:

| Hook Type     | When Triggered              | Can Block? | Use Case                     |
| ------------- | --------------------------- | ---------- | ---------------------------- |
| `PreToolUse`  | Before tool executes        | Yes        | Validation, enforcement      |
| `PostToolUse` | After tool executes         | Yes        | Verification, sync reminders |
| `Stop`        | When Claude stops executing | No         | Session metrics, cleanup     |

<!-- # SSoT-OK: This file documents the upstream Claude Code runtime bug
     reported in GitHub #55889 and references the affected upstream
     version. Those upstream version strings are NOT this marketplace's
     SSoT — they're external citations. The literal "# SSoT-OK" string
     above is the escape-hatch marker that pretooluse-version-guard.mjs
     greps for to allow upstream version mentions in this file. -->

## Hook Output Visibility (Critical)

**PostToolUse hooks**: Output is only visible to Claude when JSON contains `"decision": "block"`.

| Output Format                  | Claude Visibility |
| ------------------------------ | ----------------- |
| Plain text                     | Not visible       |
| JSON without `decision: block` | Not visible       |
| JSON with `decision: block`    | Visible           |

**Pattern for hooks that communicate with Claude**:

```bash
# PostToolUse hook - use JSON with decision:block
jq -n --arg reason "[HOOK] Your message" '{decision: "block", reason: $reason}'
exit 0
```

### Runtime Bash-Matcher Context-Channel Silent Drop (GitHub #55889 — OPEN as of 2026-05-18)

**Affected upstream Claude Code versions**: the `v2.1.123` regression of [#19432](https://github.com/anthropics/claude-code/issues/19432) — broader scope per the followup issue.

**Symptom**: For PreToolUse and PostToolUse hooks registered with `matcher: "Bash"`, **all three documented context-injection channels are silently dropped**:

| Channel                                | Outcome in affected versions |
| -------------------------------------- | ---------------------------- |
| `hookSpecificOutput.additionalContext` | dropped                      |
| top-level `systemMessage`              | dropped                      |
| plain stdout (text, not JSON)          | dropped                      |

The hook scripts execute correctly. The JSON output is well-formed. The harness receives the response (verified via diagnostic stdin-tracing). But none of it surfaces in the model's view of the tool result. **Other `hookSpecificOutput` fields still work**: `permissionDecision: "deny"` blocks correctly; `permissionDecisionReason` reaches the model on deny.

**Operator impact in this marketplace**: 26+ PostToolUse hooks (1Password reminder, ty-check, oxlint, biome, glossary-sync, etc.) register on the Bash matcher and emit reminders via plain stdout. On the affected Claude Code versions, those reminders may be silently dropped — operators see nothing in the transcript even though the hooks fire correctly.

**Confirmed workaround (verified in the affected version)**: `SessionStart` hook with `additionalContext` reliably injects context (the model's first response in a fresh session correctly references the injected reminder). For per-tool-call context that can't be expressed at session start, there's no current workaround beyond waiting for the upstream Claude Code regression to be fixed.

**Diagnosis check**: If a PostToolUse Bash hook in this marketplace appears to be "not firing" (no reminder visible to Claude), verify the hook actually executes (check `/tmp/<plugin>-<hook>-debug.log` or equivalent) before assuming the hook code is broken. The hook is likely running correctly — the runtime is dropping its output.

**Forensic source**: [GitHub #55889](https://github.com/anthropics/claude-code/issues/55889) (filed 2026-05-03, OPEN, last updated 2026-05-18 — track this issue for fix availability).

### Schema-Validator Rejection of Stop Hook additionalContext (GitHub #60993 — OPEN as of 2026-05-20)

**Forensic confirmation of the iter-66/67/68/69 audit chain.** GitHub #60993 (filed 2026-05-20, OPEN, label: `enhancement` + `area:hooks`) is an upstream feature request titled _"Revive #24244 — Stop hook needs additionalContext (or continueWith) for clean workflow continuation"_. The reporter cites the exact validator-side rejection message they received when trying to emit `additionalContext` from a Stop hook:

> "hookEventName: Stop is not a permitted value for hookSpecificOutput"

This validator error is a **hard upstream signal** (stronger than third-party blog research) that the Claude Code schema **currently rejects** Stop hook `additionalContext` at the input-validation layer — confirming the iter-66/67/68/69 audit's premise from an independent community-filed bug report.

**Why the issue exists** (from the reporter):

| Approach the reporter tried                     | Outcome                                                          |
| ----------------------------------------------- | ---------------------------------------------------------------- |
| `Stop` + `hookSpecificOutput.additionalContext` | ❌ Schema validator rejects                                      |
| `Stop` + `decision: "block"` + `reason`         | ⚠ Works but renders red **"Stop hook blocked"** error banner     |
| `UserPromptSubmit` + `additionalContext`        | ✅ Works but 1-turn delay; misses end-of-session firing entirely |

The reporter's `decision: "block"` workaround is exactly the path documented in the iter-66/67/68/69 audit's violation diagnostic — confirming it's the correct community-consensus current workaround.

**Schema-evolution watch**: if Anthropic accepts #60993 (or any of its duplicate predecessors [#24244](https://github.com/anthropics/claude-code/issues/24244), [#50682](https://github.com/anthropics/claude-code/issues/50682), [#46191](https://github.com/anthropics/claude-code/issues/46191), [#34600](https://github.com/anthropics/claude-code/issues/34600)) and ships a schema change adding `additionalContext` support to Stop hooks OR introducing a `continueWith` field that delivers context without the `decision:"block"` red-banner side effect — the iter-67/68/69 audit's premise would invert. The audit task header documents the mitigation plan (track #60993 close-status; on schema change, extend the case-statement diagnostic with a new branch differentiating "additionalContext now supported in newer Claude Code versions" from "still silent-dropped").

**Forensic source**: [GitHub #60993](https://github.com/anthropics/claude-code/issues/60993) (filed 2026-05-20, OPEN — track for schema-change signal).

## PreToolUse Hook Patterns

### Soft Block (User Can Override)

```javascript
#!/usr/bin/env bun
const input = await Bun.stdin.text();
if (!input.trim()) process.exit(0);

const data = JSON.parse(input);
const command = data.tool_input?.command ?? "";

if (shouldBlock(command)) {
  console.log(
    JSON.stringify({
      permissionDecision: "deny",
      reason: "[hook-name] Blocked: reason here\n\nUse alternative approach...",
    }),
  );
}
process.exit(0);
```

### Hard Block (No Override)

```bash
#!/usr/bin/env bash
# Exit code 2 = hard block
echo '{"error": "Operation not permitted"}'
exit 2
```

## hooks.json Structure

```json
{
  "description": "Plugin description",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/my-hook.mjs",
          "timeout": 5000
        }]
      }
    ],
    "PostToolUse": [...],
    "Stop": [...]
  }
}
```

## Timeout Values

Timeouts are in **milliseconds**:

| Value | Duration | Use Case          |
| ----- | -------- | ----------------- |
| 5000  | 5s       | Simple validation |
| 15000 | 15s      | Git operations    |
| 30000 | 30s      | Network calls     |

**Common mistake**: Using `15` instead of `15000` results in 15ms timeout.

## Network-Calling Hooks (Critical Warning)

**Avoid hooks that spawn network-calling processes** (e.g., `gh api`, `curl`, `wget`).

PreToolUse/PostToolUse hooks run on **every** tool invocation. During rapid operations (e.g., disabling 36 workflows, bulk file edits), network-calling hooks spawn hundreds of processes that pile up:

- Load average can exceed 130
- Fork failures: "resource temporarily unavailable"
- May require forced reboot to recover

**Root cause**: Network latency (~1-2s) accumulates while new hook invocations spawn faster than they complete.

**Solution**: Pre-configure authentication/validation via mise `[env]` instead of runtime validation.

**Pattern**: Pre-configure auth in mise `[env]` to avoid runtime subprocess storms.

## Hook Installation

Hooks defined in plugin `hooks.json` must be synced to `~/.claude/settings.json`:

```bash
# Via plugin's manage-hooks.sh
./plugins/my-plugin/scripts/manage-hooks.sh install

# Via global sync script (post-release)
./scripts/sync-hooks-to-settings.sh
```

## Hook Source Edits Don't Take Effect Until Next Tagged Release (3-Layer Versioned Cache Lifecycle)

<!-- SSoT-OK: this section references SemVer placeholders as documentation patterns, not as code configuration. -->

**Empirical discovery, iter-42 (2026-05-20)**: when you `git commit` a fix to a hook source file, the running Claude Code session does NOT immediately pick up the change — and frequently NEITHER does the next session. The hook continues to behave as before for hours-to-days. This section explains why and how to work around it.

### The 3-Layer Cache Architecture

cc-skills hooks travel through three independent storage layers on the operator's machine. Claude Code reads from the deepest layer; your `git push` only updates the shallowest:

```
LAYER 1: WORKING DIRECTORY                                                 ┐
  /Users/<you>/eon/cc-skills/plugins/<plugin>/hooks/<hook>.sh              │ your edits live here
                                                                            │ git push → GitHub remote
                                                                            ┘
                              │
                              │ (next tagged release via semantic-release CI)
                              ▼
LAYER 2: MARKETPLACE MIRROR                                                ┐
  ~/.claude/plugins/marketplaces/cc-skills/plugins/<plugin>/hooks/<hook>.sh│ pulled from GitHub main
                                                                            │ tracks the latest source
                                                                            ┘
                              │
                              │ (Claude Code plugin runtime sees new tag)
                              ▼
LAYER 3: VERSIONED CACHE — what Claude Code ACTUALLY loads at fire time    ┐
  ~/.claude/plugins/cache/cc-skills/<plugin>/<vX.Y.Z>/hooks/<hook>.sh      │ keyed by SemVer tag
  ~/.claude/plugins/cache/cc-skills/<plugin>/<vX.Y.Z-1>/hooks/<hook>.sh    │ historical versions
  ~/.claude/plugins/cache/cc-skills/<plugin>/<vX.Y.Z-2>/hooks/<hook>.sh    │ retained for rollback
                                                                            ┘
```

The `${CLAUDE_PLUGIN_ROOT}` variable resolves to the LAYER 3 path at hook fire time, NOT the LAYER 1 or LAYER 2 path. This is why source edits committed at LAYER 1 don't change runtime behavior — Claude Code reads the cached snapshot at the most recent SemVer tag, not the working-directory source.

### Symptom Pattern

The PostToolUse output from a hook keeps showing the OLD behavior even though:

- Your fix is committed to `main`
- `git log` shows your commit
- `cat plugins/<plugin>/hooks/<hook>.sh` at Layer 1 shows the fix
- `cat ~/.claude/plugins/marketplaces/.../hooks/<hook>.sh` at Layer 2 shows the fix
- BUT `cat ~/.claude/plugins/cache/.../<latest-tag>/hooks/<hook>.sh` at Layer 3 shows the OLD source

Until semantic-release publishes a new tag, Layer 3 stays frozen at the pre-fix snapshot.

### When Does the Cache Refresh?

The versioned cache refreshes when ALL of the following happen in sequence:

1. `git push` to `main` with a Conventional Commit message that triggers semantic-release (`fix:`, `feat:`, `perf:`, breaking change). `docs:` / `chore:` / `test:` do NOT trigger a release.
2. semantic-release CI runs and publishes a new tag.
3. The operator's Claude Code plugin runtime polls the marketplace, sees the new version, and downloads it to a new versioned cache directory.
4. The operator restarts Claude Code OR invokes `/reload-plugins` in the active session.

Steps 3 and 4 are operator-side; they don't happen automatically when you push.

### Workarounds During Active Development

For development workflows where you want hook edits to take effect immediately without cutting a release:

**A. Manual cache overwrite (fast feedback loop, single-version)**:

```bash
# After editing the source at LAYER 1:
PLUGIN=<plugin-name>
HOOK=<hook-filename>
LATEST_VERSION=$(ls -1 ~/.claude/plugins/cache/cc-skills/$PLUGIN/ | sort -V | tail -1)
cp plugins/$PLUGIN/hooks/$HOOK \
   ~/.claude/plugins/cache/cc-skills/$PLUGIN/$LATEST_VERSION/hooks/$HOOK
# Then in your active Claude Code session, run /reload-plugins (or restart)
```

This overwrites Layer 3 with your Layer 1 edits without going through a release. Effective immediately on next hook fire. WARNING: any cache eviction or version-poll refresh will revert this overlay — re-apply if the hook stops behaving as expected.

**B. Symlink the cached hook to the working copy (persistent across reloads, until next release)**:

```bash
PLUGIN=<plugin-name>
HOOK=<hook-filename>
LATEST_VERSION=$(ls -1 ~/.claude/plugins/cache/cc-skills/$PLUGIN/ | sort -V | tail -1)
ln -sf "$(pwd)/plugins/$PLUGIN/hooks/$HOOK" \
       "$HOME/.claude/plugins/cache/cc-skills/$PLUGIN/$LATEST_VERSION/hooks/$HOOK"
```

Every edit at Layer 1 is now reflected in Layer 3 immediately. WARNING: the next tagged release will replace the symlink with a regular file copy of the new tag's source.

**C. Cut a release**:

```bash
mise run release:full   # full release pipeline, including marketplace publish
```

The canonical path. Use this when you have a stable batch of changes ready to ship.

### Diagnosis Recipe — "My Hook Fix Isn't Working"

When a hook behaves like an old version despite a fresh source edit:

```bash
PLUGIN=<plugin-name>
HOOK=<hook-filename>
MARKER='<your-fix-marker-string>'

# 1. Confirm Layer 1 has your edit
grep -c "$MARKER" plugins/$PLUGIN/hooks/$HOOK

# 2. Confirm Layer 2 (marketplace mirror) has your edit
grep -c "$MARKER" \
  ~/.claude/plugins/marketplaces/cc-skills/plugins/$PLUGIN/hooks/$HOOK

# 3. Check Layer 3 (versioned cache — what Claude Code actually runs)
for d in ~/.claude/plugins/cache/cc-skills/$PLUGIN/*/; do
  echo "$(basename "$d"): $(grep -c "$MARKER" "$d/hooks/$HOOK") fix markers"
done

# 4. Check the latest tag — your fix reaches Layer 3 only after a new tag publishes
git tag --sort=-creatordate | head -1
git log --oneline "$(git describe --tags --abbrev=0)..HEAD" --grep "$MARKER"
```

If Layer 1 + Layer 2 have your fix but Layer 3 does not, the diagnosis is a pending-release lag, not a bug in your fix.

### Iter-76 Algorithmic Drift Detector (Companion Tool to the Hand-Typed Recipe)

The hand-typed recipe above probes one hook at a time and relies on operator-chosen marker strings. Iter-76 ships an algorithmic content-hash-based detector that scans EVERY plugin and reports L2-vs-L3 divergence per plugin without needing markers:

```bash
# Default: per-plugin summary across all plugins, filtered to cache-populator-kept paths
mise run audit-marketplace-mirror-layer2-vs-versioned-operator-cache-layer3-per-plugin-content-hash-drift-detector-for-iter42-three-layer-cache-lifecycle-operator-self-diagnosis

# Focus on a single plugin
... --check-plugin <plugin-name>

# Per-file divergence list for each STALE plugin
... --verbose

# Forensic mode: include cache-populator's documented benign omissions
# (CLAUDE.md, README.md, docs/, scripts/, tests/, templates/, schemas/)
... --all-divergences
```

Exit code 0 if all plugins FRESH or NOT-CACHED; exit code 1 if any STALE-CACHE detected — gates CI scripts that want to fail on operator-cache drift.

### Iter-76 Cache-Populator-Filter Forensic Finding

**Discovered while building the iter-76 drift detector**: Claude Code's plugin cache populator (L2→L3) does NOT copy the plugin source tree verbatim. It keeps ONLY these subtrees at the plugin root:

| Path                       | Cached at Layer 3? | Purpose                         |
| -------------------------- | ------------------ | ------------------------------- |
| `plugin.json`              | YES                | Plugin manifest                 |
| `hooks/**` (recursive)     | YES                | Executable hooks + their assets |
| `skills/**` (recursive)    | YES                | SKILL.md + skill resources      |
| `commands/**` (recursive)  | YES                | Slash-command definitions       |
| `agents/**` (recursive)    | YES                | Sub-agent definitions           |
| `CLAUDE.md`                | NO                 | Dev-time per-plugin docs        |
| `README.md`                | NO                 | Install/usage docs              |
| `docs/**`                  | NO                 | Design docs                     |
| `scripts/**`               | NO                 | Helper scripts (dev-time)       |
| `tests/**`                 | NO                 | Regression tests                |
| `templates/**`             | NO                 | Templates (consumed dev-time)   |
| `schemas/**`               | NO                 | JSON schemas                    |
| `LICENSE` / `CHANGELOG.md` | NO                 | Distribution metadata           |

**Operator-impact implications**:

1. If your hook references `${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh` it WILL FAIL at runtime — `scripts/` is stripped from L3. Either move helper scripts under `hooks/` (which IS cached) or invoke them via absolute path from the marketplace mirror.

2. SKILL.md is cached, but skill-internal `references/` subdirs under `skills/<skill>/references/` ARE cached (because they're under `skills/**`). So skill references work.

3. Plugin-root-level `CLAUDE.md` files (added in 2026 for self-explanatory scaffolding) ARE NOT cached. They're discoverable only from L2 (marketplace mirror), not L3. This is intentional — CLAUDE.md is for human + AI dev-context, not for runtime invocation.

The drift detector defaults to filtering by cached-subtree-only paths so the operator sees only **actionable** drift (hook/skill/command/agent content divergence). Use `--all-divergences` to surface the full L2-vs-L3 delta when you suspect the cache populator's filter rules have changed in a Claude Code update.

### Iter-77 + Iter-78 Dual-Defense Architecture for L3-Stripped-Path Prevention

The iter-76 forensic finding (above) drove two complementary preventive gates:

| Layer        | Iter | Gate                                                                                      | Trigger                      | Outcome                                                                            |
| ------------ | ---- | ----------------------------------------------------------------------------------------- | ---------------------------- | ---------------------------------------------------------------------------------- |
| Edit-time    | 78   | `pretooluse-iter78-layer3-stripped-path-edit-time-guard.ts` (Write\|Edit\|MultiEdit)      | Operator typing now          | Hook denies the edit before the violating reference lands on disk                  |
| Release-time | 77   | `audit-hook-source-files-for-references-to-iter76-cache-populator-stripped-paths…sh` (4k) | `mise run release:preflight` | Audit blocks tag publish if any hook source file contains an unjustified reference |

Both gates use the SAME allowlist (`{hooks, skills, commands, agents, plugin.json}`) and the SAME escape-hatch marker syntax (`LAYER3-STRIPPED-PATH-OK: <reason ≥ 10 chars>` on the same line OR within the three preceding lines).

**Why two layers**:

1. **Edit-time** catches the violation at the moment of authorship — fastest feedback, lowest cost to fix. Belt-and-suspenders defense (stdout JSON `permissionDecision: "deny"` + stderr diagnostic + `exit 2`) per [GitHub issue #37210](https://github.com/anthropics/claude-code/issues/37210), which documents that PreToolUse `deny` is honored for Write but ignored for Edit on some Claude Code versions. Stderr + exit 2 still hard-blocks even when stdout JSON is silently dropped.
2. **Release-time** catches anything that snuck past the edit-time gate (external edits, agent-bypassed sessions, hook-disabled sessions, copy-pasted code from L2 docs). Final guarantee before the tag publishes.

**Performance budget**: edit-time hook uses pre-JSON-parse fastpath — but the savings are bounded by the bun-cold-start floor (~44ms). See "Edit-Time Hook Overhead Cost Model" below.

## Edit-Time Hook Overhead Cost Model (iter-80 Forensic Finding)

The iter-39 / iter-40 / iter-41 / iter-55 / iter-56 "pre-JSON-parse fastpath" pattern was previously documented as "~70-200x speedup on bail-out paths". Iter-80 forensic measurement REVISES that claim with a more accurate cost model.

### Measured baseline (representative non-applicable payload)

| Hook category                                                             | Median latency over 5 runs |
| ------------------------------------------------------------------------- | -------------------------- |
| bun cold-start no-op (only emits `permissionDecision: "allow"` JSON)      | **44 ms**                  |
| Real PreToolUse hook WITH pre-JSON-parse fastpath, non-applicable payload | ~38-44 ms                  |
| Real PreToolUse hook WITHOUT fastpath, non-applicable payload             | ~39-52 ms                  |

### What this means

1. **bun process spawn dominates** edit-time hook overhead. Real-hook logic adds only ~0-8 ms beyond the bun-cold-start floor on bail-out paths.
2. **Within-hook fastpath savings are at most ~8 ms per hook** — NOT the "~70-200x speedup" previously documented. The pattern is still defensible for hooks that would otherwise pay a `jq` subprocess on every invocation (where jq adds ~15-50 ms), but the speedup ratio is bounded by bun's startup cost regardless of how trivial the in-hook fastpath check becomes.
3. **Aggregate worst-case sequential-firing overhead** for the cc-skills marketplace's current 22 PreToolUse hooks: **~884 ms** (every hook firing on a single Write/Edit). In practice each matcher narrows scope so actual per-edit overhead is lower — but the lower bound for N hooks firing is `N × ~44 ms`.

### Implication: to meaningfully reduce edit-time hook overhead, REDUCE THE BUN SPAWN COUNT

Three strategies, ordered by leverage:

| Strategy                                                                                                 | Effort               | Savings                               | Notes                                                              |
| -------------------------------------------------------------------------------------------------------- | -------------------- | ------------------------------------- | ------------------------------------------------------------------ |
| 1. PreToolUse orchestrator (combine N subhooks into 1 bun process — iter-66 stop-orchestrator precedent) | high (architectural) | ~`(N-1) × 44 ms` for N combined hooks | Saves ~352 ms across the 10-hook Write\|Edit chain if all combined |
| 2. AOT-compile hooks via `bun build --compile`                                                           | medium               | ~few ms per hook                      | Marginal, composable with #1                                       |
| 3. Within-hook fastpath (raw-stdin substring check before JSON parse)                                    | low                  | ~5-8 ms per hook on bail-out paths    | Useful but marginal — savings hard-capped by bun-startup floor     |

### Self-measurement tool

The forensic baseline above can be reproduced (and regression-watched) via:

```bash
mise run profile-edit-time-pretooluse-hook-cold-start-bun-spawn-overhead-with-non-applicable-payload-to-surface-high-overhead-outliers-above-bun-startup-floor
```

The task discovers every `plugins/*/hooks/pretooluse-*.{ts,mjs}` hook, profiles each over N=5 runs with median aggregation, flags HIGH-OVERHEAD outliers (>50ms median), and prints the optimization-strategy guidance table above. Use it to:

- Catch new-hook regressions before a hook lands (any hook >50 ms median needs investigation)
- Decide whether a planned new hook needs a fastpath (probably not — the savings are marginal)
- Verify the bun-startup-cost-floor claim if Anthropic changes the bun runtime

### Why pre-jq-fastpath is still worth it (the cases where the perf model differs)

The pre-JSON-parse fastpath documented in iter-39/40/41/55/56 was for hooks that called **`jq`** for stdin parsing instead of `JSON.parse`. `jq` is a subprocess (~15-50 ms additional fork-exec on each invocation), so checking a raw-stdin substring with bash's `case` builtin BEFORE the `jq` call DOES yield the documented "~70-200x speedup" — but the speedup is measured against the `jq` subprocess cost, not against the bun-cold-start floor (which doesn't apply to bash hooks).

For TypeScript / `.mjs` hooks that use `Bun.stdin.text()` + `JSON.parse`, the fastpath helps but the savings cap at ~8 ms per hook because bun startup dominates.

## Testing Hooks

### Manual Testing

```bash
# Test hook with sample input via pipe
echo '{"tool_name": "Bash", "tool_input": {"command": "gh issue create --title test"}}' | \
  bun plugins/gh-tools/hooks/gh-repo-identity-guard.mjs
```

### Unit Testing with Bun

For complex hooks, create a companion test file using `bun:test`:

```typescript
// hooks/my-hook.test.ts
import { describe, expect, it } from "bun:test";
import { execSync } from "child_process";
import { join } from "path";

const HOOK_PATH = join(import.meta.dir, "my-hook.ts");

function runHook(input: object): { stdout: string; parsed: object | null } {
  const inputJson = JSON.stringify(input);
  const stdout = execSync(`bun ${HOOK_PATH}`, {
    encoding: "utf-8",
    input: inputJson, // Use stdin to avoid shell escaping issues
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();

  return { stdout, parsed: stdout ? JSON.parse(stdout) : null };
}

describe("My Hook", () => {
  it("should block forbidden pattern", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "forbidden-command" },
    });
    expect(result.parsed?.decision).toBe("block");
  });

  it("should allow valid pattern", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "valid-command" },
    });
    expect(result.stdout).toBe(""); // No output = allow
  });
});
```

Run tests:

```bash
bun test plugins/itp-hooks/hooks/posttooluse-reminder.test.ts
```

## Hook Language Policy

**Preferred Language: TypeScript (Bun)**

Use TypeScript/Bun as the default for new hooks. Only use bash for simple pattern matching.

| Criteria                 | Bash             | TypeScript        |
| ------------------------ | ---------------- | ----------------- |
| Simple pattern matching  | Preferred        | Overkill          |
| Complex validation logic | Hard to test     | **Preferred**     |
| Educational feedback     | Heredocs awkward | Template literals |
| Type safety              | None             | Full              |

**Reference**: [lifecycle-reference.md](/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) → "Hook Implementation Language Policy"

## Plugins with Hooks

| Plugin               | Hook Types                    | Purpose                             |
| -------------------- | ----------------------------- | ----------------------------------- |
| `itp-hooks`          | PreToolUse, PostToolUse, Stop | Workflow + SR&ED + GPU optimization |
| `ru`                 | PreToolUse, Stop              | Autonomous loop control             |
| `gh-tools`           | PreToolUse, PostToolUse       | GitHub CLI enforcement              |
| `dotfiles-tools`     | PostToolUse, Stop             | Chezmoi sync reminder               |
| `statusline-tools`   | Stop                          | Session metrics                     |
| `productivity-tools` | PreToolUse                    | Calendar event management           |
| `gmail-commander`    | Stop                          | Bot lifecycle management            |
| `calcom-commander`   | Stop                          | Bot lifecycle management            |
| `tts-tg-sync`        | Stop                          | TTS/bot process cleanup             |

## Related ADRs

- [PreToolUse/PostToolUse Architecture](/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md)
- [Hook Visibility Issue](/docs/adr/2025-12-17-posttooluse-hook-visibility.md)
- [ITP Hooks Settings Installer](/docs/adr/2025-12-07-itp-hooks-settings-installer.md)
- [Polars Preference Hook](/docs/adr/2026-01-22-polars-preference-hook.md)

## Reference Implementation

See [lifecycle-reference.md](/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) for detailed hook development patterns.
