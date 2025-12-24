## Lifecycle Diagrams

### 1. Main Session Lifecycle

```
┌──────────────────┐
│   SessionStart   │
└──────────────────┘
  │
  │
  ∨
┌──────────────────┐
│ UserPromptSubmit │ <┐
└──────────────────┘  │
  │                   │
  │                   │
  ∨                   │
┌──────────────────┐  │
│    PreCompact    │  │
└──────────────────┘  │
  │                   │
  │                   │ new prompt
  ∨                   │
┌──────────────────┐  │
│    Tool Loop     │  │
└──────────────────┘  │
  │                   │
  │                   │
  ∨                   │
┌──────────────────┐  │
│       Stop       │ ─┘
└──────────────────┘
  │
  │
  ∨
┌──────────────────┐
│    SessionEnd    │
└──────────────────┘
```

**Hook Details:**

- **SessionStart** — Matchers: `startup|resume|clear|compact`. Cannot block. Outputs: `additionalContext`, `CLAUDE_ENV_FILE`
- **UserPromptSubmit** — CAN BLOCK (exit 2 or `decision:block`). Inputs: `prompt`, `cwd`, `session_id`
- **PreCompact** — Fires if context full OR `/compact`. Cannot block. Matchers: `manual|auto`. Fires BEFORE summarization
- **Tool Loop** — See Diagram 2 for details. May repeat multiple times per response
- **Stop** — CAN BLOCK (`decision:block` + reason). `stop_hook_active` prevents infinite loops
- **SessionEnd** — Reasons: `clear|logout|prompt_input_exit|other`. Cannot block

```{=latex}
\newpage
```

### 2. Tool Execution Loop

```
                 more tools    ┌───────────────────┐
  ┌──────────────────────────> │    PreToolUse     │ <┐
  │                            └───────────────────┘  │
  │                              │                    │
  │                              │                    │
  │                              ∨                    │
  │                            ┌───────────────────┐  │
  │                            │ PermissionRequest │  │
  │                            └───────────────────┘  │
  │                              │                    │
  │                              │                    │ more tools
  │                              ∨                    │
┌──────────────┐               ┌───────────────────┐  │
│ SubagentStop │ <──────────── │   Tool Executes   │  │
└──────────────┘               └───────────────────┘  │
  │                              │                    │
  │                              │                    │
  ∨                              ∨                    │
┌──────────────┐               ┌───────────────────┐  │
│     Stop     │ <──────────── │    PostToolUse    │ ─┘
└──────────────┘               └───────────────────┘
```

**Hook Details:**

- **PreToolUse** — CAN BLOCK. Output `permissionDecision`: `allow|deny|ask`. Can provide `updatedInput` to modify tool parameters
- **PermissionRequest** — CAN BLOCK. Output `behavior`: `allow|deny`. Skipped if PreToolUse already allowed
- **Tool Executes** — The actual tool runs (Bash, Edit, Read, Write, MCP tools)
- **SubagentStop** — CAN BLOCK. Task tool only. Validates subagent completion
- **PostToolUse** — CAN BLOCK (soft). Tool already ran; `decision:block` prompts Claude to reconsider

### 3. Blocking vs Non-Blocking Hooks

**CAN BLOCK** — These hooks can prevent or modify execution:

| Hook              | Block Type | Mechanism                           | Effect                                                |
| ----------------- | ---------- | ----------------------------------- | ----------------------------------------------------- |
| UserPromptSubmit  | Hard       | exit 2 OR `decision:block`          | Erases prompt, shows reason to user                   |
| PreToolUse        | Hard       | exit 2 OR `permissionDecision:deny` | Prevents execution, reason fed to Claude              |
| PermissionRequest | Hard       | `behavior:deny`                     | Rejects permission, optional interrupt flag           |
| PostToolUse       | Soft       | `decision:block` + reason           | Tool already ran; prompts Claude to reconsider        |
| SubagentStop      | Hard       | `decision:block` + reason           | Forces subagent to continue working                   |
| Stop              | Hard       | `decision:block` + reason           | Forces Claude to continue (check `stop_hook_active`!) |

**CANNOT BLOCK** — These hooks are informational only:

| Hook         | Purpose                                         |
| ------------ | ----------------------------------------------- |
| SessionStart | Inject context, set env vars, run setup scripts |
| PreCompact   | Backup transcripts before summarization         |
| Notification | Desktop/Slack/Discord alerts (parallel event)   |
| SessionEnd   | Cleanup, logging, archive transcripts           |

```{=latex}
\newpage
```

### 4. Parallel Events (Notification)

```
┌──────────────┐     ┌────────────┐
│  Main Flow   │ ──> │ Sequential │
└──────────────┘     └────────────┘
┌──────────────┐     ┌────────────┐
│ Notification │ ──> │  Parallel  │
└──────────────┘     └────────────┘
```

**Key Points:**

- **Main Flow** runs sequentially: SessionStart → UserPromptSubmit → PreCompact → Tools → Stop → SessionEnd
- **Notification** fires independently when Claude Code sends system notifications
- Not part of main execution flow; can fire at any time during session

**Notification Matchers:**

- `permission_prompt` — Permission dialog shown
- `idle_prompt` — Claude waiting for input
- `auth_success` — Authentication completed
- `elicitation_dialog` — Additional info requested

### 5. Universal Control (All Hooks)

Every hook can output these fields:

| Field                  | Effect                                          |
| ---------------------- | ----------------------------------------------- |
| `continue: false`      | Halts Claude entirely (overrides all decisions) |
| `stopReason: "..."`    | Message shown to user when `continue=false`     |
| `suppressOutput: true` | Hide stdout from transcript                     |
| `systemMessage: "..."` | Warning shown to user                           |

```{=latex}
\newpage
\begin{landscape}
```

## Lifecycle Behavior Details

### Blocking Mechanisms

| Hook                  | Hard Block                          | Soft Block                | Effect                                              |
| --------------------- | ----------------------------------- | ------------------------- | --------------------------------------------------- |
| **UserPromptSubmit**  | Exit 2 OR `decision:block`          | —                         | Erases prompt, shows reason to user only            |
| **PreToolUse**        | Exit 2 OR `permissionDecision:deny` | `permissionDecision:ask`  | Prevents tool execution, reason fed to Claude       |
| **PermissionRequest** | `behavior:deny`                     | —                         | Rejects permission, optional interrupt flag         |
| **PostToolUse**       | —                                   | `decision:block` + reason | Tool already ran; prompts Claude to reconsider      |
| **SubagentStop**      | `decision:block` + reason           | —                         | Forces subagent to continue working                 |
| **Stop**              | `decision:block` + reason           | —                         | Forces Claude to continue (check stop_hook_active!) |

### Universal Control (All Hooks)

- **`continue: false`** — Halts Claude entirely (overrides all other decisions)
- **`stopReason`** — Message shown to user when continue=false
- **`suppressOutput: true`** — Hide stdout from transcript
- **`systemMessage`** — Warning shown to user

### Key Flows Explained

**1. Tool Execution Loop**

- PreToolUse → PermissionRequest → Tool → PostToolUse repeats for EACH tool call
- Claude may call multiple tools in one response
- PreToolUse can skip PermissionRequest with `permissionDecision:allow`

**2. Prompt Loop**

- After Stop, user submits new prompt → cycle restarts at UserPromptSubmit
- Stop hook with `decision:block` forces continuation without new prompt

**3. Conditional Hooks**

- **PermissionRequest**: Only fires if permission dialog would be shown (skipped if PreToolUse allows or tool is pre-approved)
- **SubagentStop**: Only fires for Task tool sub-agents, not Bash/Edit/Read/Write
- **PreCompact**: Fires when context is full (auto) OR user runs /compact (manual)

**4. Parallel Events**

- **Notification**: Fires independently when Claude Code sends system notifications
- Not part of main execution flow; can fire at any time during session

**5. Loop Prevention**

- `stop_hook_active: true` in Stop/SubagentStop input means hook already triggered continuation
- MUST check this to prevent infinite loops when using `decision:block`

```{=latex}
\end{landscape}
\newpage
\begin{landscape}
```

## Hook Events Reference

### Overview

| Event                 | When It Fires                                       | Blocks? | Matchers                                                                 |
| --------------------- | --------------------------------------------------- | ------- | ------------------------------------------------------------------------ |
| **SessionStart**      | Session begins (new, `--resume`, `/clear`, compact) | No      | `startup`, `resume`, `clear`, `compact`                                  |
| **UserPromptSubmit**  | User presses Enter, BEFORE Claude processes         | **Yes** | None (all prompts)                                                       |
| **PreToolUse**        | After Claude creates tool params, BEFORE execution  | **Yes** | Tool names: `Task`, `Bash`, `Read`, `Write`, `Edit`, `mcp__*`            |
| **PermissionRequest** | Permission dialog about to show                     | **Yes** | Same as PreToolUse                                                       |
| **PostToolUse**       | After tool completes successfully                   | **Yes** | Same as PreToolUse                                                       |
| **Notification**      | System notification sent                            | No      | `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog` |
| **SubagentStop**      | Task sub-agent finishes                             | **Yes** | None (global)                                                            |
| **Stop**              | Main agent finishes (not on interrupt)              | **Yes** | None (global)                                                            |
| **PreCompact**        | Before context summarization                        | No      | `manual`, `auto`                                                         |
| **SessionEnd**        | Session terminates                                  | No      | None (global)                                                            |

### Input & Output Details

| Event                 | Key Inputs                                             | Output Capabilities                                                                              |
| --------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| **SessionStart**      | `session_id`, `source`, `transcript_path`              | `additionalContext`; `CLAUDE_ENV_FILE` for env vars                                              |
| **UserPromptSubmit**  | `prompt`, `cwd`, `session_id`                          | `{"decision": "block"}` to reject; `{"additionalContext": "..."}` to inject; Exit 2 = hard block |
| **PreToolUse**        | `tool_name`, `tool_input`, `tool_use_id`               | `permissionDecision`: `allow`/`deny`/`ask`; `updatedInput` to modify params                      |
| **PermissionRequest** | `tool_name`, `tool_input`, `tool_use_id`               | `decision.behavior`: `allow`/`deny`; `updatedInput`; `message`                                   |
| **PostToolUse**       | `tool_name`, `tool_input`, `tool_response`             | `{"decision": "block", "reason": "..."}` prompts reconsideration                                 |
| **Notification**      | `message`, `notification_type`                         | stdout in verbose mode (Ctrl+O)                                                                  |
| **SubagentStop**      | `transcript_path`, `stop_hook_active`                  | `{"decision": "block", "reason": "..."}` forces continuation                                     |
| **Stop**              | `transcript_path`, `stop_hook_active`                  | `{"decision": "block"}` continues; `{"continue": false}` stops                                   |
| **PreCompact**        | `trigger`, `custom_instructions`                       | stdout in verbose mode                                                                           |
| **SessionEnd**        | `reason`: `clear`/`logout`/`prompt_input_exit`/`other` | Debug log only                                                                                   |

```{=latex}
\end{landscape}
\newpage
```

## Use Cases by Hook Event

| Hook                  | Use Case              | Description                                                 |
| --------------------- | --------------------- | ----------------------------------------------------------- |
| **SessionStart**      | Context loading       | Load git status, branch info, recent commits into context   |
|                       | Task injection        | Inject TODO lists, sprint priorities, GitHub issues         |
|                       | Setup scripts         | Install dependencies or run setup on session begin          |
|                       | Environment vars      | Set variables via `$CLAUDE_ENV_FILE` for persistence        |
|                       | Dynamic config        | Load project-specific CLAUDE.md or context files            |
|                       | Telemetry             | Initialize logging or telemetry for the session             |
|                       | Multi-account tokens  | Validate GH_TOKEN matches expected account for directory    |
|                       | Session tracking      | Track session start for duration/correlation reporting      |
| · · · · · · · · · · · | · · · · · · · · · · · | · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·   |
| **UserPromptSubmit**  | Audit logging         | Log timestamps, session IDs, prompt content for compliance  |
|                       | Security filtering    | Detect and block sensitive patterns (API keys, passwords)   |
|                       | Context injection     | Append git branch, recent changes, sprint goals to prompts  |
|                       | Policy validation     | Validate prompts against team policies or coding standards  |
|                       | Keyword blocking      | Block forbidden keywords or dangerous instructions          |
|                       | Ralph Wiggum          | Inject reminders about testing or documentation             |
|                       | Prompt capture        | Cache prompt text + timestamp for Stop hook session summary |
| · · · · · · · · · · · | · · · · · · · · · · · | · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·   |
| **PreToolUse**        | Destructive blocking  | Block `rm -rf`, `git push --force`, `DROP TABLE`            |
|                       | File protection       | Prevent access to `.env`, `.git/`, `credentials.json`       |
|                       | Parameter validation  | Validate paths, check file existence before execution       |
|                       | Sandboxing            | Add `--dry-run` flags to dangerous commands                 |
|                       | Input modification    | Fix paths, inject linter configs, add safety flags          |
|                       | Auto-approve          | Reduce permission prompts for safe operations               |
|                       | Lock file protection  | Block writes to `package-lock.json`, `uv.lock`              |
|                       | Multi-account git     | Validate SSH auth matches expected GitHub account           |
|                       | HTTPS URL blocking    | Block git push with HTTPS (require SSH for multi-account)   |
|                       | ASCII art policy      | Block manual diagrams; require graph-easy source block      |
| · · · · · · · · · · · | · · · · · · · · · · · | · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·   |
| **PermissionRequest** | Auto-approve safe     | Auto-approve `npm test`, `pytest`, `cargo build`            |
|                       | Auto-deny dangerous   | Deny dangerous operations without user prompt               |
|                       | Command modification  | Inject flags, change parameters before approval             |
|                       | Team policies         | Implement team-specific permission policies                 |
|                       | Fatigue reduction     | Auto-approve known-safe tool patterns                       |
|                       | Audit trails          | Log all permission decisions                                |
| · · · · · · · · · · · | · · · · · · · · · · · | · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·   |
| **PostToolUse**       | Auto-format           | Run `prettier`, `black`, `gofmt` after edits                |
|                       | Lint checking         | Run `ruff check`, `eslint --fix`, `cargo clippy`            |
|                       | File validation       | Validate write success and file integrity                   |
|                       | Transcript conversion | Convert JSONL transcripts to readable JSON                  |
|                       | Task reminders        | Remind about related tasks when files modified              |
|                       | CI triggers           | Trigger CI checks or pre-commit hooks                       |
|                       | Output logging        | Log all tool outputs for debugging/compliance               |
|                       | Markdown pipeline     | markdownlint (MD058 table blanks) + prettier for .md files  |
|                       | Dotfiles sync         | Detect chezmoi-tracked files; remind to sync                |
|                       | ADR-Spec sync         | Remind to update Design Spec when ADR modified (and v.v.)   |
|                       | Graph-easy reminder   | Prompt to use skill instead of CLI for reproducibility      |
| · · · · · · · · · · · | · · · · · · · · · · · | · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·   |
| **Notification**      | Desktop alerts        | `osascript` (macOS) or `notify-send` (Linux)                |
|                       | Chat webhooks         | Slack/Discord/Teams integration for remote alerts           |
|                       | Sound alerts          | Custom sounds when Claude needs attention                   |
|                       | Email                 | Email notifications for long-running tasks                  |
|                       | Mobile push           | Pushover or similar for mobile notifications                |
|                       | Analytics             | Log notification events for analytics                       |
| · · · · · · · · · · · | · · · · · · · · · · · | · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·   |
| **SubagentStop**      | Task validation       | Validate sub-agents completed full assigned task            |
|                       | TTS announcements     | Announce completion via text-to-speech                      |
|                       | Performance logging   | Log task results and duration                               |
|                       | Force continuation    | Continue if output incomplete or fails validation           |
|                       | Task chaining         | Chain additional sub-agent tasks based on results           |
| · · · · · · · · · · · | · · · · · · · · · · · | · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·   |
| **Stop**              | Premature prevention  | Block if tests failing or task incomplete                   |
|                       | Test suites           | Run `npm test`, `pytest`, `cargo test` on every stop        |
|                       | AI summaries          | Generate completion summaries with TTS playback             |
|                       | Ralph Wiggum          | Force Claude to verify task completion                      |
|                       | Validation gates      | Ensure code compiles, lints pass, tests succeed             |
|                       | Auto-commits          | Create git commits or PR drafts when work completes         |
|                       | Team notifications    | Send completion notifications to channels                   |
|                       | Link validation       | Lychee check on modified .md files; block if broken         |
|                       | Session summary       | Generate JSON summary: git status, duration, workflows      |
|                       | Background validation | Full workspace link scan (async, non-blocking)              |
| · · · · · · · · · · · | · · · · · · · · · · · | · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·   |
| **PreCompact**        | Transcript backups    | Create backups before context compression                   |
|                       | History preservation  | Preserve conversation to external storage                   |
|                       | Event logging         | Log compaction with timestamp and trigger type              |
|                       | Context extraction    | Save important context before summarization                 |
|                       | User notification     | Notify user that context is about to be compacted           |
| · · · · · · · · · · · | · · · · · · · · · · · | · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·   |
| **SessionEnd**        | Temp cleanup          | Cleanup temporary files, caches, artifacts                  |
|                       | Session stats         | Log duration, tool calls, tokens used                       |
|                       | State saving          | Save session state for potential resume                     |
|                       | Analytics             | Send session summary to analytics service                   |
|                       | Transcript archive    | Archive transcripts to long-term storage                    |
|                       | Environment reset     | Reset env vars or undo session-specific changes             |

```{=latex}
\newpage
```

## Configuration Reference

### Settings Priority

1. `.claude/settings.local.json` — Project local (highest priority)
2. `.claude/settings.json` — Project-wide
3. `~/.claude/settings.json` — User-wide (lowest priority)

### Exit Codes

- **0** — Success/allow (JSON output processed)
- **2** — Hard block, cannot bypass (stderr only)
- **Other** — Non-blocking error

### Environment Variables

- `CLAUDE_PROJECT_DIR` — Project root (available in all hooks)
- `CLAUDE_CODE_REMOTE` — `"true"` if running in web mode (all hooks)
- `CLAUDE_ENV_FILE` — Env var persistence file (SessionStart only)

### Hook Types

**Command Hook** — Deterministic, fast, full control:

```json
{ "type": "command", "command": "/path/to/script.py", "timeout": 60 }
```

**Prompt Hook** — LLM-evaluated via Haiku, context-aware:

```json
{ "type": "prompt", "prompt": "Check if task is complete", "timeout": 30 }
```

### MCP Tool Naming

- **Pattern**: `mcp__<server>__<tool>`
- **Examples**: `mcp__memory__create_entities`, `mcp__filesystem__read_file`
- **Matchers**: `"mcp__memory__.*"`, `"mcp__.*__write.*"`

### Blocking Output Format

**PreToolUse/PermissionRequest**:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "...",
    "permissionDecision": "allow|deny|ask"
  }
}
```

**Stop/SubagentStop**:

```json
{ "decision": "block", "reason": "..." }
```

### Loop Prevention

When `stop_hook_active` is `true` in Stop/SubagentStop, a hook is already active. Check the transcript to prevent infinite loops.

### Stop Hook Schema (Critical - Verified 2025-12-18)

**CORRECT schema based on live testing:**

| Intent               | Correct Output                             | Wrong Output                              |
| -------------------- | ------------------------------------------ | ----------------------------------------- |
| **Allow stop**       | `{}` (empty object)                        | ~~`{"continue": false}`~~                 |
| **Continue session** | `{"decision": "block", "reason": "..."}`   | ~~`{"continue": true, "reason": "..."}`~~ |
| **Hard stop**        | `{"continue": false, "stopReason": "..."}` | (same)                                    |

**Key insight**: `{"continue": false}` means "HARD STOP Claude entirely" - it does NOT mean "allow normal stop". Using it incorrectly causes the confusing message:

```
Stop hook prevented continuation
```

This message appears because `continue: false` is an **active intervention** to halt Claude, not a passive "allow stop".

**Helper pattern for clarity:**

```python
def allow_stop(reason: str | None = None):
    """Allow session to stop normally."""
    print(json.dumps({}))  # Empty object = allow stop

def continue_session(reason: str):
    """Prevent stop and continue session."""
    print(json.dumps({"decision": "block", "reason": reason}))

def hard_stop(reason: str):
    """Hard stop Claude entirely (overrides everything)."""
    print(json.dumps({"continue": False, "stopReason": reason}))
```

### Common Pitfalls

| Pitfall                    | Problem                            | Solution                                                                                      |
| -------------------------- | ---------------------------------- | --------------------------------------------------------------------------------------------- |
| **Session-locked hooks**   | Hook changes don't take effect     | Hooks snapshot at session start. Run `/hooks` to apply pending changes OR restart Claude Code |
| **Script not executable**  | Hook silently fails                | Run `chmod +x script.sh` on all hook scripts                                                  |
| **Non-zero exit codes**    | Hook blocks Claude unexpectedly    | Ensure scripts return 0 on success; non-zero = error                                          |
| **Missing file matchers**  | Hook doesn't trigger on edits      | Use `Edit\|MultiEdit\|Write` to catch ALL file modifications                                  |
| **Case sensitivity**       | Matcher doesn't match              | Matchers are case-sensitive: `Bash` ≠ `bash`                                                  |
| **Relative paths**         | Script not found                   | Use `$CLAUDE_PROJECT_DIR` or absolute paths                                                   |
| **Timeout too short**      | Hook killed mid-execution          | Default is 60s; increase for slow operations                                                  |
| **JSON syntax errors**     | All hooks fail to load             | Validate with `cat settings.json \| python -m json.tool`                                      |
| **Stop hook wrong schema** | "Stop hook prevented continuation" | Use `{}` to allow stop, NOT `{"continue": false}` (see Stop Hook Schema above)                |
| **Local symlink caching**  | Edits to source not picked up      | Release new version, `/plugin install`, restart Claude Code (see Plugin Cache section below)  |

```{=latex}
\newpage
```

## Plugin Cache and Symlink Resolution (Lesson Learned 2025-12-21)

### Plugin Cache Structure

Plugins are stored in `~/.claude/plugins/cache/<marketplace>/<plugin-name>/`:

```
~/.claude/plugins/cache/cc-skills/ralph/
├── 5.15.0/              # Released version (immutable)
│   ├── commands/
│   └── hooks/
├── 5.16.0/              # Newer released version
│   ├── commands/
│   └── hooks/
└── local -> /path/to/source/repo/plugins/ralph   # Development symlink
```

### Critical Insight: Version vs Content Resolution

**Claude Code resolves version and content DIFFERENTLY:**

| What                | Resolution Source      | Example                            |
| ------------------- | ---------------------- | ---------------------------------- |
| **Version display** | `local` symlink first  | Banner shows `v5.15.0 (local)`     |
| **Skill content**   | VERSION DIRECTORY only | Executes code from `5.15.0/` cache |

**The local symlink is for version detection, NOT skill execution.**

This means:

- Editing source files does NOT affect running sessions
- Version banner shows `(local)` but code comes from version cache
- Your fix appears to be "in" but isn't being used

### Symptom: Fix Not Applied

```
========================================
  RALPH WIGGUM v5.15.0 (local)        <-- Version from local symlink
========================================

Adapter: universal                     <-- OLD CODE from 5.15.0 cache!
```

Even though the source file has the fix, Claude Code reads skill content from the cached version directory.

### Correct Update Workflow

1. **Edit source file** - `plugins/ralph/commands/start.md`
2. **Commit and push** - `git add . && git commit -m "fix: ..." && git push`
3. **Release new version** - `npm run release` (creates v5.16.0)
4. **Remove local symlink** (optional) - `rm ~/.claude/plugins/cache/cc-skills/ralph/local`
5. **Reinstall plugin** - `/plugin install cc-skills`
6. **Restart Claude Code** - Exit (Ctrl+C) and run `claude` again
7. **Verify** - Banner shows `v5.16.0 (cache)` not `(local)`

### Why Remove the Local Symlink?

The local symlink can cause confusing behavior:

| Symlink State | Version Banner    | Content Source | Confusion Level   |
| ------------- | ----------------- | -------------- | ----------------- |
| Present       | `v5.15.0 (local)` | `5.15.0/`      | HIGH - misleading |
| Removed       | `v5.16.0 (cache)` | `5.16.0/`      | LOW - accurate    |

When developing, the local symlink is useful for **version detection**. But for testing fixes, remove it to ensure you're using the released version.

### zsh Compatibility: Heredoc Wrapper Required

Skill markdown code blocks must use bash heredoc wrapper for zsh compatibility:

**Correct (works in zsh):**

```bash
/usr/bin/env bash << 'SCRIPT_NAME'
if [[ "$VAR" != "value" ]]; then
    echo "bash-specific syntax works"
fi
SCRIPT_NAME
```

**Incorrect (fails in zsh):**

```bash
/usr/bin/env bash << 'LIFECYCLE_REFERENCE_SCRIPT_EOF'
# Without heredoc, zsh interprets directly
if [[ "$VAR" != "value" ]]; then  # ERROR: condition expected: \!=
    echo "fails"
fi
LIFECYCLE_REFERENCE_SCRIPT_EOF
```

**Error signature:** `(eval):91: condition expected: \!=`

This happens when Claude Code strips the heredoc wrapper and zsh tries to interpret bash-specific `!=` in `[[ ]]`.

**Fix:** Always wrap skill bash code in heredoc per [ADR: Shell Command Portability](https://github.com/terrylica/cc-skills/blob/main/docs/adr/2025-12-06-shell-command-portability-zsh.md)

### Diagnostic Commands

```bash
# Check symlink status
ls -la ~/.claude/plugins/cache/cc-skills/<plugin>/local

# Verify version content
grep -A5 "PATTERN" ~/.claude/plugins/cache/cc-skills/<plugin>/<version>/commands/file.md

# Compare local vs version
diff <(cat ~/.../local/commands/file.md | grep "PATTERN") \
     <(cat ~/.../5.16.0/commands/file.md | grep "PATTERN")

# Remove local symlink for clean testing
rm ~/.claude/plugins/cache/cc-skills/<plugin>/local
```

### Quick Reference: Fix Not Working Checklist

- [ ] Fix is in source file? (`grep` the source)
- [ ] Fix is committed and pushed? (`git status`)
- [ ] New version released? (`git tag` shows new version)
- [ ] Local symlink removed? (`ls -la .../local`)
- [ ] Plugin reinstalled? (`/plugin install cc-skills`)
- [ ] Claude Code restarted? (Exit and re-enter)
- [ ] Banner shows new version + `(cache)`? (Not `(local)`)

### Debugging Techniques

| Technique                  | Command/Method                        | Use Case                                 |
| -------------------------- | ------------------------------------- | ---------------------------------------- |
| **Disable all hooks**      | `claude --no-hooks`                   | Recover from broken hook blocking Claude |
| **Interactive management** | `/hooks`                              | Review, edit, apply pending hook changes |
| **Capture hook input**     | `cat > /tmp/hook-input.json`          | Inspect JSON data passed to hooks        |
| **Check hook status**      | `/status`                             | View conversation stats and loaded hooks |
| **Validate JSON**          | `python -m json.tool < settings.json` | Find syntax errors in configuration      |
| **Test script manually**   | Run script in terminal                | Verify script works outside Claude       |
| **Check permissions**      | `ls -la script.sh`                    | Ensure executable bit is set             |

### Timeout Defaults

- **Command hooks**: 60 seconds (if not specified)
- **Prompt hooks**: 30 seconds (Haiku evaluation)
- **Recommended**: 180s for linting/testing operations

## Hook Configuration Example

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/validate-write.py",
            "timeout": 30
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Check if the task is truly complete. If not, explain what remains.",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

```{=latex}
\end{document}
```

---

## BUILD INSTRUCTIONS (Not printed in PDF)

This section is excluded from PDF output via `\end{document}` above.

### Required Files

All files must be in the same directory (`tmp/`):

1. `claude-code-hooks-lifecycle.md` — This source file
2. `header.tex` — LaTeX header for landscape pages
3. `table-spacing-template.tex` — Table row spacing

### header.tex

```latex
\usepackage{pdflscape}
```

### table-spacing-template.tex

```latex
\usepackage{array}
\renewcommand{\arraystretch}{1.3}
```

### Build Command

```bash
cd /Users/terryli/eon/alpha-forge/tmp

pandoc claude-code-hooks-lifecycle.md \
  -o claude-code-hooks-lifecycle.pdf \
  --pdf-engine=xelatex \
  -V documentclass=extarticle \
  -V geometry:margin=0.5in \
  -V mainfont="DejaVu Sans" \
  -V monofont="DejaVu Sans Mono" \
  -V fontsize=8pt \
  -H table-spacing-template.tex \
  -H header.tex
```

### Key Options Explained

| Option                          | Purpose                                                      |
| ------------------------------- | ------------------------------------------------------------ |
| `documentclass=extarticle`      | Enables 8pt font (standard article only supports 10/11/12pt) |
| `geometry:margin=0.5in`         | Narrow margins for more table space                          |
| `mainfont="DejaVu Sans"`        | Unicode support for box-drawing characters                   |
| `monofont="DejaVu Sans Mono"`   | Monospace font for code blocks                               |
| `fontsize=8pt`                  | Smaller font to fit wide tables                              |
| `-H header.tex`                 | Include pdflscape for landscape pages                        |
| `-H table-spacing-template.tex` | Increase table row spacing (1.3x)                            |

### Landscape Sections

Use these raw LaTeX blocks to switch orientation:

````markdown
```{=latex}
\begin{landscape}
```
````

... content in landscape ...

```{=latex}
\end{landscape}
```

````

### Page Breaks

```markdown
```{=latex}
\newpage
````

```

### Troubleshooting

| Issue | Solution |
| ----- | -------- |
| "File not found" for .tex | Ensure you're in the `tmp/` directory |
| 8pt font not working | Must use `documentclass=extarticle` |
| Box-drawing chars broken | Use DejaVu Sans fonts (has Unicode support) |
| Tables overlapping | Put section in `\begin{landscape}...\end{landscape}` |
| Section separators | Use `· · · · · · ·` rows between table sections |
```
