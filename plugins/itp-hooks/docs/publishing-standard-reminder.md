# publishing-standard-reminder

**Hook:** `hooks/publishing-standard-reminder.ts` · **Events:** PreToolUse (Bash orchestrator) and PostToolUse (Write/Edit orchestrator) · **Kind:** soft reminder, never denies · **Escape:** `PUBLISHING-STANDARD-OK` (in a command)

When a session creates an HTML page or publishes pages, this hook adds one line to the model's context pointing at `Skill(devops-tools:publishing-standard)`. That skill holds the must-haves every published page carries: a live "changed N ago" marker with a heat dot, the exact build time, version, commit and source, a link back to its site's index, one record in exactly one `published.v1` registry, and a place on the sitemap that links every site together.

## Why

Pages are built by many tools (a page builder, a static-site generator, a hand-written file, an artifact share), and each tool's own skill covers its mechanics, not what a reader needs from every page. Without a reminder at the two moments that matter, pages went out with a hard-coded "updated" text, no way back to their index, and links recorded in several places or none (operator, 2026-11-15). The rules live in the skill; this hook only points at it, in one line.

## When it fires

| Moment | Fires |
| --- | --- |
| Before a Bash command that publishes: `wrangler deploy`, `wrangler pages deploy`, `wrangler versions deploy` (npx/bunx forms included), `orca artifacts share` or `update`, `netlify deploy`, `vercel deploy` or `vercel --prod`, `firebase deploy`, `surge <dir>`, `gh-pages -d` | yes, once per session |
| The same with `--dry-run`, `--help` or `-h`, or containing `PUBLISHING-STANDARD-OK` | no |
| A command that only mentions one: `cat` or `grep` of a deploy script, quoted text, a comment, a heredoc fed to anything but a shell (the shared shell-command walker decides what the shell would run) | no |
| After a Write or Edit of a `.html`, `.htm` or `.xhtml` file | yes, once per session (its own gate) |
| The same inside a temp scratch directory | no |
| No session id, or one that is not a plain path component | no |
| Any other tool or file | no |

The two moments have separate gates, so a session that writes pages and later publishes them is reminded at both, and never more than that.

## Message

> [PUBLISHING-STANDARD] Follow Skill(devops-tools:publishing-standard) for every page: a live "changed N ago" marker with a heat dot, the exact build time, version, commit and source, a link back to its index, one record in exactly one registry (published.v1), and the sitemap regenerated after the deploy is recorded.

## Tests

`hooks/publishing-standard-reminder.test.ts`: the publish-command matcher (each host's command, dry runs, help, the escape, and commands that only mention a publish), the HTML path filter, the session-id filter and the once-per-session gates, through the hook run as a process and through the classifier.
