---
name: gmail-access
description: Access Gmail via CLI with 1Password OAuth. Use when user wants to read emails, search inbox, export messages, or mentions gmail access. TRIGGERS - gmail, email, read email, list emails, search inbox, export emails.
allowed-tools: Read, Bash, Grep, Glob, Write, AskUserQuestion
---

# Gmail Access

Read and search Gmail programmatically via Claude Code CLI.

## Prerequisite Discovery

Before using Gmail commands, verify setup:

1. **Check environment**: `echo $GMAIL_OP_UUID`
2. **If not set**: Run discovery flow (see Setup section below)

## Commands

| Command                                | Description                          |
| -------------------------------------- | ------------------------------------ |
| `gmail list -n 10`                     | List recent emails                   |
| `gmail list -l INBOX -l UNREAD --json` | List with label filters, JSON output |
| `gmail search "from:x"`                | Search with Gmail query syntax       |
| `gmail read <id>`                      | Read full email body                 |
| `gmail export -q "query" -o file.json` | Export to JSON                       |

## Gmail Search Syntax

| Query                      | Description              |
| -------------------------- | ------------------------ |
| `from:sender@example.com`  | From specific sender     |
| `to:recipient@example.com` | To specific recipient    |
| `subject:keyword`          | Subject contains keyword |
| `after:2026/01/01`         | After date               |
| `before:2026/02/01`        | Before date              |
| `label:inbox`              | Has label                |
| `is:unread`                | Unread emails            |
| `has:attachment`           | Has attachment           |

Reference: <https://support.google.com/mail/answer/7190>

## Setup Flow

If `GMAIL_OP_UUID` is not set, follow this discovery flow:

### Step 1 - Check 1Password CLI

```bash
command -v op
```

If not installed, instruct user to install 1Password CLI.

### Step 2 - List Gmail OAuth items in 1Password

```bash
op item list --vault Employee --format json | jq '.[] | select(.title | test("gmail|oauth"; "i")) | {id, title}'
```

### Step 3 - User selects OAuth credentials

Use AskUserQuestion to let user select from discovered items:

```typescript
AskUserQuestion({
  questions: [
    {
      question: "Which 1Password item contains your Gmail OAuth credentials?",
      header: "Gmail OAuth",
      options: [
        // Populate from op item list results
        { label: "Item Name (uuid)", description: "OAuth client description" },
      ],
      multiSelect: false,
    },
  ],
});
```

If no items found:

```typescript
AskUserQuestion({
  questions: [
    {
      question:
        "No Gmail OAuth credentials found in 1Password. How would you like to proceed?",
      header: "Setup",
      options: [
        {
          label: "Create new OAuth credentials",
          description: "Guide through Google Cloud Console setup",
        },
        {
          label: "I have credentials elsewhere",
          description: "Help add them to 1Password",
        },
        { label: "Skip for now", description: "Set up later" },
      ],
      multiSelect: false,
    },
  ],
});
```

### Step 4 - Output mise configuration

After user selects item, output the configuration to add:

```toml
# Add to .mise.local.toml (gitignored)
[env]
GMAIL_OP_UUID = "<selected-uuid>"
```

### Step 5 - Confirm configuration update

```typescript
AskUserQuestion({
  questions: [
    {
      question: "Add GMAIL_OP_UUID to .mise.local.toml in current project?",
      header: "Configure",
      options: [
        {
          label: "Yes, add to .mise.local.toml (Recommended)",
          description: "Creates/updates gitignored config file",
        },
        {
          label: "Show me the config only",
          description: "I'll add it manually",
        },
      ],
      multiSelect: false,
    },
  ],
});
```

### Step 6 - Reload environment

Instruct user to reload mise:

```bash
cd . && mise trust
```

### Step 7 - Test

```bash
gmail list -n 1
```

## Environment Variables

| Variable         | Required | Description                               |
| ---------------- | -------- | ----------------------------------------- |
| `GMAIL_OP_UUID`  | Yes      | 1Password item UUID for OAuth credentials |
| `GMAIL_OP_VAULT` | No       | 1Password vault (default: Employee)       |

## mise Configuration Reference

See [references/mise-templates.md](./references/mise-templates.md) for complete templates:

- `.mise.local.toml` (gitignored, contains GMAIL_OP_UUID)
- `.mise.local.toml.example` (committed, template for users)
- `.mise.toml` gmail tasks (optional convenience tasks)

## Token Storage

OAuth tokens stored at: `~/.claude/tools/gmail-tokens/<uuid>.json`

- Central location (not in plugin, not in project)
- Organized by 1Password UUID (supports multi-account)
- Created with chmod 600

## Programmatic Usage

```typescript
import {
  createGmailClient,
  listEmails,
  searchEmails,
  readEmail,
} from "./scripts/lib/index.ts";

const client = await createGmailClient();
const emails = await listEmails(client, { maxResults: 10 });
console.log(emails);
```

## Post-Change Checklist

- [ ] YAML frontmatter valid (no colons in description)
- [ ] Trigger keywords current
- [ ] Path patterns use $HOME not hardcoded paths
- [ ] References exist and are linked
