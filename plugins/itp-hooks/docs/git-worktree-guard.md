# Git Worktree Guard

> Spoke for `pretooluse-git-worktree-guard.ts`. Hub: [itp-hooks CLAUDE.md](../CLAUDE.md).
> ADR: [/docs/adr/2026-06-22-git-worktree-guard.md](/docs/adr/2026-06-22-git-worktree-guard.md).

## Policy

Every git branch must be created **inside its own git worktree** (operator directive
2026-06-22). The main checkout stays on its base branch; feature work happens in
`git worktree add`-created directories. This PreToolUse/`Bash` hook denies bare branch
creation and steers to the sanctioned path. It is **global** — `itp-hooks` is enabled in
`~/.claude/settings.json`, so the guard fires in every repository.

It is a **guardrail, not a sandbox**: it fails open (any error → allow) and only matches
the common branch-creation verbs. Exotic forms (shell aliases, `eval`, raw plumbing) can
slip through by design — the goal is to make the right thing the default, not to be
unbypassable.

## Detection

Pure logic lives in `hooks/git-worktree-guard-patterns.ts` (`classifyBranchCreation`,
`buildDenyMessage`); the hook (`hooks/pretooluse-git-worktree-guard.ts`) is a thin
stdin→decision wrapper. The command is split on `&&`, `||`, `;`, `|`, and newlines, and
each segment is classified independently — the first blocked segment denies the whole
command. Leading `VAR=value` env assignments and git global options (`-C <dir>`,
`-c k=v`, `--git-dir=...`) are skipped before reading the subcommand.

### Blocked (bare branch creation)

| Pattern                                                       | Example                                                      |
| ------------------------------------------------------------- | ------------------------------------------------------------ |
| `git checkout -b` / `-B` / `--branch`                         | `git checkout -b feature/x`                                  |
| `git switch -c` / `-C` / `--create` / `--force-create`        | `git switch -c feature/x`                                    |
| `git branch <new>` (no list/delete/move flag, a name present) | `git branch newfeat`, `git branch newfeat origin/main`       |
| git-town branch creators                                      | `git town hack f`, `git-town append f`, `git-town prepend f` |
| `gh pr checkout <n>` (creates a local branch)                 | `gh pr checkout 123`                                         |
| any of the above after global opts / env / chaining           | `git -C /repo checkout -b f`, `cd x && git switch -c f`      |

### Allowed (never blocked)

- `git worktree add ...` — including `git worktree add -b <name> <path>` (the sanctioned path).
- Switching/restoring: `git checkout <existing>`, `git checkout -- <path>`, `git checkout .`, `git switch <existing>`.
- Branch management/inspection: bare `git branch` (list), `-d`/`-D`/`-m`/`-M`/`-c`/`-C`/`-a`/`-r`/`-l`/`--list`/`--show-current`/`--merged`/`--contains`/`--set-upstream-to`/`--edit-description`/`--sort`/`--format`, etc.
- Non-creating git-town subcommands (`git town sync`) and non-checkout `gh` (`gh pr view`).
- Read-only commands (via the shared `isReadOnly` helper) and non-git commands.
- Documentation contexts: `echo`/`printf`, leading `#` comments, `grep`/`rg`, `gh issue|pr create|edit|comment`, and `git commit|tag` (so a commit message mentioning `git checkout -b` is fine).
- `git stash branch <name>` — intentionally **allowed** (rare; creates a branch from a stash). Revisit if it becomes a common bypass.

## Escape hatch

Prefix the command with **`ALLOW_BARE_BRANCH=1`** (the operator-chosen env-var override)
to silence the block for a single command — e.g. `ALLOW_BARE_BRANCH=1 git checkout -b hotfix`.

Use for CI scripts, rebase temp branches, or an emergency hotfix where a worktree is
genuinely not wanted.

> A `*-OK` comment marker was deliberately **not** used: the marketplace's iter-107/110
> escape-hatch-marker inventory audit strictly governs `UPPER-KEBAB-OK` markers (they must
> register in the iter-111 registry and use the shared helper). An env-var override keeps
> this guard out of that cohort while still giving a clean, discoverable bypass.

## Deny message

Names the blocked verb + offending segment and offers two replacements: the in-session
`EnterWorktree` tool (cleanest) and the manual `git worktree add ../<repo>-<slug> -b <branch>`,
plus the escape hatch. See `buildDenyMessage` for the exact text.

## Tests

`hooks/pretooluse-git-worktree-guard.test.ts` — two layers: pure `classifyBranchCreation`
assertions (fast) and full-hook subprocess assertions (stdin/JSON/deny wiring, fast-path,
`isReadOnly`, both escape hatches, non-Bash passthrough). Run:

```bash
bun test plugins/itp-hooks/hooks/pretooluse-git-worktree-guard.test.ts
```

## Going live

Enabled plugins run from a versioned cache dir
(`~/.claude/plugins/cache/cc-skills/itp-hooks/<version>/`), not this repo. A **cc-skills
release** (`mise run release:full`) re-populates the cache and activates the hook globally.
A manual mirror of the new hook files + `hooks.json` into the active version dir is an
immediate stopgap.
