# minimax

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-1-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()
[![Source](https://img.shields.io/badge/Source-41--iter%20campaign-orange.svg)]()

MiniMax M-series production wiring patterns for the OpenAI-compatible API at `api.minimax.io`. Distilled from a 41-iteration `MiniMax-M2.7-highspeed` exploration campaign that produced 40 verified hands-on pattern docs, ~155 Non-Obvious Learnings, and 11 documented failure modes.

> **Trigger context**: This plugin auto-loads when you mention MiniMax, MiniMax-M2.7, Hailuo, `api.minimax.io`, or any of the API quirks documented in the skill (silent-dropped parameters, `base_resp.status_code`, `cache_control`, `<think>` tags, the 11 failure modes, the Tier F quant-LLM agentic stack). See [`skills/minimax/SKILL.md`](./skills/minimax/SKILL.md) frontmatter for the full TRIGGERS list.

## Skills

Each skill's SKILL.md frontmatter is the SSoT for its description.

- [minimax](./skills/minimax/SKILL.md) — production wiring patterns (top 10 rules, decision table, defensive code snippets, 11 failure modes, API surface map)

## What this plugin solves

| Problem                                                               | Where to look                                                                                                                                                              |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Wiring MiniMax into a service (Karakeep, Linkwarden, Gmail Commander) | [SKILL.md → Quick-start](./skills/minimax/SKILL.md#quick-start-for-new-amonic-services)                                                                                    |
| OpenAI parameter silently dropped (and which 6 do this)               | [SKILL.md → Top 10 rules #4](./skills/minimax/SKILL.md#top-10-production-rules) + [api-patterns/](./references/api-patterns/)                                              |
| JSON output without `response_format` (it's silently dropped)         | [SKILL.md → JSON snippet](./skills/minimax/SKILL.md#defensive-code-snippets-copy-paste-ready)                                                                              |
| Choosing between plain `MiniMax-M2.7` vs `-highspeed`                 | [SKILL.md → Decision table + rule #6](./skills/minimax/SKILL.md#when-to-use-m27-vs-not--the-decision-table)                                                                |
| Prompt caching (~95% cost reduction; latency-neutral)                 | [SKILL.md → cache_control snippet](./skills/minimax/SKILL.md#defensive-code-snippets-copy-paste-ready) + `references/api-patterns/cache-read-semantics.md` (lands Phase B) |
| Rate limiting without HTTP 429 (use `base_resp.status_code=1002`)     | [SKILL.md → Rate-limit retry snippet](./skills/minimax/SKILL.md#defensive-code-snippets-copy-paste-ready)                                                                  |
| Quant / financial use cases (10-primitive Tier F agentic stack)       | [SKILL.md → Tier F stack](./skills/minimax/SKILL.md#canonical-tier-f-agentic-stack-quant-llm-workflow)                                                                     |
| Defending against M2.7 hallucination + saturation failures            | [SKILL.md → 11 failure modes](./skills/minimax/SKILL.md#11-documented-failure-modes--defenses)                                                                             |
| Detecting MiniMax model upgrades                                      | `scripts/minimax-check-upgrade` (lands Phase C, iter-16) + `templates/launchd-check-upgrade.plist` (iter-17)                                                               |

## Plugin layout

```
plugins/minimax/
├── plugin.json                              # Marketplace metadata
├── README.md                                # This file (high-level overview)
├── LOOP_CONTRACT.md                         # Aggregation campaign state machine (transient)
├── skills/
│   └── minimax/
│       └── SKILL.md                         # The auto-discoverable production-wiring skill (328 lines)
├── references/
│   ├── INDEX.md                             # Navigable TOC + audit-coverage matrix
│   ├── api-patterns/                        # 40 per-endpoint deep-dive docs (Phase B, iters 5-15)
│   └── fixtures/                            # Selected raw API response fixtures (~8 diagnostic)
├── scripts/
│   └── minimax-check-upgrade                # Model-upgrade detection (Phase C, iter-16)
└── templates/
    └── launchd-check-upgrade.plist          # Daily polling template (Phase C, iter-17)
```

## Install (zero-config — auto-loaded by Claude Code)

```bash
# This plugin is part of the cc-skills marketplace. It loads automatically
# when Claude Code starts in any repo that has cc-skills configured. No manual
# install needed — Claude's skill auto-trigger picks it up via the SKILL.md
# frontmatter description when relevant prompts arrive.

# To verify the skill is registered:
ls ~/.claude/plugins/marketplaces/cc-skills/plugins/minimax/skills/

# To test the auto-trigger in a fresh session, prompt Claude with:
#   "I want to wire up MiniMax-M2.7 for trade signal JSON output"
# The skill should be invoked automatically.
```

## Optional: install OPS tooling (model-upgrade detection)

Once `scripts/minimax-check-upgrade` ships in iter-16, you can wire it into your repo's CI / launchd / cron to detect when MiniMax publishes a new model.

```bash
# One-shot manual check (after iter-16):
~/.claude/plugins/marketplaces/cc-skills/plugins/minimax/scripts/minimax-check-upgrade
# Exit 0 = no change; 1 = upgrade detected; 2 = fetch error

# Daily launchd polling (after iter-17 ships the plist template):
# 1. Customize templates/launchd-check-upgrade.plist with your paths
# 2. Symlink into ~/Library/LaunchAgents/
# 3. launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/<label>.plist
```

## Dependencies

| Component   | Required | Why                                                                      |
| ----------- | -------- | ------------------------------------------------------------------------ |
| Python 3.13 | Optional | For running the `scripts/minimax-check-upgrade` diff logic               |
| `op` CLI    | Optional | For fetching the MiniMax API key from 1Password (used by the OPS script) |
| `curl`      | Optional | For ad-hoc API calls per the SKILL.md quick-start                        |
| `jq`        | Optional | For parsing JSON responses in shell pipelines                            |

No hard runtime dependencies — the skill is pure documentation. The OPS script (Phase C) needs `python3` (any version on macOS works) and `curl`.

## Related plugins

- [`gemini-deep-research`](../gemini-deep-research/) — sibling LLM-provider integration (Google Gemini Deep Research via browser automation)
- [`quant-research`](../quant-research/) — companion plugin for the financial-engineering use cases referenced in the Tier F section of SKILL.md
- [`itp`](../itp/) — workflow automation that can wrap the MiniMax wiring patterns in ADR-driven phases

## Provenance

Distilled from the 41-iteration `minimax-m27-explore` autoloop campaign at `~/own/amonic/minimax/`:

- 40 verified hands-on pattern docs (`api-patterns/*.md`)
- 1 quirks consolidation (`quirks/CLAUDE.md`)
- 1 retrospective (`RETROSPECTIVE.md`)
- 1 OPS tool with launchd plist
- ~50 API response fixtures
- 35 critical findings, 11 documented failure modes, 4 error code families, 6 compat envelope categories

Campaign verified against `MiniMax-M2.7-highspeed` between 2026-04-28 and 2026-04-29.

## Aggregation campaign status

This plugin is being built incrementally by an autoloop campaign tracked in [`LOOP_CONTRACT.md`](./LOOP_CONTRACT.md). Current status:

| Phase                                   | Status         | Iters          |
| --------------------------------------- | -------------- | -------------- |
| Phase A — Plugin scaffold               | 🔄 IN PROGRESS | 0-3 (75% done) |
| Phase B — Reference content aggregation | ⏸️ PENDING     | 5-15           |
| Phase C — OPS tool migration            | ⏸️ PENDING     | 16-18          |
| Phase D — Audit                         | ⏸️ PENDING     | 19-22          |
| Phase E — Refinement + discoverability  | ⏸️ PENDING     | 23-27          |
| Phase F — Close                         | ⏸️ PENDING     | ~28            |

Source-of-truth at `~/own/amonic/minimax/` is the authoritative archive — read-only during this campaign per user directive.

## Troubleshooting

| Issue                                                | Likely cause                                            | Solution                                                                     |
| ---------------------------------------------------- | ------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Skill not auto-triggering on "MiniMax" prompt        | Plugin not yet detected by Claude Code                  | Restart Claude Code session; `bun scripts/validate-plugins.mjs` in cc-skills |
| `<think>` tags appearing in user-facing output       | Forgot to strip server-side reasoning trace             | Add `re.sub(r"<think>[\s\S]*?</think>\s*", "", content)` to response parser  |
| `response_format` parameter has no effect            | MiniMax silently drops it                               | Use prompt engineering instead — see SKILL.md JSON snippet                   |
| `tool_choice="required"` not forcing tool use        | MiniMax silently drops `tool_choice`                    | Strict system prompt + `finish_reason == "tool_calls"` check + retry         |
| Karakeep tagging slow with `MiniMax-M2.7-highspeed`  | Plain M2.7 is faster for short outputs (<150 tokens)    | Switch to plain `MiniMax-M2.7` for tagging-style workloads                   |
| HTTP 200 but empty response                          | `max_tokens` too low; reasoning consumed budget         | Set `max_tokens >= 1024`; branch on `finish_reason == "length"`              |
| Rate-limit retry middleware never triggers           | MiniMax returns HTTP 200 + `base_resp.status_code=1002` | Watch body, not HTTP status — see SKILL.md retry snippet                     |
| `scripts/minimax-check-upgrade` not found            | Phase C iter-16 hasn't shipped yet                      | Use `~/own/amonic/bin/minimax-check-upgrade` from source repo for now        |
| Markowitz / Black-Scholes math request returns empty | M2.7 saturates on QP / numerical CDF                    | Route to scipy/numpy; M2.7 explains the framework, Python computes           |

## License

MIT
