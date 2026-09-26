# Lock Debugging -- The Two TTS Locks

Deep dive into the lock files the text-to-speech scripts use. Until 2026-09-26 this page also described a Telegram bot (`kokoro-client.ts`) sharing the lock; that bot was retired on 2026-09-24 and nothing outside the scripts below takes these locks any more.

---

## Overview

Two lock files with confusingly similar names guard two different paths:

| Lock                   | Taken by                                                                                  | Mechanism                                       | Purpose                                |
| ---------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------------- | -------------------------------------- |
| `/tmp/tts_kokoro.lock` | `tts_kokoro.sh` (the Kokoro path via the companion)                                       | `shlock -f … -p $$`, released by EXIT trap      | Queue: one companion request at a time |
| `/tmp/kokoro-tts.lock` | `tts_read_clipboard.sh` (Supertonic) and `tts-common.sh` users (`tts_kokoro_audition.sh`) | PID written to the file, heartbeat, stale check | Mutual exclusion for local playback    |

`tts_stop.sh` removes **both**. It used to clear only the first, which left a Supertonic run speaking and made the next press wait out the 30s staleness timer.

---

## `/tmp/tts_kokoro.lock` — the request queue

Each `tts_kokoro.sh` invocation loops on `shlock` every 0.3s until it owns the lock, then posts one `/tts/speak` request and holds the lock until the request returns. Consecutive presses therefore play in order; only `tts_stop.sh` preempts (it kills queued `tts_kokoro.sh` processes, removes the lock and posts `/tts/stop` to the companion).

There is no heartbeat: the lock's mtime is its creation time, so an age over 30s during a long utterance is normal. `shlock` itself detects a lock whose PID is dead.

---

## `/tmp/kokoro-tts.lock` — two-layer protocol

### Layer 1: Lock File Mtime Freshness (Heartbeat)

The holder writes its PID and, when it uses `tts-common.sh`, starts a background heartbeat that `touch`es the lock every 5 seconds:

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

### Layer 2: Active Audio Process Check (Defense-in-Depth)

Before breaking a lock whose mtime is older than 30s, `tts_read_clipboard.sh`'s `acquire_lock` checks whether `afplay` is still running. It only removes the lock when **both** hold:

1. Lock mtime is stale (no update for 30s = heartbeat died)
2. No `afplay` process is running (no active audio)

It also force-replaces a lock held by a previous `tts_read_clipboard` instance (a double-tapped key), and force-breaks any lock after 60 polls (about 30s) of waiting. `tts_read_clipboard.sh` writes its PID but runs no heartbeat, so for its own runs Layer 2 is what prevents overlap.

---

## Stale Detection Logic

```
Lock exists?
  |
  No --> Proceed (no contention)
  |
  Yes --> Held by a previous tts_read_clipboard? --> Kill it, take the lock
           |
           Check mtime
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

```bash
# Do the locks exist, and who holds them?
for f in /tmp/tts_kokoro.lock /tmp/kokoro-tts.lock; do
  if [ -f "$f" ]; then
    pid=$(cat "$f")
    age=$(( $(date +%s) - $(stat -f %m "$f") ))
    if kill -0 "$pid" 2>/dev/null; then
      echo "$f held by live PID $pid (age ${age}s): $(ps -o command= -p "$pid")"
    else
      echo "$f held by DEAD PID $pid (age ${age}s) — orphaned"
    fi
  else
    echo "$f absent"
  fi
done

# Is audio playing?
pgrep -la afplay || echo "No afplay"
```

---

## Common Lock Scenarios

### Scenario 1: Normal Operation

```
Press → tts_kokoro.sh takes /tmp/tts_kokoro.lock → companion speaks → request returns → lock released
```

A second press during playback waits in the `shlock` loop, then plays. No intervention needed.

### Scenario 2: Orphaned Lock (Heartbeat Died)

```
Local run crashes → lock left behind (and its heartbeat, if any, dies) → mtime goes stale → no afplay running
```

Both layers confirm it is safe; the next press removes it after 30s. Immediate fix: `tts_stop.sh`.

### Scenario 3: Stale Lock But Audio Still Playing

```
Script crashes → heartbeat dies → lock mtime stale → BUT afplay is still playing the last chunk
```

Layer 1 says "stale" but Layer 2 says "audio active", so the next press waits. This is correct behavior — removing the lock would cause overlap. Wait for `afplay` to finish, or `tts_stop.sh` to cut it off.

---

## Configuration

| Parameter          | Location                                              | Default                | Purpose                               |
| ------------------ | ----------------------------------------------------- | ---------------------- | ------------------------------------- |
| Local lock path    | `tts-common.sh` (`TTS_LOCK`), `tts_read_clipboard.sh` | `/tmp/kokoro-tts.lock` | Local playback lock                   |
| Queue lock path    | `tts_kokoro.sh`                                       | `/tmp/tts_kokoro.lock` | Companion request queue               |
| Heartbeat interval | `tts-common.sh`                                       | 5 seconds              | How often the holder touches the lock |
| Stale threshold    | `tts_read_clipboard.sh`                               | 30 seconds             | When to consider the lock abandoned   |
| Poll interval      | `tts_read_clipboard.sh` / `tts_kokoro.sh`             | 0.5s / 0.3s            | How often a waiter re-checks          |

---

## Key Source Files

| File                            | Role                                                       |
| ------------------------------- | ---------------------------------------------------------- |
| `scripts/lib/tts-common.sh`     | `acquire_tts_lock()` / `release_tts_lock()` with heartbeat |
| `scripts/tts_read_clipboard.sh` | `acquire_lock()` with the two-layer stale check            |
| `scripts/tts_kokoro.sh`         | `shlock` request queue                                     |
| `scripts/tts_stop.sh`           | Clears both locks and cancels the companion queue          |
