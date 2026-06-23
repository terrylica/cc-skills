# WhatsApp Business Cloud API (Tier 3 setup)

The only Meta-sanctioned way to send WhatsApp messages programmatically. Use this when
the user needs real automated sends (notifications, confirmations) rather than the
`wa.me` click-to-chat link (Tier 1).

## One-time setup (user does this in Meta)

1. Create a **Meta Business** account and an app at <https://developers.facebook.com> →
   add the **WhatsApp** product.
2. In the WhatsApp → API Setup panel, note:
   - **Phone Number ID** (the sender; a test number is provided free, or register your own).
   - A temporary **access token** (24h). For production, create a **System User** with a
     **permanent token** scoped to `whatsapp_business_messaging` + `whatsapp_business_management`.
3. Add and verify the recipient test numbers (test mode), or complete business verification
   for unrestricted sending.

## Store credentials in 1Password (mirrors gmail-commander / tlg)

Create an item in the **`Claude Automation`** vault (e.g. `WhatsApp Cloud API - <app>`):

| Field             | Type      | Value                              |
| ----------------- | --------- | ---------------------------------- |
| `token`           | concealed | permanent System User access token |
| `phone_number_id` | text      | the sender Phone Number ID         |

Resolve into the environment at call time — never hardcode:

```bash
export WHATSAPP_TOKEN="$(op item get '<ITEM>' --vault 'Claude Automation' --fields token --reveal)"
export WHATSAPP_PHONE_NUMBER_ID="$(op item get '<ITEM>' --vault 'Claude Automation' --fields phone_number_id --reveal)"
```

## Sending

- **Free-form text** (only inside the 24-hour customer-service window) — what `wa-cli.ts send`
  does:

  ```bash
  bun "$SCRIPT" send 16048168818 "Your appointment is confirmed."
  ```

- **Template** (required for first contact / outside the 24h window) — raw Graph API, since
  templates need a name + language + variable components:

  ```bash
  curl -s "https://graph.facebook.com/v21.0/${WHATSAPP_PHONE_NUMBER_ID}/messages" \
    -H "Authorization: Bearer ${WHATSAPP_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "messaging_product": "whatsapp",
      "to": "16048168818",
      "type": "template",
      "template": { "name": "hello_world", "language": { "code": "en_US" } }
    }'
  ```

## Key constraints

- **24-hour window**: free text only after the user messaged you within 24h; otherwise
  error `131047` — send an approved template instead.
- **Templates need pre-approval** in the Meta dashboard (can take minutes to a day).
- **Rate / quality tiers**: new numbers start at a low daily unique-recipient cap that rises
  with good quality ratings.
- **`WHATSAPP_GRAPH_VERSION`** env overrides the default Graph API version (`v21.0`).

## Why not WhatsApp Web automation (Tier 2)?

Driving a logged-in WhatsApp Web session (Playwright) can send as a personal account, but
it is DOM-fragile, breaks on UI updates, and automated personal-account messaging violates
WhatsApp's ToS (ban risk). Prefer Tier 1 for personal, Tier 3 for business. Only build Tier 2
if the user explicitly accepts the fragility and ToS risk.
