# GFM Anti-Patterns in Issue Comments

GitHub Flavored Markdown (GFM) has auto-linking behaviors that silently transform issue/PR comment content in unexpected ways. This reference documents known anti-patterns and their fixes.

---

## Foundational Principle: No Implicit References

**NEVER rely on `#N` shorthand for GitHub issue/PR references.** The `#N` notation causes two problems:

1. **False positives**: `#1` in a trade number column auto-links to Issue 1
2. **Inconsistency**: `#59` renders as plain text if Issue 59 doesn't exist, but `#4` becomes a link if Issue 4 does — same column, different rendering

**Rule**: Always suppress `#N` auto-linking. If you need to reference a GitHub issue, use an explicit full URL.

```markdown
<!-- BAD: implicit #N — auto-links unpredictably -->

See #13 for details.
Trade #1 had a TP exit.

<!-- GOOD: explicit URL for intentional issue references -->

See [Issue 13](https://github.com/owner/repo/issues/13) for details.

<!-- GOOD: backtick suppression for non-issue numbers -->

Trade `#1` had a TP exit.
```

---

## AP-01: `#N` Auto-Links Everywhere

**Problem**: GitHub auto-links ANY `#N` where issue/PR N exists in the repo — in prose, in tables, in list items. This is not limited to table cells.

**Policy**: NEVER write bare `#N` in issue/PR comments. Always do one of:

| Intent             | Write This                                            | Not This |
| ------------------ | ----------------------------------------------------- | -------- |
| Reference an issue | `[Issue 13](https://github.com/owner/repo/issues/13)` | `#13`    |
| Non-issue number   | `` `#1` ``                                            | `#1`     |
| Numbered list item | `Trade 1`, `Item 1`                                   | `#1`     |

**In tables** (most common trap):

```markdown
<!-- BAD: #1 and #4 become issue links, #59 stays plain text -->

| Trade | Exit |
| ----- | ---- |
| #1    | TP   |
| #4    | SL   |
| #59   | TIME |

<!-- GOOD: consistent rendering, no auto-links -->

| Trade | Exit |
| ----- | ---- |
| `#1`  | TP   |
| `#4`  | SL   |
| `#59` | TIME |
```

**What does NOT work inside table cells**:

- `\#1` — Backslash escaping is ignored
- `&#35;1` — HTML entity still auto-links
- `<span>#1</span>` — Still auto-links

**Only backtick code spans work**: `` `#1` ``

---

## AP-02: `@username` Auto-Mentions in Code Context

**Problem**: `@username` in plain text triggers a GitHub mention notification, even when discussing code (e.g., decorator syntax `@property`, email addresses).

**Example**:

```markdown
The class uses @property for lazy loading. <!-- Pings user "property" if they exist -->
Contact admin@example.com for access. <!-- May ping user "example" -->
```

**Fix**: Use backticks for code references, angle brackets for emails:

```markdown
The class uses `@property` for lazy loading.
Contact <admin@example.com> for access.
```

---

## AP-03: SHA-Like Hex Strings Auto-Link to Commits

**Problem**: Strings that look like Git commit SHAs (7+ hex characters) auto-link to commits if a matching commit exists in the repository.

**Example**:

```markdown
Error code: 0xDEADBEEF <!-- May link to a commit -->
Color value: #FF5733 <!-- Links if commit ff5733 exists -->
```

**Fix**: Use backticks for hex values, code blocks for error output:

```markdown
Error code: `0xDEADBEEF`
Color value: `#FF5733`
```

---

## AP-04: Shell Quoting Issues in `--body` Inline

**Problem**: Complex markdown with unescaped backticks, double quotes, and newlines can be mangled by shell quoting when passed via `--body "..."`.

**Fix**: Use single-quoted heredoc for complex content:

```bash
# Fragile: double-quoted string with special characters
gh issue comment 13 --body "## Title\n\nBody with `code` and \"quotes\""

# Reliable: heredoc (no escaping needed)
gh issue comment 13 --body "$(cat <<'EOF'
## Title

Long body with `code` and "quotes" — no escaping needed.
EOF
)"

# Alternative: body file for very large content (65536-char GitHub API limit)
gh issue comment 13 --body-file /tmp/comment.md
```

---

## AP-05: Bare URLs vs Reference-Style Links

**Problem**: Bare URLs in issue bodies can break if they contain parentheses, query params, or markdown-special characters.

**Example**:

```markdown
See https://example.com/path_(with_parens) <!-- Link breaks at first ) -->
See https://example.com/search?q=a&b=c#section <!-- May break at # or & -->
```

**Fix**: Use angle brackets for complex URLs:

```markdown
See <https://example.com/path_(with_parens)>
See <https://example.com/search?q=a&b=c#section>
```

---

## AP-06: Pipe Characters in Table Cell Code Blocks

**Problem**: `|` inside table cells breaks the table structure, even inside backticks in some edge cases.

**Example**:

```markdown
| Command | Description |
| ------- | ----------- | ------------- | -------------------------------- |
| `a      | b`          | Pipe operator | <!-- May break table parsing --> |
```

**Fix**: Use HTML entity `&#124;` for literal pipes in tables:

```markdown
| Command      | Description   |
| ------------ | ------------- |
| `a &#124; b` | Pipe operator |
```

---

## AP-07: Private Repo Image URLs Render as Broken

**Problem**: Images committed to a **private** repository don't render in Issue/PR bodies when referenced via `raw.githubusercontent.com`. The browser fetches `<img src>` URLs directly — `raw.githubusercontent.com` is a different domain from `github.com`, so no session cookies are sent, and the image 404s silently.

**Example**:

```markdown
<!-- BROKEN: raw.githubusercontent.com has no browser cookies for private repos -->

![screenshot](https://raw.githubusercontent.com/owner/private-repo/main/docs/images/screenshot.png)

<!-- WORKING: github.com/blob/?raw=true uses the domain where browser IS authenticated -->

![screenshot](https://github.com/owner/private-repo/blob/main/docs/images/screenshot.png?raw=true)
```

**Why `?raw=true` works**:

1. Browser requests `github.com/...?raw=true` — sends session cookies (same domain as the issue page)
2. GitHub validates repo access via cookies
3. GitHub responds with 302 redirect to `raw.githubusercontent.com/...?token=SIGNED_TEMP_TOKEN`
4. Browser follows redirect — signed token grants access without cookies
5. Image loads

**Why `raw.githubusercontent.com` fails**:

1. Browser requests `raw.githubusercontent.com/...` — **no cookies** (different domain)
2. Private repo content requires authentication
3. Request returns 404
4. Image renders as broken

**Key rules**:

| Repo Visibility | URL Format                                 | Works?  |
| --------------- | ------------------------------------------ | ------- |
| Public          | `raw.githubusercontent.com/owner/repo/...` | Yes     |
| Public          | `github.com/owner/repo/blob/...?raw=true`  | Yes     |
| **Private**     | `raw.githubusercontent.com/owner/repo/...` | **No**  |
| **Private**     | `github.com/owner/repo/blob/...?raw=true`  | **Yes** |

**URL pattern** (for scripting):

```bash
# Base URL for private repo images in Issues/PRs
IMG_BASE="https://github.com/${OWNER}/${REPO}/blob/${BRANCH}/${PATH_TO_DIR}"

# Reference in markdown
![alt text](${IMG_BASE}/filename.png?raw=true)
```

**Note**: This applies to any context where GitHub renders markdown and the browser loads images client-side — Issue bodies, Issue comments, PR descriptions, PR review comments, and Discussion posts. It does NOT affect README rendering (GitHub proxies those server-side).

**Alternative: Upload to `user-attachments` CDN directly.** Instead of committing images to the repo, Playwright can automate GitHub's file-attachment flow to get permanent CDN URLs (`https://github.com/user-attachments/assets/UUID`). These URLs work regardless of repo visibility and require no commit/push preflight. See [Playwright Automation in issue-create](../../issue-create/SKILL.md#playwright-automation-programmatic-cdn-upload) for implementation details.

---

## Quick Reference Card

| Anti-Pattern | Trigger          | Policy                                    | Fix                                                                  |
| ------------ | ---------------- | ----------------------------------------- | -------------------------------------------------------------------- |
| AP-01        | `#N` anywhere    | **NEVER** use bare `#N`                   | Backtick `` `#N` `` for non-issues; explicit URL for real references |
| AP-02        | `@name` in prose | Suppress unintentional mentions           | Backtick `` `@property` ``                                           |
| AP-03        | Hex strings      | Suppress commit auto-links                | Backtick `` `0xDEAD` ``                                              |
| AP-04        | Complex `--body` | Use heredoc for special chars             | Heredoc `$(cat <<'EOF'...)` or `--body-file`                         |
| AP-05        | Complex URLs     | Protect special characters                | Angle brackets `<URL>`                                               |
| AP-06        | Pipe in table    | Escape pipe character                     | HTML entity `&#124;`                                                 |
| AP-07        | Private repo img | **NEVER** use `raw.githubusercontent.com` | `github.com/.../blob/...?raw=true`                                   |

---

## When to Apply

These anti-patterns apply to:

- Issue bodies and comments (`gh issue create`, `gh issue comment`)
- PR descriptions (`gh pr create`)
- Discussion posts
- Wiki pages
- Any GitHub-rendered Markdown

They do NOT apply to:

- Code blocks (triple backtick fenced blocks) — auto-linking is disabled inside these
- Repository file rendering (`.md` files in repos) — same rules apply but less commonly hit
