# Model-Upgrade Detection — `mise run minimax:check-upgrade`

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/model-upgrade-detection.md` (source-of-truth — read-only, source iter-41). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-11).

**Endpoint**: `GET /v1/models`
**Tooling delivered**: 2026-04-29 (iter-41, T4.4)
**Source**: [`bin/minimax-check-upgrade`](../../bin/minimax-check-upgrade) + [`.mise/tasks/minimax/check-upgrade`](../../.mise/tasks/minimax/check-upgrade)

## Why this exists

MiniMax ships new model variants with no notification: M2.7-highspeed appeared one day; iter-1 captured the catalog snapshot on 2026-04-28; the next M2.x release will arrive without warning. amonic services that hard-code `MiniMax-M2.7-highspeed` need a tripwire — when MiniMax publishes M2.8 (or M3, or a new highspeed variant), we want to know FAST so the recommendation table in [`quirks/CLAUDE.md`](../quirks/CLAUDE.md) and the per-workload model selection rule in [`model-aliasing.md`](./model-aliasing.md) can be re-validated against the new model rather than silently drifting.

This is the OPS counterpart to the rest of this directory — most files document discovered behavior; this one continuously detects when re-discovery is needed.

## TL;DR

```bash
mise run minimax:check-upgrade            # human-readable diff
mise run minimax:check-upgrade --json     # structured JSON
mise run minimax:check-upgrade --update   # accept current live as new lock
```

Exit codes: `0` = no change, `1` = upgrade detected, `2` = fetch/parse error.

## Architecture

| Artifact                                                | Role                                                                   |
| ------------------------------------------------------- | ---------------------------------------------------------------------- |
| `minimax/api-patterns/fixtures/models-list-locked.json` | The frozen reference snapshot. Initialized from iter-1's catalog dump. |
| `bin/minimax-check-upgrade`                             | The actual logic — bash + inline Python for the diff.                  |
| `.mise/tasks/minimax/check-upgrade`                     | Thin mise wrapper. Adds `mise run minimax:check-upgrade` invocation.   |

The diff lives in Python (inline heredoc) for two reasons:

1. The diff has 3 categories (added / removed / modified) — `diff` or `jq` would need ~50 lines of awk to express the same logic
2. Python ships on every macOS install; no extra dependency

## What the diff detects

| Category   | When it fires                                                 | Common cause                                                |
| ---------- | ------------------------------------------------------------- | ----------------------------------------------------------- |
| `added`    | Live has a model id that's not in the lock                    | New model release (M2.8, M3, vision variant, new TTS model) |
| `removed`  | Lock has a model id that's not in live                        | Model deprecation (oldest M-series version EOL'd)           |
| `modified` | Same id, different metadata (`created`, `object`, `owned_by`) | Re-release with same name (rare; would be a notable signal) |

The script does NOT track ordering changes (the model array order is unstable across calls and not informative).

## Operational patterns

### One-shot manual check

```bash
mise run minimax:check-upgrade
```

Exit 0 ⇒ nothing to do. Exit 1 ⇒ inspect the diff, decide whether to re-run probes against the new model, and only then `mise run minimax:check-upgrade --update` to bless the new state as the lock.

**Don't blindly `--update`.** Whenever a new model lands, the rest of `api-patterns/` may be wrong about it. The whole point of the lock is to FORCE manual review at every catalog change.

### Daily polling via launchd (recommended)

A ready-to-install plist is shipped at [`config/plists/com.terryli.minimax-check-upgrade.plist`](../../config/plists/com.terryli.minimax-check-upgrade.plist) (the SSoT per the launchd spoke convention — never edit the symlinked copy under `~/Library/LaunchAgents/`).

```bash
# One-time install — symlink + bootstrap
ln -sf "$HOME/own/amonic/config/plists/com.terryli.minimax-check-upgrade.plist" \
       "$HOME/Library/LaunchAgents/com.terryli.minimax-check-upgrade.plist"
mkdir -p "$HOME/.local/state/launchd-logs/minimax-check-upgrade"
launchctl bootstrap "gui/$(id -u)" \
    "$HOME/Library/LaunchAgents/com.terryli.minimax-check-upgrade.plist"

# Verify scheduling
launchctl print "gui/$(id -u)/com.terryli.minimax-check-upgrade" | head -20

# Manual fire (test it works once before relying on the schedule)
launchctl kickstart "gui/$(id -u)/com.terryli.minimax-check-upgrade"
tail -f "$HOME/.local/state/launchd-logs/minimax-check-upgrade/stdout.log"
```

The plist runs daily at 09:00 local time and logs to `~/.local/state/launchd-logs/minimax-check-upgrade/{stdout,stderr}.log`. Exit 1 (upgrade detected) shows up as the diff in stdout — combine with a separate log-tailer or notification hook to surface alerts.

**Secret-handling caveat for launchd context**: the script calls `op read` to fetch the API key from 1Password. In a launchd-spawned shell, `op` may not have a valid SA session and may prompt for re-auth — defeating unattended scheduling. Two mitigations:

1. **Pre-cache the API key** to a mode-600 file once, then modify the script to prefer the file over `op read` (5-line addition; see Open follow-ups).
2. **Run as a foreground task on user-active sessions only**: leave `RunAtLoad=false` (default), let the user's interactive `op signin` cache the session via OP*SESSION*\*, and the 09:00 schedule fires while the user is logged in.

For amonic's current single-user workstation context, option 2 is fine. Production deployments (bigblack daemon, CI runners) should use option 1.

Combine with `bin/lib/notify.sh` or the existing notification hook to alert on exit 1.

### CI / cron-equivalent on bigblack

For remote scheduling, a systemd timer or cron job invoking the same script works fine:

```cron
0 9 * * * /Users/terryli/own/amonic/bin/minimax-check-upgrade >> /var/log/minimax-check-upgrade.log 2>&1
```

The script is idempotent and stateless apart from the lock file — no concurrency concerns.

### CI gate (forced refresh)

If a release pipeline wants to refuse merges when the model catalog has changed without explicit lock update:

```bash
mise run minimax:check-upgrade
# exit 0 = no drift, proceed
# exit 1 = catalog drifted, fail the gate; require an explicit commit bumping the lock
```

This is a stronger guarantee than periodic polling — it forces human review BEFORE any new code lands when MiniMax has shipped a new model.

## Test coverage

The script was end-to-end tested in iter-41 against 5 scenarios:

| Scenario                                       | Expected exit | Result |
| ---------------------------------------------- | ------------- | ------ |
| Lock matches live                              | 0             | ✅     |
| Lock has modified `created` timestamp          | 1             | ✅     |
| Lock has fake added model + missing real model | 1             | ✅     |
| `--update` flag overwrites lock                | 0             | ✅     |
| `--json` mode emits structured JSON            | 0             | ✅     |

The tests deliberately corrupt the lock; production usage should never modify the lock except via `--update`.

## Bug history (educational)

The first draft of this script used bash command substitution to capture Python's output:

```bash
DIFF_OUTPUT=$(python3 - "$LOCKED_SNAPSHOT" "$LIVE_BODY" <<'PYEOF'
...
sys.exit(1 if has_changes else 0)
PYEOF
)
PYTHON_EXIT=$?
echo "$DIFF_OUTPUT"
```

When changes were detected, Python exited 1 inside the substitution. With `set -euo pipefail` on, the substitution's non-zero exit triggered errexit, killing the script BEFORE `echo "$DIFF_OUTPUT"` ran. Symptom: exit code 1 was correct but no diff text reached stdout.

Fix: don't capture; let Python write directly to stdout, gated by `set +e` / `set -e`:

```bash
set +e
python3 - "$LOCKED_SNAPSHOT" "$LIVE_BODY" <<'PYEOF'
...
PYEOF
PYTHON_EXIT=$?
set -e
```

This is the canonical bash idiom for "I want this command's stdout AND exit code, and a non-zero exit is OK." The `var=$(cmd)` pattern is fine when you don't care about exit code OR when `set -e` isn't on.

## Caveats

- **API key dependency**: requires `op read` to fetch the MiniMax API key from 1Password. If `op` isn't configured (different machine, expired session), the script exits 2.
- **Rate limit**: `/v1/models` is a free check (no token cost) but counts against the same RPM bucket as chat-completion. Don't poll faster than once per minute.
- **No retry on transient failure**: a single 5xx from MiniMax exits 2 immediately. For production scheduling, wrap in a retry loop (3 attempts × exponential backoff).
- **Lock format is brittle**: the diff is an exact JSON-equality check on each model dict. If MiniMax adds a new field to the model object (e.g., `description`, `context_window`), every existing model will appear MODIFIED on the next check. Treat this as a feature — that's exactly the kind of change worth being alerted to.

## Related

- iter-1 [`models-endpoint.md`](./models-endpoint.md) — the original `/v1/models` characterization that produced the locked snapshot
- iter-13 [`vision-image-url.md`](./vision-image-url.md) — vision NOT supported on M2.7; a new model with vision would be the most decision-relevant upgrade
- iter-15 [`audio-tts.md`](./audio-tts.md) — TTS endpoint has its OWN model namespace (6 plan-gated speech models). T4.4 only watches chat models; a parallel `/v1/t2a_v2` model upgrade detector is a future extension
- iter-28 [`model-aliasing.md`](./model-aliasing.md) — plain M2.7 vs highspeed are distinct deployments, not aliases. A new highspeed variant would need iter-28 cross-over re-measurement
