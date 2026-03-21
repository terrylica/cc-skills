---
name: manage-members
description: "Manage Telegram group/channel members: invite, kick, list members, filter admins. TRIGGERS - telegram invite, telegram kick, telegram members, telegram add user, telegram remove user, telegram ban, list telegram members, telegram group members"
allowed-tools: Bash, Read, Grep, Glob
---

# Manage Telegram Members

Invite, kick, and list members in groups and channels.

## Usage

```bash
/usr/bin/env bash << 'EOF'
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/tlg}/scripts/send.py"

# Invite users
uv run --python 3.13 "$SCRIPT" invite <group> @user1 @user2

# Kick a user
uv run --python 3.13 "$SCRIPT" kick <group> @username

# List all members
uv run --python 3.13 "$SCRIPT" members <group>

# List admins only
uv run --python 3.13 "$SCRIPT" members <group> --admins

# Search members by name
uv run --python 3.13 "$SCRIPT" members <group> --search "Terry"
EOF
```

## Subcommands

### invite

| Parameter | Type       | Description                |
| --------- | ---------- | -------------------------- |
| group     | string/int | Group/channel              |
| users     | list       | Usernames or IDs to invite |

### kick

| Parameter | Type       | Description            |
| --------- | ---------- | ---------------------- |
| group     | string/int | Group/channel          |
| user      | string     | Username or ID to kick |

### members

| Parameter    | Type       | Description                |
| ------------ | ---------- | -------------------------- |
| group        | string/int | Group/channel              |
| `--search`   | string     | Filter by name/username    |
| `--admins`   | flag       | Show admins only           |
| `-n/--limit` | int        | Max members (default: 200) |

## Output Format

```
First Last @username (id: 12345) [admin]
```
