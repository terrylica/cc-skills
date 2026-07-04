# Pushover Message-Budget Reminder

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## Pushover Message-Budget Reminder

The `posttooluse-pushover-budget-reminder.ts` hook fires whenever Claude writes/edits code that **constructs a Pushover message** (Python, Go, TypeScript/JS, Bash) or runs an inline Pushover send via Bash, and reminds Claude to use Pushover's full budget for verbose, machine-readable provenance — without overflowing it.

### Pushover hard limits (official API, SSoT — verified 2026-05-29, re-verified 2026-06-11)

| Field        | Limit                     | Notes                                                                                                                                                       |
| ------------ | ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `message`    | **1024** UTF-8 chars      | Delivered in full, but the lock-screen/banner **preview truncates** it                                                                                      |
| `title`      | **250** chars             | At-a-glance identity channel (symbol/direction/ticket)                                                                                                      |
| `url`        | **512** chars             | Supplementary clickable link — offload long retrieval commands / deep links                                                                                 |
| `url_title`  | **100** chars             | Label for `url`                                                                                                                                             |
| `attachment` | **1** per msg, ≤ **5 MB** | Image only (`image/png` \| `image/jpeg`); multipart `attachment` or base64 `attachment_base64` + `attachment_type`                                          |
| `ttl`        | seconds (positive int)    | Message self-deletes from devices after N seconds (ignored for priority 2; clients ≥ 4.0). Employ for ephemeral progress/heartbeat sends so they self-clean |

**Quota scope change (2026-05-01, Pushover blog 2026-04)**: monthly limits are now **per-account** — the 10,000/month pool is shared across ALL of the account's applications (the observability fleet's apps draw from ONE budget; teams: 25,000). Exhaustion returns **HTTP 429** on message creation. Machine-readable SSoT: [`pushover_api_limits.json`](/plugins/pushover-commander/skills/_lib/pushover_api_limits.json).

Sources: [pushover.net/api](https://pushover.net/api), [message size limits](https://support.pushover.net/i12-message-size-and-frequency-limitations), [base64 attachment](https://support.pushover.net/i135-json-api-base64-attachment-image), [attachment size](https://support.pushover.net/i253-increase-attachment-size).

### Why PostToolUse (not PreToolUse)

PreToolUse `additionalContext` is **silently dropped** on current Claude Code versions, and **all** injection channels (`additionalContext`, `systemMessage`, plain stdout) are dropped for the **Bash** matcher ([#19432](https://github.com/anthropics/claude-code/issues/19432), [#55889](https://github.com/anthropics/claude-code/issues/55889), [#15664](https://github.com/anthropics/claude-code/issues/15664)). The Bash arm is the most important one (the live FIRING-108 sender is a bash `curl` script), so the nudge uses the repo's proven Claude-visible channel: PostToolUse `{decision:"block", reason}` (ADR `2025-12-17-posttooluse-hook-visibility`). `block` does **not** undo the completed tool — it only surfaces `reason` as a system reminder. **This hook never blocks real work.**

### Detection (precision over recall)

Every rule is anchored on Pushover-specific evidence — generic shapes (a bare `{title, message}` object, `FormData.append('message')`, a Slack lookalike) are deliberately **not** matched, because the adversarial spike workflow proved them to be false-positive magnets.

| Arm                 | Fires on                                                                                                                                                                                             |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Library / CLI usage | gregdel `pushover.New(...) … SendMessage(`, chump/python-pushover `.send_message(title=`, `new Pushover`, an import of `pushover-notifications`/`node-pushover`/`chump`, or `pushover-notify --flag` |
| Endpoint usage      | `api.pushover.net` on a **non-comment** line **AND** a real send call (`curl …-d/-F`, `requests`/`httpx` `.post(`, `http.Post`/`PostForm(`, `fetch(`, `axios`, `urlopen(`)                           |

Comments / docstrings / heredoc-prose that merely mention the endpoint have **no send call**, so they are correctly excluded.

### What the reminder tells Claude

Front-load the highest-value identifiers in the **first ~120 chars** of the body and in the **title** (since the preview truncates). Provenance priority: (1) stable IDs (UUID, ticket#/order#, deal#, magic, symbol → title), (2) decision time in **both UTC and the display/broker tz** (the screenshot-vs-UTC mismatch is the classic confusion), (3) rule/git provenance (SHA, gitHEAD, path), (4) a machine-readable retrieval pointer (`grep <uuid> <path> | jq .`). Spend the **title** and **url/url_title** side channels instead of body budget. **Overflow / CEO-readable-at-a-glance → render the provenance as a PNG image and attach it** (≤ 5 MB) — and Claude Code can generate that image on request (render a provenance table/dashboard to PNG).

### Escape hatch

Add `PUSHOVER-BUDGET-OK` anywhere in the file/command to silence the nudge (e.g. for an intentionally terse alert).

### Provenance & tests

Detection was designed and adversarially verified by a multi-subagent spike workflow (spikes → per-language detect → adversarial verify → synthesis). The 51 resulting fixtures live at `hooks/tests/pushover-budget-fixtures/` (Python/Go/TypeScript/Bash × positive/negative/edge) with a `manifest.json` of expected verdicts; `hooks/tests/posttooluse-pushover-budget-reminder.test.ts` asserts **0 false positives / 0 false negatives** against them. Documented recall limits (require AST-level analysis, not in the fixture set): dynamic endpoint built from a generic-named variable, and `new Pushover()` whose `.send()` is split across distant variable scope.


## Original hub-table narrative (PostToolUse, moved 2026-06-11)

> Moved VERBATIM from the PostToolUse hook table of the pre-refactor plugin CLAUDE.md when the full-table snapshot docs were dissolved (operator decision 2026-06-11 — snapshots drift; per-hook spokes are the living home).

**Matcher**: Bash\|Write\|Edit\|MultiEdit

**Pushover message-budget nudge** (soft; emits `{decision:block,reason}` — the Claude-visible PostToolUse channel per ADR 2025-12-17, since PreToolUse `additionalContext` is silently dropped, esp. for Bash, per [GitHub #19432](https://github.com/anthropics/claude-code/issues/19432) / [#55889](https://github.com/anthropics/claude-code/issues/55889)). Detects Pushover message construction in Python/Go/TypeScript/Bash and reminds Claude to use the full budget (message **1024** / title **250** / url **512** / url_title **100** UTF-8 chars), front-load IDs (preview truncates), spend the title+url side channels, and render overflow / CEO-readable provenance as a **≤5 MB PNG attachment**. Precision-anchored rules: `api.pushover.net` on a non-comment line + a real send call, OR a known lib/CLI (gregdel `SendMessage`, chump/`.send_message`, `new Pushover`, a pushover-client import, `pushover-notify`). Verified **0 FP / 0 FN** vs 51 adversarial spike fixtures (`hooks/tests/pushover-budget-fixtures/`). Never blocks real work. Escape hatch: `PUSHOVER-BUDGET-OK`. See [§ Pushover Message-Budget Reminder](./pushover-budget-reminder.md).
