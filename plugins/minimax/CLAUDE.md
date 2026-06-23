# minimax — Plugin SSoT (maintainers)

MiniMax M-series production-wiring patterns, distilled from a 41-iteration M2.7-highspeed
exploration campaign and extended (2026-06-01) with a live-probed **MiniMax-M3** layer.

**Hub**: [plugins/CLAUDE.md](../CLAUDE.md) | **User-facing**: [README.md](./README.md)

## What this plugin ships

| Layer            | Path                                                            | Role                                                              |
| ---------------- | --------------------------------------------------------------- | ----------------------------------------------------------------- |
| M2.7 skill       | `skills/minimax/SKILL.md`                                       | Invocable `minimax:minimax` — the 41-iter campaign distillation   |
| M3 skill         | `skills/m3/SKILL.md`                                            | Invocable `minimax:m3` — when-to-use + default profile            |
| M3 evidence      | `references/M3-EMPIRICAL.md`                                    | Live-probed M3 option/capability map + wiring snippets            |
| Deep refs        | `references/api-patterns/*.md`, `RETROSPECTIVE.md`, `quirks.md` | M2.7 per-endpoint findings (frozen campaign matrix in `INDEX.md`) |
| Catalog tripwire | `scripts/minimax-check-upgrade`                                 | Diffs `/v1/models` vs `fixtures/models-list-locked.json`          |
| M3 tripwire      | `scripts/m3-verify`                                             | Diffs live M3 capability invariants vs the locked snapshot        |
| Verify scripts   | `scripts/m3-{probe,context-probe,bench}.py` + `_m3_common.py`   | Reproduce the M3 findings on demand                               |
| Snapshots        | `references/fixtures/*-locked*.json`                            | Drift contracts for the tripwires                                 |
| Launchd template | `templates/launchd-check-upgrade.plist`                         | Schedule the tripwires                                            |

## Critical invariants (don't break these)

1. **`scripts/` is stripped from the runtime plugin cache** (`~/.claude/plugins/cache/...`).
   The verify scripts + tripwires are run from the **source checkout** (`~/eon/cc-skills/plugins/minimax`)
   or launchd — never through the plugin cache's stripped scripts dir. `references/` **does** survive
   the cache, so SKILL.md may link to `references/*` freely. (Verified 2026-06-01.)
2. **`BASE` ends in `/v1`** (`https://api.minimax.io/v1`) — request paths are `/models`,
   `/chat/completions` (no extra `/v1`). A doubled `/v1` returns 404. (`_m3_common.py` + `m3-verify`
   both rely on this; it bit `m3-verify` once during authoring.)
3. **No inline ignores** (`# noqa` / `# type: ignore`) — repo policy (code-correctness-guard).
   Narrow the except instead (`NET_ERRORS` in `_m3_common.py`). `requests`/`PIL` unresolved-import
   warnings from `ty` are runtime-dep false-positives (installed via `uv run --with`) — leave them.
4. **Key resolution order** (all scripts): `MINIMAX_API_KEY` env → 1Password `op read` (op-path
   `op://ggk4orq7rmcm7jinsb4ahygv7e/e54cb3ujopexslaq7loywpuycm/password`, account `K5BH72Z7O5BYXOGKBYT5FWTP2E`).
   MiniMax 502s through the local proxy — scripts bypass it (`trust_env=False` / `ProxyHandler({})`).
5. **MiniMax errors are HTTP 200 + `base_resp.status_code`** (or an `error` envelope) — not HTTP 4xx.
   Both skills' parsers depend on this.
6. **Both locked snapshots are review-gated** — bump only after auditing a tripwire diff, never blindly.

## Recent changes

- **2026-06-01** — Added the M3 layer: `skills/m3/SKILL.md`, `references/M3-EMPIRICAL.md`,
  `references/fixtures/m3-capabilities-locked-2026-06-23.json`, `scripts/m3-{probe,context-probe,bench}.py`
  - `_m3_common.py` + `m3-verify`. Refreshed `fixtures/models-list-locked.json` to include `MiniMax-M3`
    (catalog tripwire was correctly firing on the new model). Both tripwires verified green live.
    Key M3 facts: 512K input ceiling (docs claim 1M — not on this key), 512K output cap, `n=1`,
    native vision ✅, `reasoning_split:true` = clean output, no `M3-highspeed` on this key.

## Verify everything

```bash
cd ~/eon/cc-skills/plugins/minimax
export MINIMAX_API_KEY=...            # or rely on the op-path default
./scripts/m3-verify && ./scripts/minimax-check-upgrade   # both should exit 0
```
