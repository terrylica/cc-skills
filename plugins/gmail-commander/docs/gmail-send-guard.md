# gmail-send-guard

`hooks/gmail-send-guard.ts` is a PreToolUse hook on Bash, Write, Edit, MultiEdit, Read and Grep. It denies two things: a direct call to the Gmail send endpoints, and a raw read of the cached OAuth tokens in `~/.claude/tools/gmail-tokens/`.

## Why it exists

On 2026-10-08 an agent wrote a Bun script that read a cached token file and POSTed a raw message to the Gmail send endpoint with no From header. Gmail fills a missing From line in from the account's **default send-as identity**, and on both accounts the script used, the default was not the identity the message should have carried. The messages went only to the operator's own test address, so the cost was nine test mails; the same path pointed at a real recipient would have been an email under the wrong name.

Nothing stopped it. `gmail-draft-guard.sh` watches only the drafts API, and a Bash hook sees the command line, not a `fetch()` that lives inside a script file. So this guard also inspects the scripts a command executes, and stops the script at the moment it is written.

## What it denies

**Sends.** A send call (REST `messages/send` or `drafts/send`, or the client-library `messages.send(` / `messages().send(` / `drafts.send(`) together with a Gmail context marker (`gmail.googleapis.com`, `googleapis`, `gmail.users`, `gmail_v1`, `build("gmail"`, `users/me/messages`):

- in the Bash command text, which includes heredoc bodies and inline `bun -e` / `python3 -c`;
- in a script the Bash command executes (`bun x.ts`, `uv run python x.py`, `./x.sh`), found by reading the file;
- in a code file written with Write, or the file as it would be after an Edit or MultiEdit, when the edit is what introduces the call.

**Token reads.**

- Read and Grep on any path inside `gmail-tokens/`.
- A Bash content reader (`cat`, `jq`, `python3`, `bun -e`, `cp`, `head`, `base64`, ...) aimed at the directory, directly, after `cd` into it, or in a `for` loop over it; `find -exec` over it.
- Executing a script outside this plugin's `scripts/` whose source references the directory.

## What it allows

- The canonical draft builder `scripts/gmail-draft.ts`, the gmail CLI, and `scripts/gmail-accounts.ts`. These read the tokens themselves and never need the path on their command line.
- Metadata operations on the token directory: `ls`, `stat`, `test -f`, `mv`, `rm`, `chmod`. The documented recovery steps (move an expired token aside, remove cached app credentials) use these.
- Searching for the endpoint (`rg`, `grep`, `git grep`/`log`/`show`) when the command writes nothing.
- `git commit`, `git tag`, `gh issue|pr|release` commands whose message or body discusses the endpoint or the directory. They still deny a token file passed as an argument (`gh gist create <token file>`).
- Prose files (`.md`, `.txt`, `.rst`, ...), which may describe the API.
- Drafts create/update calls (the drafts guard owns those) and read-only GETs.

## Which identity will a message use?

```bash
bun $HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-accounts.ts
```

For each cached token it prints the mailbox the token actually owns, the access-token expiry, the granted scopes, and every send-as alias with its verification status, marking the one Gmail uses when no From line is set. It never prints a token. `--json` gives the same report for scripts, and `--account <tokenbase>` limits it to one account.

## Escape

Write the marker `GMAIL-SEND` followed by `-OK`, then a colon and a reason of at least ten characters, in the Bash command, in the content being written, or as a comment in the executed script. A shorter reason is ignored, and so is a documentation placeholder: a reason that starts with `<`, or the generic example sentence the marketplace marker reference prints for every marker. Copying an example out of a doc therefore never pastes a working escape. There is no escape for Read and Grep on the token directory: if a token file must be inspected, a person does it.

The marker is written in two parts on this page so that copying a sentence from it does not paste a working escape.

## Known gaps

This is a guard against the shapes agents actually write, not a containment boundary.

- Obfuscated code passes: an endpoint assembled from string fragments, base64, or a URL read from a config file.
- A token path that reaches a reader through a variable set in an earlier Bash call is invisible.
- A script that is executed indirectly (sourced by another script, run by a task runner) is not read.
- It fails open on input it cannot parse.

The real backstop is the account itself: set each mailbox's default send-as alias to the identity that should appear when nothing else is specified.

## Tests

`hooks/gmail-send-guard.test.ts` runs in the marketplace Bun unit suite (`moon run repo:test`). It spawns the hook as Claude Code does for four end-to-end probes (a raw fetch in a heredoc script, a Write of a `.ts` file that sends, a `cat` of a token file, the canonical `gmail-draft.ts` path), plus unit cases for every allow and deny listed above.
