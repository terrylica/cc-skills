---
name: create-group
description: "Create Telegram groups, supergroups, or channels. Optionally invite users on creation. TRIGGERS - telegram create group, telegram new group, telegram create channel, telegram new channel, make telegram group"
allowed-tools: Bash, Read, Grep, Glob
---

# Create Telegram Group/Channel

Create groups, supergroups, or channels and optionally invite users.

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/send.py"

# Create supergroup (default)
uv run --python 3.13 "$SCRIPT" create-group "My Group" --about "Group description"

# Create with initial members
uv run --python 3.13 "$SCRIPT" create-group "Project Chat" --users @user1 @user2

# Create broadcast channel
uv run --python 3.13 "$SCRIPT" create-group "Announcements" --type channel --about "Updates"

# Create legacy group (limited to ~200 members)
uv run --python 3.13 "$SCRIPT" create-group "Small Team" --type group --users @teammate
EOF
```

## Parameters

| Parameter | Type   | Description                                |
| --------- | ------ | ------------------------------------------ |
| title     | string | Group/channel name                         |
| `--type`  | choice | `supergroup` (default), `channel`, `group` |
| `--about` | string | Description text                           |
| `--users` | list   | Users to invite (usernames or IDs)         |

## Group Types

| Type         | Members   | Messaging             | Use Case          |
| ------------ | --------- | --------------------- | ----------------- |
| `group`      | ~200 max  | Two-way               | Small teams       |
| `supergroup` | 200K max  | Two-way + admin tools | Large communities |
| `channel`    | Unlimited | One-way (admins only) | Broadcasts        |
