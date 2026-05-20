# Hooks Development Guide

Comprehensive guide for developing Claude Code hooks in the cc-skills marketplace.

## Hook Lifecycle

Claude Code hooks intercept tool calls at three lifecycle points:

| Hook Type     | When Triggered              | Can Block? | Use Case                     |
| ------------- | --------------------------- | ---------- | ---------------------------- |
| `PreToolUse`  | Before tool executes        | Yes        | Validation, enforcement      |
| `PostToolUse` | After tool executes         | Yes        | Verification, sync reminders |
| `Stop`        | When Claude stops executing | No         | Session metrics, cleanup     |

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
