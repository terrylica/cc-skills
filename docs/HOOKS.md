# Hooks Development Guide

How to write, register, test and debug Claude Code hooks in the cc-skills marketplace. This page describes the current state; the history of how it got here is in git and `CHANGELOG.md`.

<!-- # SSoT-OK: this file cites upstream Claude Code behaviour and uses SemVer placeholders (vX.Y.Z) as documentation patterns. They are not this marketplace's version SSoT. The marker is the file-wide escape hatch that pretooluse-version-guard.ts honours. -->

## Hook Lifecycle

The events the plugins in this repository register:

| Hook Type          | When Triggered                 | Can Block?                                 | Use Case                          |
| ------------------ | ------------------------------ | ------------------------------------------ | --------------------------------- |
| `PreToolUse`       | Before a tool executes         | Yes                                        | Validation, enforcement           |
| `PostToolUse`      | After a tool executes          | No (the tool already ran); can add context | Verification, reminders, linting  |
| `UserPromptSubmit` | When the user submits a prompt | Yes                                        | Context injection, status notices |
| `Stop`             | When Claude finishes its turn  | Yes (keeps Claude working)                 | Session checks, cleanup           |

The upstream [hooks reference](https://code.claude.com/docs/en/hooks) is the authority for every event and field; the sections below record only what matters for hooks written here.

## Hook Output: What Reaches Claude

Read on 2026-10-01 from the upstream hooks reference:

| Output                                                                                                   | Where it goes                                                                                                                                                                      |
| -------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Plain stdout, exit 0                                                                                     | Debug log only, for most events. On `UserPromptSubmit` and `SessionStart` (among others the docs list), plain stdout is added to Claude's context.                                 |
| Stderr, exit 0                                                                                           | Debug log only. Claude never sees it.                                                                                                                                              |
| Exit 2                                                                                                   | Blocks on events that can block, whatever the JSON says. The message is the JSON's blocking reason if there is one, otherwise stderr. On `PostToolUse`, stderr is shown to Claude. |
| PreToolUse `hookSpecificOutput.permissionDecision` (`allow`\|`deny`\|`ask`) + `permissionDecisionReason` | The decision. The reason reaches Claude on deny.                                                                                                                                   |
| PostToolUse `{"decision": "block", "reason": "…"}`                                                       | The reason is placed next to the tool result. "block" is a misnomer: the tool already ran.                                                                                         |
| `hookSpecificOutput.additionalContext`                                                                   | Added to Claude's context on PreToolUse, PostToolUse, UserPromptSubmit, SessionStart and (per the current docs) Stop.                                                              |

Rules that follow from this:

- **A PostToolUse hook that wants Claude to read something must emit JSON** — `{decision: "block", reason}` or `hookSpecificOutput.additionalContext`. A `console.log` of plain text is silently invisible to Claude. `tasks/hook-lint/posttooluse-raw-stdout.sh` fails the gate on a raw-string `console.log` in a PostToolUse hook; escape `POSTTOOLUSE-RAW-STDOUT-OK: <reason>`.
- **A PreToolUse hook must use `hookSpecificOutput.permissionDecision`.** The old top-level `decision`/`reason` fields fail to block without any error. Use the `allow`/`deny`/`ask` helpers in `plugins/itp-hooks/hooks/pretooluse-helpers.ts`; `tasks/hook-lint/pretooluse-decision-schema.sh` audits every PreToolUse hook.
- **Print exactly one JSON object.** Several JSON lines on stdout are read as plain text or as a parse error, so a hook that would emit more than one response must merge them first — which is what the orchestrators below do.
- **Keep every string under 10,000 characters.** Longer `additionalContext`, `systemMessage` or plain stdout is saved to a file and replaced by a path and a 2,000-character preview, and Claude is not told to read the file. Wrap any unbounded output (linter findings, type errors) in `truncateHookOutputToStayBelowClaudeFileSpilloverThreshold()` from `plugins/itp-hooks/hooks/lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts`, which cuts at 9,000 characters and appends a note saying so. `tasks/hook-lint/reason-truncation.sh` checks the hooks known to produce unbounded output.
- **Do not make a context-injecting PostToolUse hook `async: true`.** An async hook's output arrives on the next turn and its `decision` has no effect, so the same-turn feedback loop (Claude reads a type error and fixes it) breaks. `async` suits pure side effects only: logging, notifications, backups.

**Stop hooks.** The current upstream docs accept `hookSpecificOutput.additionalContext` on `Stop` as non-error feedback that keeps Claude working, alongside `{decision: "block", reason}`. `tasks/hook-lint/stop-additional-context.sh` predates that and still fails any Stop hook that emits `additionalContext`; `plugins/itp-hooks/hooks/stop-orchestrator.ts` follows the audit and reports to stderr. Measure the current behaviour before relying on either.

**"My hook isn't firing."** Confirm the hook ran (its debug log, or `claude --debug`) before assuming its code is broken. In 2026-05 a Claude Code regression dropped every context channel for Bash-matcher hooks while the hooks executed correctly ([anthropics/claude-code#55889](https://github.com/anthropics/claude-code/issues/55889), closed as inactive, not as fixed). Also check the cache layer (below): the code that runs is the installed release, not your checkout.

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
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason:
          "[hook-name] Blocked: reason here\n\nUse alternative approach...",
      },
    }),
  );
}
process.exit(0);
```

In itp-hooks, call `deny(reason)` from `pretooluse-helpers.ts` instead of building the JSON by hand. Use `ask(reason)` to let the user decide.

### Hard Block (No Override)

```bash
#!/usr/bin/env bash
# Exit code 2 = hard block; stderr becomes the reason Claude sees
echo "Operation not permitted: <why, and what to do instead>" >&2
exit 2
```

**Reason-gated escape hatch on a hard block.** A hard block should still carry a deliberate safety valve unless the operation can never succeed. The `release-notes-extensiveness-guard` (see [itp-hooks spoke](../plugins/itp-hooks/docs/release-notes-extensiveness-guard.md)) hard-blocks release/tag commands whose notes lack a narrative paragraph plus a point-form list, but accepts `RELEASE-NOTES-OK: <≥10-char reason>` in the command for a genuinely un-narratable release. Follow the same pattern for any new marker: register it and detect it with the shared helper (see [Escape-Hatch Markers](#escape-hatch-markers)), never with a hand-rolled regex.

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
          "timeout": 5
        }]
      }
    ],
    "PostToolUse": [...],
    "Stop": [...]
  }
}
```

**File-edit matchers must include `MultiEdit`.** A matcher of `Write|Edit` silently skips every MultiEdit call. Write `Write|Edit|MultiEdit`; `tasks/hook-lint/matcher-multiedit.sh` fails the gate otherwise (escape `MATCHER-NO-MULTIEDIT-OK: <reason>` in the hook's `description`). Inside a classifier, test the tool name with `isFileEditToolNameHonoredByPreToolUseBlockingSubhook()` or `isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook()` from the contract libs rather than comparing strings. `NotebookEdit` is deliberately not in either allow-set: its payload is a notebook cell, not file content.

**No wildcard matchers on PreToolUse/PostToolUse.** `tasks/hook-lint/wildcard-matcher.sh` rejects a `*` or missing matcher there (escape `WILDCARD-MATCHER-OK: <reason>`).

## Timeout Values

Timeouts are in **seconds**. Upstream: "Seconds before canceling. … Defaults: 600 for command, http, and mcp_tool" — [hooks reference](https://code.claude.com/docs/en/hooks).

| Value | Duration | Use Case          |
| ----- | -------- | ----------------- |
| 5     | 5s       | Simple validation |
| 15    | 15s      | Git operations    |
| 30    | 30s      | Network calls     |

This table said **milliseconds** until 2026-09-04, and that single line is how dozens of hook entries across the marketplace came to be written three digits too large: a `5000` meant as five seconds parks a _blocking_ hook for 83 minutes, and one Stop hook was left at 30000 — eight hours twenty. `scripts/hooks.schema.json` now caps the field at 600, so the wrong unit fails validation instead of shipping. See issue [#109](https://github.com/terrylica/cc-skills/issues/109).

**Common mistake**: writing `15000` when you mean fifteen seconds. That is four hours ten minutes, and on a blocking hook it is indistinguishable from a hang. `15` is the correct value.

The `timeoutMs` fields inside the orchestrator registries (below) are milliseconds, because they are JavaScript timers, not hooks.json fields.

## Network-Calling Hooks (Critical Warning)

**Avoid hooks that spawn network-calling processes** (e.g., `gh api`, `curl`, `wget`).

PreToolUse/PostToolUse hooks run on **every** tool invocation. During rapid operations (e.g., disabling 36 workflows, bulk file edits), network-calling hooks spawn hundreds of processes that pile up:

- Load average can exceed 130
- Fork failures: "resource temporarily unavailable"
- May require forced reboot to recover

**Root cause**: Network latency (~1-2s) accumulates while new hook invocations spawn faster than they complete.

**Solution**: Pre-configure authentication/validation in static environment configuration, resolved once before hooks run, instead of validating at runtime.

**Pattern**: Never spawn an auth/validation subprocess per hook invocation; that is what turns latency into a subprocess storm.

## Hook Installation — there is nothing to install

Hooks defined in a plugin's `hooks/hooks.json` are auto-loaded by Claude Code from the installed plugin. Copying them into `~/.claude/settings.json` as well is a **double registration**: the hook fires twice per matching event, visible in the runtime's "Ran N stop hooks" display as the same script listed twice. That is why `scripts/sync-hooks-to-settings.sh` stopped adding entries in v20.2.3 and now only prunes leftover marketplace-path entries from older releases:

```bash
# Prune stale settings.json entries that older releases injected (idempotent)
./scripts/sync-hooks-to-settings.sh
```

The per-plugin `scripts/manage-hooks.sh` installers were the same mistake in a smaller wrapper, and four of the five were deleted in issue #127 (`itp`, `dotfiles-tools`, `gh-tools`, `productivity-tools`). Only `plugins/statusline-tools/scripts/manage-hooks.sh` remains, and only because `lychee-stop-hook.sh` is deliberately **not** in that plugin's `hooks.json` — it is an opt-in Stop hook, so injection is the only registration, not a duplicate one.

**Rule for a new plugin**: put the hook in `hooks/hooks.json`. Write an installer only for a hook you intentionally keep out of `hooks.json`, and record that intent in the script header and the plugin's CLAUDE.md.

## In-Process Orchestrators

Every hooks.json entry is a separate process start on every matching tool call, and for bun hooks that start, not the hook's logic, is most of the cost. Measured 2026-05 on Apple Silicon: each check moved out of its own entry and into a shared process saved about 17 ms per call. Before the Bash orchestrator existed, every Bash call started 26 bun processes from itp-hooks alone.

So in itp-hooks, a new check on a hot path goes **into an orchestrator, not into a new hooks.json entry**:

| Orchestrator                                                                                                                                                    | Event / matcher                      | Subhooks import                                | Aggregation                                                                                          | Doc                                                                                                        |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ---------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts`                                                     | PreToolUse `Write\|Edit\|MultiEdit`  | a pure `classify…ForOrchestrator()`            | Serial, lightest first; the first deny or ask wins                                                   | [pretooluse-write-edit-orchestrator.md](../plugins/itp-hooks/docs/pretooluse-write-edit-orchestrator.md)   |
| `posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts` | PostToolUse `Write\|Edit\|MultiEdit` | a pure `classify…ForPostToolUseOrchestrator()` | All in parallel (`Promise.all`); every contribution is merged into one `{decision: "block", reason}` | [posttooluse-write-edit-orchestrator.md](../plugins/itp-hooks/docs/posttooluse-write-edit-orchestrator.md) |
| `pretooluse-bash-guard-orchestrator.ts`                                                                                                                         | PreToolUse `Bash`                    | the guard's exported `main()`                  | deny > ask > allow; `additionalContext` from allowing guards is joined                               | [pretooluse-bash-guard-orchestrator.md](../plugins/itp-hooks/docs/pretooluse-bash-guard-orchestrator.md)   |
| `stop-orchestrator.ts`                                                                                                                                          | Stop                                 | a script path (spawned)                        | Each subhook is a child process with its own timeout                                                 | —                                                                                                          |

All four live in `plugins/itp-hooks/hooks/`. Shared behaviour of the three in-process ones: each subhook has a `timeoutMs` budget enforced with `AbortSignal.timeout()`, and a subhook that throws or overruns is skipped (fail-open), as a crashed or timed-out standalone hook was. A timed-out subhook cannot be killed — it is abandoned — so a classifier must never rely on finishing.

### Write/Edit subhook contracts

The contracts are in `plugins/itp-hooks/hooks/lib/`:

- PreToolUse: `pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts` — `PreToolUseSubhookClassifierFunction` returns `ALLOW_DECISION`, `denyDecision(reason)` or `askDecision(reason)`.
- PostToolUse: `posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts` — `PostToolUseSubhookClassifierFunction` returns `POSTTOOLUSE_SUBHOOK_NOOP_DECISION` or `buildPostToolUseAdditionalContextDecision(message)`.

A classifier:

- is a pure async function of the parsed input: no stdin read, no stdout write, no `console.log`, no `process.exit` — the orchestrator owns all I/O;
- catches its own errors and returns allow/noop;
- keeps a standalone entry point under `if (import.meta.main)`, so the file still runs on its own and its tests keep working (top-level code would otherwise run when the orchestrator imports it);
- in a PostToolUse subhook, runs subprocesses with `executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail()` from `lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts`, never `Bun.spawnSync` — a synchronous spawn blocks the event loop and serialises the whole `Promise.all`. The same file has the once-per-session reminder gates (`tryAtomicallyClaimOncePerSession…`, atomic `O_EXCL` files under `/tmp`).

Orchestrator behaviour a subhook author needs to know:

- **PreToolUse**: the first deny wins and stops the run; an ask is held while the remaining subhooks are checked for a deny. Either decision goes to stdout as `hookSpecificOutput.permissionDecision` JSON with exit 0, plus a diagnostic on stderr that only reaches the debug log. Never exit 2: it blocks whatever the JSON says (see the output table), so an `ask` would block instead of prompting.
- **PreToolUse**: the edit-time classifiers run for `Write` and `Edit` only. A `MultiEdit` is allowed without any check, because its payload (`tool_input.edits[]`) has not been adapted into "the proposed file" for any classifier. Closing that gap needs a content extractor and a per-classifier review, not a one-line change — see the comment above the tool-name check in the orchestrator.
- **PostToolUse**: the orchestrator prints nothing when every subhook returns noop. When two or more contribute, each section is prefixed `[orchestrator-subhook: <name>]`. A subhook that times out contributes a short "timed out — verify manually" note instead of silence. The merged reason is truncated below the 10,000-character cap.

### Adding a subhook

**Write/Edit (Pre or Post):**

1. In the hook file, export a classifier that satisfies the contract above, and keep the standalone `main()` behind `if (import.meta.main)`.
2. Import it in the orchestrator and add a registry entry (`name`, `timeoutMs`, `classify`, `description`). In the PreToolUse registry, order is lightest first: cheap filename/extension checks before anything that reads files or spawns a process.
3. Do not add a hooks.json entry for it.
4. Add tests. `tasks/hook-lint/orchestrator-subhook-contract.sh` statically checks every `classify*ForOrchestrator` for the `import.meta.main` guard and for forbidden I/O (informational in the gate; `--strict` to fail), and `tasks/hook-lint/orchestrator-spawnsync.sh` fails on `Bun.spawnSync` in any PostToolUse subhook (escape `SPAWN-SYNC-OK: <reason>`).

**Bash:** follow "Adding a Bash guard" in [pretooluse-bash-guard-orchestrator.md](../plugins/itp-hooks/docs/pretooluse-bash-guard-orchestrator.md): export `main()`, emit through the `pretooluse-helpers.ts` outputs, add it to `BASH_GUARD_REGISTRY`, and add a command to the differential test's corpus. A guard that rewrites the command through `updatedInput` stays a separate hooks.json entry, before `pretooluse-pueue-wrap-guard.ts`, which must stay last (`tasks/hook-lint/pueue-wrap-last.sh`).

## Escape-Hatch Markers

An escape hatch is a token such as `FILE-SIZE-OK` that an author writes in a file or command to opt out of one check. Markers are UPPER-KEBAB-CASE ending in `-OK`, `-SKIP` or `-WRAP` (`SSoT-OK` is the one grandfathered mixed-case marker), so they never collide with code identifiers and are matched as plain substrings in any comment style (`#`, `//`, `<!-- -->`).

- **Detect** with the shared helper `plugins/itp-hooks/hooks/lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts`: `hasFileWideEscapeHatchMarkerInContent(content, config)` for a file-wide marker, `detectEscapeHatchMarkerCoveringTargetSourceLine(lines, index, config)` for per-line scope. The config takes the marker token, a window mode (`SAME_LINE_ONLY`, `SAME_LINE_OR_PRECEDING_N_LINES`, `FILE_WIDE`), a case mode (`CASE_SENSITIVE` by default — leave it), and an optional minimum reason length after the colon.
- **Register** a runtime-hook marker in `lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts`, or a marker read by a `tasks/hook-lint/` audit in `lib/marketplace-wide-audit-task-escape-hatch-marker-canonical-registry-cross-task-script-iter114.ts`.
- **Regenerate** the reference doc: `bash tasks/hook-lint/marker-reference-doc.sh` rewrites [`docs/marketplace-escape-hatch-marker-reference.md`](./marketplace-escape-hatch-marker-reference.md) from both registries. Commit it with the registry change.

The gate enforces all three: `escape-hatch-cohort.sh` fails on hand-rolled marker detection, `marker-typos.sh` fails on a marker-shaped token in a plugin file that no registry knows (it catches typos such as `PROCSS-STORM-OK`), `marker-reference-doc.sh --check` fails when the generated doc is out of date, and `stale-marker-descriptions.sh` flags a registry description that no longer names its marker or consumer.

**Looking up a marker.** `tasks/marker-lookup.ts` answers both directions from the registries:

```bash
bun tasks/marker-lookup.ts FILE-SIZE-OK                                        # what does this marker do?
bun tasks/marker-lookup.ts --direction=reverse file-size-guard                 # what opts out of this hook?
bun tasks/marker-lookup.ts --json FILE-SIZE-OK | jq '.dispatchedBackendResponse.matchingMarkers[0]'
```

A query containing `/` is treated as a consumer path, a marker-shaped query as a marker, and anything else is tried as a marker first, then as a path. Lowercase, substrings, basename fragments and typos ("did you mean") also resolve. Exit codes: 0 found, 1 usage error, 2 not found. `--help` prints the full usage.

## Hook Audits (`tasks/hook-lint/`)

Static audits over hook sources and every `plugins/*/hooks/hooks.json`. `tasks/hook-lint/run` runs every `*.sh` in that directory in parallel (at most 4 at once) and prints one PASS/FAIL line per audit; it is `moon run repo:hook-lint`, a dependency of `moon run repo:check`, so it runs on every push. The directory listing is the only list: adding an audit means adding a file there. Each script's header explains what it checks and which escape marker, if any, it honours.

## Hook Source Edits Don't Take Effect Until Next Tagged Release (3-Layer Versioned Cache Lifecycle)

When you commit a fix to a hook source file, the running Claude Code session does NOT pick up the change — and frequently neither does the next session. The hook keeps its old behaviour until a release is installed. This section explains why and how to work around it.

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

Layer 3 holds the **whole** plugin tree (`docs/`, `scripts/`, `tests/`, `lib/` included); measured 2026-08-05, a diff of Layer 2 against Layer 3 differs only by the `.in_use` marker Claude Code adds. So a hook may reference any file in its own plugin through `${CLAUDE_PLUGIN_ROOT}`. The constraint that does exist is elsewhere: `${CLAUDE_PLUGIN_ROOT}` is substituted in `hooks.json` and injected into the hook's environment, but it is not set in the Bash tool, so a **SKILL.md** must resolve paths with `cc-plugin-root <plugin>` — see [skill-plugin-root-guard.md](../plugins/itp-hooks/docs/skill-plugin-root-guard.md).

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
moon run repo:release-full   # full release pipeline, including marketplace publish
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

### Drift Detector (all plugins at once)

The recipe above probes one hook with a marker string you choose. `moon run repo:diagnose-cache-drift` (or `bash tasks/diagnose-plugin-cache-drift.sh`) compares content hashes of Layer 2 against the newest Layer 3 version for every plugin and classifies each as FRESH, STALE-CACHE or NOT-CACHED-LAYER-3:

```bash
bash tasks/diagnose-plugin-cache-drift.sh                         # per-plugin summary
bash tasks/diagnose-plugin-cache-drift.sh --check-plugin itp-hooks # one plugin
bash tasks/diagnose-plugin-cache-drift.sh --verbose                # per-file divergence for each stale plugin
bash tasks/diagnose-plugin-cache-drift.sh --all-divergences        # include files outside hooks/skills/commands/agents
```

Exit 0 when every plugin is FRESH or NOT-CACHED, exit 1 when any is STALE-CACHE. By default it compares only `plugin.json`, `hooks/`, `skills/`, `commands/` and `agents/`, the files that change runtime behaviour.

## Testing Hooks

### Manual Testing

```bash
# Test hook with sample input via pipe
echo '{"tool_name": "Bash", "tool_input": {"command": "gh issue create --title test"}}' | \
  bun plugins/gh-tools/hooks/gh-repo-identity-guard.mjs
```

To exercise an orchestrator, pipe the same kind of payload into the orchestrator file; the deciding subhook is named in its output.

### Unit Testing with Bun

For complex hooks, create a companion test file using `bun:test`:

```typescript
// hooks/my-hook.test.ts
import { describe, expect, it } from "bun:test";
import { execSync } from "child_process";
import { join } from "path";

const HOOK_PATH = join(import.meta.dir, "my-hook.ts");

function runHook(input: object): { stdout: string; parsed: any } {
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
    expect(result.parsed?.hookSpecificOutput?.permissionDecision).toBe("deny");
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

Repository-wide, `moon run repo:test-hooks` runs the bash regression suite under `tasks/tests/`, and `moon run repo:check` runs it with the bun unit tests and the hook audits before every push.

## Hook Language Policy

**Preferred Language: TypeScript (Bun)**

Use TypeScript/Bun as the default for new hooks. Only use bash for simple pattern matching.

| Criteria                 | Bash             | TypeScript        |
| ------------------------ | ---------------- | ----------------- |
| Simple pattern matching  | Preferred        | Overkill          |
| Complex validation logic | Hard to test     | **Preferred**     |
| Educational feedback     | Heredocs awkward | Template literals |
| Type safety              | None             | Full              |

A bash hook that reads its input with `jq` pays a `jq` process start on every call. If most calls are irrelevant to it, test the raw stdin with a `case` substring match first and exit before calling `jq`.

**Reference**: [lifecycle-reference.md](/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) → "Hook Implementation Language Policy"

## Plugins with Hooks

| Plugin               | Hook Types                                      | Purpose                                                   |
| -------------------- | ----------------------------------------------- | --------------------------------------------------------- |
| `itp-hooks`          | PreToolUse, PostToolUse, Stop, UserPromptSubmit | Workflow enforcement, code correctness, the orchestrators |
| `gh-tools`           | PreToolUse, PostToolUse, UserPromptSubmit       | GitHub CLI enforcement, repo/account identity             |
| `devops-tools`       | PreToolUse, PostToolUse, UserPromptSubmit       | 1Password and credential reminders, research reminders    |
| `dotfiles-tools`     | PostToolUse                                     | Chezmoi sync reminder                                     |
| `statusline-tools`   | PostToolUse, Stop                               | Cron tracking and cleanup                                 |
| `productivity-tools` | PostToolUse                                     | Calendar reminder sync                                    |
| `rust-tools`         | PostToolUse                                     | Rust tooling reminder                                     |
| `gmail-commander`    | PreToolUse                                      | Gmail draft integrity                                     |
| `calcom-commander`   | Stop                                            | Bot lifecycle management                                  |

## Related ADRs

- [PreToolUse/PostToolUse Architecture](/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md)
- [Hook Visibility Issue](/docs/adr/2025-12-17-posttooluse-hook-visibility.md)
- [ITP Hooks Settings Installer](/docs/adr/2025-12-07-itp-hooks-settings-installer.md)
- [Polars Preference Hook](/docs/adr/2026-01-22-polars-preference-hook.md)

## Reference Implementation

See [lifecycle-reference.md](/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) for detailed hook development patterns.
