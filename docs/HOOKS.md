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
     above is the escape-hatch marker that pretooluse-version-guard.ts
     (renamed from .mjs in iter-85) greps for to allow upstream version
     mentions in this file. -->

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

### Community-validation of the orchestrator direction (iter-83 web research)

Iter-83 web research confirms strategy #1 above is the convergent 2026 best-practice in the broader Claude Code community:

- **[claude-code-workflow-orchestration](https://github.com/barkain/claude-code-workflow-orchestration)** consolidated 3 hooks into 1 Python script with a "stub orchestrator" pattern: ~1.1KB stub injected at SessionStart, full orchestrator (~7.5KB) loaded only on first delegation. Same architecture as iter-66 `stop-orchestrator.ts` but applied to SessionStart, saving ~6.6K tokens.
- **[Morph LLM's Claude Code as Orchestrator (2026)](https://www.morphllm.com/claude-orchestrator)** documents the 12 lifecycle hook events and identifies PreToolUse/PostToolUse + SubagentStart/SubagentStop as the highest-leverage consolidation targets.
- **[Boris Cherny's own setup](https://www.clarista.io/blog/claude-code-best-practices)** (Claude Code's creator) uses `bun run format` as a PostToolUse hook, validating the Bun-first hook language policy in the cc-skills marketplace.
- **[Obvious Works 2026 architecture guide](https://www.obviousworks.ch/en/designing-claude-md-right-the-2026-architecture-that-finally-makes-claude-code-work/)** flags Hooks + Skills + Multi-session as the three load-bearing systems that distinguish "experienced teams from amateur users by end of Q2 2026."

These independent practitioners converged on the same insight that iter-80's measurement crystallized: bun spawn count, not in-hook logic, dominates edit-time hook overhead. Future iter-83+ work building the actual PreToolUse orchestrator follows a well-trodden community path.

### Iter-84: PreToolUse edit-time orchestrator (in-process inlining, not subprocess)

Iter-84 ships the actual orchestrator at [`plugins/itp-hooks/hooks/pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts`](../plugins/itp-hooks/hooks/pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts).

**Architectural pattern that diverges from iter-66 stop-orchestrator**: iter-66 subprocess-spawned each Stop subhook for crash isolation. That works for Stop hooks (fire once per turn). For PreToolUse Write|Edit (fires on every Write/Edit tool call), subprocess-spawning each subhook would still pay 1 bun cold-start per subhook → zero savings versus the pre-iter-84 baseline.

The only way to actually realize the 308ms-per-call savings projected by the iter-81 ranker is to **inline** subhooks as imported async classifier functions running inside the orchestrator's single bun process. The subhook contract at [`lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts`](../plugins/itp-hooks/hooks/lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts) enforces this:

- Pure async function (`PreToolUseSubhookClassifierFunction`) returning a `PreToolUseSubhookDecision` object — no stdin read, no stdout write, no `process.exit`
- Per-subhook cooperative timeout via `Promise.race` + Symbol sentinel (no subprocess to SIGKILL — runaway classifiers fail-open to `allow` and are logged to stderr)
- Per-subhook `try/catch` wrap — thrown errors fail-open and are tracked via `trackHookError`
- First-deny-wins aggregation: deterministic registry-order iteration, short-circuits on first `deny` or `ask`

**Belt-and-suspenders deny defense** (iter-78 / [GitHub #37210](https://github.com/anthropics/claude-code/issues/37210)): when a subhook denies, the orchestrator emits THREE deny signals concurrently — stdout JSON `permissionDecision: "deny"`, stderr diagnostic line, and `process.exit(2)` — to survive the documented Edit-tool stdout-JSON-deny-ignored bug.

**Iter-84 registry contents (proof-of-concept)**: only `file-size-guard` is inlined. The `pretooluse-file-size-guard.ts` file was refactored to export a pure `classifyFileSizeGuardForOrchestrator(input)` function while keeping its standalone `main()` (guarded by `import.meta.main`) for direct invocation backward-compat. The standalone `hooks.json` entry for file-size-guard was removed in the same commit; the orchestrator now owns the file-size check for Write|Edit.

**Iter-85+ migration plan** (one subhook per iter, lightest-first to de-risk):

1. iter-85 — version-guard
2. iter-86 — hoisted-deps-guard
3. iter-87 — gpu-optimization-guard
4. iter-88 — mise-hygiene-guard
5. iter-89 — pyi-stub-guard
6. iter-90 — native-binary-guard
7. iter-91 — vale-claude-md-guard

Final state: 1 orchestrator entry for Write|Edit instead of 8 entries, saving (8-1) × 44 = 308ms per Write|Edit call.

**Regression coverage**: [`.mise/tasks/tests/test-pretooluse-edit-time-orchestrator-...-allow-deny-ask-fastpath-and-belt-and-suspenders-deny.sh`](../.mise/tasks/tests/test-pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter84-allow-deny-ask-fastpath-and-belt-and-suspenders-deny.sh) — 10 assertions covering the non-Write/Edit fastpath, under-threshold allow, over-threshold belt-and-suspenders deny (stdout + stderr + exit 2), escape-hatch honoring, and standalone-classifier backward-compat (reason text without orchestrator prefix).

### Iter-85: version-guard migration + audit-driven orchestrator hardening

Iter-85 extends the iter-84 orchestrator with three concurrent deliverables:

**(1) Second subhook inlined — version-guard**

- `pretooluse-version-guard.mjs` was converted to `.ts` (via `git mv` for history preservation) and refactored to export `classifyVersionGuardForOrchestrator(input)` while keeping `main()` under the `import.meta.main` guard for standalone CLI backward-compat.
- Standalone `hooks.json` entry REMOVED; orchestrator registry now owns the Write|Edit slot for version-guard.
- Registry is now lightest-first ordered: `[version-guard, file-size-guard]`. Version-guard's O(1) `.md`-extension + path-exemption pre-filter runs BEFORE file-size-guard's sync `fs.readFileSync`, minimizing wasted work on first-deny-wins paths.
- Net savings on this migration: ~44ms per Write|Edit call (one fewer bun cold-start per multi-hook iteration).

**(2) Three audit-driven orchestrator hardenings**

A multi-perspective adversarial audit of the iter-84 orchestrator surfaced three CRITICAL issues that iter-85 fixes:

| Audit finding                                                                              | Fix                                                                                                                                                      |
| ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ask` decision path missing belt-and-suspenders defense (only `deny` had stderr+exit2)     | Both `deny` AND `ask` now use the same defense via the unified `emitBeltAndSuspendersBlockingDecisionWithStdoutDrainBeforeExitCodeTwo()` function        |
| `process.exit(2)` racing the kernel stdout-write buffer could truncate large deny payloads | Replaced with `process.exitCode = 2` + callback-form `process.stdout.write(json, () => resolve())` to drain naturally before bun's event loop terminates |
| Bun's unhandledRejection logs but doesn't crash today — Node-default could change          | Installed `process.on("unhandledRejection", ...)` fail-open handler at module top-level                                                                  |

**(3) Regression test for the audit fixes**

`test-pretooluse-edit-time-orchestrator-iter85-version-guard-inlined-plus-belt-and-suspenders-ask-defense-plus-stdout-drain-before-exitcode-two.sh` — 10 assertions covering:

- version-guard inlined classifier denies hardcoded markdown version with full belt-and-suspenders defense
- CHANGELOG path exemption still honored through the orchestrator
- Standalone `.ts` (refactored from `.mjs`) backward-compat — reason text WITHOUT orchestrator prefix (proves dual-mode contract)
- Large multi-version deny payload arrives intact on stdout (drain-before-exit verification)
- Registry-order invariant: version-guard wins over file-size-guard when BOTH would deny (lightest-first ordering)

Final state after iter-85: 6 standalone Write|Edit hooks.json entries remain (iter-86→iter-91 targets), each migration unlocks the next +44ms savings (iter-87 microbenchmark later corrected this to **+17ms** per saved subhook — see iter-87 section below).

### Iter-86: hoisted-deps-guard migration + preventive subhook-contract static checker

Iter-86 lands two concurrent deliverables: (1) third subhook inlined into the orchestrator (hoisted-deps-guard, ~44ms saved per pyproject.toml Write/Edit), and (2) a preventive static checker that addresses the iter-85 adversarial-audit's HIGH FOOTGUNs #1 and #2 BEFORE future migrations can regress against the PreToolUseSubhookContract.

**Subhook migration:**

- `pretooluse-hoisted-deps-guard.mjs` → `.ts` (via `git mv` for history preservation)
- Refactored 3-policy logic into pure `classifyHoistedDepsGuardForOrchestrator()` (POLICY 1 root-only pyproject.toml + maturin PyO3 carve-out, POLICY 2 [tool.uv.sources] path-escape detection, POLICY 3 sub-package [dependency-groups] block)
- `main()` gated under `import.meta.main` (standalone CLI backward-compat)
- Registry now lightest-first ordered: `[version-guard, hoisted-deps-guard, file-size-guard]`. hoisted-deps-guard's O(1) `endsWith("pyproject.toml")` filter pre-empts the `git rev-parse` subprocess on non-pyproject.toml writes
- Existing `pretooluse-hoisted-deps-guard.test.mjs` updated to point at `.ts` (no logic changes)

**Preventive subhook-contract static checker** ([`audit-pretooluse-orchestrator-subhook-contract-violations-static-check-...sh`](../.mise/tasks/audit-pretooluse-orchestrator-subhook-contract-violations-static-check-no-stdin-stdout-exit-in-classifier-functions-and-import-meta-main-guard-on-standalone-main.sh)):

Statically scans every `plugins/itp-hooks/hooks/*.ts` file that exports a `classify*ForOrchestrator` function and enforces two contract checks:

| Check                             | Rationale                                                                                                                                                  | Detection                                                                                                                                             |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `import.meta.main` guard          | Standalone `main()` without the guard would silently re-execute when the orchestrator imports the classifier (top-level code runs on import)               | Greps for `^async function main(` declaration; if present, requires `if (import.meta.main)` somewhere in the file                                     |
| Pure-classifier no-I/O discipline | Classifier MUST NOT call `process.exit/stdout.write/stdin/console.log` — orchestrator owns I/O, so contract violations cause double-emit or premature exit | Awk-based brace-depth scan from each `classify*ForOrchestrator` signature until matching close-brace; greps for forbidden I/O calls within that range |

Two modes:

- Default (informational): prints diagnostic per violation, exits 0 (visibility without blocking)
- `--strict`: exits non-zero on any violation (release-gate use)

Wired into `release:preflight` as Check 4m (informational), with loose-coupled defensive grep extraction per the iter-70 brittle-banner hardening pattern. Iter-87+ may flip to `--strict` once the contract stabilizes.

**Regression coverage** ([`test-pretooluse-edit-time-orchestrator-iter86-hoisted-deps-guard-inlined-plus-preventive-subhook-contract-static-checker-audit-task.sh`](../.mise/tasks/tests/test-pretooluse-edit-time-orchestrator-iter86-hoisted-deps-guard-inlined-plus-preventive-subhook-contract-static-checker-audit-task.sh)) — 14 assertions:

- **Cases 1-2**: orchestrator denies sub-package pyproject.toml (POLICY 1 + POLICY 3 fixtures) with full belt-and-suspenders defense
- **Case 3**: standalone `.ts` (renamed from `.mjs`) backward-compat without orchestrator prefix
- **Case 4**: audit task reports clean state on the 3 inlined subhooks + `--strict` exits 0
- **Case 5**: audit task DETECTS synthetic contract violations via `AUDIT_REPO_ROOT_OVERRIDE` fixture (missing-guard + forbidden-I/O detection + `--strict` exits non-zero)

**Web-research context** (concurrent 2026 second-source check):

- Bun cold-start is documented as 8-15ms in community benchmarks (byteiota.com, PkgPulse 2026), suggesting our iter-80 measurement of ~44ms may include payload-handling overhead. Worth re-profiling in iter-87+.
- GitHub #37210 (Edit-tool stdout-JSON deny ignored) confirmed STILL OPEN as of May 2026 — belt-and-suspenders defense remains correct
- AbortController is the idiomatic 2026 pattern for promise cancellation (vs iter-84's Symbol-sentinel + setTimeout). Candidate refactor for iter-87+ orchestrator hardening
- Claude Code's hook event schema has expanded post-iter-69 pentad to ~27 events (claudefa.st 2026) — iter-87+ should preventively audit new event types like ConfigChange and PostToolBatch

### Iter-87: gpu-optimization-guard migration + AbortSignal.timeout refactor + empirical cold-start savings benchmark

Iter-87 ships THREE concurrent deliverables, the third of which **empirically corrects** the iter-80/iter-81 savings projection.

**(1) Fourth subhook inlined — gpu-optimization-guard**

- `pretooluse-gpu-optimization-guard.ts` (already `.ts`) refactored to export `classifyGpuOptimizationGuardForOrchestrator()`
- 6-check policy preserved (auto-batch-size, AMP, torch.compile, DataLoader optim, device-availability, cudnn.benchmark)
- `main()` gated under `import.meta.main` (standalone CLI backward-compat)
- Standalone `hooks.json` entry REMOVED
- Registry now `[version-guard, hoisted-deps-guard, gpu-optimization-guard, file-size-guard]` (4 inlined)

**(2) AbortSignal.timeout() replaces Symbol-sentinel + raw setTimeout (iter-86 web-research follow-up)**

The iter-84 cooperative-timeout used a unique `Symbol` sentinel + manual `setTimeout` to race the classifier against an in-process timer. Iter-87 refactor adopts the idiomatic 2026 `AbortSignal.timeout(ms)` Web Platform API:

| Aspect            | Iter-84 (Symbol + setTimeout)                                               | Iter-87 (AbortSignal.timeout)                                                                                                                                 |
| ----------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Timer primitive   | `setTimeout(() => resolve(SENTINEL), ms)`                                   | `AbortSignal.timeout(ms)`                                                                                                                                     |
| Race semantics    | `Promise.race([classifier, timer])` returning union of decision \| sentinel | `Promise.race([classifier, abortRejection(signal)])` rejecting with `TimeoutError` DOMException                                                               |
| Timeout detection | `raceResult === TIMEOUT_SENTINEL` (identity)                                | `err instanceof Error && err.name === "TimeoutError"` (standard Web Platform discriminator)                                                                   |
| Composability     | Custom Symbol type leaks into return-type union                             | AbortSignal composes with `fetch()` and other AbortSignal-aware APIs (future subhooks can use the same signal for HTTP cancellation, file-handle abort, etc.) |
| Idiomaticity      | Bespoke pattern, hard to grep for                                           | Recognizable standard library usage; documented across Node/Bun/Deno/browsers                                                                                 |

Cooperative-timeout semantic unchanged: classifiers still cannot be forcibly killed (no subprocess); AbortSignal merely signals the orchestrator to move on and log the laggard.

**(3) Empirical microbenchmark CORRECTS iter-80/iter-81 savings projection** ([benchmark task](../.mise/tasks/benchmark-pretooluse-edit-time-orchestrator-amortized-bun-cold-start-savings-curve-versus-pre-orchestration-baseline-per-iter81-ranker-projection.sh))

The benchmark measures wall-clock latency of:

- **Target A**: pre-orchestration baseline = sum of 4 sequential standalone `bun <subhook>` spawns
- **Target B**: orchestrator path = 1 `bun <orchestrator>` spawn invoking 4 inlined classifiers
- **Empirical savings** = A − B, compared against iter-81's predicted `(N-1) × 44ms`

**Findings from first empirical run** (smoke run, 7 iterations, 2 warmup):

- Target A median: **72 ms** (4 standalone bun spawns)
- Target B median: **20 ms** (1 orchestrator spawn)
- Empirical savings: **52 ms** (vs iter-81 projection of 132 ms)
- **Effective per-saved-subhook cost: ~17 ms** (not the iter-80 ~44 ms)

This **confirms iter-86's web-research hypothesis**: the iter-80 ~44ms measurement was inflated by stdin+JSON-parse + classifier-execution overhead, not pure bun cold-start. Community 8-15ms benchmarks (byteiota.com, PkgPulse 2026) were closer to truth. **Iter-91 final-state savings projection is now ~119ms per Write|Edit, not 308ms.** Still a meaningful win, but 2.6× smaller than originally projected. The orchestrator-as-architecture is correct; the magnitude needed empirical correction.

**Regression coverage** ([12 assertions, all pass](../.mise/tasks/tests/test-pretooluse-edit-time-orchestrator-iter87-gpu-optimization-guard-inlined-plus-abortsignal-timeout-refactor-replacing-symbol-sentinel.sh)):

- Cases 1a-e: gpu-optimization-guard inlined → deny PyTorch training script (batch-size + AMP policies fire) with belt-and-suspenders + exit 2
- Case 2: `# gpu-optimization-bypass` comment honored
- Case 3: non-PyTorch Python script falls through (fastpath)
- Cases 4a-b: standalone backward-compat (no orchestrator prefix in reason)
- Case 5: `AbortSignal.timeout()` fires `TimeoutError` after ~200ms via inline harness with hanging classifier (validates the refactor's cooperative-timeout correctness)
- Cases 6a-b: subhook-contract audit task reports 4 conforming subhooks

### Self-measurement tool

The forensic baseline above can be reproduced (and regression-watched) via:

```bash
mise run profile-edit-time-pretooluse-hook-cold-start-bun-spawn-overhead-with-non-applicable-payload-to-surface-high-overhead-outliers-above-bun-startup-floor
```

### Orchestration-candidacy ranker (iter-81)

The companion ranking tool identifies WHICH hook groupings yield the highest savings if combined into an iter-66-style orchestrator:

```bash
mise run audit-pretooluse-hook-matcher-grouping-to-rank-orchestration-candidacy-by-bun-spawn-savings-from-iter80-cold-start-floor
```

Reads every `plugins/*/hooks/hooks.json`, groups PreToolUse entries by exact matcher signature, and ranks each group by `(group_size - 1) × 44ms` estimated savings. Live marketplace finding as of iter-81:

| Rank | Plugin    | Matcher       | Group size | Savings if combined |
| ---- | --------- | ------------- | ---------- | ------------------- |
| 1    | itp-hooks | `Write\|Edit` | 8          | 308 ms              |
| 2    | itp-hooks | `Bash`        | 8          | 308 ms              |
| 3    | gh-tools  | `Bash`        | 2          | 44 ms               |

Combining the top 2 groups would save **616 ms per Write/Edit and per Bash invocation respectively** — the highest-leverage edit-time perf opportunity in the marketplace. Architectural template: `plugins/itp-hooks/hooks/stop-orchestrator.ts` (iter-66).

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
