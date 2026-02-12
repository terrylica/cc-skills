# Claude Code + Pueue Integration Patterns

Patterns for using pueue as a telemetry and orchestration layer within Claude Code sessions.

## Background Task Execution

Queue a task, continue working, poll results later:

```bash
# Queue and capture task ID
TASK_ID=$(pueue add --print-task-id -w ~/project -- python train_model.py)
echo "Queued as task $TASK_ID"

# ... continue other work ...

# Check status via JSON (structured for AI consumption)
pueue status --json | jq ".tasks[\"$TASK_ID\"]"

# Get results when done
pueue log "$TASK_ID" --full
```

## Synchronous Wrapper Pattern

Claude Code expects synchronous stdout. This pattern wraps pueue to behave synchronously while capturing telemetry:

```bash
TASK_ID=$(pueue add --print-task-id -w "$(pwd)" -- <original-command>) && \
  pueue wait "$TASK_ID" --quiet && \
  pueue log "$TASK_ID" --full
```

**What you get**: The command runs through pueue (timing, exit code, log persistence, env snapshot) but stdout/stderr flows back to Claude Code as if the command ran directly.

## Structured Monitoring via JSON

`pueue status --json` returns structured data ideal for AI agent consumption:

```bash
# All tasks with full metadata
pueue status --json | jq '.tasks | to_entries[] | {
  id: .key,
  command: .value.command,
  status: .value.status,
  group: .value.group,
  label: .value.label
}'

# Filter by group
pueue status --json | jq '[.tasks | to_entries[] | select(.value.group == "mygroup")]'

# Count by status
pueue status --json | jq '.tasks | to_entries | group_by(.value.status | keys[0]) | map({status: .[0].value.status | keys[0], count: length})'
```

## Callback as Completion Signal

Use a sentinel file pattern for scripts that need to react to task completion:

```yaml
# In pueue.yml
daemon:
  callback: "echo '{{id}}:{{result}}:{{exit_code}}' >> /tmp/pueue-completions.log"
```

Then poll the sentinel:

```bash
# Wait for specific task ID to appear in completions
while ! grep -q "^${TASK_ID}:" /tmp/pueue-completions.log 2>/dev/null; do
  sleep 1
done
RESULT=$(grep "^${TASK_ID}:" /tmp/pueue-completions.log | cut -d: -f2)
```

**Note**: `pueue wait` is simpler for most cases. Use callbacks when you need to react asynchronously or trigger external systems.

## Batch Test/Build Orchestration

Run tests or builds across multiple packages using groups and DAGs:

```bash
# Create group with parallelism limit
pueue group add tests --parallel 4

# Queue test suite
for pkg in pkg-a pkg-b pkg-c pkg-d pkg-e; do
  pueue add --group tests --label "test:$pkg" -w ~/project \
    -- uv run pytest "packages/$pkg/tests/" -x
done

# Wait for all tests
pueue wait --group tests

# Check results
pueue status --json | jq '[.tasks | to_entries[] |
  select(.value.group == "tests") |
  {label: .value.label, result: .value.status.Done.result}]'
```

### Build DAG with `--after`

```bash
# Build dependencies first, then dependents
BUILD_A=$(pueue add --print-task-id --group build -- make -C lib-a)
BUILD_B=$(pueue add --print-task-id --group build -- make -C lib-b)

# App depends on both libs
pueue add --group build --after "$BUILD_A" "$BUILD_B" \
  --label "build:app" -- make -C app
```

## PreToolUse Hook Auto-Wrapping

The `pretooluse-pueue-wrap-guard.ts` hook (in `itp-hooks`) silently rewrites non-trivial Bash commands to run through pueue. This provides invisible telemetry — Claude Code operates normally while every non-trivial command gets timing, logs, and exit code capture.

### How It Works

1. Claude Code generates a bash command (e.g., `python train.py`)
2. The PreToolUse hook intercepts the command before execution
3. If non-trivial, it rewrites to the synchronous wrapper pattern
4. Claude Code sees stdout/stderr as if the command ran directly
5. Pueue captures full telemetry in the background

### Skip Tier (No Wrapping)

Read-only commands, pueue commands, interactive commands, and very short commands pass through without wrapping.

### Escape Hatch

Add `# PUEUE-SKIP` comment to any command to bypass auto-wrapping:

```bash
python populate_cache.py --phase 1  # PUEUE-SKIP
```

## Telemetry Query Patterns

After accumulating tasks, query the telemetry:

```bash
# Average runtime by label prefix
pueue status --json | jq '
  [.tasks | to_entries[] |
   select(.value.status.Done) |
   {label: .value.label,
    duration_s: ((.value.status.Done.end | split(".")[0] | fromdate) -
                 (.value.start | split(".")[0] | fromdate))}] |
  group_by(.label | split(":")[0]) |
  map({prefix: .[0].label | split(":")[0],
       avg_s: (map(.duration_s) | add / length),
       count: length})'

# Failed tasks with exit codes
pueue status --json | jq '[.tasks | to_entries[] |
  select(.value.status.Done.result != "Success") |
  {id: .key, label: .value.label, result: .value.status.Done.result}]'
```
