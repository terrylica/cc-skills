---
name: send-message
description: user wants to send a WhatsApp message, share a link or document via WhatsApp, generate a wa.me click-to-chat link, or message a contact on WhatsApp by phone number.
allowed-tools: Bash, Read, Grep, Glob
---

# Send WhatsApp Message

Reach a contact on WhatsApp. Unlike Telegram (`tlg`, full MTProto personal send) and
Gmail (`gmail-commander`, OAuth API send), **WhatsApp has no sanctioned personal-account
send API** — Meta only offers programmatic send through the **Business Cloud API**, and
everything else (WhatsApp Web automation, `whatsmeow`/`Baileys`/`wppconnect` libraries)
is unofficial and risks account bans. This skill therefore defaults to the safe,
zero-credential path and escalates only when the user has set up the Cloud API.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Capability Tiers (pick the lowest that works)

| Tier            | Method                          | Actually sends?                                                   | Credentials                                               | When to use                                                                                                                           |
| --------------- | ------------------------------- | ----------------------------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| **1 (default)** | **`wa.me` click-to-chat link**  | No — opens WhatsApp with text pre-filled; the human taps **Send** | None                                                      | Almost always. ToS-safe, instant, works for any number.                                                                               |
| 2               | WhatsApp Web browser automation | Yes, but brittle                                                  | A logged-in WhatsApp Web session (QR)                     | **Not implemented here** — DOM-fragile and ToS-gray. Document, don't build, unless the user insists.                                  |
| 3               | **WhatsApp Business Cloud API** | Yes, officially                                                   | `WHATSAPP_TOKEN` + `WHATSAPP_PHONE_NUMBER_ID` (1Password) | The user has a Meta Business app + registered number. See [references/business-cloud-api.md](../../references/business-cloud-api.md). |

**Default to Tier 1.** Only use Tier 3 when the user has explicitly set up the Business
Cloud API and the credentials resolve (see Preflight).

## Preflight

1. **You need the recipient's phone number in international format** (any punctuation is
   fine — the CLI strips non-digits). If you only have an email/username, ask for the
   number; WhatsApp is phone-number addressed.
2. **WhatsApp registration is not verifiable** from here — a `wa.me` link still opens even
   if the number is not on WhatsApp (it shows an "invalid number" notice on tap). State
   this assumption rather than claiming delivery.
3. **For Tier 3 only**, confirm credentials are present:

```bash
[ -n "${WHATSAPP_TOKEN:-}" ] && [ -n "${WHATSAPP_PHONE_NUMBER_ID:-}" ] && echo "cloud-api: READY" || echo "cloud-api: NOT CONFIGURED — use the link tier"
```

## Usage: wa-cli.ts

The CLI is function/enum-driven Bun TypeScript — run it directly with `bun` (no build step).

```bash
/usr/bin/env bash << 'WA_EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/whatsapp-commander}/scripts/wa-cli.ts"

# Tier 1 — build a click-to-chat link (the recommended default)
bun "$SCRIPT" link "+1 (604) 816-8818" "Hi Iris — short note and a link: https://example.com/x"

# Tier 1 — body read from a file (multi-paragraph messages are awkward inline)
bun "$SCRIPT" link 16048168818 --file ./whatsapp-message.txt

# Tier 3 — actually send via the Business Cloud API (creds resolved into env first)
export WHATSAPP_TOKEN="$(op item get <ITEM> --vault 'Claude Automation' --fields token --reveal)"
export WHATSAPP_PHONE_NUMBER_ID="$(op item get <ITEM> --vault 'Claude Automation' --fields phone_number_id --reveal)"
bun "$SCRIPT" send 16048168818 "Your appointment is confirmed."
WA_EOF
```

### What to hand back to the user

- **Tier 1**: present the `wa.me` URL as a Markdown link and tell them tapping it opens the
  chat with the text pre-filled — **the final Send tap is theirs** (WhatsApp does not allow
  automating that tap). On desktop they need WhatsApp Web logged in; on phone it deep-links.
- **Tier 3**: the API returns JSON with a `messages[0].id`; report the message id as proof
  of submission (subject to the 24-hour window / template rules — see references).

## Cloud API Window Rules (Tier 3)

The Business Cloud API does **not** let you send arbitrary text to anyone at any time:

- **Inside the 24-hour customer-service window** (the user messaged you in the last 24h):
  free-form `type: "text"` messages are allowed. `wa-cli.ts send` sends exactly this.
- **Outside the window** (first contact / re-engagement): you may send **only
  pre-approved message templates** (`type: "template"`), not free text. A free-text send
  outside the window returns error `131047`. For first contact, prefer Tier 1, or send an
  approved template via the raw Graph API (see references).

## Anti-Patterns (NEVER DO)

| Anti-Pattern                                                                                     | Why It Fails                                                                    |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| Claiming a `wa.me` link "sent" the message                                                       | It only **pre-fills**; the human taps Send. Say so.                             |
| Using an unofficial library (`Baileys`, `whatsmeow`, `wppconnect`) to send as a personal account | Violates WhatsApp ToS; risks number ban. Not part of this skill.                |
| Passing a number without a country code                                                          | `wa.me` needs full E.164; the CLI rejects <8 digits.                            |
| Free-text Cloud API send to a cold contact                                                       | Outside the 24h window only approved templates send (error 131047).             |
| Hardcoding the Cloud API token in a script/commit                                                | Resolve from 1Password into env at call time (mirrors `gmail-commander`/`tlg`). |

## Error Handling

| Symptom                                     | Cause                                    | Fix                                               |
| ------------------------------------------- | ---------------------------------------- | ------------------------------------------------- |
| CLI: `too few digits`                       | Number missing country code              | Pass full international format                    |
| CLI: `Cloud API send needs WHATSAPP_TOKEN…` | Tier 3 creds absent                      | Use Tier 1 `link`, or resolve creds via 1Password |
| API `Cloud API HTTP 401`                    | Token expired/invalid                    | Rotate the token in Meta → update 1Password       |
| API error `131047`                          | Outside 24h window                       | Send an approved template, or use Tier 1          |
| `wa.me` opens but shows "invalid number"    | Recipient not on WhatsApp / wrong number | Confirm the number with the user                  |

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused it.
2. **Did `wa-cli.ts` flags or output change?** — Update the Usage block to match.
3. **Was a workaround needed?** — Capture it here so the next run doesn't rediscover it.
4. **New convention learned about WhatsApp's limits?** — Add it to the tier table / window rules.

Only update if the issue is real and reproducible — not speculative.

## Evolution Log

- **2026-06-22 — initial skill.** WhatsApp has no personal-account send API. Modelled on
  `tlg`/`gmail-commander` conventions but split into capability tiers because the platform
  forbids the equivalent of MTProto/OAuth personal send. Default = `wa.me` link (the path
  proven in the VanJobbers ↔ CPC engagement); Cloud API send wired but credential-gated.
  CLI written as function/enum-driven Bun TypeScript per the repo language preference.
