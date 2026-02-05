---
name: gmail-access
description: Access Gmail via CLI with 1Password OAuth. Use when user wants to read emails, search inbox, export messages, create drafts, or mentions gmail access. TRIGGERS - gmail, email, read email, list emails, search inbox, export emails, create draft, draft email, compose email.
allowed-tools: Read, Bash, Grep, Glob, Write, AskUserQuestion
---

# Gmail Access

Read and search Gmail programmatically via Claude Code CLI.

## MANDATORY PREFLIGHT (Execute Before Any Gmail Operation)

**CRITICAL**: You MUST complete this preflight checklist before running any Gmail commands. Do NOT skip steps.

### Step 1: Check CLI Binary Exists

```bash
ls -la "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-tools/skills/gmail-access/scripts/gmail" 2>/dev/null || echo "BINARY_NOT_FOUND"
```

**If BINARY_NOT_FOUND**: Build it first:

```bash
cd ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-tools/skills/gmail-access/scripts && bun install && bun run build
```

### Step 2: Check GMAIL_OP_UUID Environment Variable

```bash
echo "GMAIL_OP_UUID: ${GMAIL_OP_UUID:-NOT_SET}"
```

**If NOT_SET**: You MUST run the Setup Flow below. Do NOT proceed to Gmail commands.

### Step 2.5: Verify Account Context (CRITICAL)

**ALWAYS verify you're accessing the correct email account for the current project.**

```bash
# Show current project context
echo "=== Gmail Account Context ==="
echo "Working directory: $(pwd)"
echo "GMAIL_OP_UUID: ${GMAIL_OP_UUID}"

# Check where GMAIL_OP_UUID is defined (mise hierarchy)
echo ""
echo "=== mise Config Source ==="
grep -l "GMAIL_OP_UUID" .mise.local.toml .mise.toml ~/.config/mise/config.toml 2>/dev/null || echo "Not found in standard locations"

# Get the email address from 1Password for this UUID
echo ""
echo "=== Email Account for this UUID ==="
op item get "${GMAIL_OP_UUID}" --fields label=email 2>/dev/null || op item get "${GMAIL_OP_UUID}" --format json 2>/dev/null | jq -r '.title'
```

**STOP and confirm with user** before proceeding:

- Display the email account that will be accessed
- Verify this matches the project's intended email (check `RECRUITER_EMAIL` or similar project-specific vars)
- If mismatch, inform user and do NOT proceed

**Example verification:**

```bash
# Compare configured email with project expectation
PROJECT_EMAIL="${RECRUITER_EMAIL:-$(grep -m1 'email' .mise.toml 2>/dev/null | cut -d'"' -f2)}"
echo "Project expects: ${PROJECT_EMAIL:-'(not specified)'}"
echo "Gmail UUID maps to: $(op item get "${GMAIL_OP_UUID}" --fields label=email 2>/dev/null)"
```

### Step 3: Verify 1Password Authentication

```bash
op account list 2>&1 | head -3
```

**If error or not signed in**: Inform user to run `op signin` first.

---

## Setup Flow (When GMAIL_OP_UUID is NOT_SET)

Follow these steps IN ORDER. Use AskUserQuestion at decision points.

### Setup Step 1: Check 1Password CLI

```bash
command -v op && echo "OP_CLI_INSTALLED" || echo "OP_CLI_MISSING"
```

**If OP_CLI_MISSING**: Stop and inform user:

> 1Password CLI is required. Install with: `brew install 1password-cli`

### Setup Step 2: Discover Gmail OAuth Items in 1Password

```bash
op item list --vault Employee --format json 2>/dev/null | jq -r '.[] | select(.title | test("gmail|oauth|google"; "i")) | "\(.id)\t\(.title)"'
```

**Parse the output** and proceed based on results:

### Setup Step 3: User Selects OAuth Credentials

**If items found**, use AskUserQuestion with discovered items:

```
AskUserQuestion({
  questions: [{
    question: "Which 1Password item contains your Gmail OAuth credentials?",
    header: "Gmail OAuth",
    options: [
      // POPULATE FROM op item list RESULTS - example:
      { label: "Gmail API - dental-quizzes (56peh...)", description: "OAuth client in Employee vault" },
      { label: "Gmail API - personal (abc12...)", description: "Personal OAuth client" },
    ],
    multiSelect: false
  }]
})
```

**If NO items found**, use AskUserQuestion to guide setup:

```
AskUserQuestion({
  questions: [{
    question: "No Gmail OAuth credentials found in 1Password. How would you like to proceed?",
    header: "Setup",
    options: [
      { label: "Create new OAuth credentials (Recommended)", description: "I'll guide you through Google Cloud Console setup" },
      { label: "I have credentials elsewhere", description: "Help me add them to 1Password" },
      { label: "Skip for now", description: "I'll set this up later" }
    ],
    multiSelect: false
  }]
})
```

- If "Create new OAuth credentials": Read and present [references/gmail-api-setup.md](./references/gmail-api-setup.md)
- If "I have credentials elsewhere": Guide user to add to 1Password with required fields
- If "Skip for now": Inform user the skill won't work until configured

### Setup Step 4: Confirm mise Configuration

After user selects an item (with UUID), use AskUserQuestion:

```
AskUserQuestion({
  questions: [{
    question: "Add GMAIL_OP_UUID to .mise.local.toml in current project?",
    header: "Configure",
    options: [
      { label: "Yes, add to .mise.local.toml (Recommended)", description: "Creates/updates gitignored config file" },
      { label: "Show me the config only", description: "I'll add it manually" }
    ],
    multiSelect: false
  }]
})
```

**If "Yes, add to .mise.local.toml"**:

1. Check if `.mise.local.toml` exists
2. If exists, append `GMAIL_OP_UUID` to `[env]` section
3. If not exists, create with:

```toml
[env]
GMAIL_OP_UUID = "<selected-uuid>"
```

1. Verify `.mise.local.toml` is in `.gitignore`

**If "Show me the config only"**: Output the TOML for user to add manually.

### Setup Step 5: Reload and Verify

```bash
mise trust 2>/dev/null || true
cd . && echo "GMAIL_OP_UUID after reload: ${GMAIL_OP_UUID:-NOT_SET}"
```

**If still NOT_SET**: Inform user to restart their shell or run `source ~/.zshrc`.

### Setup Step 6: Test Connection

```bash
GMAIL_OP_UUID="${GMAIL_OP_UUID}" $HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-tools/skills/gmail-access/scripts/gmail list -n 1
```

**If OAuth prompt appears**: This is expected on first run. Browser will open for Google consent.

---

## Gmail Commands (Only After Preflight Passes)

```bash
GMAIL_CLI="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-tools/skills/gmail-access/scripts/gmail"

# List recent emails
$GMAIL_CLI list -n 10

# Search emails
$GMAIL_CLI search "from:someone@example.com" -n 20

# Search with date range
$GMAIL_CLI search "from:phoebe after:2026/01/27" -n 10

# Read specific email with full body
$GMAIL_CLI read <message_id>

# Export to JSON
$GMAIL_CLI export -q "label:inbox" -o emails.json -n 100

# JSON output (for parsing)
$GMAIL_CLI list -n 10 --json

# Create a draft email
$GMAIL_CLI draft --to "user@example.com" --subject "Hello" --body "Message body"

# Create a draft reply (threads into existing conversation)
$GMAIL_CLI draft --to "user@example.com" --subject "Re: Hello" --body "Reply text" --reply-to <message_id>
```

## Creating Draft Emails

The `draft` command creates emails in your Gmail Drafts folder for review before sending.

**Required options:**

- `--to` - Recipient email address
- `--subject` - Email subject line
- `--body` - Email body text

**Optional:**

- `--reply-to` - Message ID to reply to (creates threaded reply with proper headers)
- `--json` - Output draft details as JSON

**Example: Create reply drafts from conversation:**

```bash
# 1. Find the message to reply to
$GMAIL_CLI search "from:someone@example.com subject:meeting" -n 5 --json

# 2. Create draft reply using message ID
$GMAIL_CLI draft \
  --to "someone@example.com" \
  --subject "Re: Meeting tomorrow" \
  --body "Thanks for the update. I'll be there at 2pm." \
  --reply-to "19c1e6a97124aed8"

# 3. Review drafts in Gmail
# Open: https://mail.google.com/mail/u/0/#drafts
```

**Note:** After creating drafts, users need to re-authenticate if they previously only had read access. The CLI will prompt for OAuth consent to add the `gmail.compose` scope.

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

## Environment Variables

| Variable         | Required | Description                               |
| ---------------- | -------- | ----------------------------------------- |
| `GMAIL_OP_UUID`  | Yes      | 1Password item UUID for OAuth credentials |
| `GMAIL_OP_VAULT` | No       | 1Password vault (default: Employee)       |

## Token Storage

OAuth tokens stored at: `~/.claude/tools/gmail-tokens/<uuid>.json`

- Central location (not in plugin, not in project)
- Organized by 1Password UUID (supports multi-account)
- Created with chmod 600

## References

- [mise-templates.md](./references/mise-templates.md) - Complete mise configuration templates
- [mise-setup.md](./references/mise-setup.md) - Step-by-step mise setup guide
- [gmail-api-setup.md](./references/gmail-api-setup.md) - Google Cloud OAuth setup guide

## Post-Change Checklist

- [ ] YAML frontmatter valid (no colons in description)
- [ ] Trigger keywords current
- [ ] Path patterns use $HOME not hardcoded paths
- [ ] References exist and are linked
