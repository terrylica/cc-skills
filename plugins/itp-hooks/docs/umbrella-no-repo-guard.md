# Umbrella-folder "never a repository" guard

An **umbrella folder** represents an owner or namespace and _contains_ repositories. It is not one itself. Operator ruling, 2026-09-05:

> "~/459ecs should never become a repository because it is representing user, but never a repository."

This guard is a PreToolUse hook on `Bash` that refuses commands which would turn an umbrella folder into a git repository.

## Why a hook, when a filesystem sentinel already exists

Each umbrella folder carries an immutable `.git` **file** (`chflags uchg`), which makes `git init` fail with `fatal: invalid gitfile format`. That is a strictly harder stop than any hook — the kernel enforces it, and no agent reasoning can talk its way past it.

The problem is that it is silent about _why_. A cryptic `invalid gitfile format` is exactly the kind of error a helpful agent decides to "fix", and the measured behaviour bears that out: an agent proposed turning `~/459ecs` into a repository **twice in one session**. The sentinel stopped the write both times and taught nothing either time.

So the two layers do different jobs. The sentinel guarantees the outcome; the hook explains it, which is what makes the protection survive contact with the next session. Neither replaces the other, and the hook deliberately fails open (below) precisely because it is not the layer of last resort.

## What it blocks

Only when the **resolved target is an umbrella folder itself**:

- `git init`, including `--separate-git-dir` and `--bare`
- `gh repo create` run from inside one
- `git clone <url> <umbrella-path>` — cloning _onto_ the folder

## What it deliberately allows

- Anything targeting a **subdirectory** (`~/459ecs/newthing`). Nested repositories are the entire point of an umbrella folder, so blocking those would break the thing the folder exists for.
- `git init` anywhere else on the machine.

A guard that is wrong on ordinary work gets disabled, and a disabled guard is worse than none — the same reasoning that keeps the PII reminder non-blocking.

## Where the folder list lives

SSoT: `~/.claude/path-owner-registry.toml`, `[[umbrella]]` entries. The guard reads those paths without a TOML dependency, scanning for keys between an `[[umbrella]]` header and the next `[[...]]` header.

Adding an umbrella folder is a registry edit, not a code change.

## Fail-open, on purpose

An unreadable or unparseable registry means **allow**. A guard that locks the machine out of `git init` because a config file has a typo is a worse failure than the one it prevents — and the immutable sentinel is still standing underneath it, so failing open here does not leave the folder unprotected.

## Escape hatch

`ALLOW_UMBRELLA_REPO=1` anywhere in the command. No reason string is required, unlike the credential guard: turning a folder into a repository is an ordinary, defensible action that the operator may genuinely want, and the sentinel will still refuse unless it is also cleared.

## Known gap, stated rather than hidden

`GIT_DIR=/elsewhere git init` is not matched by the filesystem sentinel, because it never touches the folder's `.git` path at all. The hook is the only layer that sees that form.

## Where this sits in the four-layer defense

Recorded in `~/.claude/decisions-security-CLAUDE.md`:

| Layer | Mechanism                                                         |
| ----- | ----------------------------------------------------------------- |
| 1     | Immutable `.git` sentinel (`chflags uchg`) on every umbrella root |
| 2     | **This guard** — refuses with a reason so the rule is learnable   |
| 3     | `GIT_CEILING_DIRECTORIES`                                         |
| 4     | `path-owner-registry.toml` as the SSoT the other layers read      |

## Tests

`plugins/itp-hooks/hooks/pretooluse-umbrella-no-repo-guard.test.sh` — both directions, including that the escape hatch is honoured and that an unrelated command merely _mentioning_ git is allowed through.

## Note

This adds a 17th `PreToolUse:Bash` matcher block. Issue #111 tracks collapsing those into one orchestrator using the `iter66` pattern already applied to `Write|Edit|MultiEdit`; this guard makes that consolidation marginally more valuable rather than addressing it.
