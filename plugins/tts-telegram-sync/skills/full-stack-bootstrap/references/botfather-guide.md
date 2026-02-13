# BotFather Guide

Step-by-step guide for creating a Telegram bot via BotFather and managing its credentials.

## Creating a New Bot

### Step 1: Open BotFather

1. Open Telegram (desktop or mobile)
2. Search for `@BotFather` (verified blue checkmark)
3. Start a conversation with `/start`

### Step 2: Create the Bot

1. Send `/newbot`
2. BotFather asks: "Alright, a new bot. How are we going to call it?"
3. Enter a display name (e.g., `Claude Code Terry Bot`)
4. BotFather asks: "Good. Now let's choose a username for your bot."
5. Enter a username ending in `bot` (e.g., `ccterrybot`)
6. BotFather responds with the HTTP API token

### Step 3: Copy the Token

The token looks like: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`

**Never share this token publicly.** It provides full control over the bot.

### Step 4: Verify the Token

```bash
curl -s "https://api.telegram.org/bot<TOKEN>/getMe" | jq .
```

Expected response:

```json
{
  "ok": true,
  "result": {
    "id": 123456789,
    "is_bot": true,
    "first_name": "Claude Code Terry Bot",
    "username": "ccterrybot"
  }
}
```

## Getting Your chat_id

The bot needs your `chat_id` to send messages to you directly.

### Step 1: Send a Message to the Bot

Open your bot in Telegram and send any message (e.g., `/start` or `hello`).

### Step 2: Retrieve the chat_id

```bash
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | jq '.result[0].message.chat.id'
```

This returns your numeric chat ID (e.g., `987654321`).

## Storing Credentials

### Secrets File

Store both `BOT_TOKEN` and `CHAT_ID` in the secrets file:

```bash
mkdir -p ~/.claude/.secrets
chmod 700 ~/.claude/.secrets

cat > ~/.claude/.secrets/ccterrybot-telegram << 'EOF'
BOT_TOKEN=<your-bot-token>
CHAT_ID=<your-chat-id>
EOF

chmod 600 ~/.claude/.secrets/ccterrybot-telegram
```

### mise Integration

The bot's `.mise.local.toml` (gitignored) loads the secrets file:

```toml
[env]
_.file = "{{env.HOME}}/.claude/.secrets/ccterrybot-telegram"
```

This makes `BOT_TOKEN` and `CHAT_ID` available as environment variables when mise is activated in the bot directory.

## Managing the Bot

### Useful BotFather Commands

| Command           | Purpose                                |
| ----------------- | -------------------------------------- |
| `/mybots`         | List all your bots                     |
| `/setname`        | Change bot display name                |
| `/setdescription` | Set bot description (shown on profile) |
| `/setabouttext`   | Set "About" text                       |
| `/setuserpic`     | Set bot profile picture                |
| `/setcommands`    | Define bot command menu                |
| `/deletebot`      | Permanently delete a bot               |
| `/token`          | View current token                     |
| `/revoke`         | Revoke and regenerate token            |

### Revoking a Compromised Token

If the token is leaked:

1. Open `@BotFather`
2. Send `/revoke`
3. Select the bot
4. BotFather generates a new token
5. Update `~/.claude/.secrets/ccterrybot-telegram` with the new token
6. Restart the bot process

## Verifying an Existing Token

If a token already exists at `~/.claude/.secrets/ccterrybot-telegram`:

```bash
# Source the secrets file
source ~/.claude/.secrets/ccterrybot-telegram

# Verify token is valid
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" | jq '.ok'
# Expected: true

# Verify chat_id receives messages
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "text=Bootstrap verification" | jq '.ok'
# Expected: true
```

If both return `true`, skip the BotFather setup phase.
