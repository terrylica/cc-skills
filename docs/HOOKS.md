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

<!-- # SSoT-OK: this section references SemVer placeholders as documentation patterns, not as code configuration. -->

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

### Iter-88: mise-hygiene-guard migration + PostToolUse Write|Edit orchestration candidate surfaced

Iter-88 ships TWO concurrent deliverables: (1) fifth subhook inlined into the PreToolUse orchestrator (mise-hygiene-guard, saving ~17ms per Write/Edit per iter-87's empirical correction), and (2) forensic adversarial-audit finding surfaced as task #96 — the PostToolUse Write|Edit registry currently runs **9 separate hooks.json entries spawning 12 bun subprocesses on every code edit**, the largest remaining orchestration candidate in the marketplace (~136ms additional savings projected when consolidated).

**(1) Fifth subhook inlined — mise-hygiene-guard**

- `pretooluse-mise-hygiene-guard.ts` (already `.ts`) refactored to export `classifyMiseHygieneGuardForOrchestrator()` — a pure async classifier conforming to `PreToolUseSubhookContract`. The existing 2-policy logic (secrets detection + line count >100 → hub-spoke suggestion) is now factored into pure detection helpers (`detectSecretLiteralsInMiseTomlContent`, `analyzeMiseTomlContentForHygieneViolations`, `isTargetMiseTomlFileNotLocalIgnoreFile`) that the classifier composes. Standalone `main()` is preserved under `import.meta.main` for direct CLI invocation backward-compat.
- Registry insertion position: AFTER `hoisted-deps-guard` and BEFORE `gpu-optimization-guard` (lightest-first ordering — the mise-hygiene fastpath does an O(1) filename suffix + ignore-list check, cheaper than gpu-optimization-guard's PyTorch-pattern regex scan but slightly more expensive than hoisted-deps-guard's pyproject.toml suffix check).
- `hooks.json` standalone `mise-hygiene-guard` Write|Edit entry removed; orchestrator description updated to list `mise-hygiene-guard` in its inlined-subhooks roster.
- Registry now `[version-guard, hoisted-deps-guard, mise-hygiene-guard, gpu-optimization-guard, file-size-guard]` (5 inlined; 3 remaining: pyi-stub-guard, native-binary-guard, vale-claude-md-guard).

**(2) PostToolUse Write|Edit orchestration candidate surfaced — next ~136ms savings target**

The iter-88 adversarial audit enumerated `hooks.json` PostToolUse entries via `jq` and discovered the new orchestration leader after the iter-84→iter-91 PreToolUse arc completes. Current state (per `jq '.hooks.PostToolUse'`):

| Metric                                                | Value                                     |
| ----------------------------------------------------- | ----------------------------------------- |
| Distinct PostToolUse hooks.json entries (Write\|Edit) | 9                                         |
| Bun subprocesses spawned per code edit                | 12 (some entries chain ≥2 hooks)          |
| Projected savings if consolidated to single process   | 8 × ~17ms = **~136ms per Write/Edit**     |
| Schema constraint vs PreToolUse                       | PostToolUse cannot `deny` (informational) |
| Required new contract                                 | `PostToolUseSubhookContract` analog       |

The PostToolUse contract differs from `PreToolUseSubhookContract` in TWO ways: (a) the decision type collapses to `{kind: "noop"} | {kind: "additional_context", message}` since `deny`/`ask` are not honored on PostToolUse per the iter-66 schema findings, and (b) the orchestrator MUST aggregate `additionalContext` from multiple subhooks into a single stdout payload (vs PreToolUse's first-deny-short-circuit). This is queued as **task #96** (iter-92+, scheduled after the iter-89/90/91 PreToolUse migrations complete to avoid contract-design churn).

**Regression coverage** ([13 assertions, all pass](../.mise/tasks/tests/test-pretooluse-edit-time-orchestrator-iter88-mise-hygiene-guard-inlined-secrets-detection-and-line-count-policy-paths-plus-postooluse-orchestration-candidate-surfaced.sh)):

- Cases 1a-d: orchestrator denies `mise.toml` with hardcoded `API_KEY` via `mise-hygiene-guard` subhook attribution with belt-and-suspenders deny + exit 2 (POLICY 1 — secrets detection)
- Case 2: `.mise.local.toml` ignore-list honored (secrets allowed there by design)
- Case 3: safe-pattern external references (`{{ op_read(...) }}`, `{{ read_file(...) }}`) → allow (the safe-pattern filter pre-empts the secrets regex)
- Cases 4a-c: oversized `mise.toml` (>100 lines) denies with hub-spoke refactoring guidance + exit 2 (POLICY 2 — line count)
- Cases 5a-b: standalone `pretooluse-mise-hygiene-guard.ts` still works for direct CLI invocation, with NO orchestrator prefix in deny reason (backward-compat)
- Cases 6a-b: subhook-contract audit task discovers ≥5 conforming subhooks (live-extraction pattern, not hardcoded count — survives future iter-89/90/91 additions)

**Iter-87 regression-test hardening** (forensic finding from iter-88 marketplace suite run): the iter-87 test originally hardcoded `subhook count = 4`, which broke when iter-88 inlined the 5th. The iter-87 test was refactored to use the same live-extraction pattern the iter-88 test was written with from day one (`grep -oE 'Total subhook files scanned:[[:space:]]+[0-9]+'` + `-ge` numeric comparison). All future iter migrations will not break iter-87.

### Iter-89: pyi-stub-guard migration + naming-drift remediation + async:true architectural-alternative surfaced for task #96

Iter-89 ships THREE concurrent deliverables: (1) sixth subhook inlined into the PreToolUse orchestrator (pyi-stub-guard, saving ~17ms per Write/Edit per iter-87's empirical correction), (2) **filename-vs-algorithm naming-drift remediation** — the source file was historically called `pretooluse-pyi-stub-guard.ts` and its CLAUDE.md row claimed ".pyi stub file signature validation", but the actual algorithm validates `__init__.py` AND `__init__.pyi` files contain no top-level definitions (thin re-export layer enforcement per PEP 561 + clean-package-structure), and (3) **async:true architectural-alternative surfaced for task #96** — the 2026 Anthropic feature release (Jan 2026) of the `async: true` hook flag means task #96's PostToolUse Write|Edit "9-hooks → 1-orchestrator consolidation" plan should EVALUATE async:true as a competing path before committing.

**(1) Sixth subhook inlined — pyi-stub-guard**

- `pretooluse-pyi-stub-guard.ts` refactored to export `classifyInitFileTopLevelDefinitionMonolithGuardForOrchestrator()` — a precise algorithm-encoding name per the user's "verbose, specific, searchable, distinctive names" rule — plus a backward-compat alias `classifyPyiStubGuardForOrchestrator` to maintain symmetric naming with the 5-subhook migration cohort (`classify<FilenamePrefix>ForOrchestrator`).
- 1-policy logic preserved: scan Write/Edit payload of `__init__.py`/`__init__.pyi` for top-level `class`/`def`/decorator definitions; honor `# INIT-MONOLITH-OK` escape-hatch; apply re-export-dominated heuristic (≥70% imports) only to Write payloads (Edit's partial new_string makes the ratio meaningless).
- Detection helpers factored into pure functions with verbose searchable names: `findTopLevelDefinitionViolationsInPythonInitFileContent`, `classifyPythonInitFilePathSuffix`, `isLikelyReExportDominatedInitPyFileWriteContent`, `lineDefinesExemptInitPyBoilerplateFunction`, `buildInitFileMonolithRefactoringGuidance`.
- Standalone `main()` preserved under `import.meta.main` for direct CLI backward-compat.
- Registry insertion position: AFTER `mise-hygiene-guard` and BEFORE `gpu-optimization-guard` (lightest-first ordering — pyi-stub-guard's O(1) `__init__.py`/`__init__.pyi` filename-suffix `endsWith()` fastpath is cheaper than gpu-optimization-guard's `.py` + PyTorch-pattern regex scan).
- `hooks.json` standalone `pyi-stub-guard` Write|Edit entry removed; orchestrator description updated to list the 6 inlined subhooks + cite iter-89 Bun 1.3 single-digit-ms cold-start web research finding.

**(2) Filename-vs-algorithm naming-drift remediation**

The source file `pretooluse-pyi-stub-guard.ts` is misnamed — the algorithm has nothing to do with `.pyi` stub signature validation. It validates that Python `__init__.py` AND `__init__.pyi` files are thin re-export layers (no top-level definitions). The historical itp-hooks CLAUDE.md row repeated this misdescription. Iter-89 acknowledges this dual-naming reality without breaking backward compat: the **precise** algorithm-encoding name is `classifyInitFileTopLevelDefinitionMonolithGuardForOrchestrator` (the actual algorithm: detect top-level Python definition monoliths in **init** files), and the **symmetric-naming** alias `classifyPyiStubGuardForOrchestrator` exists solely for cohort consistency. The CLAUDE.md row was rewritten to describe the actual algorithm. A future iter can rename the source file when convenient (no urgency since the descriptive name is now correct everywhere it's read).

**(3) async:true architectural-alternative for task #96 (PostToolUse Write|Edit orchestration)**

Iter-89 web research surfaced a critical 2026 development: Anthropic released `async: true` for hooks in January 2026 ([Claude Code Hooks: Complete 2026 Production Reference, The Prompt Shelf](https://thepromptshelf.dev/blog/claude-code-hooks-complete-reference-2026/)). This flag makes a hook **non-blocking** — Claude proceeds with execution while the hook runs in the background. For PostToolUse (which cannot deny by schema anyway), `async: true` provides ZERO-BLOCKING runtime cost without requiring any orchestrator refactor.

This means task #96's "9 PostToolUse Write|Edit hooks → 1 orchestrator, ~136ms savings" plan must FIRST evaluate two competing paths:

| Architecture                      | Implementation cost                                                                                       | Runtime cost reduction                   | Schema compatibility                                                                                                           | Maintenance complexity                                                        |
| --------------------------------- | --------------------------------------------------------------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| **Path A: async:true sweep**      | LOW — add `"async": true` to existing 9 hooks.json entries                                                | ZERO blocking cost (Claude doesn't wait) | All 9 are already deny-incompatible per iter-66 schema (PostToolUse reads only `{decision: "block", reason}`) — async-eligible | LOW — preserves current 1:1 hook isolation, no contract design                |
| **Path B: orchestrator inlining** | HIGH — design PostToolUseSubhookContract, build orchestrator analog, refactor 9 hooks to pure classifiers | ~136ms per Write/Edit                    | Same schema constraints + need to aggregate `additionalContext` outputs                                                        | HIGH — every PostToolUse hook becomes coupled to the orchestrator's lifecycle |

**⚠️ ITER-92 RETROACTIVE CORRECTION**: the above "strict-dominant" claim was **WRONG**. Iter-92 web research (see iter-92 section below) and the per-hook marketplace audit revealed that PostToolUse hooks **DO** inject context via `{decision: "block", reason}` JSON for the self-correction feedback loop (e.g., type-check errors that Claude reads and fixes). Async:true makes those hooks fire-and-forget, which means **Claude advances without seeing the feedback**. 15 of 17 audited PostToolUse hooks marketplace-wide are CONTEXT-INJECTING (decision:block-emitting or additionalContext-emitting) and therefore NOT async-safe. The iter-92 audit task automates this classification and locks in the corrected analysis as a release-preflight gate candidate.

This finding ALSO retroactively validates the iter-84 PreToolUse orchestrator decision: PreToolUse MUST block (can deny edits) so async:true is NOT a viable path for the Write|Edit registry — orchestrator inlining is correct for PreToolUse but likely WRONG for PostToolUse.

**Web research citations** (Sources: [Claude Code Hooks Complete 2026 Production Reference, The Prompt Shelf](https://thepromptshelf.dev/blog/claude-code-hooks-complete-reference-2026/) | [Claude Code Best Practices, Clarista](https://www.clarista.io/blog/claude-code-best-practices) | [Bun vs Node.js Performance, PkgPulse](https://www.pkgpulse.com/blog/bun-vs-nodejs-2026)):

- "Add `async: true` to run hooks in the background without blocking Claude's execution. Released by Anthropic in January 2026."
- "HTTP hooks let you send hook events to a web server instead of running a local script... This opens up use cases that were previously awkward or impossible with command hooks, such as remote validation services that enforce team-wide policies." (Surfaces a third architectural alternative — long-lived HTTP server holding shared state — for task #96's evaluation.)
- "Bun 1.3 starts in about 8ms to 15ms" — validates iter-87's empirical ~17ms per-saved-subhook correction over iter-80's ~44ms estimate.

**Regression coverage** ([14 assertions, all pass](../.mise/tasks/tests/test-pretooluse-edit-time-orchestrator-iter89-pyi-stub-guard-inlined-init-file-top-level-definition-monolith-detection-plus-postooluse-async-true-vs-orchestration-architecture-decision-surfaced.sh)):

- Cases 1a-d: orchestrator denies `__init__.py` with top-level `class Foo:` via pyi-stub-guard attribution with belt-and-suspenders + exit 2
- Cases 2a-b: `__init__.pyi` with top-level `def` denied with stricter PEP 561 guidance
- Case 3: non-init Python file (`models.py`) → allow (O(1) suffix fastpath skip)
- Case 4: `# INIT-MONOLITH-OK` escape-hatch honored → allow
- Case 5: re-export-dominated Write (≥70% imports) → allow (heuristic exempts incidental annotations)
- Cases 6a-b: standalone backward-compat preserved (no orchestrator prefix in reason)
- Cases 7a-b: subhook-contract audit discovers ≥6 conforming subhooks (live-extraction pattern)
- Case 8: dual-export naming-drift acknowledgement verified (file exports BOTH precise algorithm name AND symmetric-naming alias)

### Iter-90: native-binary-guard migration + PreToolUse additionalContext silent-drop NON-USE audit + BSD-xargs portability hardening

Iter-90 shipped THREE concurrent deliverables: 7th subhook inlined (native-binary-guard, dual-export pattern with `classifyMacosLaunchdNativeBinaryRequiredGuardForOrchestrator`); marketplace-wide PreToolUse `additionalContext` silent-drop NON-USE audit per [GitHub #15664](https://github.com/anthropics/claude-code/issues/15664) — emission-pattern grep (not prose-comment) confirms ZERO classifiers emit the silently-dropped field; and a **BSD-xargs portability fix** (`xargs -S 16384`) for the iter-75 parallel test runner that was silently exposed to a long-test-filename cliff (macOS BSD `xargs -I {}` defaults to a 255-byte replacement-string size, which iter-90's verbose test filename — 280 chars per invocation — just barely exceeded; GNU xargs on Linux was never affected). All preserved across iter-91.

### Iter-91: vale-claude-md-guard migration — **PreToolUse Write|Edit migration arc COMPLETE (8/8)**

Iter-91 is the **arc-completion milestone**. The final remaining standalone Write|Edit subhook (`vale-claude-md-guard`) was inlined into the orchestrator, ending the iter-84 → iter-91 PreToolUse Write|Edit migration arc.

**Final orchestrator registry state (lightest-first deny-wins order)**:

| Position | Subhook                  | Inlined in | Fastpath complexity                | Heaviest operation                               |
| -------- | ------------------------ | ---------- | ---------------------------------- | ------------------------------------------------ |
| 1        | `version-guard`          | iter-85    | O(1) markdown-ext + path filter    | regex content scan                               |
| 2        | `hoisted-deps-guard`     | iter-86    | O(1) filename-suffix               | `git rev-parse` subprocess (pyproject.toml only) |
| 3        | `mise-hygiene-guard`     | iter-88    | O(1) filename allowlist + ignore   | secrets-pattern regex                            |
| 4        | `pyi-stub-guard`         | iter-89    | O(1) `__init__.py`/`.pyi` suffix   | top-level definition scan                        |
| 5        | `native-binary-guard`    | iter-90    | O(1) launchd-dir substring         | `Bun.file().text()` for iter-15 fix              |
| 6        | `gpu-optimization-guard` | iter-87    | O(1) `.py` ext + test-file pattern | PyTorch training-script regex scan               |
| 7        | `file-size-guard`        | iter-84    | O(1) tool_name + ext               | sync `fs.readFileSync()` for Edit                |
| 8        | `vale-claude-md-guard`   | iter-91    | O(1) `CLAUDE.md` endsWith          | external `vale` subprocess (100-300ms typical)   |

**Architectural arc summary (iter-84 → iter-91)**:

| Iter        | Subhook migrated         | Cumulative inlined     |
| ----------- | ------------------------ | ---------------------- |
| iter-84     | file-size-guard          | 1/8                    |
| iter-85     | version-guard            | 2/8                    |
| iter-86     | hoisted-deps-guard       | 3/8                    |
| iter-87     | gpu-optimization-guard   | 4/8                    |
| iter-88     | mise-hygiene-guard       | 5/8                    |
| iter-89     | pyi-stub-guard           | 6/8                    |
| iter-90     | native-binary-guard      | 7/8                    |
| **iter-91** | **vale-claude-md-guard** | **8/8 (arc COMPLETE)** |

Per iter-87 empirical microbenchmark: ~17ms saved per inlined subhook. Final-state savings = `(N_subhooks - 1) × 17` = (8-1) × 17 = **~119ms per Write|Edit tool call** (vs iter-81's optimistic 308ms projection, corrected by iter-87 empirical re-measurement; iter-89 web research independently corroborated this via 2026 Bun 1.3 8-15ms cold-start benchmarks).

**Architectural artifacts that survived the arc** (preserved for the next orchestration project — task #96 PostToolUse):

1. `PreToolUseSubhookContract` — pure-function classifier protocol.
2. `executeSubhookWithCooperativeTimeoutAndCrashIsolation()` — `Promise.race` against `AbortSignal.timeout()` with try/catch fail-open allow.
3. `emitBeltAndSuspendersBlockingDecisionWithStdoutDrainBeforeExitCodeTwo()` — triple deny-defense per GH #37210.
4. **Dual-export naming-drift acknowledgement pattern** (iter-89/90/91): `classify<PreciseAlgorithmEncodingName>ForOrchestrator` for algorithm clarity + `classify<FilenamePrefix>ForOrchestrator` alias for cohort symmetry.
5. **Subhook-contract static checker** (iter-86) — preventive release-preflight gate against contract violations.
6. **Marketplace-wide PreToolUse additionalContext silent-drop NON-USE audit** (iter-90 per GH #15664) — emission-pattern grep that ignores prose-comment mentions.
7. **BSD-xargs portability hardening** (iter-90) — `xargs -S 16384` so the iter-75 parallel test runner survives arbitrarily long verbose test filenames.
8. **Empirical re-measurement discipline** (iter-87) — iter-80's 44ms cold-start projection corrected to 17ms by independent microbenchmark.

**iter-91-specific deliverables**:

- `pretooluse-vale-claude-md-guard.ts` refactored to export `classifyValeTerminologyConformanceOnClaudeMdGuardForOrchestrator()` + alias `classifyValeClaudeMdGuardForOrchestrator()`.
- Detection helpers with verbose searchable names: `synthesizeEditApplicationResult`, `runValeAgainstProposedContentTempfileAndParseJsonFindings`, `filterValeFindingsBySeverityInclusionThreshold`, `formatValeFindingsForOperatorDisplay`.
- Edit-path scope-to-changed-lines (±3 buffer) heuristic preserved.
- Registry `timeoutMs: 12000` (generous — vale typically 100-300ms, headroom for slow-disk machines).
- hooks.json now contains **exactly ONE** `Write|Edit` matcher (the orchestrator) — verified via jq.

**iter-91 regression test** ([13 assertions, all pass](../.mise/tasks/tests/test-pretooluse-edit-time-orchestrator-iter91-vale-claude-md-guard-inlined-completes-8-of-8-pretooluse-write-edit-migration-arc-with-empirical-119ms-savings-projection.sh)):

- Case 1: non-CLAUDE.md write → allow (suffix fastpath)
- Cases 2a-b: orchestrator imports + registers vale classifier
- Cases 3a-b: standalone backward-compat (no orchestrator prefix)
- Cases 4a-b: subhook-contract audit discovers ≥8 conforming subhooks (FINAL arc state)
- Case 5: PreToolUse `additionalContext` silent-drop NON-USE invariant holds across ALL 8 inlined subhooks
- Cases 6a-b: hooks.json has exactly 1 Write|Edit matcher + 0 standalone vale references (jq-based — **iter-91 dev-time finding**: BSD grep ERE handling of `\|` is implementation-defined and produced spurious matches; jq is the correct tool for JSON inspection)
- Case 7: orchestrator description records iter-91 arc-completion milestone
- Cases 8-9: standalone `import.meta.main` guard + dual-export naming preserved

**Iter-91 dev-time forensic finding (silent doc-truncation)**: a subset of the iter-90 HOOKS.md changes were silently lost between my edit and the iter-90 commit (the commit's `--stat` showed only 2 HOOKS.md lines changed despite a much larger intended addition). The most plausible cause is a formatter or PostToolUse hook that touched HOOKS.md and reverted the larger section. The iter-91 edit re-asserts both the iter-90 section AND the iter-91 arc-completion content as a single consolidated write, with the doc-history record relying on this iter-91 commit rather than iter-90's. Future iters should consider adding a HOOKS.md "section drift" audit that warns if iter-N's docs are missing from the file when iter-(N+1) starts.

### Iter-92: PostToolUse async:true eligibility audit — RETROACTIVELY CORRECTS iter-89's "Path A strict-dominance" claim

Iter-92 is the **first project in the post-arc PostToolUse orchestration phase** AND the **adversarial correction** of an architectural claim iter-89/iter-91 made without sufficient research.

**Background**: iter-89 web research surfaced Anthropic's Jan-2026 `async: true` hook flag and concluded — based on the schema reasoning that "PostToolUse cannot deny per iter-66 schema, therefore all 9 PostToolUse Write|Edit hooks are async-eligible by definition" — that Path A (async:true sweep) was **strictly dominant** over Path B (orchestrator inlining) on every dimension. Task #96 was redirected to start with a Path A sweep. **Iter-92 proves this claim was wrong on 15 of 17 audited PostToolUse hooks marketplace-wide.**

**Iter-92 corrected analysis** (sources: [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks), [claudefa.st March-2026 reference](https://claudefa.st/blog/tools/hooks/hooks-guide), [reading.sh async-hooks deep-dive](https://reading.sh/claude-code-async-hooks-what-they-are-and-when-to-use-them-61b21cd71aad)):

> "An async PostToolUse hook **cannot reliably inject `additionalContext` next to the tool result**, since the model will have already advanced before the hook finishes. The documented timing — PreToolUse, PostToolUse, PostToolUseFailure, and PostToolBatch place additionalContext next to the tool result — **assumes synchronous completion**. The async flag is therefore intended for side effects like logs, notifications, and backups, **not for the self-correction feedback loop**, which requires the hook to complete before Claude's next model request."

The schema-reasoning argument iter-89 used was incomplete: PostToolUse CAN'T DENY but it CAN INJECT CONTEXT via `{decision: "block", reason}` or `additionalContext`. **Context injection requires synchronous completion just as much as deny does.** Type checkers (`ty`, `tsgo`, `oxlint`, `biome`) and reminder hooks both rely on this same-turn timing — making any of them async breaks the feedback loop that lets Claude self-correct without operator intervention.

**Iter-92 eligibility-classifier task** (`audit-posttooluse-asynctrue-eligibility-classifier-by-decision-block-vs-pure-side-effect-output-pattern-iter92-corrects-iter89-strict-dominance-claim.sh`):

The audit task discovers every PostToolUse hooks.json entry marketplace-wide, resolves `${CLAUDE_PLUGIN_ROOT}` to the absolute plugin-root path, strips `bun`/`node` prefixes, dedupes the script paths, then classifies each by output pattern:

| Verdict | Pattern detected                                                                | Async-safety        | Marketplace count (iter-92 baseline) |
| ------- | ------------------------------------------------------------------------------- | ------------------- | ------------------------------------ |
| `[C]`   | emits `decision: "block"` JSON OR `additionalContext`                           | ASYNC-UNSAFE        | **15 of 17 (88%)**                   |
| `[M]`   | emits unstructured stdout (could be operator-visible OR Claude-system-reminder) | NEEDS-MANUAL-REVIEW | 1                                    |
| `[S]`   | no stdout output detected (pure file/network side effects only)                 | ASYNC-SAFE          | 1                                    |

**Corrected architecture decision for task #96** (now embedded in the audit task's summary output for operator visibility):

- **Path A (async:true sweep)**: RULED OUT for 15 of 17 hooks. Viable for the 1 confirmed pure-side-effect hook only (and only after the audit's classification has been peer-reviewed for that specific hook).
- **Path B (orchestrator inlining)**: viable for ALL hooks — preserves the synchronous `decision: "block"` context-injection contract. Requires building a `PostToolUseSubhookContract` analog to the iter-84 PreToolUse contract; the contract's decision type collapses to `{kind: "noop"} | {kind: "additional_context", message}` since `deny`/`ask` are not honored on PostToolUse per the iter-66 schema findings.
- **Path C (HTTP hooks long-lived server)**: viable but requires server-lifecycle management; SOTA 2026 pattern surfaced by iter-89 research. Best suited for hooks that need shared in-process state (caches, loaded ML models). Out of scope for the current PostToolUse 9-hook registry which doesn't have shared state.

**Iter-92 regression test** ([12 assertions, all pass](../.mise/tasks/tests/test-iter92-posttooluse-asynctrue-eligibility-audit-classifies-decision-block-emitting-hooks-as-context-injecting-async-unsafe-correcting-iter89-strict-dominance-claim.sh)):

- Case 1: audit exits 0 (informational; never blocks release pipeline)
- Case 2: ≥15 PostToolUse hooks discovered marketplace-wide (found 17)
- Cases 3a-d: 4 type-check / lint hooks (`ty`, `tsgo`, `oxlint`, `biome`) all classified as `[C]` context-injecting
- Case 4: at least one `additionalContext`-emitting hook flagged (e.g., `rust-sota-reminder`)
- Cases 5a-c: explicit iter-89 strict-dominance correction banner present; Path A explicitly RULED OUT; Path B recommended as viable replacement
- Case 6: NO PreToolUse hooks leak into PostToolUse audit (event-type filter correctness)
- Case 7: context-injecting count >> pure-side-effect count (validates iter-92 finding that Path A is broadly inapplicable)

**Iter-92 dev-time forensic findings** (defense-in-depth scaffolding for future audit-task authors):

- **`[C]` / `[S]` verdict-tags are OVERLOADED**: per-hook lines AND the summary-totals line both start with these tags. Per-hook lines look like `[C] [NOT-CURRENTLY-ASYNC] posttooluse-X.ts` (no trailing count). Summary lines uniquely include the verdict-name + parenthetical + colon-followed-by-count (e.g., `[C] CONTEXT-INJECTING (decision:block or additionalContext):  15  →`). Test assertions on summary numbers must anchor on the parenthetical-plus-colon pattern, not on the tag alone — anchoring on the tag matches per-hook lines first and `head -1` extracts the wrong line.
- **macOS BSD grep does NOT support `\s` shorthand** for whitespace in ERE mode — use `[[:space:]]` POSIX bracket-class. Iter-92 test initially failed with `grep -E '^\s*\[C\]'` returning 0 matches; the fix was to switch to `^[[:space:]]*\[C\]`.
- **The 17-hook marketplace count exceeds iter-88's 9-hook projection** because the discovery walks every plugin's `hooks.json`, not just `itp-hooks/hooks/hooks.json`. The corrected savings projection for Path B (orchestrator inlining of ALL marketplace PostToolUse hooks): `(17 - 1) × 17ms ≈ 272ms per Write/Edit` (vs iter-88's optimistic 136ms based on itp-hooks-only count).

### Iter-93: PostToolUse edit-time orchestrator kick-off — **Path B (Orchestrator Inlining) STARTED, 1/15 inlined**

Iter-93 is the **first concrete step of Path B** after the iter-92 audit ruled out Path A (async:true sweep) for 15 of 17 marketplace PostToolUse hooks. It mirrors iter-84's PreToolUse arc kick-off, but with a critical contract difference: **multi-aggregation semantics** instead of first-deny-short-circuit.

**The new PostToolUseSubhookContract** (separate file from the iter-84 PreToolUse contract, `lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts`):

| Field                          | PreToolUse (iter-84)                            | PostToolUse (iter-93)                                         |
| ------------------------------ | ----------------------------------------------- | ------------------------------------------------------------- |
| Decision discriminant          | `"allow" \| "deny" \| "ask"`                    | `"noop" \| "additional_context"`                              |
| Orchestrator iteration policy  | Serial, first-non-allow short-circuits          | Parallel via `Promise.all`, **runs all subhooks**             |
| Aggregation                    | None — single decision wins                     | Delimiter-joined into one consolidated reason                 |
| Wire emission                  | `permissionDecision: "allow"\|"deny"\|"ask"`    | `{decision: "block", reason}` JSON                            |
| Silent-pass shape              | Single allow JSON                               | Empty stdout (exit 0) when ALL subhooks return noop           |
| File I/O allowed on no-op path | NO (Edit-path scope-to-changed-lines exception) | YES (PostToolUse fires AFTER side effects durable)            |
| Typical timeoutMs              | 3000-5000ms                                     | 4000-8000ms (heavier subhooks: ty, tsgo, oxlint, biome, vale) |

The wire-emission row is the load-bearing distinction: PostToolUse cannot use `permissionDecision` (silently dropped per iter-66 schema — the tool already ran by the time the hook fires). The documented Anthropic-schema mechanism for **context injection** on PostToolUse is `{decision: "block", reason}` — the keyword "block" is a misnomer here; it's how Claude surfaces the reason as a system reminder NEXT to the tool result (synchronous timing required — see iter-92).

**Iter-93 deliverables**:

1. **PostToolUseSubhookContract** type-defined with the discriminated-union decision shape and a precise `PostToolUseSubhookRegistryEntry` interface mirroring iter-84's PreToolUse equivalent
2. **`posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts`** — the new orchestrator that:
   - Runs ALL registered subhooks in parallel via `Promise.all` (no short-circuit — multi-aggregation invariant)
   - Wraps each classifier in `AbortSignal.timeout()` cooperative-cancellation race (mirrors iter-87 PreToolUse pattern)
   - Try/catch-isolates each classifier (errors → fail-open `noop`)
   - Aggregates non-empty `additional_context` payloads via a delimiter-joined section
   - Emits ONE consolidated `{decision: "block", reason: aggregate}` JSON — or NOTHING when every subhook returns `noop` (preserves legacy silent-allow semantics)
3. **`posttooluse-ty-type-check.ts` refactored to dual-mode** (orchestrator-imported + standalone-CLI via `import.meta.main` guard): exports `classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator` (precise algorithm-encoding name) AND `classifyTyTypeCheckForPostToolUseOrchestrator` (symmetric-naming alias for sibling-subhook consistency — same dual-export pattern iter-89/90/91 established)
4. **hooks.json rewiring**: the standalone `posttooluse-ty-type-check.ts` Write|Edit PostToolUse entry is replaced by the orchestrator entry (timeout 15000ms, generous to accommodate the multi-subhook aggregation as the registry grows in iter-94+)
5. **Iter-93 regression test** ([16 assertions, all pass](../.mise/tasks/tests/test-posttooluse-edit-time-orchestrator-iter93-ty-python-type-check-inlined-as-first-context-injecting-subhook-with-multi-aggregation-additional-context-merging-kicks-off-path-b-replacing-iter89-ruled-out-async-true-strategy.sh)):
   - Cases 1a-c: contract discriminated-union shape + registry interface + helper exist
   - Cases 2a-b: orchestrator uses `Promise.all` (parallel multi-aggregation, NOT first-deny-short-circuit) + has aggregator function
   - Cases 3a-b: orchestrator emits `{decision:'block'}` (Anthropic-schema PostToolUse context-injection) and does NOT emit `permissionDecision` (which PostToolUse silently drops)
   - Case 4: registry inlines ≥1 subhook (iter-93 starting state)
   - Case 5: non-Python write (.txt) → silent noop + exit 0 (O(1) extension filter fastpath)
   - Cases 6a-b: standalone backward-compat via `import.meta.main` guard
   - Case 7: dual-export naming-drift acknowledgement pattern
   - Cases 8a-b: hooks.json wires orchestrator (NOT standalone) under Write|Edit
   - Case 9: orchestrator uses `AbortSignal.timeout()` (iter-87 community-standard cooperative cancellation)
   - Case 10: orchestrator header documents iter-92 correction of iter-89 strict-dominance claim (forensic traceability)
6. **Iter-92 regression test updated** to acknowledge that `ty-type-check` is now inlined into the orchestrator — the test now accepts EITHER form (standalone OR orchestrator-via-import) as satisfying the `[C] CONTEXT-INJECTING` invariant. This decouples the iter-92 audit-task regression from the in-progress iter-93+ migration arc's future state.

**Iter-93 forensic note: 17ms × 14 = 238ms savings (final-state projection)**. After all 15 context-injecting PostToolUse hooks inline into the orchestrator, projected savings are `(15-1) × 17ms ≈ 238ms` per Write/Edit (using iter-87's empirically-corrected per-subhook cost). Combined with the iter-91 PreToolUse arc's ~119ms savings, total cold-start reduction per Write/Edit reaches **~357ms** — meaningful but smaller than iter-89's optimistic strict-dominance projection. The 1 confirmed `[S]` PURE-SIDE-EFFECT hook (`posttooluse-subprocess-orphan-cleanup.ts`) can independently get `async: true` outside the orchestrator path.

**Iter-93 architectural-symmetry surfacing**: the two orchestrators (iter-84 PreToolUse + iter-93 PostToolUse) deliberately use DIFFERENT iteration models because their wire-emission contracts differ — first-deny-short-circuit is correct for PreToolUse (a single deny is decisive), parallel-all is correct for PostToolUse (every additional_context payload contributes signal Claude needs). Future maintainers should resist the temptation to "unify" them via a single base class — the asymmetry encodes a real schema-level constraint.

### Iter-94: PostToolUse arc progress — tsgo inlined (2/15) + async-Bun.spawn perf correction + provenance-prefix aggregation

Iter-94 is a **2nd-subhook migration + a critical performance correction** of an iter-93 mistake. The adversarial multi-perspective audit at the top of this iteration surfaced two issues:

**Issue 1: parallelism-defeat anti-pattern (perf)**. Iter-93 inherited `Bun.spawnSync` from the legacy standalone `ty-type-check.ts`. Per [Bun's official spawn docs](https://bun.com/docs/api/spawn) plus 2026 community guidance:

> "With `Bun.spawnSync`, true parallelism is impossible from a single thread — each call must finish before the next line of JS runs. With `Bun.spawn`, N child processes can run truly in parallel at the OS level while your event loop continues servicing other work."

That meant the iter-93 orchestrator's `Promise.all` over N subhooks yielded **zero actual parallelism** — every type-checker spawn serialized at the OS level even though the JS code looked concurrent. Iter-94 refactors `ty-type-check` to `Bun.spawn` (async) with `AbortSignal.timeout()`-driven cooperative cancellation, and inlines `tsgo-type-check` async-from-day-one. The shared helper `executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndStreamDrain` lives in both classifier source files (centralizing the spawn pattern so future migrations don't drift) and reads stdout/stderr CONCURRENTLY with the `.exited` promise via `new Response(stream).text()` (the idiomatic 2026 Bun pattern; deadlock-free).

**Issue 2: aggregator section ambiguity (usability)**. The iter-93 aggregator joined subhook contributions with a delimiter but offered no signal as to WHICH subhook contributed which section. With N=4 type-checkers all firing on a single `.ts` edit, Claude would have to infer the provenance from the `[TY]` / `[TSGO]` etc. internal tags — which weren't guaranteed to be present or distinctive. Iter-94 prefixes every aggregated section with `[orchestrator-subhook: <registry-name>]` (the function renamed to `aggregatePostToolUseSubhookAdditionalContextMessagesIntoSingleReasonStringWithProvenancePrefixPerSection` encodes the invariant).

**Iter-94 deliverables**:

1. **`posttooluse-ty-type-check.ts` refactored**: `Bun.spawnSync` → `Bun.spawn` (async), with the new shared async-spawn helper, atomic O_EXCL-creation gate-file helper, and a fresh fail-open path for the spawn-failed-to-start case (posix_spawn ENOENT → surface install reminder once per session). All while preserving the dual-export precise+alias naming and the `import.meta.main` standalone guard.
2. **`posttooluse-tsgo-type-check.ts` migrated as 2nd subhook**: async-from-day-one (no spawnSync legacy). Precise name: `classifyTsgoNativeGoTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator` (the "project-scoped" qualifier acknowledges that tsgo reads tsconfig.json and checks the whole project, not just the edited file). Alias: `classifyTsgoTypeCheckForPostToolUseOrchestrator`. Filters subprocess output by the edited file's tsconfig-relative path to avoid basename collisions (e.g., two `index.ts` files in different project subdirs).
3. **Orchestrator aggregator enhancement**: every aggregated section now carries a `[orchestrator-subhook: <name>]` provenance prefix; the function rename encodes the invariant.
4. **`hooks.json` rewiring**: standalone `posttooluse-tsgo-type-check.ts` PostToolUse entry removed; orchestrator entry's description updated to reflect 2/15 and the iter-94 async-Bun.spawn rule.
5. **Iter-94 static audit task** (`audit-no-bun-spawnsync-in-posttooluse-orchestrator-subhooks-because-it-defeats-promise-all-parallelism-per-bun-docs-and-2026-community-guidance.sh`): parses the orchestrator's import graph, scans every classifier source file for `Bun.spawnSync(` invocations, filters out JSDoc continuation / `//` line comments / backtick-template-literal mentions (emission-pattern audit, not prose-mention audit — mirrors iter-90's PreToolUse additionalContext NON-USE audit pattern), and exits non-zero on any real invocation. Informational gate; release:preflight Check 4n candidate.
6. **Iter-94 microbenchmark task** (`benchmark-posttooluse-orchestrator-async-bun-spawn-parallelism-gain-versus-hypothetical-spawnsync-serialization-iter94-empirical-confirmation.sh`): median-of-N=5 orchestrator wall-clock across 3 synthetic payloads (.txt non-applicable baseline / .py applicable / .ts applicable). On dev hardware (Apple Silicon M1 Max, 2026-05-21): all medians ≈ 22-26ms — the bun cold-start floor — because both subhooks short-circuit via O(1) extension+existsSync filters. The wall-clock gain from async vs sync becomes visible only when MULTIPLE subhooks actually spawn real subprocesses on the same payload (future state when oxlint, biome, etc. inline).
7. **Iter-94 regression test** ([14 assertions, all pass](../.mise/tasks/tests/test-posttooluse-edit-time-orchestrator-iter94-tsgo-inlined-as-second-subhook-plus-async-bun-spawn-refactor-defeats-the-spawnsync-promise-all-anti-pattern-with-provenance-prefix-aggregation-and-static-audit-gate.sh)): orchestrator imports BOTH classifiers, registry ≥ 2 entries, dual-export naming present, NEITHER classifier uses `Bun.spawnSync`, static audit task passes cleanly, hooks.json no longer wires standalone tsgo, provenance-prefix-emitting aggregator function present, both classifiers use the shared async-spawn helper, both retain `import.meta.main` guard, orchestrator silent-noops on .txt, microbenchmark runs to completion.
8. **Iter-92 regression test follow-on update**: Case 3b now accepts EITHER standalone OR orchestrator-via-import as satisfying the [C] CONTEXT-INJECTING invariant — same migration-arc-decoupling pattern applied to Case 3a in iter-93.

**Iter-94 forensic note (bash gotcha)**: my first iter-94 test failed Case 4a/4b because `grep -c PATTERN file || echo 0` PREPENDS a second "0" when grep exits non-zero (which it does for 0-match files). Fix: use `|| true` instead of `|| echo 0`. Documented here so future iterations avoid the same pitfall.

**Iter-94 architectural takeaway**: the orchestrator's iteration model is correct only if the subhook classifiers respect the iteration model's contract. `Promise.all` parallelism requires async classifiers; mixing in `spawnSync` is a silent contract violation that defeats the whole optimization. The static audit + microbenchmark + dual-classifier shared helper together lock in the invariant for all future iter-95+ migrations.

### Iter-95: PostToolUse arc progress — oxlint + biome inlined (4/15) + shared lib/ helpers + conditional provenance prefix + empirical-parallelism benchmark

Iter-95 is a **2-subhook migration + a DRY refactor + a usability refinement + an empirical perf confirmation**, surfaced by the iter-95 adversarial multi-perspective audit. The audit found three issues:

**Issue 1 (DRY)**: the iter-94 async-spawn helper + the install-reminder gate-file pattern were duplicated verbatim across `ty-type-check` + `tsgo-type-check`. With iter-95 inlining oxlint + biome (3rd + 4th subhooks), we'd have FOUR copies of the same helpers and drift between them would silently undermine the iter-94 async-Bun.spawn invariant. Iter-95 hoists everything into `lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts`:

| Helper                                                                                                    | Purpose                                                                                                                                                                                                                                                                                       |
| --------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail` | Single source of truth for async subprocess execution. Iter-95 enhancement: adds a `maxBuffer` safety net (8MiB default, per [Bun docs](https://bun.com/docs/api/spawn) guidance) so a runaway linter producing hundreds of MB of diagnostics is killed before exhausting orchestrator memory |
| `tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName`                                    | O_EXCL atomic gate-file creation, race-safe even when N classifiers concurrently detect missing-binary                                                                                                                                                                                        |
| `drainBunSubprocessReadableStreamToUtf8TextSwallowingErrors`                                              | Idiomatic `new Response(stream).text()` drain                                                                                                                                                                                                                                                 |
| `DEFAULT_SUBPROCESS_OUTPUT_MAX_BUFFER_BYTES_PER_BUN_DOCS_SAFETY_NET = 8 * 1024 * 1024`                    | The exported constant — operators tuning this for high-output linters override via the optional `maxBufferBytes` option                                                                                                                                                                       |

**Issue 2 (usability — conditional provenance prefix)**: iter-94 unconditionally prefixed every aggregated section with `[orchestrator-subhook: <name>]`. For the common single-subhook case (a `.py` edit only triggers `ty`), the prefix was noise. Iter-95 renames the aggregator to `aggregatePostToolUseSubhookAdditionalContextMessagesIntoSingleReasonStringWithProvenancePrefixOnlyWhenMultipleSectionsContribute` and emits the prefix ONLY when ≥2 sections contribute. Single-section payloads now match the legacy standalone-hook UX. Multi-section payloads still get unambiguous provenance.

**Issue 3 (empirical confirmation gap)**: iter-94's microbenchmark deliberately fed non-existent files so subhooks short-circuited via existsSync/tsconfig-presence — that measured only the bun cold-start floor, not the parallelism gain. Iter-95 adds a second benchmark variant (`benchmark-posttooluse-orchestrator-real-subprocess-firing-with-actual-typescript-file-empirically-confirms-async-bun-spawn-parallelism-gain-iter95.sh`) that creates a REAL `.ts` file in a tsconfig-rooted dir so multiple subprocesses (tsgo + oxlint + biome) actually fire. Empirical median wall-clock on dev hardware (Apple Silicon M1 Max, 2026-05-21):

| Payload                         | Median wall-clock | Notes                                                                                                |
| ------------------------------- | ----------------- | ---------------------------------------------------------------------------------------------------- |
| non-applicable .txt             | 19.28 ms          | bun cold-start + orchestrator overhead only (all 4 subhooks short-circuit via O(1) extension filter) |
| REAL .ts in tsconfig-rooted dir | 70.53 ms          | tsgo + oxlint + biome subprocesses fire CONCURRENTLY via Bun.spawn                                   |

The delta is **~51 ms** — much less than the SUM of individual tool times (~150-200 ms if serialized via Bun.spawnSync). Empirical confirmation that the iter-94 async refactor is working: `wall-clock ≈ MAX(subhook_i)`, not SUM. If a future regression reintroduces spawnSync, the static audit (iter-94) catches it statically AND this benchmark catches it empirically.

**Iter-95 deliverables**:

1. **Shared lib module** at `lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts` with 4 helpers + 1 constant. Imported by all 4 inlined classifiers.
2. **`posttooluse-ty-type-check.ts` + `posttooluse-tsgo-type-check.ts`** refactored to import from the shared lib (iter-94 inline copies removed).
3. **`posttooluse-oxlint-check.ts`** migrated as 3rd subhook. Precise name: `classifyOxlintCorrectnessAndSuspiciousCategoryLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator` (the "correctness + suspicious" qualifier captures the actual rules enabled; "OnEditedJavaScriptOrTypeScriptFile" qualifies the input scope). Alias: `classifyOxlintCheckForPostToolUseOrchestrator`.
4. **`posttooluse-biome-lint.ts`** migrated as 4th subhook. Precise name: `classifyBiomeComplementaryToOxlintLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator` (the "ComplementaryToOxlint" qualifier captures the design contract: biome runs ALONGSIDE oxlint, not as a replacement — catches useConst, noDoubleEquals, useNodejsImportProtocol, noImplicitAnyLet, noAssignInExpressions which oxlint's default rule set misses). Alias: `classifyBiomeLintForPostToolUseOrchestrator`. Also: the 6 highest-noise biome rules are explicitly named in the constant `BIOME_LINT_RULES_SUPPRESSED_AT_HOOK_TIME_BECAUSE_TOO_NOISY_FOR_REAL_CODEBASES`.
5. **Orchestrator aggregator** renamed to `aggregatePostToolUseSubhookAdditionalContextMessagesIntoSingleReasonStringWithProvenancePrefixOnlyWhenMultipleSectionsContribute` — the boolean `shouldEmitProvenancePrefix` makes the conditional invariant explicit.
6. **`hooks.json` rewiring**: standalone oxlint + biome entries removed; orchestrator description bumped to 4/15.
7. **Empirical-parallelism benchmark task** with median-of-N=5 across real-subprocess-firing .ts payload.
8. **Iter-95 regression test** (14 assertions all pass): shared lib helper exports correct surface, ALL 4 classifiers import from shared lib (DRY invariant), registry ≥4 entries, dual-export naming present for oxlint + biome, hooks.json no longer wires standalone oxlint/biome, iter-94 static audit STILL passes (no spawnSync regression in any of the 4 classifiers), aggregator renamed + shouldEmitProvenancePrefix present, all 4 classifiers retain import.meta.main standalone guards, benchmark task runs to completion.
9. **iter-92 + iter-94 regression tests** updated for migration-arc decoupling (accept EITHER standalone OR orchestrator-via-import; threshold lowered from ≥15 to ≥10 PostToolUse hooks marketplace-wide as more subhooks consolidate).

**Iter-95 architectural-symmetry observation**: with 4 type-checkers/linters now inlined, the orchestrator's `Promise.all` parallelism becomes load-bearing. The shared lib + static audit + empirical benchmark together form a **3-layer regression defense**:

| Layer | Defense                             | Catches                                                            |
| ----- | ----------------------------------- | ------------------------------------------------------------------ |
| 1     | Compile-time (static audit)         | New classifiers using `Bun.spawnSync`                              |
| 2     | Test-time (iter-95 regression test) | Classifiers not importing from shared lib (DRY drift)              |
| 3     | Runtime (empirical benchmark)       | Wall-clock regressing from MAX → SUM if (1) and (2) miss something |

This locks in the iter-94 invariant for the rest of the iter-93+ migration arc.

### Iter-96: PostToolUse arc progress — vale-claude-md inlined (5/15) + Bun.stdin.text() one-shot migration + timeout-aware additional_context + maxBuffer right-sized

Iter-96 is a **5th-subhook migration + 3 audit-driven refinements** of the iter-93→iter-95 architecture. The iter-96 adversarial audit surfaced three high-leverage issues plus one natural-next-migration target:

**Issue 1 (silent false-negative on timeout)**. Iter-93/94/95 fail-open `noop` on subhook timeout. The 2026 community guidance [`The Silent Failure Mode in Claude Code Hook Every Dev Should Know About`](https://thinkingthroughcode.medium.com/the-silent-failure-mode-in-claude-code-hook-every-dev-should-know-about-0466f139c19f) plus the [Anthropic operator-visibility best practice](https://code.claude.com/docs/en/hooks) — "Use `additionalContext` (not stderr) to surface diagnostic information back to Claude" — converged on the fix: when a subhook times out, the orchestrator now emits a TIMEOUT-AWARE `additional_context` decision via the new contract helper `buildPostToolUseTimeoutAwareAdditionalContextDecisionForOperatorVisibility(subhookName, timeoutMs)`. Claude sees "type-check timed out — manually verify" instead of assuming the check passed. The helper's invariants:

- Operator-actionable message (subhook name + tool + suggested manual-verify command)
- ≤200 chars so aggregate reason doesn't blow up
- Fold-compatible with the iter-95 conditional-prefix aggregator

**Issue 2 (stdin reader: stream → text)**. Iter-93/94/95 used `Bun.stdin.stream()` + manual `TextDecoder` loop — sub-optimal per [Bun docs](https://bun.com/guides/process/stdin). The 2026 idiomatic one-shot read is `await Bun.stdin.text()`: decoding happens in native code (no userspace TextDecoder cost), and the chunk-coalescing bugs documented in [Bun #7500](https://github.com/oven-sh/bun/issues/7500) / [#11553](https://github.com/oven-sh/bun/issues/11553) / [#3255](https://github.com/oven-sh/bun/issues/3255) (all affecting `stdin.stream()`) are bypassed entirely. Iter-96 migrates the orchestrator + ALL 5 classifier standalone-CLI mains (6 entry points total).

**Issue 3 (maxBuffer right-sizing)**. Iter-95 set `maxBuffer = 8 MiB` as a Node-parity default. Real-world type-checker/linter output is ≤50 KB typical, ≤200 KB pathological. 8 MiB was overkill. Iter-96 tightens to **256 KiB** so runaway subprocess output (e.g., a misconfigured linter spamming stack-traces) surfaces earlier as a hook diagnostic rather than silently consuming orchestrator memory. The exported constant `DEFAULT_SUBPROCESS_OUTPUT_MAX_BUFFER_BYTES_PER_BUN_DOCS_SAFETY_NET` keeps the algorithm intent encoded in the name.

**Migration target (vale-claude-md as 5th subhook)**. PostToolUse twin to the iter-91 PreToolUse `vale-claude-md-guard` — different semantic (PreToolUse BLOCKS, PostToolUse INFORMS) but same vale subprocess invocation. Dual-export naming: `classifyValeTerminologyConformanceOnEditedClaudeMdFileForPostToolUseOrchestrator` (precise: encodes that this checks TERMINOLOGY CONFORMANCE, not grammar/spelling) + alias `classifyValeClaudeMdForPostToolUseOrchestrator`. Registry `timeoutMs: 12000ms` (heaviest classifier; vale spawns ~100-300ms typical wall-clock).

**Iter-96 deliverables**:

1. **Contract enhancement** at `lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts`: new `buildPostToolUseTimeoutAwareAdditionalContextDecisionForOperatorVisibility` helper.
2. **Shared lib enhancement** at `lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts`: maxBuffer constant tightened from `8 * 1024 * 1024` to `256 * 1024`.
3. **Orchestrator update**: imports + uses the timeout-aware helper in the abort-error branch (replaces silent fail-open noop). Stdin reader migrated to `Bun.stdin.text()`.
4. **5 classifier mains**: ty, tsgo, oxlint, biome, and the new vale-claude-md — all standalone-CLI mains migrated to `Bun.stdin.text()`.
5. **`posttooluse-vale-claude-md.ts` rewritten** with the iter-95 shared-lib pattern: async Bun.spawn, dual-export naming, import.meta.main guard preserved.
6. **`hooks.json` rewiring**: standalone vale-claude-md entry removed from its shared PostToolUse Write|Edit array (leaving glossary-sync + terminology-sync intact); orchestrator description bumped to 5/15 with the iter-96 enhancements summarized.
7. **Iter-96 regression test** (13 assertions all pass): vale dual-export naming, registry ≥5 entries, ALL 6 entry points migrated to Bun.stdin.text(), maxBuffer = 256KiB, timeout-aware helper exists + imported, iter-94 static audit still passes (5 classifiers scanned cleanly), hooks.json clean, ALL 5 classifiers retain `import.meta.main`, orchestrator silent-noop on .txt, orchestrator description records 5/15.
8. **Final marketplace state**: 33/33 hook regression tests pass; 37/37 plugins valid.

**Iter-96 architectural takeaway**: iter-96 closes the "silent failure" gap that the iter-93/94/95 design left open. The iter-94 static audit defends against `Bun.spawnSync` regression. The iter-95 shared-lib defends against DRY drift. The iter-96 timeout-aware additionalContext closes the **operator-visibility gap**: silent fail-open is no longer the worst-case outcome of a subhook running over its budget — Claude is informed and can choose to manually verify. The 3-layer regression defense (compile-time static audit + test-time DRY check + runtime parallelism benchmark) plus the iter-96 timeout-visibility surface comprise a **4-layer correctness defense** for the iter-93+ orchestrator architecture.

### Iter-97: PostToolUse arc progress — ssot-principles inlined (6/15) + FIRST real Promise.all parallel fan-out + latent /tmp temp-file race eliminated + shell-spawn overhead removed

Iter-97 is a **6th-subhook migration + 3 adversarial-audit remediations**. This iteration crosses a qualitative architectural threshold: **for the first time, the orchestrator's `Promise.all` parallelism is exercised by overlapping extension filters**, not just by cold-start amortization.

**The parallelism-fan-out milestone**. Pre-iter-97, the 5 inlined classifiers had DISJOINT extension filters:

| Classifier      | Extensions matched                           |
| --------------- | -------------------------------------------- |
| ty-type-check   | `.py`, `.pyi`                                |
| tsgo-type-check | `.ts`, `.tsx`                                |
| oxlint-check    | `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs` |
| biome-lint      | `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs` |
| vale-claude-md  | `.md` (only CLAUDE.md)                       |

Note that even tsgo/oxlint/biome overlap on `.ts`/`.tsx`/`.js`/`.jsx` — but the cold-start savings dominated because the heavy work in each is a SUBPROCESS spawn (ty/tsgo/oxlint/biome/vale binaries) so `Promise.all` was already buying real wall-clock parallelism for those overlapping cases. Iter-97 adds `ssot-principles` which overlaps EVERYTHING `.py`/`.ts`/`.tsx`/`.js`/`.jsx`/`.rs`/`.go`/`.java`/`.kt`/`.rb`. Wall-clock measurement now structurally converges to MAX(subhook), not SUM(subhook) — the iter-93 design goal made empirical.

**Audit-driven finding 1 (latent /tmp temp-file race)**. The pre-iter-97 `posttooluse-ssot-principles.ts` wrote proposed content to a FIXED scratch path under `/tmp` keyed only by the file-extension suffix (`/tmp/.claude-ssot-scan` + extname). Two concurrent Claude sessions writing the same extension would corrupt each other's scan buffer. Iter-97 fix: PostToolUse fires AFTER the tool executes, so the file IS on disk with new content by the time we run — scan `filePath` directly, eliminating the temp-file branch entirely. **No race possible.** This is the kind of subtle bug that adversarial audit + filesystem-concurrency-thinking finds before it bites in production.

**Audit-driven finding 2 (shell-spawn overhead via `bun $` template literal)**. The pre-iter-97 implementation used Bun's `$` template literal:

```typescript
const result = await $`ast-grep scan ${filePath} --json`
  .cwd(AST_GREP_RULES_DIR)
  .quiet()
  .nothrow();
```

This spawns a SHELL for argument parsing (~5-10 ms cost per call). Iter-97 migrates to the iter-95 shared helper `executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail` which uses `Bun.spawn` directly (no shell):

- No shell parse overhead
- Inherits the iter-96 256 KiB `maxBuffer` safety net (ast-grep's `--json` output is potentially huge for files with many findings)
- Inherits `AbortSignal.timeout`-driven cooperative cancellation (the pre-iter-97 code had `.nothrow()` but NO timeout binding — a pathological ast-grep run could hang the entire orchestrator)

**Audit-driven finding 3 (no cooperative timeout)**. Pre-iter-97 had no AbortSignal bound to the ast-grep call. Iter-97 inherits the shared helper's 2000 ms timeout (`AST_GREP_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS`).

**Iter-97 deliverables**:

1. **`posttooluse-ssot-principles.ts` rewritten** with the iter-95 shared-lib pattern: async Bun.spawn via shared helper, dual-export naming (`classifySsotPrinciplesAstGrepBasedAntiPatternDetectionOncePerSessionForPostToolUseOrchestrator` + alias `classifySsotPrinciplesForPostToolUseOrchestrator`), `import.meta.main` standalone-CLI guard preserved.
2. **Latent /tmp temp-file race eliminated**: classifier scans `filePath` directly per PostToolUse invariant.
3. **Shell-spawn overhead removed**: migrated from `bun $` template literal to direct `Bun.spawn` via shared helper.
4. **Cooperative timeout bound**: 2000 ms `AbortSignal.timeout`.
5. **Orchestrator update**: imports `classifySsotPrinciplesForPostToolUseOrchestrator`; registry has 6 entries (lightest-last position because once-per-session gate keeps actual work rare). Description bumped to 6/15.
6. **`hooks.json` rewiring**: standalone ssot-principles entry removed (only via orchestrator import); orchestrator description records the iter-97 milestones.
7. **Iter-97 regression test** (12 assertions all pass): dual-export naming, registry ≥6 entries, shared async-spawn helper imported, legacy `await $\`...\``emission absent, latent`/tmp/.claude-ssot-scan`scratch emission absent, iter-94 static audit still passes (6 classifiers scanned cleanly), hooks.json clean of standalone entry, orchestrator description records 6/15,`import.meta.main`standalone guard retained, all 7 entry points (orchestrator + 6 classifier mains) use`Bun.stdin.text()`, end-to-end`.py`edit fires ssot-principles via orchestrator and emits`decision:block` JSON.
8. **Iter-94 static audit naturally scales**: now scans 6 classifiers, no spawnSync regression.

**Iter-97 architectural takeaway**: the migration arc has now ACTUALLY exercised the parallel-fan-out machinery — every prior iteration was infrastructure or single-classifier work. The remaining 9 hooks to inline (posttooluse-reminder, code-correctness-guard, glossary-sync, terminology-sync, readme-pypi-links, calendar-reminder-sync, gh-issue-title-reminder, rust-sota-reminder, memory-efficiency-reminder) will each add more overlap surface. With ssot-principles' once-per-session gate adding negligible cost when already-claimed, the wall-clock budget for the orchestrator stays close to MAX(subhook) regardless of registry size. The iter-93+ architecture has reached **the milestone where its design assumption (Promise.all wall-clock ≈ MAX, not SUM) became empirically observable**.

### Iter-98: PostToolUse arc progress — memory-efficiency-reminder inlined (7/15) + long-standing silent context-drop bug FIXED + once-per-session gate-file helper hoisted to shared lib

Iter-98 is a **7th-subhook migration that uncovered and FIXED a long-standing silent-context-drop bug**, plus a DRY uplift of the once-per-session gate-file logic into the shared lib.

**Audit-driven finding (the bug)**. The pre-iter-98 standalone `posttooluse-memory-efficiency-reminder.ts` emitted its reminder via `console.log(\`[MEMORY-EFFICIENCY] ...\`)`— raw text, NOT`{decision: "block", reason: ...}` JSON. Per the iter-66/93 forensic finding (cited verbatim in the original 2025 Anthropic PostToolUse schema docs): plain-text stdout from PostToolUse hooks is rendered into the operator transcript (Ctrl-R-visible) but **never delivered to Claude's next-turn context**. The reminder was therefore EFFECTIVELY INVISIBLE to Claude — operator-visible but Claude-invisible. This had existed since the hook was originally written.

Why the iter-92 async-eligibility audit didn't catch it: the iter-92 classifier pattern-matches on `decision: "block"` / `permissionDecision: "deny"` / `additionalContext:` source-code emission shapes to bucket each hook as `[C] CONTEXT-INJECTING / ASYNC-UNSAFE` vs `[S] PURE-SIDE-EFFECT / ASYNC-SAFE`. memory-efficiency-reminder matched NEITHER pattern (raw `console.log` doesn't match either), so iter-92 returned `[M] MIXED — couldn't statically classify`. The `[M]` bucket was treated as "manually review later" and effectively shelved — the bug stayed hidden in plain sight. **Adversarial-audit lesson**: a static-classifier bucket of `MIXED / UNKNOWN` is itself a finding to investigate, not a deferral.

**The fix**. Inline the hook into the orchestrator (whose aggregator wraps every contributing `additional_context` decision into a proper `{decision: "block", reason: aggregate}` JSON Claude DOES read). The standalone-CLI path now also emits JSON via `JSON.stringify({decision: "block", reason})` instead of raw `console.log`. Pre-iter-98 sessions running the standalone hook saw no reminder reach Claude; post-iter-98 sessions get the reminder both ways.

**Audit-driven finding 2 (race-unsafe gate-file write)**. Pre-iter-98 used `existsSync(sentinelPath) + writeFileSync(sentinelPath, ...)` for the once-per-session gate. This is **NOT atomic** — two concurrent invocations (extremely unlikely under serial orchestrator dispatch but possible across parallel Claude sessions) could BOTH pass the `existsSync` check before either calls `writeFileSync`, double-firing the reminder. The iter-95 install-reminder helper and iter-97 ssot-principles local helper both use `O_CREAT | O_EXCL` (atomic at POSIX layer — exactly one caller wins, all others see EEXIST). Iter-98 unifies all three paths via the new shared helper.

**DRY uplift (the shared helper)**. Iter-97 documented a TODO: "when iter-98 inlines memory-efficiency-reminder, hoist a generic-reminder gate-file helper to the shared lib." Iter-98 cashes that TODO in. The new helper `tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName(reminderName, sessionId)` constructs the gate path as `/tmp/.claude-${reminderName}-reminder/${sessionId}.reminded` and uses the same atomic O_EXCL pattern as the iter-95 install-reminder helper. Both ssot-principles AND memory-efficiency-reminder now consume the same helper — the atomic invariant cannot drift between sibling reminder-style classifiers.

| Helper                                                                               | Gate path                                                               | Consumers                                   |
| ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------- | ------------------------------------------- |
| `tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName` (iter-95)     | `/tmp/.claude-${tool}-install-reminder/${sid}-${tool}-install.reminded` | ty, tsgo, oxlint, biome                     |
| `tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName` (iter-98) | `/tmp/.claude-${reminder}-reminder/${sid}.reminded`                     | ssot-principles, memory-efficiency-reminder |

Both helpers atomic via `O_CREAT | O_EXCL`; both fail-closed on filesystem errors; both return `false` on the EEXIST loser-of-race path.

**Iter-98 deliverables**:

1. **Shared lib hoist** at `lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts`: new `tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName(reminderName, sessionId)` exported alongside the iter-95 install-reminder helper. The file name is preserved (iter95 in path) because the contract is additive — iter-98 didn't break iter-95 callers.
2. **`posttooluse-memory-efficiency-reminder.ts` rewritten** with the iter-95 shared-lib pattern: dual-export naming (`classifyMemoryEfficiencyBestPracticesReminderOncePerSessionForPostToolUseOrchestrator` + alias `classifyMemoryEfficiencyReminderForPostToolUseOrchestrator`), `import.meta.main` standalone-CLI guard with proper JSON emission, atomic O_EXCL gate via shared helper.
3. **`posttooluse-ssot-principles.ts` uplifted** to import the same shared helper; iter-97-era local `tryAtomicallyClaimOncePerSessionSsotPrinciplesReminderGateFile` function removed. Gate-file on-disk path preserved (`/tmp/.claude-ssot-principles-reminder/${sessionId}.reminded`) — existing sessions are NOT re-reminded after the upgrade.
4. **Orchestrator update**: imports `classifyMemoryEfficiencyReminderForPostToolUseOrchestrator`; registry has 7 entries (memory-efficiency-reminder placed BEFORE ssot-principles because once-per-session means most invocations are sub-ms gate-claim noops); description bumped to 7/15.
5. **`hooks.json` rewiring**: standalone memory-efficiency-reminder entry removed; orchestrator description records the iter-98 milestones (silent-drop bug fix + DRY hoist).
6. **Iter-98 regression test** (16 assertions all pass): dual-export naming, registry ≥7, silent-drop bug fix in BOTH orchestrator path AND standalone path, raw `console.log(\`...\`)`template-literal emission removed, iter-98 shared helper exists + consumed by both classifiers, iter-97 local gate helper removed, iter-94 static audit still passes (7 classifiers scanned), hooks.json clean of standalone entry, description ≥7/15,`import.meta.main`retained, race-unsafe`existsSync(sentinelPath)`pattern removed, end-to-end orchestrator fires BOTH memory-efficiency AND ssot-principles on .py edit with conditional`[orchestrator-subhook: <name>]` provenance prefix activated (≥2 sections).

**Iter-98 architectural takeaway**: iter-92's `[M] MIXED` classifier bucket is not a "review later" deferral — it is an **active finding** worth digging into. The memory-efficiency-reminder silent-drop bug had been undetected through iter-92 → iter-97 because static pattern-matching can't distinguish "deliberately operator-only" (correct use of raw stdout for transcript visibility) from "accidentally Claude-invisible" (broken context-injection masquerading as a working reminder). The bug required adversarial multi-perspective audit (reading the hook's intent vs reading the Anthropic schema docs vs running the hook and observing what Claude actually saw) to surface. The fix delivers what the hook always intended: Claude-visible context every session, not transcript-only operator visibility.

### Iter-99: marketplace-wide preventive audit for the silent-context-drop pattern + Check 4n preflight gate

Iter-98 closed the single-hook silent-context-drop bug in `posttooluse-memory-efficiency-reminder.ts`. Iter-99 **scales the fix to a marketplace invariant** by building a preventive static audit task — directly parallel to how iter-94 turned the iter-93 single-classifier async-spawn fix into the marketplace-wide spawnSync-regression gate.

**The two valid Claude-visible PostToolUse stdout schemas**. Iter-99 documents that PostToolUse hooks have TWO accepted Claude-visible stdout schemas, not one. Pre-iter-99 the iter-66/93 forensic finding only emphasized the `{decision: "block", reason}` schema; iter-99 adds the `hookSpecificOutput.additionalContext` schema discovered in `rust-tools/hooks/posttooluse-rust-sota-reminder.ts` (which cites ADR `2025-12-17-posttooluse-hook-visibility.md` updated 2026-05-19).

| Schema                                                                           | Used by                                                                                                                          |
| -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `{decision: "block", reason: "..."}`                                             | iter-93+ orchestrator + 7 inlined subhooks + bash `posttooluse-1password-pattern-reminder.sh` + bash `code-correctness-guard.sh` |
| `{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: "..."}}` | `rust-tools/hooks/posttooluse-rust-sota-reminder.ts`                                                                             |

Anything else on stdout (raw template-literal text, raw string-literal text, arbitrary plain output) is **silently dropped** by Claude Code — operator-transcript-visible only (Ctrl-R).

**The preventive audit**. The new task `audit-no-raw-stdout-emission-in-posttooluse-typescript-hooks-because-anthropic-schema-routes-non-json-stdout-to-operator-transcript-only-and-silently-drops-it-from-claude-context.sh`:

- Discovers every `plugins/*/hooks/posttooluse-*.{ts,mjs}` (17 hooks at iter-99 time).
- Flags `console.log(\`...\`)` template-literal emissions (the iter-98 incident shape).
- Flags `console.log("...")` and `console.log('...')` plain-string emissions (alternative raw-text shapes).
- Allows `console.log(JSON.stringify(...))` (the audit regex `console\.log\((\`|"|')`does not match a`J` first-character argument).
- Allows `console.log(variableName)` — too hard to statically verify variable contents always hold JSON; trust author + escape hatch if needed.
- Skips JSDoc continuation lines (`^\s*\*`) and `//` line-comments — prose mentions of the bad pattern don't false-positive.
- Honors `// POSTTOOLUSE-RAW-STDOUT-OK: <reason ≥ 10 chars>` escape hatch on the same line or within the 3 preceding lines, for explicitly-operator-only intent.

**Marketplace state at iter-99**: 17 PostToolUse TypeScript hooks scanned, **0 violations**. iter-98's fix was confirmed the unique instance of the silent-drop pattern across the marketplace.

**Wired into release preflight as Check 4n** (informational gate alongside iter-86's Check 4m subhook-contract checker). The gate will visibly warn operators when a future hook accidentally introduces the silent-drop pattern, without blocking release.

**Iter-99 regression test** (11 assertions all pass): audit-task existence, live-marketplace passes clean (17 hooks), detection regex catches iter-98 incident shape + double-quoted + single-quoted variants, JSDoc + line-comment prose mentions correctly skipped (no false-positives), same-line + 3-line preceding-window escape hatches honored, `JSON.stringify`-wrapped emissions NOT flagged, end-to-end fixture-injection (a synthesized bad-pattern hook placed inside `plugins/` triggers audit failure and is reported in the output).

**Iter-99 architectural takeaway — the "preventive gate" pattern**. iter-98 fixed one hook; iter-99 prevents the entire class of bug from recurring across the marketplace. This mirrors several prior iterations:

| Iter  | Single-hook fix                         | Marketplace-wide preventive gate                                            |
| ----- | --------------------------------------- | --------------------------------------------------------------------------- |
| 63→65 | stdin-inlet-guard matcher narrowed      | iter-65 wildcard-matcher audit                                              |
| 66→67 | stop-orchestrator additionalContext fix | iter-67 Stop-hook additionalContext-emission audit (extended in iter-68/69) |
| 77→78 | link-tools L3-stripped-path silent-fail | iter-78 edit-time L3 audit + iter-77 release-time Check 4k                  |
| 93→94 | ty-type-check spawnSync→spawn migration | iter-94 marketplace-wide no-spawnSync audit                                 |
| 98→99 | memory-efficiency-reminder silent-drop  | **iter-99 marketplace-wide silent-context-drop audit (this iteration)**     |

The pattern: **single-instance fix in iter-N → marketplace-wide static audit + preflight gate in iter-N+1**. Each gate is informational by default (warns without blocking) and may be flipped to `--strict` once the marketplace baseline stabilizes. The cumulative effect is a growing set of **schema-correctness gates** that prevent recurrence of bugs the marketplace has already discovered and fixed.

### Iter-100 MILESTONE: orchestrator matcher broadened Write|Edit → Write|Edit|MultiEdit (web-research-driven gap closure) + canonical tool-name allow-set helper hoisted to contract lib + iter-99 audit scope refined

Iter-100 — the centennial iteration — closes a **matcher-coverage gap** in the iter-93+ orchestrator that web research into 2026 Anthropic + community best-practice surfaced. Pre-iter-100, the orchestrator + all 7 inlined classifiers honored only `Write` and `Edit`. The recommended 2026 matcher for file-edit PostToolUse hooks is `Write|Edit|MultiEdit` — Claude uses `MultiEdit` when applying multiple Edits to a single file in one tool call, and a classifier missing `MultiEdit` silently skips that entire class of input.

**The coverage gap was empirically demonstrable.** Pre-iter-100 a MultiEdit payload returned empty stdout from the orchestrator. Post-iter-100 the orchestrator fires the expected subhooks with the iter-95 conditional `[orchestrator-subhook: <name>]` provenance prefix activated.

**The fix is a one-line `hooks.json` matcher broadening + a per-classifier tool-name-guard refactor centralized via a new contract helper**:

```typescript
// lib/posttooluse-subhook-contract-...iter93.ts (iter-100 addition)

export const FILE_EDIT_TOOL_NAMES_HONORED_BY_POSTTOOLUSE_CONTEXT_INJECTING_SUBHOOKS: ReadonlySet<string> =
  new Set(["Write", "Edit", "MultiEdit"]);

export function isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook(
  toolName: string | undefined,
): boolean {
  if (!toolName) return false;
  return FILE_EDIT_TOOL_NAMES_HONORED_BY_POSTTOOLUSE_CONTEXT_INJECTING_SUBHOOKS.has(
    toolName,
  );
}
```

Three classifiers (`vale-claude-md`, `ssot-principles`, `memory-efficiency-reminder`) had explicit hand-rolled `toolName !== "Write" && toolName !== "Edit"` guards — those were the silent-reject points for MultiEdit. They now import + call the canonical helper. The other 4 classifiers (`ty`, `tsgo`, `oxlint`, `biome`) check `file_path` + extension only without checking `tool_name`, so they worked natively on MultiEdit once the matcher broadened.

**Why centralize the allow-set in the contract**: future Anthropic tool-name additions (a hypothetical `BatchEdit` or `ApplyDiff`) update ONE constant, not N classifier files. Eliminates the drift hazard where the orchestrator's hooks.json matcher string and each classifier's tool-name guard fall out of sync.

**Per-tool MultiEdit-handling notes**:

- `ty-type-check`, `tsgo-type-check`, `oxlint-check`, `biome-lint`: scan filePath + extension only. MultiEdit fires naturally — the file on disk reflects all edits applied.
- `ssot-principles`, `memory-efficiency-reminder`: once-per-session reminders, fire on first eligible edit regardless of edit shape. MultiEdit fires naturally.
- `vale-claude-md`: has Write (whole-file) vs Edit (changed-line-range) line-scoping logic. For MultiEdit it currently falls through to whole-file scan (same as Write). Acceptable baseline — slightly noisier output than per-edit line scoping but never silently drops violations. Future iter could compute MultiEdit-specific line ranges from the `edits[]` array.

**Iter-99 audit scope refinement (companion improvement)**: pre-iter-100 the iter-99 audit's `find` glob scanned `*/hooks/lib/*` files alongside real PostToolUse hooks. These lib helpers are imported by classifiers but never run as PostToolUse entry points themselves. Iter-100 adds `-not -path '*/hooks/lib/*'` to the find — scope tightens from 17 files (15 real + 2 lib) to 15 real hooks. No semantic change (lib helpers had 0 emissions to start), but the audit scope is now precisely "files that actually run as PostToolUse-event entry points."

**Iter-100 architectural takeaway — "matcher hygiene" as a category of preventive maintenance**. The iter-100 gap was discovered not by the existing static audits (no audit looked at matcher strings) but by **explicit web research into 2026 best-practice docs**. This establishes a fourth category alongside the three pre-existing surfacing mechanisms:

| Surfacing mechanism            | Reads                                        | Example                                    |
| ------------------------------ | -------------------------------------------- | ------------------------------------------ |
| Static-pattern audit           | Marketplace source for known bad patterns    | iter-94 spawnSync, iter-99 silent-drop     |
| Single-hook intent vs behavior | Hook intent vs what Claude actually receives | iter-98 memory-efficiency silent-drop      |
| Web-research-driven            | 2026 Anthropic docs + community guides       | **iter-100 MultiEdit matcher (THIS ITER)** |
| Schema-evolution watch         | GitHub issue forensic tracking               | iter-72 GitHub #60993 confirmation         |

Iterations should rotate through all four categories. Iter-100 establishes the **web-research-driven** category as a first-class member of the rotation.

Sources for iter-100 web research:

- [Anthropic Claude Code Hooks Docs](https://code.claude.com/docs/en/hooks-guide)
- [Claude Code Hooks Complete Guide (2026)](https://claudefa.st/blog/tools/hooks/hooks-guide)
- [DEV Community: Claude Code Hooks Complete Guide with 20+ Ready-to-Use Examples (2026)](https://dev.to/lukaszfryc/claude-code-hooks-complete-guide-with-20-ready-to-use-examples-2026-dcg)
- [Claude Code Hooks: From Linting to Hardened AI Workflows](https://thomas-wiegold.com/blog/claude-code-hooks/)

### Iter-101: marketplace-wide matcher-hygiene audit — scales iter-100 single-orchestrator fix to a marketplace invariant

Iter-100 fixed the MultiEdit coverage gap in **one** PostToolUse orchestrator. Iter-101 asks: how many OTHER hooks across the marketplace silently allow MultiEdit through? Built `audit-pretooluse-and-posttooluse-hook-matchers-for-write-or-edit-without-multiedit-coverage-gap-surfaced-by-iter100-postooluse-orchestrator-matcher-broadening-scaled-to-marketplace-invariant.sh` to scan every `plugins/*/hooks/hooks.json` and surface PreToolUse/PostToolUse matcher entries that include `Write` or `Edit` token but NOT `MultiEdit`.

**Audit findings on first run** (8 violations across 3 plugins):

| Plugin         | Event       | Matcher (pre-iter-101)                | Hook                                                       | Severity                                                                                                         |
| -------------- | ----------- | ------------------------------------- | ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| itp-hooks      | PreToolUse  | `Write\|Edit`                         | `pretooluse-edit-time-orchestrator-...iter66-precedent.ts` | **CRITICAL** — entire iter-84→iter-91 PreToolUse orchestrator (8 inlined subhooks) silently no-op'd on MultiEdit |
| itp-hooks      | PreToolUse  | `Bash\|Write\|Edit`                   | `pretooluse-process-storm-guard.mjs`                       | High — fork-bomb content in MultiEdit payloads bypassed                                                          |
| itp-hooks      | PostToolUse | `Bash\|Write\|Edit`                   | `posttooluse-reminder.ts`                                  | Medium — PUEUE/UV reminders missed on MultiEdit                                                                  |
| itp-hooks      | PostToolUse | `Bash\|Write\|Edit`                   | `code-correctness-guard.sh`                                | High — silent-failure detection bypassed on MultiEdit                                                            |
| itp-hooks      | PostToolUse | `Write\|Edit`                         | `posttooluse-glossary-sync.ts`                             | Medium — GLOSSARY.md MultiEdits skipped sync                                                                     |
| itp-hooks      | PostToolUse | `Write\|Edit`                         | `posttooluse-terminology-sync.ts`                          | Medium — terminology drift undetected on MultiEdit                                                               |
| dotfiles-tools | PostToolUse | `Edit\|Write`                         | `chezmoi-sync-reminder.sh`                                 | Medium — chezmoi-managed dotfile MultiEdits silently skipped                                                     |
| rust-tools     | PostToolUse | `Read\|Glob\|Grep\|Bash\|Edit\|Write` | `posttooluse-rust-sota-reminder.ts`                        | Low — Rust SOTA reminder skipped MultiEdit                                                                       |

All 8 fixed by appending `|MultiEdit` to each matcher string. Per-classifier `tool_name` guards inside individual classifiers may still exclude MultiEdit (future iter-102 candidate: PreToolUse-side canonical-helper hoist mirroring iter-100's PostToolUse work). Iter-101 closes the matcher-level silent-allow gap; downstream classifier behavior either correctly handles MultiEdit (orchestrator route) or silently no-ops (status quo preserved).

**Escape hatch**: `MATCHER-NO-MULTIEDIT-OK: <reason ≥ 10 chars>` in the hook's `description` field for explicitly-justified MultiEdit exclusions (0 current uses; 100% of surfaced violations were unjustified).

**Wired into preflight as Check 4o** (informational, parallel to Check 4n iter-99 silent-context-drop + Check 4m iter-94 spawnSync). Future iters may flip to `--strict` once the marketplace stabilizes.

**Iter-101 regression test** (10 assertions all pass): audit-task existence, live-marketplace passes clean post-fixes (10 hooks.json files scanned, 29 matcher tuples checked), fixture-based detection of `Write|Edit` + `Bash|Write|Edit` + reversed-order `Edit|Write` (token-membership detection is order-independent), `MATCHER-NO-MULTIEDIT-OK` escape hatch honored per-inner-hook (not per-matcher), `Bash`/`Read`/`WebFetch|WebSearch`-only matchers correctly skipped (no false-positives on non-edit tools), all 6 marketplace broadenings verified present in the actual hooks.json files (2 standalone + 4 itp-hooks; 0 residual itp-hooks gaps).

**Iter-101 architectural takeaway — the "preventive gate" pattern is now applied twice in succession**. iter-100 fixed one hook; iter-101 fixed the entire marketplace and built the preventive infrastructure. This is the same iter-98→iter-99 pattern (single fix → marketplace audit + preflight gate) applied to the iter-100 discovery — establishing that the "preventive gate" workflow is the **default response** to any web-research-driven discovery, not a one-off exception. Future web-research-driven iters should automatically generate audit-gate companion work in the next iteration.

**Iter-101 scope refinement vs iter-102 follow-up**: iter-101 closes the matcher-level silent-allow gap. A latent gap remains at the per-classifier `tool_name` guard level inside the PreToolUse orchestrator's 8 inlined classifiers (file-size-guard, vale-claude-md-guard, version-guard, hoisted-deps-guard, mise-hygiene-guard, pyi-stub-guard, native-binary-guard, gpu-optimization-guard) — those still use `toolName === "Write" || toolName === "Edit"` guards that exclude MultiEdit at the classifier level. The matcher fix is necessary but not sufficient; iter-102 should hoist a `FILE_EDIT_TOOL_NAMES_HONORED_BY_PRETOOLUSE_BLOCKING_SUBHOOKS` canonical helper into the PreToolUse contract lib (mirroring iter-100's `FILE_EDIT_TOOL_NAMES_HONORED_BY_POSTTOOLUSE_CONTEXT_INJECTING_SUBHOOKS`) and migrate all 8 PreToolUse classifiers. Status quo for iter-101: matcher fires on MultiEdit → orchestrator routes → classifiers self-skip (silent no-op preserved, no regression).

### Iter-102: PreToolUse canonical-helper hoist + 8 classifier migration — mirrors iter-100 PostToolUse-side helper hoist

Iter-102 closes the residual gap iter-101 documented. Symmetric to iter-100's PostToolUse work:

| Layer                 | Iter-100 (PostToolUse)                                                   | Iter-102 (PreToolUse)                                                                               |
| --------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| Constant              | `FILE_EDIT_TOOL_NAMES_HONORED_BY_POSTTOOLUSE_CONTEXT_INJECTING_SUBHOOKS` | `FILE_EDIT_TOOL_NAMES_HONORED_BY_PRETOOLUSE_BLOCKING_SUBHOOKS`                                      |
| Helper                | `isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook`          | `isFileEditToolNameHonoredByPreToolUseBlockingSubhook`                                              |
| Migrated classifiers  | 3 (vale, ssot, memory-eff)                                               | 8 (file-size, vale, version, hoisted-deps, mise-hygiene, pyi-stub, native-binary, gpu-optimization) |
| Contract lib location | `lib/posttooluse-subhook-contract-...-iter93.ts`                         | `lib/pretooluse-subhook-contract-...-iter84.ts`                                                     |

**Iter-102 staged-migration short-circuit**: each migrated classifier adds `if (tool_name === "MultiEdit") return ALLOW_DECISION;` immediately after the canonical-helper guard. This preserves status quo (silent no-op on MultiEdit) while preventing false-positives that would otherwise occur if MultiEdit payloads reached the downstream Edit branches (which would access `tool_input.old_string` / `tool_input.new_string` — undefined on MultiEdit — and silently corrupt content-replacement logic). iter-103+ scope: per-classifier MultiEdit content-extraction logic (each classifier teaches itself to read `tool_input.edits[]` and apply them sequentially against the existing file content).

**Iter-102 web-research discovery — NotebookEdit gap**: 2026 best-practice docs ([Claude Code Tools Reference](https://code.claude.com/docs/en/tools-reference), [Claude Code Hooks Complete Guide March 2026](https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/), [Claude Code Hooks Complete 2026 Production Reference](https://thepromptshelf.dev/blog/claude-code-hooks-complete-reference-2026/)) document the canonical "any file modification" matcher as **`Edit|MultiEdit|Write|NotebookEdit`** — which means **iter-101 was also incomplete** (we broadened to 3 tools, the canonical recommendation is 4). NotebookEdit has a fundamentally different payload shape (`tool_input.notebook_path` + `cell_id` + `edit_mode` + `new_source` — operates on Jupyter `.ipynb` cells, not file content), so it cannot be added to the canonical allow-set via simple matcher broadening. iter-102 deliberately EXCLUDES NotebookEdit from the canonical allow-set with explicit rationale in the contract lib comment block. Iter-103+ candidate: dedicated NotebookEdit-coverage audit + per-applicable-classifier NotebookEdit payload-shape adaptation (file-size-guard might apply to notebook cell sizes; the file-path-only classifiers like vale-claude-md-guard, pyi-stub-guard, native-binary-guard, version-guard would not apply because notebooks aren't CLAUDE.md / `__init__.py` / launchd plists / version-pinned files).

**Iter-102 architectural takeaway — the "preventive gate" pattern enters its FOURTH succession**:

1. **iter-98 → iter-99**: single silent-context-drop fix → marketplace silent-context-drop audit
2. **iter-100 → iter-101**: single MultiEdit-orchestrator-matcher fix → marketplace matcher-hygiene audit
3. **iter-101 → iter-102**: single PostToolUse canonical-helper hoist (iter-100) → PreToolUse canonical-helper hoist (iter-102; this iter)
4. **iter-102 → iter-103**: per-classifier MultiEdit content extraction + NotebookEdit coverage audit (next iter)

Each successive iter applies the SAME "fix once, then scale the fix to invariant via preventive infrastructure" pattern. The web-research-driven discovery category (iter-100 establishment) is now self-sustaining across 3 iterations.

**Iter-102 regression test** (8 assertions all pass): canonical allowlist + helper exist in PreToolUse contract lib, allowlist contains Write + Edit + MultiEdit, all 8 inlined classifiers import + consume the canonical helper, legacy hardcoded `tool_name !==` guards removed from all 8, iter-102 staged-migration MultiEdit short-circuit present in all 8, orchestrator backward-compat preserved (clean Write payload still allows), MultiEdit payload routes through orchestrator + 8 classifiers self-skip (no false-positive deny), contract lib documents iter-100 precedent + iter-103 follow-up scope + NotebookEdit non-acceptance.

Sources for iter-102 web research:

- [Claude Code Tools Reference (2026)](https://code.claude.com/docs/en/tools-reference)
- [Claude Code Hooks Complete Guide March 2026 Edition](https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/)
- [Claude Code Hooks: The Complete 2026 Production Reference (32+ Events, 5 Handler Types)](https://thepromptshelf.dev/blog/claude-code-hooks-complete-reference-2026/)
- [Claude Code Hooks: Complete Guide to All 12 Lifecycle Events](https://claudefa.st/blog/tools/hooks/hooks-guide)

### Iter-103: NotebookEdit applicability audit + per-classifier matrix — preventive infrastructure for the 4-tool canonical quadruple

Iter-102 surfaced the canonical 2026 file-edit tool quadruple `Edit|MultiEdit|Write|NotebookEdit`. Iter-103 scales that discovery to the per-classifier level via a marketplace-wide **NotebookEdit applicability audit** that produces a curated SSoT matrix.

**Key dichotomy — file-path-suffix vs content-pattern classifiers**:

| Category                  | Example classifiers                                                                                                                                                             | NotebookEdit applicability                                                                                                                                     |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| File-path-suffix          | vale-claude-md, hoisted-deps (pyproject.toml), mise-hygiene, pyi-stub (`__init__.py`), native-binary (plists), glossary-sync (GLOSSARY.md), terminology-sync, readme-pypi-links | **NOT-APPLICABLE** — notebooks (.ipynb) never match these suffixes                                                                                             |
| Content-pattern           | version-guard (hardcoded version regex), gpu-optimization-guard (PyTorch patterns), ssot-principles (ast-grep DI), memory-efficiency-reminder                                   | **APPLICABLE** — patterns occur identically in notebook cell source as in `.py`/`.ts` files                                                                    |
| Content-pattern (partial) | file-size-guard (per-cell vs per-file semantic mismatch), inline-ignore-guard, fake-data-guard, iter78-L3-stripped-path                                                         | **POTENTIALLY-APPLICABLE** — semantic decisions per-hook                                                                                                       |
| Language-tool-specific    | ty (`.py`/`.pyi`), tsgo (`.ts`/`.tsx`), oxlint, biome                                                                                                                           | **NOT-APPLICABLE-VIA-NOTEBOOKEDIT** — underlying tool requires `.py`/`.ts` file extension; notebook code path is `nbqa` / Jupyter MCP server, not NotebookEdit |

**Audit results on first run**: 4 APPLICABLE + 4 POTENTIALLY-APPLICABLE + 15 NOT-APPLICABLE classifiers across the marketplace. Current marketplace coverage: **0** matchers honor NotebookEdit (baseline state — iter-104+ starts gradual broadening for the 4 APPLICABLE cohort).

**Community-validated 2026 cautions** (informational deferral signal — iter-103 audit cites all three):

1. **NotebookEdit insert-positioning bug** ([anthropics/claude-code#18538](https://github.com/anthropics/claude-code/issues/18538)) — cells inserted at position 0 instead of after `cell_id`
2. **Git-diff noise + format-revert war with JupyterLab** ([ReviewNB blog](https://www.reviewnb.com/claude-code-with-jupyter-notebooks)) — NotebookEdit writes cell source as single JSON string; every edit shows as a whole-cell rewrite that reverts the moment JupyterLab saves
3. **Community recommendation**: use the **Jupyter MCP server** (kernel-aware, executes cells, reads outputs) instead of NotebookEdit for serious notebook workflows

Per these cautions, iter-103 is **deliberately INFORMATIONAL** (never blocks release). Iter-104+ per-hook broadening decisions evaluate three factors:

1. Is per-cell enforcement semantically meaningful vs per-file? (e.g., file-size-guard threshold applies to FILE size, not cell size — likely punted)
2. Is upstream NotebookEdit stability sufficient? (insert-bug, diff noise still open as of 2026-05)
3. Is the canonical Jupyter MCP server path preferable? (community-recommended workaround for production notebook workflows)

**Audit wired into preflight as Check 4p** (informational, parallel to Check 4n iter-99 silent-context-drop + Check 4o iter-101 matcher-hygiene). Future iters MAY add `--strict` mode once iter-104+ per-classifier adaptation lands.

**Iter-103 regression test** (9 assertions all pass): audit-task existence + executability, audit always exits 0 (informational), per-classifier matrix produces expected counts (4 APPLICABLE: version-guard + gpu-optimization-guard + ssot-principles + memory-efficiency-reminder; ≥12 NOT-APPLICABLE file-path-suffix hooks correctly excluded), all 4 APPLICABLE classifiers appear in detailed-rationale section, all 3 community-validated cautions cited (insert-bug + git-diff noise + Jupyter MCP recommendation), iter-104+ deferred-scope rationale present (payload-shape adaptation + iter-104 follow-up scope), live marketplace baseline state verified (0 matchers honor NotebookEdit), discrimination categories present (file-path-suffix vs content-pattern dichotomy).

**Iter-103 architectural takeaway — "preventive gate" pattern in 5th succession + introduces the INFORMATIONAL-ONLY variant**:

1. iter-98 → iter-99: silent-context-drop fix → marketplace silent-context-drop audit (blocking via exit code)
2. iter-100 → iter-101: MultiEdit-orchestrator-matcher fix → marketplace matcher-hygiene audit (blocking via exit code)
3. iter-101 → iter-102: PostToolUse canonical-helper hoist → PreToolUse canonical-helper hoist
4. iter-102 → iter-103: NotebookEdit web-research discovery → marketplace applicability audit (**INFORMATIONAL ONLY** — never blocks; per-classifier matrix as SSoT)
5. iter-103 → iter-104: per-classifier NotebookEdit payload-shape adaptation for the 4 APPLICABLE cohort (next iter, conditional on upstream stability)

The iter-103 informational-only variant is a NEW preventive-gate sub-pattern. When the underlying surfaced concern requires per-hook nuanced decisions (not a universal invariant), the audit's role shifts from "block recurrence" to "surface the matrix + document the decision pattern." This is appropriate when:

- Per-hook applicability is heterogeneous (file-path-suffix vs content-pattern classifiers)
- Upstream stability concerns make universal broadening premature
- Multiple valid adaptation paths exist (e.g., NotebookEdit direct adaptation vs Jupyter MCP server alternative)

Sources for iter-103 web research:

- [Claude Code Tools Reference (2026) — NotebookEdit payload spec](https://code.claude.com/docs/en/tools-reference)
- [Claude Code + Jupyter Notebooks Finally Work Well (ReviewNB)](https://www.reviewnb.com/claude-code-with-jupyter-notebooks)
- [anthropics/claude-code Issue #18538 — NotebookEdit insert-positioning bug](https://github.com/anthropics/claude-code/issues/18538)
- [anthropics/claude-code Issue #46013 — cell_id in IDE selection context](https://github.com/anthropics/claude-code/issues/46013)
- [Claude Code System Prompts — NotebookEdit tool description (Piebald-AI)](https://github.com/Piebald-AI/claude-code-system-prompts/blob/main/system-prompts/tool-description-notebookedit.md)

### Iter-104: hook-output-size-cap canonical truncation helper — defends against Claude's 10,000-character file-spillover threshold

Adversarial web research surfaced a previously-undiscovered silent-context-degradation hazard documented in the official 2026 Anthropic Claude Code hook docs:

> "Hook output strings, including additionalContext, systemMessage, and plain stdout, are capped at 10,000 characters. Output that exceeds this limit is saved to a file and replaced with a preview and file path, the same way large tool results are handled."

— [Claude Code Hooks Reference (2026)](https://code.claude.com/docs/en/hooks)

**The silent-degradation mechanism**: when a hook emits output >10K chars, Claude only sees the preview stub, NOT the full content. The file containing the full diagnostic is written to the operator's machine — Claude's sandbox cannot follow the file path. The classifier may believe it gave Claude actionable context, but Claude actually receives a truncated stub with an unfollowable file path. Net effect: the subhook's diagnostic intelligence is **silently lost**, the same failure mode as iter-66/98's silent context-drop but via a different mechanism (size cap instead of schema mismatch).

**Worst-offender classifiers** (highest output-volume risk):

| Classifier                                   | Output-growth dimension            | Realistic worst-case                          |
| -------------------------------------------- | ---------------------------------- | --------------------------------------------- |
| `posttooluse-vale-claude-md.ts` (iter-104 ★) | N vale findings per CLAUDE.md edit | 50-200+ findings; ~5-20K chars                |
| `posttooluse-ty-type-check.ts`               | N ty diagnostics per `.py` edit    | Variable; can exceed 10K on multi-error edits |
| `posttooluse-tsgo-type-check.ts`             | N tsgo errors per `.ts` edit       | Same                                          |
| `posttooluse-oxlint-check.ts`                | N oxlint findings per JS/TS edit   | Same                                          |
| `posttooluse-biome-lint.ts`                  | N biome findings per JS/TS edit    | Same                                          |
| `posttooluse-ssot-principles.ts`             | N ast-grep anti-pattern findings   | Bounded by ast-grep result count              |
| `pretooluse-vale-claude-md-guard.ts`         | Vale findings on proposed content  | Same dimension as PostToolUse vale            |

Iter-104 establishes the canonical truncation helper in the PostToolUse contract lib + applies it to the highest-risk classifier (`posttooluse-vale-claude-md.ts`, observed empirically to produce 50-200+ findings on a single CLAUDE.md edit). Iter-105+ scope = marketplace audit + apply to remaining 6 unbounded-output classifiers. Mirrors the iter-100 single-hook-fix-then-marketplace-scale pattern.

**Canonical helper API** (hoisted into [`lib/posttooluse-subhook-contract-...-iter93.ts`](../plugins/itp-hooks/hooks/lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts)):

```typescript
export const MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER = 9000;

export function truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(
  rawOutput: string,
): string {
  if (rawOutput.length <= MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER) {
    return rawOutput;  // fast-path: small reasons returned verbatim
  }
  // Over-threshold: truncate + append Claude-actionable marker
  return rawOutput.slice(0, budget) + HOOK_OUTPUT_TRUNCATION_MARKER_SUFFIX_...;
}
```

**Design rationale**:

1. **9000-char threshold** = 1000-char safety margin below Anthropic-documented 10000 spillover cap (room for the marker suffix without overflow into spillover)
2. **Fast-path return-verbatim** for ≤9000 chars preserves zero overhead in the dominant case (most reasons are 100-500 chars)
3. **Truncation marker is Claude-actionable**: explicitly cites the 10K threshold (so Claude knows WHY content was truncated), points to operator transcript via Ctrl-R (so Claude knows WHERE the full content exists), and prefixes a `Claude:` instruction (so Claude knows what to DO — act on visible findings, assume more may exist of the same kind)

**Iter-104 regression test** (8 assertions all pass): canonical constant + helper exist in contract lib, threshold = 9000 with 1000-char safety margin documented, marker suffix is Claude-actionable (cites 10K threshold + Ctrl-R + Claude:-prefixed instruction), vale-claude-md.ts first-adopter imports + applies helper, fast-path return-verbatim semantics preserved (small reasons unchanged + NO marker appended), over-threshold input truncated to ≤9000 chars + Claude-actionable marker appended (no silent file-spillover), vale-claude-md.ts emission site wraps unbounded reason in helper BEFORE passing to `buildPostToolUseAdditionalContextDecision`, contract lib documents Anthropic-docs citation + iter-105 follow-up + worst-offender list.

**Iter-104 architectural takeaway — adds a 5th silent-context-degradation defense layer**:

1. iter-66/93: PostToolUse stdout must be JSON (not raw text) — schema-level defense
2. iter-95: conditional `[orchestrator-subhook: <name>]` provenance prefix only when ≥2 sections contribute — UX-level defense
3. iter-96: timeout-aware additional_context surface — operator-visibility defense
4. iter-98/99: console.log raw-text emission audit — silent-drop preventive gate
5. **iter-104 (this iter)**: 10K-character file-spillover threshold defense — silent-size-truncation preventive layer

Each layer addresses a DIFFERENT failure mode at a different defense depth. The cumulative effect: every hook emission path now has guards against the 5 known silent-context-degradation mechanisms.

**Iter-105 follow-up scope**: marketplace audit + apply truncation helper to the remaining 6 unbounded-output classifiers (ty, tsgo, oxlint, biome, ssot-principles, pretooluse-vale). The PostToolUse orchestrator's aggregated reason — which concatenates ALL contributing subhook messages — is itself at higher risk than any single classifier and should also adopt the helper at the aggregation site (multiple medium-size messages can sum past 10K).

### Iter-105: Marketplace-wide truncation-helper invariant (scales iter-104 single-hook fix to 8 cohort hooks + aggregation-site sum-overflow defense)

Iter-104 established the canonical truncation helper `truncateHookOutputToStayBelowClaudeFileSpilloverThreshold` and applied it to the highest-risk single classifier (posttooluse-vale-claude-md.ts). Iter-105 scales the protection marketplace-wide and adds a new defense layer at the aggregation site.

**Iter-105 cohort (8 hooks, all wrapped via canonical helper)**:

| Cohort hook                                                  | Unbounded source                                         | Iter     |
| ------------------------------------------------------------ | -------------------------------------------------------- | -------- |
| `posttooluse-vale-claude-md.ts`                              | N vale findings on CLAUDE.md edit (50-200+, ~5-20K)      | iter-104 |
| `posttooluse-ty-type-check.ts`                               | ty diagnostic stream per .py/.pyi edit                   | iter-105 |
| `posttooluse-tsgo-type-check.ts`                             | tsgo diagnostic stream per project check                 | iter-105 |
| `posttooluse-oxlint-check.ts`                                | oxlint correctness+suspicious findings                   | iter-105 |
| `posttooluse-biome-lint.ts`                                  | biome complementary-rules findings                       | iter-105 |
| `posttooluse-ssot-principles.ts`                             | ast-grep anti-pattern matches (multi-language fan-out)   | iter-105 |
| `pretooluse-vale-claude-md-guard.ts` (cross-lib import)      | vale findings on proposed CLAUDE.md content              | iter-105 |
| `posttooluse-orchestrator (...iter93...)` (aggregation site) | concatenation of ALL subhook reasons + provenance prefix | iter-105 |

**New defense layer — aggregation-site sum-overflow defense**: even when each subhook stays under 10K individually (via iter-104+iter-105 per-classifier wrap), the PostToolUse orchestrator concatenates N contributions + per-section `[orchestrator-subhook: <name>]` provenance prefix into ONE consolidated `{decision: "block", reason: aggregate}` JSON. The sum can exceed 10K. The orchestrator now applies the canonical helper to the aggregated reason as the absolute last line of defense before emitting the decision JSON.

**Cross-lib import pattern**: `pretooluse-vale-claude-md-guard.ts` imports the helper from the PostToolUse contract lib (`./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts`). The helper is pure string truncation, semantically shared across PreToolUse + PostToolUse paths per iter-104 design rationale. **Iter-106+ candidate**: extract to a dedicated shared-lib file once more cross-Pre/PostToolUse helpers emerge. Currently pragmatic single-source-of-truth approach.

**Preventive infrastructure**:

- **Audit task**: `.mise/tasks/audit-pretooluse-and-posttooluse-hook-classifiers-for-unbounded-reason-emission-not-wrapped-in-canonical-truncation-helper-against-claude-file-spillover-threshold-iter105-marketplace-scale-of-iter104-single-hook-fix.sh` — curated 8-hook cohort + per-hook static-grep for canonical-helper import + usage.
- **Preflight gate**: Check 4q (informational, parallel to Check 4n/4o/4p — iter-99 silent-context-drop, iter-101 matcher-hygiene, iter-103 NotebookEdit applicability matrix).
- **Regression test**: `.mise/tasks/tests/test-iter105-marketplace-wide-truncation-helper-invariant-audit-scales-iter104-single-hook-fix-to-eight-cohort-hooks-including-postooluse-orchestrator-aggregation-site-for-sum-overflow-defense.sh` — 8 assertions including cross-lib import works + orchestrator aggregation site wraps + iter-104 helper threshold (`MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER = 9000`) unchanged + cohort count = 8.

**Defense-in-depth synthesis (iter-105 expands to 6-layer marketplace stack)**:

1. iter-66/93: stdout JSON schema correctness — additionalContext-silently-dropped audit
2. iter-94: Bun.spawn async invariant — no spawnSync in orchestrator subhooks
3. iter-96: timeout-aware additional_context surface — operator-visibility defense
4. iter-98/99: console.log raw-text emission audit — silent-drop preventive gate
5. iter-104: 10K-character file-spillover threshold defense (single-hook fix) — silent-size-truncation preventive layer
6. **iter-105 (this iter)**: marketplace-wide invariant for unbounded-emission hook classifiers + aggregation-site sum-overflow defense

**Iter-106+ candidates**:

1. Extract `truncateHookOutputToStayBelowClaudeFileSpilloverThreshold` to a dedicated shared-lib file (eliminate iter-105 cross-lib import pattern) — **delivered in iter-106 below**
2. Add new unbounded-source PostToolUse classifiers to the cohort enumeration as they land
3. Promote audit gate from informational (Check 4q) to strict (block release) once iter-106 helper-extraction is done

### Iter-106: Truncation-helper canonical home relocated to dedicated cross-Pre/PostToolUse shared lib (eliminates iter-105 cross-lib import awkwardness)

Iter-105 documented a deferred follow-up: extract the truncation helper from the PostToolUse contract lib to a dedicated cross-Pre/PostToolUse shared lib once additional cross-Pre/PostToolUse helpers emerged. Iter-106 delivers that extraction even before more helpers materialize — the iter-105 cross-lib import (PreToolUse vale-claude-md-guard importing from the PostToolUse contract lib) was the single most awkward shape in the iter-104/iter-105 helper chain, and eliminating it now establishes the shared-lib pattern for future cross-Pre/PostToolUse helpers.

**File layout transition**:

| File                                                                                                               | Iter-104 / iter-105 role                        | Iter-106 role                                                            |
| ------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------- | ------------------------------------------------------------------------ |
| `lib/posttooluse-subhook-contract-...-iter93.ts`                                                                   | Canonical home for the helper (literal exports) | Transitive re-exports only (backward-compat bridge for iter-104-era API) |
| `lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts` | (did not exist)                                 | **NEW canonical home — holds the 3 literal exports + design rationale**  |

**Iter-106 invariants enforced by audit task**:

1. The shared-lib file exists at the documented path
2. The shared lib holds the literal `export const MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER`, `export const HOOK_OUTPUT_TRUNCATION_MARKER_SUFFIX_...`, and `export function truncateHookOutputToStayBelowClaudeFileSpilloverThreshold` definitions
3. The PostToolUse contract lib has been reduced to `export { ... } from "./shared-truncation-helper-..."` re-exports (NOT duplicate `export const` definitions) — verifies no source-of-truth duplication
4. All 8 iter-105 cohort hooks import the helper from the iter-106 shared-lib canonical home (NOT from the PostToolUse contract lib's re-export bridge, even though that bridge remains available for external consumers)
5. The threshold value remains `9000` (unchanged from iter-104 baseline — verified at the iter-106 canonical home)
6. The iter-105 marketplace-wide invariant audit continues to pass (no regression on the helper-consumption invariant during the relocation)

**Cross-lib import pattern ELIMINATED**: `pretooluse-vale-claude-md-guard.ts` now imports the helper directly from `./lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts` instead of `./lib/posttooluse-subhook-contract-...iter93.ts`. The cross-lib import that iter-105 documented as "currently pragmatic; refactor when more cross-Pre/PostToolUse helpers emerge" is gone.

**Backward-compatibility contract**: the PostToolUse contract lib re-exports all 3 helper symbols via `export { MAX_..., HOOK_OUTPUT_..., truncate... } from "./shared-truncation-helper-..."`. Any external consumer (audit tasks, regression tests, documentation, vendored downstream code) that referenced the iter-104 import-source continues to resolve correctly through the transitive re-export. **Iter-104 API surface stability preserved**.

**Preventive infrastructure**:

- **Audit task**: `.mise/tasks/audit-truncation-helper-canonical-home-relocated-from-posttooluse-contract-lib-to-dedicated-cross-pretooluse-and-posttooluse-shared-lib-iter106-eliminates-iter105-cross-lib-import-awkwardness.sh` — verifies the 3 iter-106 invariants (file exists + literal exports + cohort hooks import from canonical home)
- **Preflight gate**: Check 4r (informational, parallel to Check 4n/4o/4p/4q)
- **Regression test**: `.mise/tasks/tests/test-iter106-truncation-helper-canonical-home-relocated-from-posttooluse-contract-lib-to-dedicated-shared-lib-with-eight-cohort-hooks-importing-directly-and-backward-compat-re-exports-preserved.sh` — 7 assertions
- **Updated iter-104 + iter-105 tests**: file-location assumptions in the iter-104 + iter-105 tests rewritten to read from the iter-106 canonical home (where the literal definitions now live)

**Defense-in-depth synthesis (iter-106 adds the canonical-home invariant on top of iter-105's marketplace cohort invariant)**:

1. iter-66/93: stdout JSON schema correctness — additionalContext-silently-dropped audit
2. iter-94: Bun.spawn async invariant — no spawnSync in orchestrator subhooks
3. iter-96: timeout-aware additional_context surface — operator-visibility defense
4. iter-98/99: console.log raw-text emission audit — silent-drop preventive gate
5. iter-104: 10K-character file-spillover threshold defense (single-hook fix)
6. iter-105: marketplace-wide invariant for unbounded-emission hook classifiers + aggregation-site sum-overflow defense
7. **iter-106 (this iter)**: canonical-home invariant — the truncation helper lives in a dedicated cross-Pre/PostToolUse shared lib; cross-lib import awkwardness eliminated; backward-compat re-exports preserved

**Iter-107+ candidates**:

1. Extract the iter-95 async-spawn helper (`executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail`) to the cross-Pre/PostToolUse shared-lib home if PreToolUse classifiers adopt async subprocess execution (currently the helper lives in `lib/posttooluse-subhook-async-subprocess-execution-...-iter95.ts`, which would create the same cross-lib pattern iter-106 just eliminated)
2. Add a shared escape-hatch-marker detection helper (`// MARKER-NAME-OK: <reason>`) that all per-classifier opt-out comments converge on — each hook currently rolls its own variant; a shared helper would standardize the marker grammar + same-line vs. preceding-3-lines window semantics
3. Promote the iter-105 + iter-106 audits from informational (Check 4q + 4r) to strict-block once a marketplace-wide refactor pass establishes the invariants as universally true (current iter-105 + iter-106 cohort = 8 hooks; the strict promotion should wait until cohort scope is documented to be EXHAUSTIVE rather than just CURRENT)

Sources for iter-104 web research:

- [Claude Code Hooks Reference (2026) — output size cap documented](https://code.claude.com/docs/en/hooks)
- [Claude Code Hooks: The Complete 2026 Production Reference — 32+ events, 5 handler types, exit code semantics](https://thepromptshelf.dev/blog/claude-code-hooks-complete-reference-2026/)
- [Claude Code Best Practices: Official and Community-Tested Guide 2026 — deny reason actionability patterns](https://thepromptshelf.dev/blog/claude-code-best-practices-2026/)
- [Hooks in Claude Code (Gaurav Negi, Medium) — self-correcting feedback loop architecture](https://medium.com/@negi.gaurav2/hooks-in-claude-code-718cb145214a)
- [Claude Code Hook Control Flow (Steve Kinney) — exit code vs JSON signaling tradeoffs](https://stevekinney.com/courses/ai-development/claude-code-hook-control-flow)
- [Bun 1.3 Cold Start Benchmarks — 8-15ms vs Node.js 200ms (PkgPulse Blog)](https://www.pkgpulse.com/blog/bun-vs-nodejs-npm-runtime-speed-2026)
- [Claude Code Hooks Mastery (disler) — community-validated hook patterns](https://github.com/disler/claude-code-hooks-mastery)

### Iter-107: Shared escape-hatch-marker detection helper + iter-78 migration as proof of integration

Iter-106 documented a follow-up iter-107 candidate: a shared escape-hatch-marker detection helper that all per-classifier opt-out comments converge on. Iter-107 delivers that helper as the SECOND cross-Pre/PostToolUse shared lib (after iter-106's truncation helper), with the iter-78 layer3-stripped-path-guard migrated as proof-of-integration.

**Pre-iter-107 marketplace state**: every hook with an escape-hatch comment rolled its own detection logic — a regex literal (varying grammar) plus (for window-scoped variants) a hand-coded preceding-window lookup loop. Iter-107 web research ([Anthropic Claude Code hook docs 2026](https://code.claude.com/docs/en/hooks), Anthropic GitHub issue #20259, community-validated patterns) confirmed there is NO official Claude Code escape-hatch convention. The marketplace inherited the drift:

| Marker                               | Hook                                                                     | Window semantics                     | Reason policy          |
| ------------------------------------ | ------------------------------------------------------------------------ | ------------------------------------ | ---------------------- |
| `# BASH-LAUNCHD-OK`                  | `pretooluse-native-binary-guard.ts`                                      | FILE_WIDE (`<!-- -->` also)          | none                   |
| `# SSoT-OK`                          | `pretooluse-version-guard.ts`                                            | FILE_WIDE                            | none                   |
| `# INLINE-IGNORE-OK`                 | `pretooluse-inline-ignore-guard.ts`                                      | SAME_LINE_ONLY                       | none                   |
| `# CWD-DELETE-OK`                    | `pretooluse-cwd-deletion-guard.ts`                                       | FILE_WIDE                            | none                   |
| `# PROCESS-STORM-OK`                 | `pretooluse-process-storm-guard.mjs`                                     | FILE_WIDE                            | none                   |
| `# FILE-SIZE-OK`                     | `pretooluse-file-size-guard.ts`                                          | FILE_WIDE                            | none                   |
| `# LAYER3-STRIPPED-PATH-OK: …`       | `pretooluse-iter78-layer3-stripped-path-edit-time-guard.ts` (iter-107 ★) | SAME_LINE_OR_PRECEDING_N_LINES (N=3) | ≥10 chars after `:`    |
| `// CARGO-TTY-SKIP` / `-WRAP`        | `pretooluse-cargo-tty-guard.ts`                                          | FILE_WIDE                            | none                   |
| `// STOP-HOOK-ADDITIONAL-CONTEXT-OK` | `stop-orchestrator.ts`                                                   | SAME_LINE_ONLY                       | ≥10 chars (informally) |

**Iter-107 canonical helper** at `plugins/itp-hooks/hooks/lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts`:

- `EscapeHatchMarkerWindowSemanticsMode`: enum with the 3 documented modes (`SAME_LINE_ONLY` | `SAME_LINE_OR_PRECEDING_N_LINES` | `FILE_WIDE`)
- `EscapeHatchMarkerDetectionConfiguration`: per-call config (marker token + window mode + optional preceding-N-lines count + optional reason-policy gate in characters)
- `detectEscapeHatchMarkerCoveringTargetSourceLine(allSourceLines, targetLineZeroBasedIndex, configuration)`: per-line scoping
- `hasFileWideEscapeHatchMarkerInContent(contentBlob, configuration)`: convenience wrapper for the file-wide case (saves a `content.split("\n")` when caller doesn't already have lines)

**Comment-style-agnostic** via UPPER-KEBAB-CASE convention: marker names like `BASH-LAUNCHD-OK`, `LAYER3-STRIPPED-PATH-OK`, `INLINE-IGNORE-OK` never collide with code identifiers, so substring-matching is safe across `#`, `//`, `<!-- -->`, and any other comment shape.

**Iter-78 migration as proof-of-integration**: the iter-78 layer3-stripped-path-guard's hand-rolled regex literal + 3-line preceding-window lookup loop replaced by a single helper call configured from a per-hook configuration object. Behavior-preserving: iter-78 regression test still passes 7/7. The migration commit demonstrates the canonical migration pattern for future hooks.

**Preventive infrastructure**:

- **Audit task**: `.mise/tasks/audit-marketplace-wide-escape-hatch-marker-detection-inventory-with-recommendation-to-migrate-hand-rolled-patterns-to-iter107-canonical-shared-helper.sh` — enumerates hand-rolled marker detection patterns + reports migrated vs. hand-rolled counts
- **Preflight gate**: Check 4s (informational, parallel to Check 4n/4o/4p/4q/4r)
- **Regression test**: 8 assertions including 4 programmatic API probes (`SAME_LINE_ONLY` mode, `SAME_LINE_OR_PRECEDING_N_LINES` with N-line window boundary, `FILE_WIDE` + convenience wrapper, ≥10-char reason policy gate)
- **Marketplace regression suite**: 44/44 PASS (was 43/43 before iter-107 test added)

**Iter-108+ migration roadmap** (one hook per iter, behavior-preserving):

1. `pretooluse-file-size-guard.ts` (FILE_WIDE, `# FILE-SIZE-OK`) — pending
2. `pretooluse-version-guard.ts` (FILE_WIDE, `# SSoT-OK`) — **MIGRATED iter-108 ✓**
3. `pretooluse-native-binary-guard.ts` (FILE_WIDE, `# BASH-LAUNCHD-OK` / `<!-- BASH-LAUNCHD-OK -->`) — pending (requires `caseSensitivityMode: "CASE_INSENSITIVE"` since the pre-existing regex used `/i`)
4. `pretooluse-process-storm-guard.mjs` (FILE_WIDE, `# PROCESS-STORM-OK`) — pending (requires `caseSensitivityMode: "CASE_INSENSITIVE"`)
5. `pretooluse-cwd-deletion-guard.ts` (FILE_WIDE, `# CWD-DELETE-OK`) — pending (requires `caseSensitivityMode: "CASE_INSENSITIVE"`)
6. `pretooluse-inline-ignore-guard.ts` (SAME_LINE_ONLY, `// INLINE-IGNORE-OK`) — **MIGRATED iter-108 ✓**
7. `pretooluse-cargo-tty-guard.ts` (FILE_WIDE, `// CARGO-TTY-SKIP` / `-WRAP`) — pending (two markers per hook; requires `caseSensitivityMode: "CASE_INSENSITIVE"`)

Once all migrations land, promote the iter-107 inventory audit from informational (Check 4s) to strict-block.

### Iter-108: Helper case-sensitivity extension + 2 migrations (version-guard FILE_WIDE + inline-ignore-guard SAME_LINE_ONLY)

Iter-108 extends the iter-107 canonical helper with a new `caseSensitivityMode` configuration option AND migrates the first 2 hooks from the iter-107 roadmap. The case-sensitivity extension was forced by an iter-108 adversarial audit finding: 4 of the 7 roadmap hooks (`native-binary-guard`, `process-storm-guard`, `cwd-deletion-guard`, `cargo-tty-guard`) historically used `/i` (case-insensitive matching) in their hand-rolled regexes. The iter-107 helper baseline was strict UPPER-KEBAB-CASE — sufficient for iter-78's `LAYER3-STRIPPED-PATH-OK` but a silent BEHAVIOR-CHANGE risk for any case-insensitive migration.

**Iter-108 helper extension**:

| New config field      | Values                                 | Default          | Migration use case                                                  |
| --------------------- | -------------------------------------- | ---------------- | ------------------------------------------------------------------- |
| `caseSensitivityMode` | `CASE_SENSITIVE` \| `CASE_INSENSITIVE` | `CASE_SENSITIVE` | Set to `CASE_INSENSITIVE` ONLY when migrating a hook that used `/i` |

The default aligns with the marketplace UPPER-KEBAB-CASE convention going forward. New hooks should leave the field unset (defaults to strict). Existing hooks being migrated set the field explicitly to preserve pre-iter-108 behavior.

**Iter-108 migrations**:

| Hook                                | Window mode      | Marker token       | Case mode        | Notes                                                                                            |
| ----------------------------------- | ---------------- | ------------------ | ---------------- | ------------------------------------------------------------------------------------------------ |
| `pretooluse-version-guard.ts`       | `FILE_WIDE`      | `SSoT-OK`          | `CASE_SENSITIVE` | Mixed-case marker (Single-Source-of-Truth abbreviated). Pre-iter-108 `/#\s*SSoT-OK/` was strict. |
| `pretooluse-inline-ignore-guard.ts` | `SAME_LINE_ONLY` | `INLINE-IGNORE-OK` | `CASE_SENSITIVE` | Pre-iter-108 `/INLINE-IGNORE-OK/` was strict. Per-line scoping is by design.                     |

Both migrations are behavior-preserving — the iter-107 + iter-78 regression tests still pass + the full marketplace suite is 44/44.

**Iter-108 regression test enhancement**: added a new Case 9 probe to the iter-107 regression test that exercises `caseSensitivityMode`: lowercase marker `# foo-ok` with `CASE_SENSITIVE` does NOT match configured token `FOO-OK`; same lowercase with `CASE_INSENSITIVE` DOES match; uppercase always matches under both modes. Marketplace regression suite: 44/44 PASS (iter-107 test extended to 9 assertions, no new files added).

**Iter-110 (arc-complete) update**: file-size-guard migrated, audit promoted to STRICT-BLOCK, marketplace fully consolidated. See iter-110 section below.

**Iter-109+ migration roadmap** (the remaining 5 hooks):

The 4 hooks that historically used `/i` will set `caseSensitivityMode: "CASE_INSENSITIVE"` to be behavior-preserving — operators who relied on the lenient matching continue to see their lowercase markers honored. Once all 5 remaining migrations land, the iter-107 inventory audit promotes from informational (Check 4s) to strict-block.

### Iter-114: Second parallel canonical registry for AUDIT-TASK escape-hatch markers + iter-113 doc generator extended to render both lifecycle layers

Iter-114 closes the marker-coverage gap left by iter-111 (which covered only RUNTIME-HOOK markers). The marketplace now has two parallel canonical registries, mirroring two distinct lifecycle layers:

| Layer        | Consumer              | When                       | Registry                | Entries (iter-114 baseline) |
| ------------ | --------------------- | -------------------------- | ----------------------- | --------------------------- |
| RUNTIME-HOOK | Pre/PostToolUse hooks | Every Write/Edit/Bash      | iter-111 registry       | 12                          |
| AUDIT-TASK   | `.mise/` audit tasks  | Once per release-preflight | iter-114 registry (NEW) | 8                           |

**Why two registries instead of one polymorphic registry**

Each registry's TypeScript shape encodes consumer-type-specific fields without polymorphism:

- iter-111 entries declare `consumerHookSourceFileRelativePath` + `windowSemanticsModeDeclaredAtConsumerCallSite` (runtime hooks consume markers via the iter-107 helper, which has window-semantics)
- iter-114 entries declare `consumerAuditTaskSourceFileRelativePath` (audit tasks consume markers via bash grep, which has no window-semantics — they grep the whole file)

A single polymorphic registry would either lose type safety (`consumerSourceFileRelativePath` could refer to either kind) or require a discriminated union with a `markerCategory` field that complicates every iteration. The two-registry split is simpler.

**Iter-114 baseline: 8 audit-task markers**

| Marker                            | Consumer audit                         | Suppresses                                               |
| --------------------------------- | -------------------------------------- | -------------------------------------------------------- |
| `ESCAPE-HATCH-AUDIT-OK`           | iter-110 escape-hatch invariant        | Cohort requirement for a specific hook                   |
| `HOOK-OUTPUT-SIZE-CAP-OK`         | iter-105 unbounded-emission truncation | Truncation-helper wrap for a classifier                  |
| `MATCHER-NO-MULTIEDIT-OK`         | iter-101 matcher-hygiene               | MultiEdit inclusion requirement on Write\|Edit matchers  |
| `ORDERING-OK`                     | iter-61 pueue-wrap last-entry          | pueue-wrap-guard must-be-last invariant                  |
| `POSTTOOLUSE-RAW-STDOUT-OK`       | iter-99 raw-stdout-emission            | Raw stdout in PostToolUse TypeScript hooks               |
| `SPAWN-SYNC-OK`                   | iter-94 no-Bun.spawnSync               | spawnSync in PostToolUse orchestrator subhooks           |
| `STOP-HOOK-ADDITIONAL-CONTEXT-OK` | iter-67/68/69 Stop-hook pentad         | additionalContext-emission in lifecycle-tail event hooks |
| `WILDCARD-MATCHER-OK`             | iter-65 wildcard-matcher               | `*` or null matcher in Pre/PostToolUse hook entries      |

Audit markers all require ≥10-character reason after the colon (release-blocking invariants demand justification).

**Iter-113 doc generator extended**

The iter-113 generator now imports BOTH registries and renders TWO distinct catalogs in `docs/marketplace-escape-hatch-marker-reference.md`:

1. `## Runtime-hook marker catalog (12 registered markers consumed by iter-107 shared helper)`
2. `## Audit-task marker catalog (8 registered markers consumed by .mise/ release-preflight audit tasks)`

Operators get a single discoverable artifact (20 marker sections in alphabetical order within each catalog) covering both lifecycle layers. The doc-drift detection (preflight Check 4u) continues to work — it validates that the on-disk doc matches the registry-derived output regardless of which registry produced each section.

**Iter-114 regression test (6 cases)**

| Case | Verifies                                                                                             |
| ---- | ---------------------------------------------------------------------------------------------------- |
| 1    | iter-114 audit-task registry has all 4 documented exports                                            |
| 2    | Registry contains all 8 iter-114 baseline audit markers                                              |
| 3    | Every `consumerAuditTaskSourceFileRelativePath` references an existing `.mise/tasks/audit-*.sh` file |
| 4    | iter-113 doc generator renders all 8 audit-task marker sections in dedicated audit-task catalog      |
| 5    | Lookup-by-name helper resolves known marker with full field set; returns undefined for unknown       |
| 6    | iter-113 generator idempotency invariant still holds with two-registry input (no drift on `--check`) |

**Behavior-preserving end-to-end**

- iter-114 regression: 6/6 PASS
- iter-113 regression: 7/7 PASS (test updated to recognize two-catalog structure)
- iter-110 STRICT audit: PASS (9/9 cohort migrated)
- iter-111 producer-marker audit: PASS (0 unregistered)
- Marketplace regression suite: **48/48 PASS** (iter-114 test auto-discovered, up from 47)

**Iter-115+ candidates**

1. Promote Check 4t (iter-111 producer-typo audit) + Check 4u (iter-113 doc-drift detector) from informational to STRICT-BLOCK now that both marker families are formally registered
2. Add reverse-search accessor `lookupCanonicalRegistryEntryByConsumerSourceFileRelativePath` spanning both registries (operators can ask "what marker suppresses hook/audit X?" programmatically)
3. Extend the iter-111 producer-typo audit to scan `.mise/` files for audit-task-marker typos (currently the audit excludes `.mise/`); requires careful scope to avoid false-positives on the audit-task scripts that USE their own markers as documentation

### Iter-113: Registry-to-docs generator emitting operator-facing `docs/marketplace-escape-hatch-marker-reference.md` from the iter-111 canonical registry as SSoT

Iter-113 closes the operator-discoverability gap left by iter-111: the canonical producer-marker registry was a TypeScript SSoT readable by static-analysis tools but NOT by operators browsing the repo. Iter-113 introduces a deterministic markdown rendering of the registry that is committed to git and kept in sync with the source via a drift-detection check.

**Why operators need this**

Pre-iter-113, an operator asking "what marker do I write to suppress the `file-size-guard` for this one file?" had to either (a) grep the marketplace for usage examples, (b) read the iter-111 registry TypeScript source, or (c) read the hook source itself. None of those are discoverable from a github browser without prior knowledge of where to look.

Post-iter-113, the answer is `docs/marketplace-escape-hatch-marker-reference.md` — a single artifact with every legitimate marker token, its consumer hook, case/window/reason policies, and example usage.

**Idempotency invariant + drift detection**

The generator is deterministic: re-running on an unchanged registry produces a byte-identical doc. This is what makes the iter-113 drift-detection check meaningful — any non-empty diff between the on-disk doc and the registry-derived output means SSoT divergence (either the registry was edited without regenerating the doc, OR the doc was hand-edited without updating the registry).

**Three invocation modes**

| Mode       | Behavior                                                                 | Use case                                   |
| ---------- | ------------------------------------------------------------------------ | ------------------------------------------ |
| `--write`  | Regenerate on-disk doc (default)                                         | Author workflow after editing the registry |
| `--check`  | Diff registry-derived output against on-disk doc; exit non-zero on drift | CI / preflight (informational in iter-113) |
| `--stdout` | Emit doc to stdout with no on-disk side effects                          | Manual inspection, pipe into pager, etc.   |

**Preflight Check 4u wired (informational)**

Complementary to iter-110's Check 4s (CONSUMER-side STRICT) and iter-111's Check 4t (PRODUCER-side informational). The three checks now form a triplet covering the full escape-hatch lifecycle:

| Check | Side     | Mode          | Catches                                                               |
| ----- | -------- | ------------- | --------------------------------------------------------------------- |
| 4s    | CONSUMER | STRICT-BLOCK  | Hook bypasses canonical helper OR cohort member missing helper import |
| 4t    | PRODUCER | Informational | Producer-side marker token not registered (potential typo)            |
| 4u    | DOC SYNC | Informational | On-disk reference doc out of sync with registry SSoT                  |

**Iter-113 regression validation (7 cases)**

| Case | Verifies                                                                                                     |
| ---- | ------------------------------------------------------------------------------------------------------------ |
| 1    | Generator task exists and is executable                                                                      |
| 2    | `--check` mode passes against the on-disk committed doc                                                      |
| 3    | `--stdout` mode emits non-empty doc with all 12 baseline marker sections                                     |
| 4    | Idempotency — two consecutive runs produce byte-identical output (required for meaningful drift detection)   |
| 5    | On-disk doc renders all 12 baseline markers in alphabetical order                                            |
| 6    | On-disk doc contains all 8 expected non-catalog sections (preamble + purpose + how-to + invariants + ...)    |
| 7    | Drift-detection correctly fails when the on-disk doc is mutated (synthetic-mutation probe with cleanup-trap) |

All 7 cases pass. Marketplace regression suite: **47/47** (up from 46 in iter-112 — iter-113 test auto-discovered).

**Iter-114+ candidates documented inline**

1. Extend iter-111 registry to cover the AUDIT-marker family (~10 markers consumed by `.mise/` audit tasks rather than runtime hooks): `WILDCARD-MATCHER-OK`, `MATCHER-NO-MULTIEDIT-OK`, `POSTTOOLUSE-RAW-STDOUT-OK`, `HOOK-OUTPUT-SIZE-CAP-OK`, `STOP-HOOK-ADDITIONAL-CONTEXT-OK`, `SPAWN-SYNC-OK`, `TRUNCATION-OK`, `ORDERING-OK`, `ESCAPE-HATCH-AUDIT-OK`, `FAST-PATH-OK`. Separate registry layer because audit-marker lifecycle differs from runtime-hook lifecycle.
2. Promote Check 4t (iter-111 producer-typo audit) + Check 4u (iter-113 doc-drift detector) from informational to STRICT-BLOCK once the AUDIT-marker family is also registered.
3. Add a search-by-suppression-target accessor to the registry (`lookupCanonicalRegistryEntryByConsumerHookSourceFileRelativePath`) so operators can ask the registry "what marker suppresses this hook?" programmatically.

### Iter-112: Migrate posttooluse-reminder.ts SETPROCTITLE-OK detection to iter-107 canonical helper — closes iter-111-surfaced registry-consistency gap + expands iter-110 cohort 8 → 9 + widens comment-prefix tolerance

Iter-112 closes the registry-consistency gap that iter-111's typo-detection audit surfaced on its first live run: `posttooluse-reminder.ts` consumed the `SETPROCTITLE-OK` marker via raw `fileContent.includes("# SETPROCTITLE-OK")` substring check rather than through the iter-107 canonical helper. Iter-111 registered the marker (closing the producer-side audit gap) but flagged the consumer-side migration as iter-112+ scope. Iter-112 delivers it.

**What changed in the consumer**

Pre-iter-112 (`posttooluse-reminder.ts:494`):

```typescript
if (fileContent.includes("# SETPROCTITLE-OK")) return null;
```

Post-iter-112:

```typescript
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";

const SETPROCTITLE_REMINDER_ESCAPE_HATCH_CONFIGURATION_REGISTERED_IN_ITER111_CANONICAL_REGISTRY =
  {
    markerNameTokenIncludingSuffix: "SETPROCTITLE-OK",
    caseSensitivityMode: "CASE_SENSITIVE" as const,
  };

if (
  hasFileWideEscapeHatchMarkerInContent(
    fileContent,
    SETPROCTITLE_REMINDER_ESCAPE_HATCH_CONFIGURATION_REGISTERED_IN_ITER111_CANONICAL_REGISTRY,
  )
) {
  return null;
}
```

**Side benefit: widened comment-prefix tolerance**

The pre-iter-112 raw-substring check required the literal `#` prefix. Post-iter-112 the helper does pure substring matching, so operators can now use ANY of these and the marker is honored:

- `# SETPROCTITLE-OK` (shell-style — pre-iter-112 only form)
- `// SETPROCTITLE-OK` (TypeScript/JavaScript)
- `<!-- SETPROCTITLE-OK -->` (HTML/plist)
- `SETPROCTITLE-OK` (no prefix at all — bare token)

This matches the UPPER-KEBAB-CASE-never-collides convention used by the other 8 cohort members and is the operator-friendly default. The pre-iter-112 leading-`#` requirement was incidental to the implementation, never documented as a constraint, so widening tolerance is a pure usability win.

**Cohort growth (8 → 9)**

| Iter     | Cohort size | Latest addition                                                           |
| -------- | ----------- | ------------------------------------------------------------------------- |
| iter-107 | 1           | iter-78 layer3-stripped-path guard                                        |
| iter-108 | 3           | + version-guard + inline-ignore-guard                                     |
| iter-109 | 7           | + native-binary + process-storm + cwd-deletion + cargo-tty (multi-marker) |
| iter-110 | 8           | + file-size-guard (config-string pattern → helper)                        |
| iter-112 | **9**       | + **posttooluse-reminder (SETPROCTITLE — raw .includes → helper)**        |

**Iter-112 regression validation**

| Gate                                                              | Status                                         |
| ----------------------------------------------------------------- | ---------------------------------------------- |
| Iter-112 regression test (6 cases including widened-prefix probe) | 6/6 PASS                                       |
| Iter-110 STRICT-BLOCK audit                                       | PASS (9/9 cohort migrated)                     |
| Iter-111 producer-marker typo audit                               | PASS (0 unregistered / 12 registered)          |
| Marketplace regression suite                                      | **46/46 PASS** (iter-112 test auto-discovered) |

**Iter-113+ candidates**

1. Extend iter-111 registry to cover the AUDIT-marker family (~10 markers consumed by `.mise/` audit tasks rather than runtime hooks — `WILDCARD-MATCHER-OK`, `MATCHER-NO-MULTIEDIT-OK`, `POSTTOOLUSE-RAW-STDOUT-OK`, `HOOK-OUTPUT-SIZE-CAP-OK`, `STOP-HOOK-ADDITIONAL-CONTEXT-OK`, `SPAWN-SYNC-OK`, `TRUNCATION-OK`, `ORDERING-OK`, `ESCAPE-HATCH-AUDIT-OK`, `FAST-PATH-OK`). Separate registry layer because audit-marker lifecycle differs from runtime-hook lifecycle.
2. Promote iter-111 audit (preflight Check 4t) from informational to STRICT-BLOCK once the AUDIT-marker family is also registered.
3. Build a registry-to-documentation generator that emits operator-facing `escape-hatch-marker-reference.md` from the iter-111 registry — single source of truth for "how do I opt out of hook X".

### Iter-111: Marketplace-wide PRODUCER-side escape-hatch-marker canonical registry + typo-detection audit + `@deprecated ESCAPE_HATCH` cleanup

Iter-111 introduces the second half of the escape-hatch consolidation arc's invariant pair. Iter-110 closed the CONSUMER-side invariant ("every consumer hook must route through the iter-107 canonical helper"); iter-111 introduces the PRODUCER-side invariant ("every producer-side marker token operators write must be recognized by some consumer hook").

**The silent-fail typo class iter-111 catches**

Pre-iter-111, an operator writing `# PROCSS-STORM-OK` (missing the first `E`) would experience:

1. The marker is meant to suppress process-storm-guard's enforcement
2. The hook scans for the exact token `PROCESS-STORM-OK` (the registered marker)
3. The typo doesn't match — the hook blocks the operation
4. The operator sees "blocked by process-storm-guard" and is confused why their "escape hatch" didn't actually escape
5. No static check existed to surface the typo at authorship time

Iter-111 introduces a producer-side typo-detection audit that catches this entire silent-fail class at preflight time.

**1. Canonical producer-marker registry**

A single TypeScript module at `plugins/itp-hooks/hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts` declares every legitimate marker token with full provenance:

| Field                                                            | Purpose                                                                                     |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `markerNameTokenIncludingSuffix`                                 | Exact spelling (UPPER-KEBAB-CASE by convention; `SSoT-OK` grandfathered mixed-case)         |
| `consumerHookSourceFileRelativePath`                             | Which hook reads this marker                                                                |
| `caseSensitivityModeDeclaredAtConsumerCallSite`                  | Must match the configuration object passed to the iter-107 helper at the consumer call site |
| `windowSemanticsModeDeclaredAtConsumerCallSite`                  | `SAME_LINE_ONLY` / `SAME_LINE_OR_PRECEDING_N_LINES` / `FILE_WIDE`                           |
| `minimumReasonCharacterCountRequiredAfterColonOrZeroForOptional` | 0 if bare marker accepted; else min char count (e.g., LAYER3-STRIPPED-PATH-OK enforces ≥10) |
| `humanReadableEscapeHatchDescriptionForOperatorDocumentation`    | Plain-English description for operator-facing docs generators                               |

Iter-111 baseline: **12 entries** (the iter-110 cohort plus `SETPROCTITLE-OK` which the audit surfaced on first run as a real unregistered marker consumed by `posttooluse-reminder.ts` via raw `.includes()` substring check).

**2. Producer-side typo-detection audit**

`.mise/tasks/audit-marketplace-wide-producer-escape-hatch-marker-typo-detection-against-canonical-iter111-registry.sh` greps the marketplace for `\b[A-Z][A-Z0-9-]+-(OK|SKIP|WRAP)\b` tokens in producer files and verifies each appears in the registry. Scope rules:

- INCLUDES: every file under `plugins/<plugin>/` except `plugins/itp-hooks/hooks/` (consumers, not producers) and except `.mise/` (audit-marker family — different lifecycle layer, iter-112+ scope)
- EXCLUDES: `tests/`, `docs/`, `references/`, `*.test.*`, `test-*`, `*_test.*`, `*.spec.*` (test fixtures use synthetic `FOO-OK`/`BAR-OK`/`BAZ-OK`/`QUX-OK` markers that aren't real)
- EXCLUDES: vendor/build dirs (`.build`, `node_modules`, `.venv`, `target`, `.git`)

Audit case-insensitive — `# process-storm-ok` and `# PROCESS-STORM-OK` both resolve to the same registered token. Consumer-side case-sensitivity remains the consumer's call.

**3. Audit immediately surfaced a real unregistered marker on first run**

The iter-111 audit was designed to catch hypothetical typos. On its very first run against the live marketplace, it surfaced a **real unregistered marker**: `SETPROCTITLE-OK` in `plugins/tlg/scripts/tg-cli.py` (consumed by `posttooluse-reminder.ts:494` via raw `fileContent.includes("# SETPROCTITLE-OK")` substring check). This is the kind of latent issue that has no failure mode UNTIL someone misspells it — the audit caught it before that happened. Resolved by registering it; iter-112+ candidate to migrate the consumer to the iter-107 canonical helper for behavioral consistency.

**4. `@deprecated ESCAPE_HATCH` exports dropped**

Iter-109 preserved the pre-migration `export const ESCAPE_HATCH = /.../i;` regex literals in `process-storm-patterns.mjs` and `cwd-deletion-patterns.mjs` for backward compat. Iter-111 verified via marketplace-wide grep that the only consumer of the process-storm export was an unused-import in `process-storm-patterns.test.mjs:10` and that `cwd-deletion-patterns.mjs::ESCAPE_HATCH` had zero external consumers. Both exports + the unused import dropped in this iter; the canonical detection path is now exclusively the iter-107 helper call.

**Iter-111 audit + regression validation**:

| Gate                                                                         | Status                                                     |
| ---------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Iter-111 typo-detection audit                                                | PASS (0 unregistered markers / 12 known registered tokens) |
| Iter-111 regression test (6 cases, including synthetic-typo-injection probe) | 6/6 PASS                                                   |
| Iter-107 regression test                                                     | 10/10 PASS (unchanged)                                     |
| Iter-110 strict audit                                                        | PASS (8/8 cohort migrated)                                 |
| Marketplace regression suite                                                 | 45/45 PASS (iter-111 test auto-discovered)                 |
| Preflight Check 4t (iter-111 informational only — never blocks)              | Wired in alongside iter-110's Check 4s STRICT-BLOCK        |

**Iter-112+ candidates** documented inline:

1. Migrate `posttooluse-reminder.ts`'s `# SETPROCTITLE-OK` detection from raw `.includes()` to the iter-107 canonical helper for behavioral consistency with the other 11 cohort members.
2. Extend the registry to cover the 10+ AUDIT-marker family (`WILDCARD-MATCHER-OK`, `MATCHER-NO-MULTIEDIT-OK`, `POSTTOOLUSE-RAW-STDOUT-OK`, `HOOK-OUTPUT-SIZE-CAP-OK`, `STOP-HOOK-ADDITIONAL-CONTEXT-OK`, `SPAWN-SYNC-OK`, `TRUNCATION-OK`, `ORDERING-OK`, `ESCAPE-HATCH-AUDIT-OK`, `FAST-PATH-OK`) — these are consumed by `.mise/` audit tasks rather than runtime hooks and represent a parallel marker registry layer.
3. Promote iter-111 audit from informational (Check 4t) to STRICT-BLOCK once the AUDIT-marker family is also registered AND the marketplace stabilizes.

### Iter-110: Close iter-107 → iter-109 escape-hatch consolidation arc with file-size-guard migration + audit STRICT-BLOCK promotion + multi-marker probe

Iter-110 closes the iter-107 → iter-109 migration arc by delivering the final 3 pieces:

**1. file-size-guard migration (the last hand-rolled consumer)**

`pretooluse-file-size-guard.ts` was the last marketplace hook with hand-rolled escape-hatch detection, but its implementation used a CONFIG-STRING pattern (`content.includes(config.escapeComment)` where `escapeComment` is loaded at runtime from `.claude/file-size-guard.json`) rather than a regex literal. This kept it invisible to the iter-107 inventory audit's regex-literal heuristic (catching it would require a different scan). Iter-110 migrates by routing `hasEscapeComment(content, escapeComment)` through `hasFileWideEscapeHatchMarkerInContent(content, { markerNameTokenIncludingSuffix: escapeComment, caseSensitivityMode: "CASE_SENSITIVE" })` — behavior-preserving since `content.includes` IS what the helper's CASE_SENSITIVE mode does internally. The distinguishing feature of file-size-guard (operator-overridable marker token via per-project config) composes cleanly because the helper accepts arbitrary marker tokens at runtime.

**2. Audit promoted from informational to STRICT-BLOCK**

The iter-107 inventory audit was informational since its introduction (intentional — gave operators a one-iter visibility window before enforcement). Iter-110 promotes to STRICT-BLOCK with TWO release-blocking invariants:

| Invariant                                                                                                    | Catches                                                                                                             |
| ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| (1) NO hand-rolled escape-hatch-marker regex detection in any hook source file                               | A new hook author bypassing the canonical shared helper (heuristic: `ESCAPE_HATCH=` or `/MARKER-OK/` regex literal) |
| (2) ALL 8 canonical cohort members import the iter-107 shared helper (curated list in the audit task source) | Silent removal of a previously-migrated helper consumption (e.g., a refactor that accidentally drops the import)    |

The curated 8-cohort list is now the SSoT for marketplace escape-hatch consumers and lives at the top of the audit task script. When a new hook adds an escape-hatch comment, the discipline is: (a) migrate to the shared helper at authorship time + (b) add to the curated cohort.

**3. Multi-marker probe (Case 10) added to the iter-107 regression test**

Iter-109's cargo-tty-guard migration introduced the first multi-marker pattern (one hook calling the helper with TWO different marker configurations: `CARGO-TTY-SKIP` opt-out + `CARGO-TTY-WRAP` opt-in). Iter-110 adds Case 10 to the iter-107 regression test that probes this pattern programmatically — verifies the helper has no hidden global state and each call is independent (`SKIP` marker matches command with `SKIP` only; `WRAP` marker matches command with `WRAP` only; neither marker matches command with neither). Documents the multi-marker pattern as an explicit API contract.

**Marketplace state after iter-110 (FINAL — arc complete)**:

| Hook                                                        | Marker(s)                             | Window mode                      | Case mode          | Migrated iter  |
| ----------------------------------------------------------- | ------------------------------------- | -------------------------------- | ------------------ | -------------- |
| `pretooluse-iter78-layer3-stripped-path-edit-time-guard.ts` | `LAYER3-STRIPPED-PATH-OK`             | `SAME_LINE_OR_PRECEDING_N_LINES` | `CASE_SENSITIVE`   | iter-107       |
| `pretooluse-version-guard.ts`                               | `SSoT-OK`                             | `FILE_WIDE`                      | `CASE_SENSITIVE`   | iter-108       |
| `pretooluse-inline-ignore-guard.ts`                         | `INLINE-IGNORE-OK`                    | `SAME_LINE_ONLY`                 | `CASE_SENSITIVE`   | iter-108       |
| `pretooluse-native-binary-guard.ts`                         | `BASH-LAUNCHD-OK`                     | `FILE_WIDE`                      | `CASE_INSENSITIVE` | iter-109       |
| `process-storm-patterns.mjs`                                | `PROCESS-STORM-OK`                    | `FILE_WIDE`                      | `CASE_INSENSITIVE` | iter-109       |
| `cwd-deletion-patterns.mjs`                                 | `CWD-DELETE-OK`                       | `FILE_WIDE`                      | `CASE_INSENSITIVE` | iter-109       |
| `pretooluse-cargo-tty-guard.ts`                             | `CARGO-TTY-SKIP` + `CARGO-TTY-WRAP`   | `FILE_WIDE`                      | `CASE_INSENSITIVE` | iter-109       |
| `pretooluse-file-size-guard.ts`                             | `FILE-SIZE-OK` (operator-overridable) | `FILE_WIDE`                      | `CASE_SENSITIVE`   | **iter-110 ★** |

**Iter-110 regression validation**:

- iter-107 regression test extended to 10 assertions (Case 10 multi-marker probe added); 10/10 PASS
- iter-110 strict-mode audit: PASSED — 8/8 canonical cohort migrated, 0 hand-rolled detections
- preflight Check 4s upgraded from informational to STRICT-BLOCK (audit non-zero exit now fails preflight)
- Marketplace regression suite: 44/44 PASS

**Iter-107 → iter-110 arc summary** (the escape-hatch consolidation arc, complete):

| Iter     | Deliverable                                                                                                                  | Net change                                                |
| -------- | ---------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| iter-107 | Canonical shared helper + 3 window-semantics modes + reason-policy gate + iter-78 migration as proof-of-integration + audit  | 1 hook migrated; audit informational                      |
| iter-108 | `caseSensitivityMode` extension + version-guard FILE_WIDE + inline-ignore-guard SAME_LINE_ONLY                               | 3 hooks migrated; audit still informational               |
| iter-109 | Batch-migrate 4 CASE_INSENSITIVE consumers (native-binary, process-storm, cwd-deletion, cargo-tty 2-marker) + biome side-fix | 7 hooks migrated; audit still informational               |
| iter-110 | file-size-guard migration + audit STRICT-BLOCK promotion + multi-marker probe                                                | **8/8 hooks migrated; audit enforced as release blocker** |

**Iter-111+ candidates** (post-arc):

1. Drop `@deprecated` legacy `ESCAPE_HATCH` regex constants from `process-storm-patterns.mjs` + `cwd-deletion-patterns.mjs` once the `process-storm-patterns.test.mjs` consumers migrate to import the helper directly.
2. Extract the iter-95 async-spawn helper (`executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail`) to a third dedicated shared-lib file IF PreToolUse classifiers adopt async subprocess execution (preventive — same iter-106 awkwardness pattern).
3. Cross-plugin sweep: scan plugins OUTSIDE itp-hooks for any hand-rolled escape-hatch patterns that should also migrate to the canonical helper (e.g., other plugins that ship hooks with opt-out comments).

### Iter-109: Batch-migrate 4 CASE_INSENSITIVE consumers + surface pre-existing biome lint bug as iter-109 side-effect cleanup

Iter-109 delivers the largest migration batch in the iter-107+ arc: 4 hooks (`pretooluse-native-binary-guard.ts`, `process-storm-patterns.mjs`, `cwd-deletion-patterns.mjs`, `pretooluse-cargo-tty-guard.ts`) migrated in a single iter to use the iter-107 shared helper with `caseSensitivityMode: "CASE_INSENSITIVE"`. All four shared the legacy `/i` regex flag and the simple `FILE_WIDE` window-semantics mode; batching saved the per-iter ceremonial cost of separate audits + commits + releases while preserving behavior across all four.

**Iter-109 migrations**:

| Hook                                | Marker(s)                           | Detection sites                                            | Notes                                                                                                                                                                                                                                                                                                                                             |
| ----------------------------------- | ----------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pretooluse-native-binary-guard.ts` | `BASH-LAUNCHD-OK`                   | 2 (proposed content + iter-15 existing-file-fallback path) | Pre-iter-109 regex `/[#/]\s*BASH-LAUNCHD-OK/i` required `#` or `/` comment prefix; helper uses pure-substring match (safe — UPPER-KEBAB-CASE never collides). Honors `#` (shell), `//` (TS), `<!-- -->` (plist) via marker alone.                                                                                                                 |
| `process-storm-patterns.mjs`        | `PROCESS-STORM-OK`                  | 1 (in `detectPatterns`)                                    | `.mjs` file importing from `.ts` shared lib via bun's native cross-format resolution. Pre-iter-109 export `ESCAPE_HATCH` regex preserved as `@deprecated` for backward compat with `process-storm-patterns.test.mjs` consumers.                                                                                                                   |
| `cwd-deletion-patterns.mjs`         | `CWD-DELETE-OK`                     | 1 (in `detectCwdDeletion`)                                 | Pre-iter-109 export `ESCAPE_HATCH` regex preserved as `@deprecated` for backward compat. **iter-109 side-effect cleanup**: surfaced + fixed a pre-existing biome `lint/suspicious/noAssignInExpressions` issue at the `while ((match = rmPattern.exec(command)) !== null)` pattern by replacing it with the modern stateless `matchAll` iterator. |
| `pretooluse-cargo-tty-guard.ts`     | `CARGO-TTY-SKIP` + `CARGO-TTY-WRAP` | 2 (opt-out + opt-in in `isUnsafeBackground`)               | **FIRST hook with TWO marker configurations** — proves the helper composes cleanly for multi-marker hooks (one configuration object per marker, same helper API).                                                                                                                                                                                 |

**Adversarial-audit side-effect cleanup (iter-109 contribution beyond migration)**: editing `cwd-deletion-patterns.mjs` triggered the iter-105+iter-106 PostToolUse biome-lint orchestrator, which surfaced a pre-existing `lint/suspicious/noAssignInExpressions` issue at the `while ((match = rmPattern.exec(command)) !== null)` regex-iteration pattern. The issue had been latent since the file's original authorship; iter-109's full-file lint pass caught it. Fixed by replacing the imperative `let match; while ((match = exec(command)) !== null)` pattern with the modern stateless `for (const m of command.matchAll(...))` iterator (idiomatic 2026 JavaScript, no `lastIndex` stewardship needed). Behavior-preserving. The fix is documented inline as an iter-109 adversarial-audit byproduct.

**Marketplace state after iter-109**: **7 of 7 hooks migrated** (per the iter-107 inventory audit's hand-rolled-regex detection heuristic). The iter-107 roadmap also listed `pretooluse-file-size-guard.ts`, but that hook uses a different code path (`escapeComment: "FILE-SIZE-OK"` config-string, not a regex literal) which the iter-107 audit does not classify as hand-rolled. file-size-guard remains the last non-migrated escape-hatch consumer; its migration is iter-110+ scope.

**Iter-109 regression validation**:

- iter-90 native-binary-guard regression test: 15/15 PASS (covers proposed-content escape hatch + iter-15 file-on-disk fallback + escape-hatch on all comment styles)
- `process-storm-patterns.test.mjs` (13 unit tests): 13 pass, 0 fail (covers escape-hatch on separate line + per-category fork-bomb / gh-recursion / credential-storm / mise-fork detection)
- Marketplace regression suite: 44/44 PASS (no new test files added; existing suite covers the migrations through downstream consumer tests)
- iter-107 inventory audit: 7 migrated / 0 hand-rolled — **the marketplace is now fully migrated** per the iter-107 detection heuristic

**Iter-110+ candidates** (in priority order):

1. Migrate `pretooluse-file-size-guard.ts` — currently uses `escapeComment: "FILE-SIZE-OK"` config-string detection (not a regex literal); requires a small wrapper or config-shape adaptation to plug into the iter-107 helper. Once migrated, the iter-107 inventory audit can detect 100% of marketplace escape-hatch consumers and the audit becomes a tautological PASS — at that point, **promote from informational (Check 4s) to strict-block** as the iter-107 documented final state.
2. Add iter-109 multi-marker probe to the iter-107 regression test — explicitly exercise the cargo-tty-guard two-marker pattern as a documented helper API contract.
3. Extract the `@deprecated` legacy regex constants from `process-storm-patterns.mjs` + `cwd-deletion-patterns.mjs` once external consumers (test files) drop their references — currently kept as backward-compat to avoid breaking `process-storm-patterns.test.mjs`.

Source on Bun's `.mjs` ↔ `.ts` cross-format module resolution (used by `process-storm-patterns.mjs` importing the `.ts` shared helper): [Bun module resolution docs](https://bun.com/docs/runtime/modules) — Bun's resolver natively handles `.ts` from `.mjs` and vice versa without requiring `.ts → .mjs` build step.

### Iter-108: Helper case-sensitivity extension + 2 migrations (version-guard FILE_WIDE + inline-ignore-guard SAME_LINE_ONLY)

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
