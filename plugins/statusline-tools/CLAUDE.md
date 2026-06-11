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

| Indicator                                   | Meaning                                                                                                                                                                                                                                                                              |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| M/D/S/U                                     | Modified, Deleted, Staged, Untracked files                                                                                                                                                                                                                                           |
| ↑/↓                                         | Commits ahead/behind remote                                                                                                                                                                                                                                                          |
| ≡                                           | Stash count                                                                                                                                                                                                                                                                          |
| ⚠                                           | Merge conflicts                                                                                                                                                                                                                                                                      |
| Σ &lt;n&gt; LOC                             | Total lines of code (via `scc`, all tracked files)                                                                                                                                                                                                                                   |
| `claude-…[1m]`                              | Model id from statusline stdin `.model.id` (falls back to `.model.display_name`), gray suffix on line 1                                                                                                                                                                              |
| effort:&lt;lvl&gt; / thinking:on·off / fast | Inference-mode badges from `.effort.level`, `.thinking.enabled`, `.fast_mode`                                                                                                                                                                                                        |
| ✦ ultracode                                 | **Heuristic** badge: `effort==xhigh AND thinking AND NOT fast_mode`. No native statusline field exists (binary-string forensics + live-payload audit, 2026-06-10); a manual `/effort xhigh` is indistinguishable. See render comment in `custom-statusline.sh` ("✦ ultracode badge") |
| cx &lt;n&gt;                                | Cyclomatic complexity (yellow when ≥ 1k)                                                                                                                                                                                                                                             |
| MD/TS/Py …                                  | Top 3 languages by code share (% of total LOC)                                                                                                                                                                                                                                       |
| ~$&lt;n&gt;                                 | COCOMO basic-organic cost estimate (informational)                                                                                                                                                                                                                                   |

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

## Optional: doorward gateway health integration

The statusline reads doorward (the cc-router admission gateway in front of sub2api on bigblack el02) on every render and surfaces gate health, rotation pool size, canary state, and local ccmax-claude wrapper version. This integration is **optional** — public cc-skills users without doorward/tailnet membership see graceful degradation (no curl reaches the endpoint, the entire segment is suppressed when no other ccmax signal exists).

> **What changed (2026-05-13):** the prior implementation read the legacy `localhost:18095/api/status` endpoint and rendered an OAuth account email + 5h/7d quota windows. Under the new architecture, the ccmax-claude PTY wrapper sets `ANTHROPIC_BASE_URL=https://bigblack.tail0f299b.ts.net:8450` and doorward picks from a rotation pool of OAuth accounts dynamically per-request. The local keychain's OAuth account is therefore no longer the credential that's actually being used, and the 5h/7d quota numbers describe a credential the user isn't consuming. We replaced both with the four signals below, which reflect the live pipeline.

### What it shows

When doorward is reachable, the datetime line gains:

```
Wed 13 May 2026 03:47 UTC | Tue 12 20:47 PDT | doorward 3/3 ✓ 1.93.0                          ← all healthy
Wed 13 May 2026 03:47 UTC | Tue 12 20:47 PDT | doorward 3/3 ✗AU 3d since-boot 1.93.0          ← today's actual state (config bug, gray)
Wed 13 May 2026 03:47 UTC | Tue 12 20:47 PDT | doorward 2/3 ⚠UP 3m flapping 1.93.0            ← one backend transient
Wed 13 May 2026 03:47 UTC | Tue 12 20:47 PDT | doorward 1/3 ⚠UP 12m partial-outage 1.93.0     ← last healthy account, pre-warn
Wed 13 May 2026 03:47 UTC | Tue 12 20:47 PDT | doorward 0/3 ✗UP 47m outage 1.93.0             ← total outage, alarm
Wed 13 May 2026 03:47 UTC | Tue 12 20:47 PDT | doorward 3/3 ✓ 1.2.0=1.2.0                      ← wrapper exactly at floor, pre-warn
Wed 13 May 2026 03:47 UTC | Tue 12 20:47 PDT | doorward unreachable 1.93.0                    ← gateway down
```

**L1d multi-dimensional unified render (2026-05-13).** Replaced the raw consecutive-failure-count (the prior `✗1090` "magic number") with a three-token composite — severity glyph + RFC-9457-style type code + humanized duration — plus an operator-facing state-name word that doubles as the playbook hint. The state-name maps to a clear action (`since-boot` → file an issue; `flapping` → watch; `partial-outage` → intervene; `outage` → page). The full source-of-truth legend for every visible token lives in `custom-statusline.sh` — search for "Doorward gateway summary — render LEGEND".

**Antecedent label-stripping rounds (all 2026-05-13):** (1) dropped the `pool`, `canary`, `wrapper` field labels — within a segment already anchored by `doorward`, the slash-fraction format is self-evidently a ratio, the `✗<type-code>` glyph is unambiguous, and a three-dot semver is visually distinct; (2) dropped the leading `🟢/🟡/🔴` gate-state emoji — every state the dot could signal was already expressed by per-token coloring + state-name word; (3) retired the `[5th-fleet]` bearer-mode badge — presence of the doorward block itself implies bearer-mode routing.

| Render token              | Source field (in `/v1/router-status`)                                                                   | Meaning (short)                                                                                                                                                                                                  |
| ------------------------- | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| _(no gate dot)_           | retired 2026-05-13 — formerly synthesised 🟢/🟡/🔴 from those four fields                               | State is now expressed entirely by per-token coloring (red ✗N, red pool ratio, red "unreachable", yellow version<floor)                                                                                          |
| `doorward`                | (anchor word, not a field)                                                                              | Names the subsystem so trailing numbers have context                                                                                                                                                             |
| `3/3`                     | `pool.schedulable_active_accounts` / (`schedulable_active_accounts` + `error_accounts`)                 | Rotation working-set ratio. Denominator EXCLUDES admin-inactive accounts (paused by operator intent, not failing). Red when any `error_accounts > 0`                                                             |
| `✓` / `✗AU 3d` / `⚠UP 3m` | `canary_self_test.last_observed_http_status_code` + `consecutive_failures` × `configured_interval_secs` | Canary outcome glyph + RFC 9457 type code + humanized failure duration when degraded (L1d render). The raw consecutive-failure count is logged to `~/.claude/doorward-state.jsonl` (L2 telemetry), not displayed |
| `1.92.0` / `<1.2.0`       | `ccmax-claude --version` vs `DOORWARD_MIN_WRAPPER_VERSION`                                              | Local wrapper version, with `<floor` suffix in yellow when below                                                                                                                                                 |
| _(no pin badge)_          | retired 2026-05-13 — formerly synthesised `[<scope>:<mode>]` from the layered-pin resolver              | Pin parsing still runs upstream to feed bearer-mode detection; only the badge rendering is dropped per operator directive                                                                                        |
| `unreachable`             | (synthesized when fetch fails and no usable cache)                                                      | Literal word in RED that replaces the numeric tokens — distinguishes "doorward genuinely down" from "got a response but couldn't parse"                                                                          |

#### Pool denominator semantics (why we don't show `pool 3/4`)

The doorward `/v1/router-status` response distinguishes three account states inside the rotation pool:

| State                                                   | Meaning                                                                                      | Counted in denominator? |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------------- | ----------------------- |
| `status: active` + `schedulable: true`                  | In the rotation, picking traffic                                                             | Yes (and in numerator)  |
| `status: active` + counted in `error_accounts`          | In the rotation, currently failing (transient: refresh chain dead, throttled, etc.)          | Yes                     |
| `status: inactive` (counted in `other_status_accounts`) | Administratively dormant by operator intent (account intentionally paused or de-provisioned) | **No**                  |

Including an admin-inactive account in the denominator would frame an operator-intended deactivation as a partial pool failure, which is exactly the wrong reading. Under the live fleet today (4 registered accounts, 1 administratively inactive, 3 active and schedulable), the correct render is `pool 3/3`, not `pool 3/4`.

### Data source

Only two doorward routes are wrapper-version-gate-exempt and therefore safe for an anonymous statusline curl to hit on every render:

| Route                   | Bypass decision header                                    | Used by statusline?                                      |
| ----------------------- | --------------------------------------------------------- | -------------------------------------------------------- |
| `GET /v1/health`        | `x-doorward-decision: health-probe-bypass`                | No (subset of `/v1/router-status`)                       |
| `GET /v1/router-status` | `x-doorward-decision: router-status-introspection-bypass` | **Yes** — superset response with pool breakdown + canary |

The latter is a superset of `/v1/health` (it includes everything from health plus `pool.per_account_summaries[]`), so one fetch covers all four signals. Doorward enforces a 30 s server-side TTL on this route; the statusline overlays a 60 s client-side cache at `/tmp/ccmax-doorward-cache.json` for two-window coverage with headroom. On fetch failure the cache is read stale rather than going dark.

Every other doorward route (`/v1/messages`, `/api/v1/keys/info`, etc.) requires the `X-Ccmax-Wrapper-Version` header injected by ccmax-claude's local reverse proxy, so they can't be queried from a bare curl invocation — those are off-limits to the statusline by design.

### Pin scope+mode resolution (badge RETIRED 2026-05-13)

`custom-statusline.sh` still runs the layered pin resolution upstream via ccmax-monitor's helper at `~/.claude/plugins/marketplaces/ccmax/hooks/pin-helper.sh` because the helper output feeds the bearer-mode detection cascade that gates whether the doorward render-block fires at all. The helper walks three scopes (highest → lowest precedence):

1. `~/.config/ccmax/pin-by-session/<session-uuid>.toml` — session scope (auto-pruned at 24 h JSONL staleness)
2. `~/.config/ccmax/pin-by-repo/<md5-prefix-8>.toml` — repo scope (cwd path → MD5 → 8-hex prefix)
3. `~/.config/ccmax/pin.toml` — device scope (the original HEART-23 location)

**The visible `[<scope>:<mode>]` badge was retired 2026-05-13** (operator directive: under bearer-mode routing, doorward picks the upstream account dynamically per-request, so the operator has no remaining need to see WHICH scope holds the pin). The pin parsing continues to run because it feeds bearer-mode detection; only the badge rendering is dropped.

**Backwards compat for older ccmax-monitor installs**: if `pin-helper.sh` is missing at the marketplace path (older release OR no ccmax-monitor at all), the statusline falls back to a tiny inline awk parser that reads only the device-scope file. Public cc-skills users without ccmax-monitor never had a pin badge anyway (no pin file). The retirement is therefore transparent to public users.

### Wrapper version + skew check

The local `ccmax-claude` binary's version is read once (cached by binary mtime) and rendered as a bare semver. When the version is below the doorward floor, the segment turns yellow with explicit floor: `wrapper 1.1.0<1.2.0`. This surfaces version-skew **before** a real request fails with 403, instead of after.

The floor is **AUTO-DISCOVERED** (L1a, 2026-05-13): the statusline anonymously probes a wrapper-gated doorward route (`/v1/users/me`) without the version header and parses `minimum_wrapper_version_required` out of the 403 body, caching it at `/tmp/ccmax-doorward-floor` (3600s TTL). When doorward raises its floor, the next render within the hour picks it up — **no manual constant bump required**. The compiled-in `DOORWARD_MIN_WRAPPER_VERSION_FALLBACK` is used only when the probe fails (doorward unreachable, gate disabled, parse error). Until the local binary is updated to meet a raised floor, the wrapper segment stays yellow and the operator knows to `gh release download` a fresh ccmax-claude.

### Statistics surface — JSONL log + analytics CLI (L2, 2026-05-13)

Every statusline render appends a parsed-state JSON record to `~/.claude/doorward-state.jsonl`. The schema is documented in-script (search `custom-statusline.sh` for "L2 STATISTICS SURFACE — JSONL append per render") and covers 20 fields per render: gate status, pool primitives + state-machine label, canary primitives + classification + type-code + duration, wrapper version + floor + skew/at-floor pre-warn flags, pin scope/mode, bearer-mode routing flag.

The sibling analytics CLI at `plugins/statusline-tools/scripts/doorward-telemetry-analytics-from-statusline-jsonl-log.py` reads the JSONL log and emits a time-windowed operator report. Verbose name encodes "telemetry analytics from the statusline jsonl log" so the file's purpose is discoverable from grep alone.

Usage:

```bash
# 24h comprehensive report (all metrics)
doorward-telemetry-analytics-from-statusline-jsonl-log.py --since 24h

# 7d single-metric report
doorward-telemetry-analytics-from-statusline-jsonl-log.py --since 7d --metric type-codes
doorward-telemetry-analytics-from-statusline-jsonl-log.py --since 7d --metric state-transitions
```

The six metric subsets:

| `--metric`          | Answers operator question                                                      |
| ------------------- | ------------------------------------------------------------------------------ |
| `uptime`            | What fraction of the window was the gateway reachable?                         |
| `type-codes`        | Of the failures observed, which RFC 9457 taxonomy bucket dominated?            |
| `state-names`       | What fraction of the window did we spend in each operator-facing state?        |
| `state-transitions` | How many "from→to" flips between unified states? (leading flapping indicator)  |
| `pre-warnings`      | When did wrapper-skew, wrapper-at-floor, and partial-outage pre-warnings fire? |
| `pool-health`       | What fraction of the window was the rotation pool at each resilience state?    |
| `all`               | (default) All six in one report                                                |

Read-only — never mutates the JSONL log. Log path overridable via `--jsonl <path>` for testing. Time windows accept `15m`, `1h`, `24h`, `7d`, `4w` forms.

### Graceful degradation

Two independent triggers gate whether the ccmax line is rendered at all (any one is sufficient):

1. Doorward reachable (cached or fresh) → render gate badge + pool + canary
2. Bearer-mode detected (env var or pin file) → triggers render so that a red `unreachable` warning still appears when doorward is down on a bearer-routed session

If neither is true (most likely a public cc-skills install with no integration), just the bare datetime line renders. Public users see no change vs. a fully unconfigured statusline.

Note: the prior pin-badge render-trigger was retired 2026-05-13 along with the visible `[scope:mode]` badge — pin resolution still runs upstream to feed bearer-mode detection, but it no longer produces a standalone render trigger.

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
