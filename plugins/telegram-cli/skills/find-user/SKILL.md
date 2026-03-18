---
name: find-user
description: "Find and resolve Telegram users by username, phone number, or ID. Get profile info. TRIGGERS - telegram find user, telegram user info, telegram resolve username, telegram who is, telegram lookup, telegram profile"
allowed-tools: Bash, Read, Grep, Glob
---

# Find Telegram User

Resolve usernames, phone numbers, or IDs to full user/chat profile information.

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/telegram-cli}/scripts/send.py"

# By username
uv run --python 3.13 "$SCRIPT" find-user @username

# By user ID
uv run --python 3.13 "$SCRIPT" find-user 2124832490

# By phone (must be in contacts)
uv run --python 3.13 "$SCRIPT" find-user +16043008878

# Works for groups/channels too
uv run --python 3.13 "$SCRIPT" find-user @channelname
EOF
```

## Output

Returns JSON with profile information:

```json
{
  "type": "User",
  "id": 2124832490,
  "first_name": "Name",
  "last_name": null,
  "username": "username",
  "phone": "1234567890",
  "bot": false
}
```

For groups/channels:

```json
{
  "type": "Channel",
  "id": 1234567890,
  "title": "Group Name",
  "username": "groupname",
  "participants_count": 42
}
```
