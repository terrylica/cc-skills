---
name: manage-members
description: "Use when user wants to manage Telegram group or channel members, including inviting users, kicking or banning someone, listing members, or filtering admins."
allowed-tools: Bash, Read, Grep, Glob
---

# Manage Telegram Members

Invite, kick, and list members in groups and channels.

## Preflight

1. Session must exist: `~/.local/share/telethon/<profile>.session`
   - If missing, run `/tlg:setup` first

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

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If send.py's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
