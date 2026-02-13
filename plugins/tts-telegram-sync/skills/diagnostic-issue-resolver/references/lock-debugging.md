# Lock Debugging -- Two-Layer Lock Mechanism

Deep dive into the TTS lock protocol shared between shell scripts and the Telegram bot.

---

## Overview

The TTS system uses a shared lock file at `/tmp/kokoro-tts.lock` to prevent audio overlap between:

- Shell scripts (tts_kokoro.sh, tts_read_clipboard.sh, etc.)
- Telegram bot (kokoro-client.ts)

Both writers and both readers use the same two-layer protocol.

---

## Two-Layer Lock Protocol

### Layer 1: Lock File Mtime Freshness (Heartbeat)

The lock holder writes its PID to the lock file and starts a background heartbeat that `touch`es the lock every 5 seconds.

**Shell scripts** (via `tts-common.sh`):

```bash
acquire_tts_lock() {
    echo "$$" > "$TTS_LOCK"
    # Background heartbeat: touch lock every 5s while parent is alive
    (
        while kill -0 $$ 2>/dev/null; do
            touch "$TTS_LOCK" 2>/dev/null || true
            sleep 5
        done
    ) &
    _TTS_HEARTBEAT_PID=$!
}
```

**Bot** (via `kokoro-client.ts`):

```typescript
function acquireTtsLock(): () => void {
  fs.writeFileSync(TTS_LOCK_FILE, String(process.pid));
  return () => {
    fs.unlinkSync(TTS_LOCK_FILE);
  };
}
```

Note: The bot does NOT run a heartbeat because its lock duration is bounded by the `afplay` subprocess -- it acquires before `afplay` and releases immediately after.

### Layer 2: Active Audio Process Check (Defense-in-Depth)

Even if the lock mtime is stale (>30s), the system checks whether an audio process (`afplay` or `say`) is actually running before removing the lock.

**Bot** (via `waitForTtsLock()` in `kokoro-client.ts`):

```typescript
// Only removes lock if BOTH:
// 1. Lock mtime is stale (no update for 30s = heartbeat died)
// 2. No afplay/say process is running (no active audio)
```

This prevents a race where:

- Script A is playing audio via `afplay`
- Script A's heartbeat process died (orphaned lock)
- Bot sees stale lock and removes it
- Bot starts its own `afplay`, causing overlap

With Layer 2, the bot sees `afplay` is still running and waits.

---

## Stale Detection Logic

A lock is considered **stale** when:

1. Lock file exists
2. Lock mtime is older than 30 seconds (no heartbeat update)
3. No `afplay` or `say` process is running

If all three conditions are met, the lock is safe to remove.

```
Lock exists?
  |
  No --> Proceed (no contention)
  |
  Yes --> Check mtime
           |
           Fresh (<30s) --> Wait and re-check
           |
           Stale (>30s) --> Check audio processes
                             |
                             Running --> Wait (Layer 2 safety)
                             |
                             Not running --> Remove lock, proceed
```

---

## Diagnostic Commands

### Check Lock State

```bash
# Does the lock exist?
ls -la /tmp/kokoro-tts.lock 2>/dev/null || echo "No lock file"

# What PID holds it?
cat /tmp/kokoro-tts.lock 2>/dev/null || echo "No lock"

# When was it last touched (heartbeat)?
stat -f "Last modified: %Sm" /tmp/kokoro-tts.lock 2>/dev/null

# How old is it in seconds?
if [ -f /tmp/kokoro-tts.lock ]; then
  lock_mtime=$(stat -f %m /tmp/kokoro-tts.lock)
  now=$(date +%s)
  echo "Lock age: $(( now - lock_mtime )) seconds"
fi
```

### Check Audio Processes

```bash
# Is afplay running?
pgrep -la afplay || echo "No afplay"

# Is say running?
pgrep -la say || echo "No say"
```

### Check Lock Holder

```bash
# Is the PID in the lock file still alive?
if [ -f /tmp/kokoro-tts.lock ]; then
  lock_pid=$(cat /tmp/kokoro-tts.lock)
  if kill -0 "$lock_pid" 2>/dev/null; then
    echo "Lock holder PID $lock_pid is alive"
    ps -p "$lock_pid" -o pid,command
  else
    echo "Lock holder PID $lock_pid is DEAD (orphaned lock)"
  fi
fi
```

---

## Common Lock Scenarios

### Scenario 1: Normal Operation

```
Shell script starts -> acquires lock -> heartbeat every 5s -> plays audio -> releases lock
```

Lock mtime stays fresh. Other TTS requests wait. No intervention needed.

### Scenario 2: Orphaned Lock (Heartbeat Died)

```
Shell script crashes -> heartbeat subprocess dies -> lock mtime goes stale -> no afplay running
```

Both Layer 1 (stale mtime) and Layer 2 (no audio) confirm it is safe to remove. The bot's `waitForTtsLock()` handles this automatically after 30s.

Manual fix: `rm -f /tmp/kokoro-tts.lock`

### Scenario 3: Stale Lock But Audio Still Playing

```
Shell script crashes -> heartbeat dies -> lock mtime stale -> BUT afplay is still playing the last chunk
```

Layer 1 says "stale" but Layer 2 says "audio active". The bot waits. This is correct behavior -- removing the lock would cause audio overlap.

Manual: Do NOT remove the lock. Wait for `afplay` to finish, then the bot will clean up.

### Scenario 4: Lock Race Between Bot and Shell

```
Bot checks: no lock -> Bot creates lock -> Shell checks: lock exists -> Shell waits
```

This is the normal mutual exclusion path. The 500ms poll interval in `waitForTtsLock()` means worst-case audio gap between bot and shell is ~500ms.

---

## Configuration

| Parameter          | Location                             | Default                | Purpose                                |
| ------------------ | ------------------------------------ | ---------------------- | -------------------------------------- |
| Lock file path     | `tts-common.sh` / `kokoro-client.ts` | `/tmp/kokoro-tts.lock` | Shared lock location                   |
| Heartbeat interval | `tts-common.sh`                      | 5 seconds              | How often shell scripts touch the lock |
| Stale threshold    | `kokoro-client.ts`                   | 30 seconds             | When to consider lock abandoned        |
| Poll interval      | `kokoro-client.ts`                   | 500ms                  | How often bot re-checks the lock       |

---

## Key Source Files

| File                                                                 | Role                                                         |
| -------------------------------------------------------------------- | ------------------------------------------------------------ |
| `scripts/lib/tts-common.sh`                                          | `acquire_tts_lock()` / `release_tts_lock()` with heartbeat   |
| `~/.claude/automation/claude-telegram-sync/src/tts/kokoro-client.ts` | `waitForTtsLock()` / `acquireTtsLock()` with two-layer check |
