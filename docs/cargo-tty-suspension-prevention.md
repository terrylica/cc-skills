# Cargo TTY Suspension Prevention Hook

## Problem Statement

When running cargo commands with backgrounding (`&`) inside Claude Code interactive shell, the session immediately suspends with:

```
[2]  + 50212 suspended (tty input)  css
```

This blocks Claude Code from continuing and requires manual `fg` to resume.

## Root Cause Analysis

**Technical mechanism**:

1. Cargo spawns child processes (benchmarks, test runners, build systems)
2. These subprocesses **inherit stdin** from the Claude Code parent process
3. When backgrounded with `&`, the OS detects TTY contention
4. SIGSTOP signal suspends the entire Claude Code process
5. Claude Code can't recover because it's frozen

**Affected commands**:

- `cargo bench --bench <name> &`
- `cargo test -p <pkg> &`
- `cargo build --release &`
- `cargo run --example <name> &`
- `cargo check &`

**Related GitHub Issues**:

- [#11898](https://github.com/anthropics/claude-code/issues/11898): TTY suspension on iTerm2
- [#12507](https://github.com/anthropics/claude-code/issues/12507): Subprocess stdin inheritance
- [#13598](https://github.com/anthropics/claude-code/issues/13598): Spurious /dev/tty reader

## Solution Architecture

### Hook: `pretooluse-cargo-tty-guard.ts`

**Location**: `~/eon/cc-skills/plugins/itp-hooks/hooks/pretooluse-cargo-tty-guard.ts`

**Type**: PreToolUse hook (runs before Bash execution)

**Mechanism**:

```
User types: cargo bench &
              ↓
Hook intercepts (PreToolUse)
              ↓
Pattern match: cargo + unsafe backgrounding?
              ↓
YES → Redirect to PUEUE daemon
         (process-isolated, no stdin inheritance)
         Result: ✅ No TTY suspension
              ↓
NO  → Allow command to pass through
```

### Protection Layers

| Layer                    | Mechanism                      | Handles                         |
| ------------------------ | ------------------------------ | ------------------------------- |
| **1. PUEUE Daemon**      | Spawn in separate process tree | Eliminates stdin inheritance    |
| **2. Nohup Fallback**    | `nohup cmd </dev/null`         | Backup if PUEUE unavailable     |
| **3. Escape Hatches**    | Comments in command            | User override when needed       |
| **4. Pattern Detection** | Allowlist of cargo commands    | Only target known problem cases |

## Behavior Matrix

| Command                          | Detection          | Action            | Result                  |
| -------------------------------- | ------------------ | ----------------- | ----------------------- |
| `cargo bench &`                  | ✅ Unsafe          | Redirect to PUEUE | ✅ Safe (no suspension) |
| `cargo test &`                   | ✅ Unsafe          | Redirect to PUEUE | ✅ Safe                 |
| `cargo bench`                    | ✗ Safe             | Allow             | ✅ Pass through         |
| `nohup cargo bench &`            | ✗ Already detached | Allow             | ✅ Already safe         |
| `cargo bench </dev/null &`       | ✗ Already detached | Allow             | ✅ Already safe         |
| `cargo bench & # CARGO-TTY-SKIP` | ✓ Opt-out          | Allow             | ✅ User override        |
| `cargo bench # CARGO-TTY-WRAP`   | ✓ Opt-in           | PUEUE wrapper     | ✅ Force protection     |

## Hook Implementation Details

### PUEUE Integration

The hook automatically queues cargo commands to the PUEUE daemon for process isolation:

```bash
# What happens internally:
TASK_ID=$(pueue add --print-task-id -w '/cwd' -- cargo bench 2>/dev/null | tail -1)
pueue wait "$TASK_ID" --quiet 2>/dev/null
pueue log "$TASK_ID" 2>/dev/null  # Show output (cleaner than --full)
```

**Key design points**:

- Uses PUEUE's `--print-task-id` for reliable task tracking
- Suppresses STDERR logging (`2>/dev/null`) for cleaner output
- Extracts task ID with `tail -1` (simpler than regex)
- Waits for task completion synchronously before returning
- Falls back to `nohup` if PUEUE daemon unavailable

### Task Observability

When a cargo command is queued:

```
🛡️  Cargo TTY Guard: Redirecting cargo command to PUEUE daemon
ℹ️  PUEUE task 42 queued
✓ PUEUE task 42 completed
[actual cargo output...]
```

User can manually track task progress:

```bash
pueue log 42              # View task output
pueue status              # View all queued tasks
pueue follow 42           # Stream task output in real-time
```

### Fallback Behavior

If PUEUE daemon is not running:

```bash
⚠️  PUEUE unavailable, falling back to nohup
   Output saved to: /tmp/cargo-tty-12345.log
```

The command still completes safely with output logged to a temporary file for debugging.

## Installation & Deployment

### Prerequisites

```bash
# 1. Ensure PUEUE is installed
brew install pueue          # or: cargo install pueue

# 2. Start PUEUE daemon (one-time setup)
pueue start

# 3. Verify daemon running
pueue status                # Should show: Running ✓
```

### Deployment Steps

```bash
# 1. Navigate to hook directory
cd ~/eon/cc-skills/plugins/itp-hooks/hooks

# 2. Hook already created:
#    - pretooluse-cargo-tty-guard.ts (main hook)
#    - pretooluse-cargo-tty-guard.test.ts (unit tests)

# 3. Verify registration in hooks.json
grep -A 3 "pretooluse-cargo-tty-guard" hooks.json
# Should show the hook in PreToolUse section

# 4. Run tests
bun test pretooluse-cargo-tty-guard.test.ts
# Expected: 15 pass, 0 fail

# 5. Sync hook to Claude Code
# (Automatic when plugin is installed/updated)
```

### Activation in Claude Code

The hook activates automatically once the plugin is loaded:

```bash
# In Claude Code shell:
/plugin list                    # Verify itp-hooks is installed
/hooks                          # View all hooks

# The hook appears as:
# PreToolUse: pretooluse-cargo-tty-guard.ts (Bash)
```

## Usage & Escape Hatches

### Standard Usage (Automatic Protection)

```bash
# ❌ Before: Would suspend Claude Code
cargo bench --bench rangebar_bench &

# ✅ After: Automatically redirected to PUEUE
# Console output:
# 🛡️  Cargo TTY Guard: Redirecting cargo command to PUEUE daemon
#    (Prevents TTY suspension from subprocess stdin conflicts)
# ✓ PUEUE task 42 completed
```

### Disable Protection (Opt-Out)

```bash
# If you want to skip the guard for a specific command:
cargo bench & # CARGO-TTY-SKIP

# Console: Command passes through unchanged
```

### Force Protection (Opt-In)

```bash
# Force PUEUE wrapping even without &:
cargo bench # CARGO-TTY-WRAP

# Console: Redirected to PUEUE daemon
```

### Manual PUEUE Usage

```bash
# Queue a cargo command manually
pueue add cargo bench --bench rangebar_bench

# Monitor execution
pueue status                    # List all queued jobs
pueue follow <task-id>          # Stream output
pueue log <task-id>             # View full log
```

## Testing & Validation

### Unit Tests (15 tests)

```bash
cd ~/eon/cc-skills/plugins/itp-hooks/hooks
bun test pretooluse-cargo-tty-guard.test.ts
```

**Coverage**:

- ✅ Pattern matching (unsafe, safe, edge cases)
- ✅ Escape hatches (skip, force wrap)
- ✅ Integration scenarios (complex flags, paths)
- ✅ Hook I/O format validation

**Result**: 15 pass, 0 fail

### Empirical Validation (6 tests)

```bash
# Automated hook execution tests
bash /tmp/test-cargo-hook.sh

# Tests:
# 1. Unsafe cargo bench → PUEUE redirect ✅
# 2. Safe cargo bench → Pass through ✅
# 3. Skip comment honored ✅
# 4. Force wrap comment honored ✅
# 5. Already detached (nohup) → No modification ✅
# 6. Non-Bash tool → Pass through ✅
```

**Result**: 6 pass, 0 fail

## Troubleshooting

### Issue: Hook not running

```bash
# Check if hook is registered
grep pretooluse-cargo-tty-guard ~/.claude/settings.json

# Check if plugin is installed
claude plugin list | grep itp-hooks

# Restart Claude Code:
# Exit and reopen terminal
```

### Issue: PUEUE daemon not running

```bash
# Start daemon
pueue start

# Verify
pueue status                    # Should show: Running ✓

# If it fails to start, check logs
pueue log
```

### Issue: Command still suspended

```bash
# Verify hook output
# Run with debug shell:
set -x
cargo bench &

# Should see:
# 🛡️  Cargo TTY Guard: Redirecting...

# If not showing, hook may be disabled
/hooks                          # Check status
```

### Issue: PUEUE queue full or stuck

```bash
# View queue status
pueue status

# Clear failed/finished tasks
pueue clean

# Reset queue if needed
pueue reset                     # ⚠️ Dangerous: clears all tasks
```

## Performance Impact

| Metric                 | Impact     | Notes                                               |
| ---------------------- | ---------- | --------------------------------------------------- |
| **Hook latency**       | <100ms     | Pattern matching only                               |
| **Memory overhead**    | <1MB       | PUEUE daemon background                             |
| **CPU overhead**       | Negligible | No polling, event-driven                            |
| **Benchmark accuracy** | None       | Benchmarks run in isolated process (same execution) |

## FAQ

**Q: Does PUEUE affect benchmark results?**
A: No. Benchmarks run in PUEUE with same environment and compile flags as direct execution.

**Q: Can I disable the hook globally?**
A: Yes, but not recommended. Per-command override via `# CARGO-TTY-SKIP` is safer.

**Q: What if I accidentally kill the PUEUE daemon?**
A: Hook automatically falls back to `nohup` wrapper. Commands continue working.

**Q: Can I use this with other long-running commands?**
A: Hook is cargo-specific. For other commands, use the general `pretooluse-pueue-wrap-guard.ts`.

**Q: Does this work in non-interactive Claude Code?**
A: Not applicable — suspension only occurs in interactive shell mode.

## Architecture Diagram

```
Claude Code Shell (TTY-safe)
│
├─ Hook: pretooluse-cargo-tty-guard.ts
│  ├─ Pattern match: cargo bench &?
│  ├─ YES → Wrap with PUEUE
│  └─ NO  → Allow pass-through
│
├─ PUEUE Daemon Process (isolated)
│  ├─ cargo bench (no stdin inheritance)
│  ├─ cargo test
│  └─ cargo build
│
└─ Result: Claude Code stays interactive ✅
   No TTY suspension, no SIGSTOP
```

## References

- **Hook**: `~/eon/cc-skills/plugins/itp-hooks/hooks/pretooluse-cargo-tty-guard.ts`
- **Tests**: `~/eon/cc-skills/plugins/itp-hooks/hooks/pretooluse-cargo-tty-guard.test.ts`
- **Registration**: `~/eon/cc-skills/plugins/itp-hooks/hooks/hooks.json`
- **PUEUE Docs**: <https://github.com/Nukesor/pueue>
- **GitHub Issues**: #11898, #12507, #13598
