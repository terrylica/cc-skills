# GitHub PAT Setup Guide

## Phase 3: GitHub PAT Setup

**Use AskUserQuestion:**

```
Question: "Do you already have a GitHub Fine-Grained PAT for asciinema backups?"
Header: "GitHub PAT"
Options:
  - label: "No, guide me through creating one (Recommended)"
    description: "Opens GitHub in browser with step-by-step instructions"
  - label: "Yes, I have a PAT ready"
    description: "I'll paste my existing PAT"
  - label: "What's a Fine-Grained PAT?"
    description: "Show explanation before proceeding"
```

**If "No, guide me through":**

1. Open browser:

```bash
open "https://github.com/settings/tokens?type=beta"
```

1. Display instructions:

```markdown
## Create GitHub Fine-Grained PAT

Follow these steps in the browser window that just opened:

1. Click **"Generate new token"**

2. **Token name**: `asciinema-chunker`

3. **Expiration**: 90 days (recommended) or custom
   - Longer expiration = less frequent token rotation
   - Shorter = more secure

4. **Repository access**: Click **"Only select repositories"**
   - Select your asciinema recording repositories
   - Example: `your-org/your-repository`

5. **Permissions** (expand "Repository permissions"):
   - **Contents**: Read and write
   - **Metadata**: Read-only

6. Click **"Generate token"**

7. **IMPORTANT**: Copy the token immediately!
   It starts with `github_pat_...`
   You won't be able to see it again.
```

**Use AskUserQuestion:**

```
Question: "Have you copied your new GitHub PAT?"
Header: "PAT Ready"
Options:
  - label: "Yes, I've copied it"
    description: "Proceed to enter the PAT"
  - label: "Not yet, still creating"
    description: "I need more time"
  - label: "I need help"
    description: "Show troubleshooting tips"
```

**If "Yes, I've copied it" - Use AskUserQuestion to get PAT:**

```
Question: "Paste your GitHub PAT (will be stored securely in macOS Keychain):"
Header: "PAT Input"
Options:
  - label: "Enter my PAT"
    description: "Use the 'Other' field below to paste your token"
```

User enters PAT via the "Other" option.

## Store in Keychain

```bash
/usr/bin/env bash << 'STORE_PAT_EOF'
PAT_VALUE="${1:?PAT required}"

# Store in Keychain (update if exists)
security add-generic-password \
  -s "asciinema-github-pat" \
  -a "$USER" \
  -w "$PAT_VALUE" \
  -U 2>/dev/null || \
security add-generic-password \
  -s "asciinema-github-pat" \
  -a "$USER" \
  -w "$PAT_VALUE"

echo "PAT stored in Keychain"
STORE_PAT_EOF
```

## Verify PAT

```bash
/usr/bin/env bash << 'VERIFY_PAT_EOF'
PAT_VALUE="${1:?PAT required}"

RESPONSE=$(curl -s -H "Authorization: Bearer $PAT_VALUE" \
  https://api.github.com/user 2>&1)

if echo "$RESPONSE" | jq -e '.login' &>/dev/null; then
  USERNAME=$(echo "$RESPONSE" | jq -r '.login')
  echo "PAT_VALID:$USERNAME"
else
  ERROR=$(echo "$RESPONSE" | jq -r '.message // "Unknown error"')
  echo "PAT_INVALID:$ERROR"
fi
VERIFY_PAT_EOF
```

**If PAT_INVALID, use AskUserQuestion:**

```
Question: "PAT verification failed: {error}. What would you like to do?"
Header: "PAT Error"
Options:
  - label: "Try a different PAT"
    description: "Enter a new PAT"
  - label: "Check PAT permissions"
    description: "Review required permissions"
  - label: "Continue anyway (not recommended)"
    description: "Proceed without verification"
```
