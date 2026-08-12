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
| M3 tripwire      | `scripts/m3-cli.ts verify`                                      | Diffs live M3 capability invariants vs the locked snapshot        |
| Verify CLI       | `scripts/m3-cli.ts {probe,context-probe,bench}`                 | Reproduce the M3 findings on demand (one Bun CLI)                 |
| Snapshots        | `references/fixtures/*-locked*.json`                            | Drift contracts for the tripwires                                 |
| Launchd template | `templates/launchd-check-upgrade.plist`                         | Schedule the tripwires                                            |

## Critical invariants (don't break these)

1. **`scripts/` is stripped from the runtime plugin cache** (`~/.claude/plugins/cache/...`).
   The verify scripts + tripwires are run from the **source checkout** (`~/eon/cc-skills/plugins/minimax`)
   or launchd — never through the plugin cache's stripped scripts dir. `references/` **does** survive
   the cache, so SKILL.md may link to `references/*` freely. (Verified 2026-06-01.)
2. **`BASE` ends in `/v1`** (`https://api.minimax.io/v1`) — request paths are `/models`,
   `/chat/completions` (no extra `/v1`). A doubled `/v1` returns 404. (`m3-cli.ts` relies on this;
   it bit the tripwire once during authoring.)
3. **No inline ignores** (`// @ts-ignore` / `// eslint-disable`) — repo policy
   (code-correctness-guard). Narrow the catch instead (typed `errOf` envelope). `m3-cli.ts` is pure
   Bun — no `uv` / `requests` / `pillow` runtime; oxlint + `tsc --strict` run clean.
4. **Key resolution order** (all scripts): `MINIMAX_API_KEY` env → 1Password `op read` (op-path
   `op://<vault>/<minimax-api-key-item>/credential`, account `<op-account>`).
   MiniMax 502s through the local proxy — `m3-cli.ts` bypasses it by deleting `*_PROXY` from its env at startup.
5. **MiniMax errors are HTTP 200 + `base_resp.status_code`** (or an `error` envelope) — not HTTP 4xx.
   Both skills' parsers depend on this.
6. **Both locked snapshots are review-gated** — bump only after auditing a tripwire diff, never blindly.
7. **M3's usable input is far smaller than its accepted input.** The API accepts ~1M tokens
   (1,048,576 is rejected), but deep retrieval regresses well below the ceiling — a 400K needle
   misses. Budget **≤ ~256K for reliable retrieval**; a 1M prefill costs ~235 s. Output caps at
   **524,288**, and `n>1` is **silently dropped, not rejected** — never infer `n` was honoured.

## Verify everything

```bash
cd ~/eon/cc-skills/plugins/minimax
export MINIMAX_API_KEY=...            # or rely on the op-path default
bun scripts/m3-cli.ts verify && ./scripts/minimax-check-upgrade   # both should exit 0
```
