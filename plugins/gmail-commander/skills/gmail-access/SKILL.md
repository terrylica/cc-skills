---
name: gmail-access
description: Access Gmail via CLI with 1Password OAuth. Use when user wants to read emails, search inbox, export messages, create drafts, or.
allowed-tools: Read, Bash, Grep, Glob, Write, AskUserQuestion
---

# Gmail Access

Read and search Gmail programmatically via Claude Code.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## MANDATORY PREFLIGHT (Execute Before Any Gmail Operation)

**CRITICAL**: You MUST complete this preflight checklist before running any Gmail commands. Do NOT skip steps.

### Step 1: Check CLI Binary Exists

```bash
ls -la "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail" 2>/dev/null || echo "BINARY_NOT_FOUND"
```

**If BINARY_NOT_FOUND**: Build it first:

```bash
cd ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli && bun install && bun run build
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

# Quick connectivity test — shows the account email from a real email
echo ""
echo "=== Account Verification ==="
$GMAIL_CLI list -n 1 2>&1 | head -5
```

**STOP and confirm with user** before proceeding:

- The `list -n 1` output shows the account's inbox — verify this matches the project's intended email
- If the wrong account is shown, check which `.mise.local.toml` sets `GMAIL_OP_UUID` in the mise hierarchy
- If mismatch, inform user and do NOT proceed

**Multi-account disambiguation (when `GMAIL_OP_UUID` is NOT_SET but tokens exist).**
There is no `whoami` subcommand; map each cached token UUID to its mailbox by
probing, then pick the one that fits the project:

```bash
# Which accounts are cached, and which mailbox does each resolve to?
for f in ~/.claude/tools/gmail-tokens/*.json; do
  case "$(basename "$f")" in *.app-credentials.json|'*.json') continue ;; esac
  uuid=$(basename "$f" .json)
  who=$(GMAIL_OP_UUID="$uuid" $GMAIL_CLI list -n 1 --json 2>/dev/null \
        | jq -r '.[0].to // "(probe failed / token expired)"')
  echo "$uuid → $who"
done
```

A probe that returns `invalid_grant` means that account's refresh token is dead
(see "Diagnosing `invalid_grant`"). Pick the working UUID whose mailbox matches
the project, pin it in `.mise.local.toml`, and confirm it's gitignored. A child
project often needs a DIFFERENT account than its parent — verify, never assume
the parent's UUID.

### Step 3: Verify Token Health

```bash
# Check cached token exists and is not expired
TOKEN_FILE="$HOME/.claude/tools/gmail-tokens/${GMAIL_OP_UUID}.json"
APP_CREDS="$HOME/.claude/tools/gmail-tokens/${GMAIL_OP_UUID}.app-credentials.json"
echo "Token file: $([ -f "$TOKEN_FILE" ] && echo "EXISTS" || echo "MISSING")"
echo "App credentials: $([ -f "$APP_CREDS" ] && echo "CACHED" || echo "MISSING — will need 1Password on first run")"
```

**If token file is MISSING**: First run will open a browser for OAuth consent. This is expected.
**If app credentials are MISSING**: 1Password will be called once to cache `client_id`/`client_secret`, then never again.

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
# Try common vaults — "Claude Automation" for service accounts, "Employee" for interactive
for VAULT in "Claude Automation" "Employee" "Personal"; do
  ITEMS=$(op item list --vault "$VAULT" --format json 2>/dev/null | jq -r '.[] | select(.title | test("gmail|oauth|google"; "i")) | "\(.id)\t\(.title)"')
  [ -n "$ITEMS" ] && echo "=== Vault: $VAULT ===" && echo "$ITEMS"
done
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
GMAIL_OP_UUID="${GMAIL_OP_UUID}" $HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail list -n 1
```

**If OAuth prompt appears**: This is expected on first run. Browser will open for Google consent.

---

## Gmail Commands (Only After Preflight Passes)

```bash
GMAIL_CLI="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-cli/gmail"

# List recent emails
$GMAIL_CLI list -n 10

# Search emails
$GMAIL_CLI search "from:someone@example.com" -n 20

# Search with date range
$GMAIL_CLI search "from:phoebe after:2026/01/27" -n 10

# Read specific email with full body
$GMAIL_CLI read <message_id>

# Read and download inline images (copy-pasted screenshots in compose)
$GMAIL_CLI read <message_id> --save-images

# Download inline images to a specific directory
$GMAIL_CLI read <message_id> --save-images --image-dir ./attachments/my-folder/

# Shorthand: --image-dir implies --save-images
$GMAIL_CLI read <message_id> --image-dir ./attachments/my-folder/

# JSON output with image metadata and saved paths
$GMAIL_CLI read <message_id> --save-images --json

# Download REAL file attachments (PDF, docx, csv, …) — distinct from inline images
$GMAIL_CLI read <message_id> --save-attachments

# Download attachments to a specific directory (implies --save-attachments)
$GMAIL_CLI read <message_id> --attachment-dir ./files/case-17402939/

# Export search results to JSON (full body + inlineImages + attachments metadata per message)
$GMAIL_CLI export -q "label:inbox" -o emails.json -n 100

# JSON output (for parsing)
$GMAIL_CLI list -n 10 --json

# Create a draft email
$GMAIL_CLI draft --to "user@example.com" --subject "Hello" --body "Message body"

# Create a draft reply (threads into existing conversation)
$GMAIL_CLI draft --to "user@example.com" --subject "Re: Hello" --body "Reply text" --reply-to <message_id>

# Draft with body loaded from a file (multi-paragraph bodies are awkward via --body)
$GMAIL_CLI draft --to "user@example.com" --subject "Report" --body-file ./email-body.txt

# Draft with file attachments (--attach is repeatable; MIME type guessed from extension)
$GMAIL_CLI draft --to "user@example.com" --subject "Q1 Report" \
  --body-file ./email-body.txt \
  --attach ./report.pdf \
  --attach ./screenshot.png

# Draft reply with both body-file and multiple attachments
$GMAIL_CLI draft --to "user@example.com" --subject "Re: Project" \
  --reply-to <message_id> \
  --body-file ./reply.txt \
  --attach ./diagram.pdf
```

## Inline Image Extraction

Emails often contain **copy-pasted screenshots** (inline images embedded in the HTML body, not file attachments). These appear as `[image: image.png]` placeholders in plain text but contain real image data accessible via the Gmail API.

### Key Behavior

| Flag                 | Effect                                                                                     |
| -------------------- | ------------------------------------------------------------------------------------------ |
| `--save-images`      | Download all inline images to disk (default: `~/.claude/tools/gmail-images/<message_id>/`) |
| `--image-dir <path>` | Custom output directory (implies `--save-images`)                                          |
| No flag              | Shows image metadata (count, filenames, sizes) but does NOT download                       |

### Output Sections (when images are present)

```
--- Inline Images (3) ---
  image.png   image/png   245.3 KB
  image.png   image/png   512.1 KB
  photo.jpg   image/jpeg  89.7 KB

--- Saved to Disk ---
  ./attachments/01_image.png  (251,234 B)
  ./attachments/02_image.png  (524,001 B)
  ./attachments/03_photo.jpg  (91,852 B)

--- Markdown References ---
![01_image.png](./attachments/01_image.png)
![02_image.png](./attachments/02_image.png)
![03_photo.jpg](./attachments/03_photo.jpg)
```

### Important: Inline Images vs File Attachments

These are **two disjoint channels**, surfaced and downloaded separately:

| Channel              | MIME parts                                                             | Metadata field   | Download flag                             |
| -------------------- | ---------------------------------------------------------------------- | ---------------- | ----------------------------------------- |
| **Inline images**    | `image/*` with `attachmentId` (copy-pasted screenshots)                | `inlineImages[]` | `--save-images` / `--image-dir`           |
| **File attachments** | non-image parts with a `filename` + `attachmentId` (PDF, docx, csv, …) | `attachments[]`  | `--save-attachments` / `--attachment-dir` |

A plain `gmail read <id>` (no flags) shows **both** as metadata blocks (filename, MIME, size) without downloading — so you can see a PDF exists before pulling it. `export` and `read --json` both carry `attachments[]` (and `inlineImages[]`) in their JSON.

**`has:attachment` matches real file attachments but NOT inline images.** Gmail search has no operator for inline images. To discover emails with inline images, you must read the email and check the MIME tree.

**Strategy for finding emails with inline images:**

```bash
# Search by sender/date, then read each to check for images
$GMAIL_CLI search "from:sender@example.com after:2026/02/01" -n 10 --json | \
  jq -r '.[].id' | while read id; do
    COUNT=$($GMAIL_CLI read "$id" --json | jq '.inlineImages | length')
    [ "$COUNT" -gt 0 ] && echo "$id has $COUNT inline image(s)"
  done
```

### Gmail Threading and Image Deduplication

When downloading images from a **thread** (multiple reply emails), later replies include all prior inline images. The last email in a thread is typically the superset.

**Recommendation**: For threaded conversations, download images from the **latest reply only** to avoid duplicates. Compare by file size if unsure.

### Filename Collision Handling

Copy-pasted screenshots often all share the generic filename `image.png`. The CLI prefixes a zero-padded index: `01_image.png`, `02_image.png`, etc. These machine-generated names should be renamed to descriptive names for correspondence archival.

### Post-Download: Annotation Transcription Protocol

When inline images contain **handwritten annotations** (circles, arrows, written text overlaid on screenshots), perform a systematic two-level analysis:

1. **Scene description**: What does the screenshot show? (e.g., "Career portal main page showing position listings")
2. **Annotation inventory**: Exhaustively catalog every non-original markup element:
   - **Hand-drawn shapes**: circles, ovals, arrows, underlines, crosses — note what they encompass
   - **Handwritten text**: transcribe verbatim in quotes, note legibility and location on the image
   - **Typed test inputs**: text entered into form fields visible in the screenshot
   - **Highlights or color markings**: note color and what is highlighted

**Format annotations as blockquote captions** beneath each image in markdown:

```markdown
![Scene description — annotation summary](path/to/image.png)

> **Annotation transcription**: [Detailed description of visual markup.]
> Handwritten text reads: _"exact transcription here"_
> [Interpretation of what the annotator is requesting.]
```

**Do NOT defer annotation transcription to a second pass.** Capture all annotations on the first image examination to avoid redundant re-reads.

## File Attachment Extraction

Real file attachments (PDF, docx, csv, …) are surfaced in `attachments[]` and
downloaded with `--save-attachments` / `--attachment-dir`. Same fetch path as
inline images, different metadata field.

```bash
# See what a message carries (no download) — both metadata blocks print
$GMAIL_CLI read <id>          # → "--- Attachments (1) ---  foo.pdf  application/pdf  192.5 KB"

# Download to a chosen dir; files are index-prefixed + sanitized
$GMAIL_CLI read <id> --attachment-dir ./files/

# Discover which messages in a corpus actually carry attachments
$GMAIL_CLI search "from:sender@example.com has:attachment" -n 20 --json | \
  jq -r '.[].id' | while IFS= read -r id; do
    N=$($GMAIL_CLI read "$id" --json | jq '.attachments | length')
    [ "$N" -gt 0 ] && echo "$id → $N attachment(s)"
  done
```

**Why this matters for archival**: in clinical/legal/operational mail the
attached PDF (a protocol, a vendor form, a signed consent) is often the most
important payload. A body-only export silently loses it. Always check
`attachments[]` when archiving a correspondence thread.

## Bulk Retrieval & Thread Archival

The canonical pattern for archiving a whole correspondence (verified on a
27-message, 15-thread clinical corpus):

1. **Scope with high-signal queries, not generic keywords.** A bare keyword
   (`"Curve"`) returns mostly newsletter noise. Prefer:
   - **domain**: `curvedental.com` (matches from/to/cc on the org)
   - **participant**: `from:dr.phoebe.tsang@gmail.com OR to:…`
   - **project code**: any internal tag the sender uses (e.g. `1233V`)
2. **Collect message IDs** from `search --json` (snippet-only) and curate the
   in-scope set out of the noise.
3. **Fetch full bodies** with a `read --json` loop (one file per message).
4. **Group by `threadId`** client-side — Gmail's list/search APIs return
   individual messages, _not_ threads; you reconstruct threads yourself.
5. **Sort within a thread by parsed `Date`** and **strip quoted history**
   (drop `>`-prefixed lines and everything after `On … wrote:`) to expose each
   message's new content.
6. **Pull attachments** for any message whose `attachments[]` is non-empty.

```bash
# Robust batch fetch. NOTE: in zsh `for id in $VAR` does NOT word-split —
# always loop with `while IFS= read -r` over newline-delimited IDs.
printf '%s\n' $IDS | while IFS= read -r id; do
  [ -n "$id" ] && $GMAIL_CLI read "$id" --json > "raw/$id.json"
done
```

### `export` is the one-call shortcut (fixed)

`gmail export -q "<query>" -o out.json -n N` writes one JSON array with full
body + `inlineImages[]` + `attachments[]` per message — the batch-fetch
shortcut when a single query captures your set. (Historical note: before the
fix, `export` printed `"Exported N emails to <path>"` but **wrote no file** —
`outputPath` was an unused parameter. If you see that symptom, the binary is
stale; rebuild it.) `export` does **not** download attachment bytes — it only
carries the metadata; use `read --save-attachments` per message for the files.

## Creating Draft Emails

The `draft` command creates emails in your Gmail Drafts folder for review before sending.

**Required options:**

- `--to` - Recipient email address
- `--subject` - Email subject line
- `--body` OR `--body-file` - Email body text (one of the two)

**Optional:**

- `--body-file` - Read body from a file instead of `--body`. Useful for multi-paragraph bodies that are awkward to pass on the shell. Mutually exclusive with `--body`; if both are passed, `--body` wins with a stderr warning.
- `--attach` - File path to attach. **Repeatable** for multiple attachments. MIME type is guessed from extension (PDF, PNG, JPEG, DOCX, XLSX, ZIP, MD, JSON, etc. → mapped; unknown → `application/octet-stream`). Total message size ≤ 25 MB (Gmail limit; the CLI surfaces a 413 with a helpful hint if you exceed it).
- `--from` - Sender email alias (auto-detected when replying, see Sender Alignment below)
- `--reply-to` - Message ID to reply to (creates threaded reply with proper headers)
- `--json` - Output draft details as JSON

### MANDATORY Sender Alignment (NON-NEGOTIABLE)

The user has multiple Send As aliases configured in Gmail. The From address MUST match correctly or the recipient sees a reply from the wrong identity.

**Rule 1 - Replies (--reply-to is set):**
The CLI auto-detects the correct sender by reading the original email's To/Cc/Delivered-To headers and matching against the user's Send As aliases. No manual intervention needed. The CLI will print:

```
From: amonic@gmail.com (auto-detected from original email)
```

If auto-detection fails (e.g., the email was BCC'd), explicitly pass `--from`.

**Rule 2 - New emails (no --reply-to):**
When drafting a brand new email (not a reply), you MUST use AskUserQuestion to confirm which sender alias to use BEFORE creating the draft. Never assume the default.

```
AskUserQuestion({
  questions: [{
    question: "Which email address should this be sent from?",
    header: "Send As",
    options: [
      // Populate from known aliases or let user specify
      { label: "amonic@gmail.com", description: "Personal Gmail" },
      { label: "terry@eonlabs.com", description: "Work email" },
    ],
    multiSelect: false
  }]
})
```

Then pass the selected address via `--from`:

```bash
$GMAIL_CLI draft --to "recipient@example.com" --from "amonic@gmail.com" --subject "Hello" --body "Message"
```

**Rule 3 - Always verify in output:**
After draft creation, confirm the From address is shown in the output. If it's missing or wrong, delete the draft and recreate.

### MANDATORY Post-Draft Step (NON-NEGOTIABLE)

After EVERY draft creation, you MUST present the user with a direct Gmail link to review the draft. This is critical because drafts should always be visually confirmed before sending.

**Always output this after creating a draft:**

```
Draft created! Review it here:
  https://mail.google.com/mail/u/0/#drafts
From: <sender_address>
```

**Never skip this step.** The user must be able to click through to Gmail and visually verify the draft content, sender, recipients, and threading before sending.

### Example: Reply to an email (auto-detected sender)

```bash
# 1. Find the message to reply to
$GMAIL_CLI search "from:someone@example.com subject:meeting" -n 5 --json

# 2. Create draft reply - From is auto-detected from original email's To header
$GMAIL_CLI draft \
  --to "someone@example.com" \
  --subject "Re: Meeting tomorrow" \
  --body "Thanks for the update. I'll be there at 2pm." \
  --reply-to "19c1e6a97124aed8"

# 3. ALWAYS present the review link + From address to user
```

### Example: New email (must ask user for sender)

```bash
# 1. Ask user which alias to send from (AskUserQuestion)
# 2. Create draft with explicit --from
$GMAIL_CLI draft \
  --to "someone@example.com" \
  --from "amonic@gmail.com" \
  --subject "Hello" \
  --body "Message body"

# 3. ALWAYS present the review link + From address to user
```

**Note:** After creating drafts, users need to re-authenticate if they previously only had read access. The CLI will prompt for OAuth consent to add the `gmail.compose` scope.

## Gmail Search Syntax

| Query                      | Description                                                                          |
| -------------------------- | ------------------------------------------------------------------------------------ |
| `from:sender@example.com`  | From specific sender                                                                 |
| `to:recipient@example.com` | To specific recipient                                                                |
| `subject:keyword`          | Subject contains keyword                                                             |
| `after:2026/01/01`         | After date                                                                           |
| `before:2026/02/01`        | Before date                                                                          |
| `label:inbox`              | Has label                                                                            |
| `is:unread`                | Unread emails                                                                        |
| `has:attachment`           | Has file attachment (**does NOT match inline images** — see Inline Image Extraction) |

Reference: <https://support.google.com/mail/answer/7190>

## Environment Variables

| Variable         | Required | Description                                                                                                                                                                                       |
| ---------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GMAIL_OP_UUID`  | Yes      | 1Password item UUID for OAuth credentials                                                                                                                                                         |
| `GMAIL_OP_VAULT` | No       | 1Password vault (default: `Employee`)                                                                                                                                                             |
| `HTTPS_PROXY`    | No       | Honored by the underlying `gaxios` library, BUT the CLI auto-injects `*.googleapis.com` into `NO_PROXY` at startup so corporate proxies don't break Gmail traffic. See "Proxy Auto-Bypass" below. |

## Proxy Auto-Bypass for Google API Hosts

If `HTTPS_PROXY` (or `HTTP_PROXY`) is set in the environment, the CLI automatically injects the following hosts into `NO_PROXY` at module load — **before any auth or API call is made**:

- `.googleapis.com` (covers `gmail.googleapis.com`, `oauth2.googleapis.com`, etc.)
- `.google.com`
- `accounts.google.com`
- `oauth2.googleapis.com`

**Why this exists**: many corporate networks (Cloudflare WARP, mitmproxy local interceptors, ITP-style local proxies) can't tunnel CONNECT to Google API hosts. When the proxy fails, the response surface returns HTTP 502 with an empty error body — the googleapis library throws a gaxios error whose `.message` is empty, which used to render as a useless empty `Error:` in stderr.

By force-bypassing the proxy for Google hosts, end-users with a corporate proxy can run the CLI without manually setting `NO_PROXY` or unsetting `HTTPS_PROXY` per-command.

**Idempotent**: the injection only adds entries that aren't already present in `NO_PROXY`. If you've manually configured `NO_PROXY=.googleapis.com`, the CLI leaves it alone.

**Diagnosing remaining proxy issues** (rare): if you still see HTTP 5xx errors, the CLI's new error formatter prints the full URL + response body + a hint. Check that `HTTPS_PROXY` was set BEFORE the CLI started (env-var detection is one-shot at module load).

## Error Messages

The CLI's top-level error handler renders unknown errors as structured messages with HTTP status, request URL, response body snippet, and a category-specific hint. Example for a 404 on a bogus draft ID:

```
Error: HTTP 404 Not Found DELETE https://gmail.googleapis.com/gmail/v1/users/me/drafts/r-doesnotexist123
  body: {"error":{"code":404,"message":"Requested entity was not found.",...}}
  hint: message / draft ID not found. List existing drafts with `gmail drafts` first.
```

Hint categories:

| Status      | Hint                                                                                                                                                     |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 401         | Token expired/revoked. Delete `~/.claude/tools/gmail-tokens/$GMAIL_OP_UUID.json` to force re-auth.                                                       |
| 403         | OAuth scope insufficient (drafts/attachments need `gmail.compose`) or Send As alias not configured.                                                      |
| 404         | Message / draft ID not found. List existing drafts with `gmail drafts` first.                                                                            |
| 413         | Attachment(s) exceed Gmail's 25 MB per-message limit. Split or use Drive links.                                                                          |
| 502/503/504 | Gateway error — usually a proxy that can't tunnel to Google. The auto-bypass should prevent this; check that HTTPS_PROXY was set BEFORE the CLI started. |

Network-layer errors (`ECONNREFUSED`, `ENOTFOUND`, etc.) are surfaced with their error code instead of the empty `Error:` of the prior implementation.

## Token Architecture

### Storage Layout

```
~/.claude/tools/gmail-tokens/
├── <uuid>.json                    # OAuth token (access + refresh), refreshed hourly
└── <uuid>.app-credentials.json    # client_id + client_secret (static, cached from 1Password)
```

- Central location (not in plugin, not in project)
- Organized by 1Password UUID (supports multi-account)
- Created with chmod 600

### Auth Flow (1Password is one-time only)

1. **First run**: 1Password is called to fetch `client_id`/`client_secret` → cached to `<uuid>.app-credentials.json`
2. **First run**: Browser opens for Google OAuth consent → tokens saved to `<uuid>.json`
3. **All subsequent runs**: Reads cached files only — **no 1Password call, no browser**
4. **Hourly refresher** (launchd): Keeps access_token alive by calling Google's token endpoint with the cached refresh_token

To force a fresh 1Password lookup (e.g., after rotating OAuth app credentials):

```bash
rm ~/.claude/tools/gmail-tokens/<uuid>.app-credentials.json
```

### Diagnosing `invalid_grant`

A refresh token in a Google OAuth app whose **publishing status is "Testing"** expires after **7 days — period.** The hourly refresher renews the _access_ token but does NOT extend the _refresh_ token's 7-day clock, so a Testing-mode account dies roughly weekly and can only be revived by a browser re-consent. (An app in **"In production"** status issues long-lived refresh tokens that don't expire on that clock.)

**Recovery (re-consent)**: Delete the expired token file and re-authorize via browser:

```bash
# 1. Back up and remove the expired token
mv ~/.claude/tools/gmail-tokens/<uuid>.json ~/.claude/tools/gmail-tokens/<uuid>.json.expired

# 2. Run any gmail command — browser will open for OAuth consent
#    (sign in with the SPECIFIC account that <uuid> maps to — see accounts.json labels)
$GMAIL_CLI list -n 1

# 3. Verify the hourly refresher picks up the new token
~/.claude/automation/gmail-token-refresher/gmail-oauth-token-refresher 2>&1

# 4. Clean up backup
rm ~/.claude/tools/gmail-tokens/<uuid>.json.expired
```

**Durable fix (stop the weekly death — "keep everything re-auth")**: publish the
OAuth app to Production so refresh tokens stop expiring on the 7-day clock.

1. If an account survives indefinitely while another dies weekly, they use
   **different OAuth apps** (check `accounts.json` `vault` per uuid). Only the
   dying one is stuck in Testing.
2. Google Cloud Console → the project owning that OAuth client (the
   `client_id` prefix is the project number; the CLI prints the full
   `client_id` in the consent URL during re-auth).
3. **APIs & Services → OAuth consent screen → Publishing status → Publish app
   → confirm "In production".** (External + Production with Gmail scopes may
   warn "unverified" for _new_ users, but already-consented accounts get
   long-lived refresh tokens; full Google verification is only needed for
   public/>100-user apps.)
4. Re-consent once more after publishing; the hourly refresher then keeps the
   access token fresh indefinitely with no weekly re-auth.

### Multi-Account Token Status

```bash
# Check all accounts at once
for f in ~/.claude/tools/gmail-tokens/*.json; do
  [ "$(basename "$f")" = "*.json" ] && continue
  case "$(basename "$f")" in *.app-credentials.json) continue ;; esac
  UUID=$(basename "$f" .json)
  python3 -c "
import json, datetime
t = json.load(open('$f'))
exp = datetime.datetime.fromtimestamp(t.get('expiry_date',0)/1000)
delta = (exp - datetime.datetime.now()).total_seconds()
status = 'VALID' if delta > 0 else 'EXPIRED'
print(f'  {\"$UUID\"}: {status} (expires in {int(delta/60)}m)' if delta > 0 else f'  {\"$UUID\"}: EXPIRED ({int(-delta/3600)}h ago)')
" 2>/dev/null
done
```

## References

- [mise-templates.md](./references/mise-templates.md) - Complete mise configuration templates
- [mise-setup.md](./references/mise-setup.md) - Step-by-step mise setup guide
- [gmail-api-setup.md](./references/gmail-api-setup.md) - Google Cloud OAuth setup guide

## Post-Change Checklist

- [ ] YAML frontmatter valid (no colons in description)
- [ ] Trigger keywords current
- [ ] Path patterns use $HOME not hardcoded paths
- [ ] References exist and are linked

## Evolution Log

- **2026-05-31 — export silent failure + no attachment retrieval (clinical archival task).**
  - _Trigger_: archiving a 27-message Curve-Dental correspondence. `gmail export -o <path>` printed `"Exported N emails to <path>"` but wrote nothing (`exportEmails` returned the array, never wrote `outputPath`). Separately, the CLI surfaced no file attachments (only `inlineImages`), so 11 messages' attached PDFs (a vendor certification form, protocols) were silently dropped.
  - _Fix_: (1) `exportEmails` now `writeFile`s the JSON. (2) Added `extractAttachments` + `attachments[]` metadata in `formatMessage`, `saveAttachments()` in gmail-images.ts, `--save-attachments`/`--attachment-dir` flags, and an Attachments metadata block in `printEmails`. Documented the inline-image-vs-attachment split, the bulk thread-archival pipeline, the multi-account UUID→mailbox probe, and the zsh `while read` batch-loop gotcha.
  - _Evidence_: `export -q curvedental.com -o /tmp/x.json` now writes 3 emails with full bodies; `read <id> --attachment-dir` pulled `CDAnet Software Vendor Certification Application form.pdf` (197,168 B, valid PDF 1.7, 3 pages). Rebuilt binary, `tsc --noEmit` clean.

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path before editing.
1. **What failed?** — Fix the instruction that caused it.
2. **What worked better than expected?** — Promote to recommended practice.
3. **What drifted?** — Fix any script, reference, or dependency that no longer matches reality.
4. **Log it.** — Evolution-log entry with trigger, fix, and evidence.

Do NOT defer. The next invocation inherits whatever you leave behind.
