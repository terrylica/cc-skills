# Hooks Development Guide

Comprehensive guide for developing Claude Code hooks in the cc-skills marketplace.

## Hook Lifecycle

Claude Code hooks intercept tool calls at three lifecycle points:

| Hook Type     | When Triggered              | Can Block? | Use Case                      |
| ------------- | --------------------------- | ---------- | ----------------------------- |
| `PreToolUse`  | Before tool executes        | Yes        | Validation, enforcement       |
| `PostToolUse` | After tool executes         | Yes        | Verification, sync reminders  |
| `Stop`        | When Claude stops executing | No         | Session metrics, cleanup      |

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
  console.log(JSON.stringify({
    permissionDecision: "deny",
    reason: "[hook-name] Blocked: reason here\n\nUse alternative approach..."
  }));
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

| Value  | Duration | Use Case             |
| ------ | -------- | -------------------- |
| 5000   | 5s       | Simple validation    |
| 15000  | 15s      | Git operations       |
| 30000  | 30s      | Network calls        |

**Common mistake**: Using `15` instead of `15000` results in 15ms timeout.

## Hook Installation

Hooks defined in plugin `hooks.json` must be synced to `~/.claude/settings.json`:

```bash
# Via plugin's manage-hooks.sh
./plugins/my-plugin/scripts/manage-hooks.sh install

# Via global sync script (post-release)
./scripts/sync-hooks-to-settings.sh
```

## Testing Hooks

```bash
# Test hook with sample input
echo '{"tool_name": "Bash", "tool_input": {"command": "gh issue create --body test"}}' | \
  bun plugins/gh-tools/hooks/gh-issue-body-file-guard.mjs
```

## Plugins with Hooks

| Plugin                 | Hooks                                | Purpose                      |
| ---------------------- | ------------------------------------ | ---------------------------- |
| `itp-hooks`            | PreToolUse (3), PostToolUse (2)      | Workflow enforcement         |
| `ralph`                | PreToolUse (2), Stop (1)             | Autonomous loop control      |
| `git-account-validator`| PreToolUse (2)                       | Multi-account isolation      |
| `gh-tools`             | PreToolUse (2)                       | GitHub CLI enforcement       |
| `dotfiles-tools`       | PostToolUse (1), Stop (1)            | Chezmoi sync reminder        |
| `statusline-tools`     | Stop (1)                             | Session metrics              |
| `link-tools`           | Stop (1)                             | Link validation              |

## Related ADRs

- [PreToolUse/PostToolUse Architecture](/docs/adr/2025-12-06-pretooluse-posttooluse-hooks.md)
- [Hook Visibility Issue](/docs/adr/2025-12-17-posttooluse-hook-visibility.md)
- [ITP Hooks Settings Installer](/docs/adr/2025-12-07-itp-hooks-settings-installer.md)

## Reference Implementation

See [lifecycle-reference.md](/plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md) for detailed hook development patterns.
