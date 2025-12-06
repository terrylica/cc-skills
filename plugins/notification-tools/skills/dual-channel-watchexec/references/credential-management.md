**Skill**: [Dual-Channel Watchexec Notifications](../SKILL.md)

## Credential Management

### Pattern 1: Doppler (Recommended)

**For Pushover** (notifications/dev):

```bash
# Load Pushover credentials from Doppler
export PUSHOVER_APP_TOKEN=$(doppler secrets get PUSHOVER_APP_TOKEN \
  --project notifications \
  --config dev \
  --plain)
export PUSHOVER_USER_KEY=$(doppler secrets get PUSHOVER_USER_KEY \
  --project notifications \
  --config dev \
  --plain)
```

**For Telegram** (generic example):

```bash
# Load from Doppler project (use bash wrapper for zsh compatibility)
/usr/bin/env bash -c 'export TELEGRAM_BOT_TOKEN=$(doppler secrets get TELEGRAM_BOT_TOKEN --plain) && export TELEGRAM_CHAT_ID=$(doppler secrets get TELEGRAM_CHAT_ID --plain)'
```

### Pattern 2: Environment Variables

```bash
# From shell environment
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] && [[ -n "${TELEGRAM_CHAT_ID:-}" ]]; then
    # Send notification
fi
```

### Pattern 3: Keychain (macOS)

```bash
/usr/bin/env bash -c 'PUSHOVER_TOKEN=$(security find-generic-password -s "pushover-app-token" -a "username" -w 2>/dev/null)'
```

**Security**: Never hardcode credentials in scripts or skill files!
