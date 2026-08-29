# Secret + third-party-PII exposure guards

Two hooks and one shared detector library, closing the structural gap that let live credentials and a third party's personal data reach public repositories.

| File                                             | Lifecycle                            | Behaviour                         |
| ------------------------------------------------ | ------------------------------------ | --------------------------------- |
| `hooks/lib/secret-and-pii-exposure-detector.ts`  | —                                    | Pure detectors + message builders |
| `hooks/pretooluse-secret-exposure-guard.ts`      | PreToolUse `Write\|Edit\|MultiEdit`  | **Hard deny** on credentials      |
| `hooks/posttooluse-pii-exposure-reminder.ts`     | PostToolUse `Write\|Edit\|MultiEdit` | Non-blocking reminder on PII      |
| `hooks/pretooluse-secret-exposure-guard.test.ts` | —                                    | 48 bun tests, positive + negative |

## The incident (2026-08-28)

A 23-repository audit of the published tree found, **after two deliberate scrub campaigns had already run**:

1. A **live Telegram bot token**. It survived both scrubs because **gitleaks has no Telegram-bot-token rule**. Only trufflehog's provider-side verification caught it.
2. **Live Pushover app tokens and a user key**. These are bare 30-character alphanumerics with no prefix: trufflehog has no detector for them at all, and gitleaks caught exactly one — by luck, because the adjacent variable happened to be named `PUSHOVER_APP_TOKEN`.
3. A third-party contact's **real name, business email and phone number reintroduced** into the published tree **six days after** an eleven-agent scrub of 2,602 files removed them.
4. Every credential found sat in an **ADR, design spec or planning doc**, pasted as a worked example of a `doppler secrets set …` provisioning command — frequently in a file that simultaneously said the secret lived in Doppler.

Two lessons drive the design. First, **`docs/` is the dangerous directory, not `src/`** — the scanners were pointed at code, the leaks were in prose. Second, **a one-time sweep does not hold**: finding 3 happened because the next agent re-derived the same content from the same upstream source and pasted it back. Only an edit-time gate holds.

## What each detector fires on

### Credential class → **hard block** (PreToolUse deny)

| Detector                     | Fires on                                                                                                                                                                                              | Does not fire on                                                                                   |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Telegram bot token           | `\b\d{8,10}:AA[A-Za-z0-9_-]{32,}\b` — the BotFather format verbatim                                                                                                                                   | `<telegram-bot-token>`, `123456789:AAxxxx…`, env references                                        |
| Pushover-style bare token    | A bare 30-char mixed-alphanumeric run **within ±80 chars** of a `PUSHOVER` / `app_token` / `user_key` / `api_token` / `--token` cue                                                                   | The same 30-char shape with no cue, `$PUSHOVER_APP_TOKEN`, `<pushover-app-token>`, all-letter runs |
| Provisioning command literal | `doppler secrets set`, `op item create\|edit`, `vault set\|put`, `gh secret set`, `wrangler secret put`, `aws secretsmanager …`, `security add-generic-password` + a ≥16-char non-placeholder literal | Placeholder values, `$VAR` references, prose flag values containing whitespace                     |

Only **new** content is scanned (`content`, `new_string`, `edits[].new_string`), and MultiEdit fragments are scanned **separately**, so a naming cue in one edit cannot license a token blob in another. Matched values are redacted before they reach the transcript.

### PII class → **reminder only** (PostToolUse `decision: "block"` context injection)

| Detector | Fires on                                                                                                      | Does not fire on                                                                                                                                                      |
| -------- | ------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Email    | An address at a real, routable domain                                                                         | `example.com/.org/.net`, `.test`/`.invalid`/`.local`, `users.noreply.github.com`, the operator's own addresses, role local-parts (`support@`, `info@`, `noreply@`, …) |
| Phone    | E.164 (`+1 604 321 7788`) anywhere; bare NANP `nnn-nnn-nnnn` **only** beside a telephony cue within ±40 chars | `555-01xx` (the NANP reserved fictional range), version strings, IP-like text, ID ranges like `100-200-3000` with no cue                                              |

Scanned extensions are prose and config only (`.md .markdown .txt .rst .adoc .json .jsonc .yaml .yml .toml .ini .cfg .conf .env .csv .html`); source files are out of scope, and temp scratch is exempt via the iter-124 shared helper.

## Why the asymmetry

The credential regexes are structurally distinctive and the cost of a miss is a rotated credential at best. The PII regexes are not: an email address in a doc is frequently legitimate — a vendor support address, an RFC author, a git commit trailer, a maintainer contact in a plugin manifest. A guard that denied on that would be wrong several times a day, **and a guard that is wrong several times a day gets disabled — which is strictly worse than no guard at all.** So the fuzzy class reminds and the sharp class blocks.

## Escape hatches

| Marker                     | Consumer                               | Reason required          |
| -------------------------- | -------------------------------------- | ------------------------ |
| `SECRET-SCAN-OK: <reason>` | `pretooluse-secret-exposure-guard.ts`  | **Yes — ≥10 characters** |
| `PII-SCAN-OK`              | `posttooluse-pii-exposure-reminder.ts` | No                       |

Both are FILE_WIDE and case-sensitive, registered in the iter-111 canonical registry.

The mandatory reason on `SECRET-SCAN-OK` is deliberate and unusual for this repo: in the audit, **every** leaked credential was accompanied by the belief that it was just an example, so a bare marker would reproduce the exact failure the guard exists to prevent. Legitimate uses are narrow — a synthetic fixture in this guard's own test suite, or a genuinely revoked value quoted in a post-mortem. **If the value was ever live, the marker is the wrong answer: remove it and rotate the credential.**

## Audit-gate change: trufflehog runs in verified mode

`plugins/itp/skills/code-hardcode-audit/scripts/{audit_hardcodes.py,run_trufflehog.py}` now pass `--results=verified,unknown`.

Verification is what caught finding 1, so it is load-bearing rather than a tuning knob. `unknown` is retained alongside `verified` so an unreachable verification endpoint cannot silently downgrade into a clean report; the `unverified` bucket (entropy guesswork) is excluded because that noise is why people turn scanners off.

Note the limit that motivated the hooks in the first place: **no scanner detects the Pushover shape**, and gitleaks detects no Telegram token. The gate and the hooks cover different blind spots and neither replaces the other.

## Known false-positive risk

- A 30-char alphanumeric build fingerprint, nanoid or hash quoted in the same paragraph as the word "pushover" would block. Rare, and the escape hatch is one comment away.
- A `gh secret set NAME=<16+ char base64 test vector>` in a shell fixture would block.
- The phone detector's E.164 arm needs no context word; a raw `+1 604 …`-shaped identifier in a data file would remind (never block).
