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

---

## Third surface: the commit message (2026-08-29)

### The second incident

An audit found that this repo's own **PII-scrub commits republished, verbatim and publicly, every value they redacted.** semantic-release turns commit bodies into release prose, so a conscientious "removed X, Y, Z" message became the leak — with a permanent public URL that no later commit retracts. It was still recurring two releases after the scrub: the habit outlived the fix.

The two hooks above could not have caught it. **They inspect file writes; no file was ever written.** Same detector, invisible surface.

### Mechanism: `scripts/commit-message-exposure-guard.ts`, run from the `commit-msg` git hook

Invoked as Step 3b of the iter-157 commit-msg hook body, before the conventional-commit classifier (a message that leaks must be rejected however well-formed its subject is). A PreToolUse guard on `Bash` was rejected as the primary mechanism: it would only see agent commits with an inline `-m`, and would miss operator-typed commits, `-F file`, editor sessions, `--amend`, and any other git client. `commit-msg` is git's own interception point and sees all of them — and this repo already runs a `pre-commit` PII guard and this very `commit-msg` hook, so it extends an established pattern rather than adding a parallel one.

| Property        | Behaviour                                                                                |
| --------------- | ---------------------------------------------------------------------------------------- |
| Credential kinds | **BLOCK** (exit 1) — same three detectors as the file surface                            |
| PII kinds        | **REMIND** (exit 0) — same asymmetry, same reasoning                                     |
| Skipped          | Merge/Revert/fixup!/squash!/amend! subjects; empty messages                              |
| Never scanned    | `#` comment lines, and everything below the `--verbose` `>8` scissors line               |
| Escape hatch     | `SECRET-SCAN-OK: <reason ≥10 chars>` in the message — same marker, same gate             |
| Failure mode     | Fail-OPEN and loud (a crashing or missing guard must not make the repo uncommittable)    |

**The scissors exclusion is load-bearing.** The most likely commit this guard ever sees is the one that *removes* a leaked value; with `commit --verbose` that value sits in the diff below the scissors. Scanning it would block precisely the commit that fixes the problem.

Reporting is class + line + **redacted** excerpt, never the value — echoing it into hook output (scrollback, CI logs, screenshots, agent transcripts) would be the same republication error one level up.

### Three identifier detectors added to the shared detector

All three are PII-class (remind), because none is a usable credential on its own. What they leak is **attribution**: whose account, which client, which deal.

| Kind                                 | Shape                                        | Required cue within ±80 chars                    |
| ------------------------------------ | -------------------------------------------- | ------------------------------------------------ |
| `aws-account-id`                     | bare 12-digit run                            | `aws` / `arn:aws` / `account id` / `iam` / `sts` |
| `client-scoped-workers-dev-hostname` | `<project>.<account>.workers.dev`            | none — but ≥2 labels, and no placeholder label   |
| `vault-item-identifier`              | 26-char `[a-z2-7]` base32 blob               | `1password` / `op item` / `op://` / `item id`    |

Documentation filler never fires: AWS's own `123456789012`, all-zero runs, single-label `foo.workers.dev`, and any placeholder label.

### False-positive risk

- A **12-digit** ID column value or epoch quoted in a paragraph about AWS reminds (never blocks). Git SHAs, semver and `#1234` issue numbers are all the wrong shape and are covered by explicit negative tests.
- A real multi-label `workers.dev` host belonging to the operator reminds every time it is mentioned in a commit body. Deliberate: the class is exactly what leaked.
- A 26-char base32 hash near the word `uuid` reminds.
- **No PII class can block**, so every risk above costs one advisory line on stderr and nothing else. Only the three credential classes gate a commit, and those are unchanged from the file surface.

### Tests

`scripts/commit-message-exposure-guard.test.ts` — synthetic stand-ins for the real incident shapes (never the real values; this file is itself published), plus a false-positive floor of ordinary release-shaped commit prose: semver bumps, git SHAs, issue numbers, `<redacted>`, `example.com`, `555-01xx`, and AWS's documentation account ID.
