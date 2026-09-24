# Environment Setup for Cal.com Commander

Every Cal.com Commander component (CLI, bot, sync, deploy steps) reads plain process environment variables. Nothing loads a per-directory config file for you; jdx/mise, which used to, is retired and not used.

## Where the Variables Come From

| Consumer                       | Source                                                                                                                                                                     |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Interactive CLI / deploy steps | `export` in the current shell, or pass inline (`CALCOM_OP_UUID=<uuid> calcom event-types list`)                                                                            |
| Bot + sync (launchd)           | `~/own/amonic/.env.launchd` — gitignored, hand-maintained, the SSoT for daemon env in amonic. The launcher scripts in `~/own/amonic/bin/` `source` it before `exec`ing Bun |

Secrets themselves stay in 1Password. The `*_REF` variables hold `op://` references, resolved with `op read` at the point of use (for example `DATABASE_URL=$(op read "$SUPABASE_DB_URL_REF")`). `.env.launchd` is pre-baked rather than resolved at launch, which keeps launchd free of macOS Automation prompts.

## Variables

Add these to `~/own/amonic/.env.launchd` (daemons) or export them in your shell (interactive use), in `export KEY='value'` form:

```bash
# Cal.com API
export CALCOM_OP_UUID='<1password-item-uuid>'
export CALCOM_API_URL='https://your-instance.run.app'

# Telegram Bot
export TELEGRAM_BOT_TOKEN='<bot-token>'
export TELEGRAM_CHAT_ID='<chat-id>'

# AI Model
export HAIKU_MODEL='claude-haiku-4-5-20251001'

# GCP (for deployment)
export CALCOM_GCP_PROJECT='<gcp-project-id>'
export CALCOM_GCP_ACCOUNT='<gcp-account-email>'
export CALCOM_GCP_BILLING='<billing-account-id>'
export CALCOM_GCP_REGION='us-central1'

# Supabase
export SUPABASE_PROJECT_REF='<supabase-project-ref>'
export SUPABASE_DB_URL_REF='op://Claude Automation/<item-id>/DATABASE_URL'
export SUPABASE_DB_DIRECT_URL_REF='op://Claude Automation/<item-id>/DATABASE_DIRECT_URL'
export SUPABASE_ACCESS_TOKEN_REF='op://Claude Automation/<item-id>/credential'

# Cal.com Secrets (1Password)
export CALCOM_NEXTAUTH_SECRET_REF='op://Claude Automation/<item-id>/NEXTAUTH_SECRET'
export CALCOM_ENCRYPTION_KEY_REF='op://Claude Automation/<item-id>/CALENDSO_ENCRYPTION_KEY'
export CALCOM_CRON_API_KEY_REF='op://Claude Automation/<item-id>/CRON_API_KEY'
```

## Verify

```bash
env | grep -E "CALCOM|TELEGRAM|SUPABASE" | sed -E 's/=.*/=<set>/'
```

## Gitignore

`.env.launchd` must never be committed:

```bash
git -C ~/own/amonic check-ignore -q .env.launchd && echo "ignored" || echo "NOT IGNORED — fix .gitignore"
```
