# statusline-tools Plugin

> Custom status line with git status indicators.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Siblings**: [itp-hooks](../itp-hooks/CLAUDE.md) | [asciinema-tools](../asciinema-tools/CLAUDE.md) | [link-tools](../link-tools/CLAUDE.md)

## Skills

- [tether](./skills/tether/SKILL.md) — renamed from `hooks` to avoid `/hooks` clash
- [ignore](./skills/ignore/SKILL.md)
- [session-info](./skills/session-info/SKILL.md)
- [setup](./skills/setup/SKILL.md)

## Commands

| Command                    | Purpose                      |
| -------------------------- | ---------------------------- |
| `/statusline-tools:setup`  | Configure statusline         |
| `/statusline-tools:ignore` | Manage ignore patterns       |
| `/statusline-tools:tether` | Manage link validation hooks |

## Hooks

| Hook                  | Trigger                              | Purpose                                   |
| --------------------- | ------------------------------------ | ----------------------------------------- |
| `cron-tracker.ts`     | PostToolUse (CronCreate/Delete/List) | Tracks active cron jobs in session state  |
| `stop-cron-gc.ts`     | Stop                                 | Prunes stale cron entries on session exit |
| `lychee-stop-hook.sh` | Stop (installed via manage-hooks.sh) | Link validation on session exit           |

## Status Line Indicators

| Indicator       | Meaning                                            |
| --------------- | -------------------------------------------------- |
| M/D/S/U         | Modified, Deleted, Staged, Untracked files         |
| ↑/↓             | Commits ahead/behind remote                        |
| ≡               | Stash count                                        |
| ⚠               | Merge conflicts                                    |
| Σ &lt;n&gt; LOC | Total lines of code (via `scc`, all tracked files) |
| cx &lt;n&gt;    | Cyclomatic complexity (yellow when ≥ 1k)           |
| MD/TS/Py …      | Top 3 languages by code share (% of total LOC)     |
| ~$&lt;n&gt;     | COCOMO basic-organic cost estimate (informational) |

## Code Statistics Line

Layout: `Σ <LOC> · <files> files · cx <complexity> · <top3 langs %> · ~$<cost> COCOMO`

Implementation: `scc --format=json2` piped through `jq` for compact formatting.
Runs on every render — no cache (selected for freshness 2026-04-26). Bounded by
1s timeout so pathologically large repos drop the line silently rather than
hang the statusline. Skipped when `scc` is not installed or cwd is not a git
work tree.

Cost on cc-skills repo: ~70ms cold (scc with complexity) + ~20ms jq = ~100ms
incremental over the pre-existing 1.1s baseline.

Dependency: `brew install scc` (Go binary, single-shot — no daemon).

## Optional: ccmax-monitor Integration

The status line includes an optional integration with [ccmax-monitor](https://github.com/terrylica/ccmax-monitor), a **private internal fleet system** for managing multi-account Claude Code Max subscriptions. This integration is **not required** and gracefully degrades — public users without ccmax-monitor see no change.

### What it shows

When ccmax-monitor is running locally, the datetime line gains:

```
2026-05-09 17:25 PDT | usalchemist 42% 1d 22h [device:soft]
                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                       account  5h-used  7d-reset  scope-mode-badge
```

| Element                                | Source                                                      | Meaning                                   |
| -------------------------------------- | ----------------------------------------------------------- | ----------------------------------------- |
| Account email prefix                   | `GET localhost:18095/api/status` (cached 60s)               | Which fleet account is active on this Mac |
| `42%`                                  | Same API response                                           | 5-hour quota utilization                  |
| `1d 22h`                               | Same API response                                           | Time until 7-day quota reset              |
| `[<scope>:<mode>]` (one of six values) | `ccmax_resolve_layered_pin` from ccmax-monitor's pin-helper | Pin scope+mode override (HEART-23 v2)     |
| `[5th-fleet]`                          | Bearer-key `account_mode` pin or injected bearer env        | Fifth-fleet Anthropic-compatible API path |

### Pin scope+mode badge (HEART-23 v2)

`custom-statusline.sh` resolves the layered pin via ccmax-monitor's helper at `~/.claude/plugins/marketplaces/ccmax/hooks/pin-helper.sh`. The helper walks three scopes (highest → lowest precedence):

1. `~/.config/ccmax/pin-by-session/<session-uuid>.toml` — session scope (auto-pruned at 24h JSONL staleness)
2. `~/.config/ccmax/pin-by-repo/<md5-prefix-8>.toml` — repo scope (cwd path → MD5 → 8-hex prefix)
3. `~/.config/ccmax/pin.toml` — device scope (the original HEART-23 location)

The first hit wins; the badge shows WHICH scope is winning and its mode. **No badge** = following fleet rotation.

If the winning pin has `account_mode = "bearer_key_anthropic_compatible_api_mode"`, the statusline shows the pinned account name directly, for example `el02-doorward-bearer-api-1 [repo:soft] [5th-fleet]`, and skips OAuth quota windows because the fifth-fleet bearer path is served by cc-router/sub2api rather than a Claude Max subscription account.

| Badge                     | Meaning                                                                          |
| ------------------------- | -------------------------------------------------------------------------------- |
| _(none)_                  | Following fleet rotation (default)                                               |
| `[session:soft]` (yellow) | Session-scoped pin; auto-fallback to next layer when pinned account is unhealthy |
| `[session:strict]` (red)  | Session-scoped pin; honored regardless of health                                 |
| `[repo:soft]` (yellow)    | Repo-scoped pin; auto-fallback when unhealthy                                    |
| `[repo:strict]` (red)     | Repo-scoped pin; honored regardless                                              |
| `[device:soft]` (yellow)  | Device-scoped pin (replaces the legacy `[soft]` rendering); auto-fallback        |
| `[device:strict]` (red)   | Device-scoped pin (replaces the legacy `[strict]` rendering); honored regardless |

**Backwards compat for older ccmax-monitor installs**: if `pin-helper.sh` is missing at the marketplace path (older release OR no ccmax-monitor at all), the statusline falls back to a tiny inline awk parser that reads only the device-scope file and renders `[device:<mode>]`. Public cc-skills users without ccmax-monitor see no badge (the file doesn't exist).

**Performance**: the layered helper uses awk single-pass parsing (~2 ms per resolve including 3 file checks) versus the prior python+tomllib path (~17 ms). On every statusline render the savings are imperceptible to the user but eliminate a recurring Python interpreter startup.

### Graceful degradation

If ccmax-monitor is not running (`localhost:18095` unreachable), `curl` times out in 1–2 seconds and the entire ccmax section is silently omitted. The status line continues to work normally. The 60-second cache (`/tmp/ccmax-statusline-cache.json`) means one tunnel drop doesn't immediately blank the display.

### Scope

This integration is internal to the `terrylica` fleet. Public cc-skills users will never have `localhost:18095` listening, so the block is effectively a no-op — the `curl` silently fails and nothing appears.

## Antifragile Network Probes — the `probe_direct` invariant

**Invariant**: every outbound network call in `custom-statusline.sh` (any `gh api`, `gh release`, `gh auth`, or `curl`) MUST be wrapped with the `probe_direct` helper. Enforced by the bats test _"every outbound gh/curl call in custom-statusline.sh is wrapped with probe_direct"_ — adding an unwrapped call fails CI.

**Call pattern**:

```bash
release_out=$(probe_direct timeout 2 gh release view --repo "$owner_repo" ...)
vis_out=$(probe_direct timeout 2 gh api "repos/${owner_repo}" ...)
ccmax_raw=$(probe_direct curl -sf --connect-timeout 1 --max-time 2 "${CCMAX_BASE}/api/status" ...)
```

`probe_direct` goes **first**, before `timeout`/`gh`/`curl`. Inverting the order (`timeout 2 probe_direct gh ...`) silently fails because `timeout` is an external coreutils binary and cannot resolve shell functions — you'd get `"No such file or directory"` for `probe_direct` itself.

**What it does**: strips `HTTPS_PROXY`, `HTTP_PROXY`, `ALL_PROXY` (and their lowercase variants) from the subprocess env using `env -u`. `NO_PROXY` is left intact (defensive whitelist, harmless).

**Why this exists**: discovered 2026-05-12 when ccmax-claude's bearer-pin CONNECT proxy on `127.0.0.1:<random-port>` started 502'ing every CONNECT target it doesn't intercept — including `api.github.com`. Every child process of ccmax-claude (including this statusline) inherits `HTTPS_PROXY=http://127.0.0.1:<port>`, so without the guard `gh api` 502s, the `(?)` visibility badge permanently replaces `(private)`/`(public)`, and `gh release view` permanently surfaces `⌁ offline` even though the real network is fine.

**The statusline is a diagnostic instrument** — it must be a faithful mirror of system state, not a victim of whatever proxy state the host imposes on it. Probes go direct; the proxy is irrelevant to whether the badge is correct.

**Pinned by three bats tests** (`tests/test_statusline.bats`):

| Test                                                                               | What it catches                                                  |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `probe_direct strips HTTPS_PROXY/HTTP_PROXY/ALL_PROXY from subprocess`             | Helper definition regresses (e.g. someone removes a `-u` flag)   |
| `every outbound gh/curl call in custom-statusline.sh is wrapped with probe_direct` | New unwrapped probe call added                                   |
| `statusline survives broken HTTPS_PROXY in env (antifragile)`                      | End-to-end: poisoned proxy in env still produces a correct badge |
