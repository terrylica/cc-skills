---
status: implemented
date: 2026-06-22
decision-maker: Terry Li
consulted: [lifecycle-reference.md, uv-reminder-hook ADR, cwd-deletion-guard]
research-method: existing-hook-pattern-reuse
---

# ADR: Git Worktree Guard — enforce worktree-per-branch

## Context and Problem Statement

Standing operator practice: **every git branch must be created inside its own git
worktree**, never as a bare branch in the main checkout. This kept being enforced by
memory alone. The user asked to _harden_ it so branch creation is always routed through a
worktree, with edge cases fully covered.

## Decision Drivers

- **Global** — must apply in every repository, not just cc-skills.
- **Block + guide** — deny the bare-branch command and show the correct worktree command,
  rather than silently fixing or merely warning.
- **Escape hatch** — a deliberate bypass for legitimate exceptions (CI scripts, rebase temp
  branches, emergency hotfix) so the guard can never hard-lock the user out.
- **Coverage** — core git plus `git-town` and `gh` branch-creating paths.
- Reuse existing hook infrastructure; fail open; never block real work.

## Considered Options

### Option A: PreToolUse/Bash guard in the itp-hooks plugin (Selected)

`itp-hooks@cc-skills` is enabled globally, so a `PreToolUse`/`Bash` hook there fires in
every repo. Modeled on `pretooluse-uv-enforcement-guard.ts` (fast-path → exceptions →
classify → `deny()`), with pure detection split into `git-worktree-guard-patterns.ts` for
direct unit testing.

**Pros**: one global delivery vehicle; matches the chosen "all repos" scope; reuses the
shared helpers (`parseStdinOrAllow`, `isReadOnly`, `deny`, `trackHookError`); consistent
with sibling Bash guards.

**Cons**: only goes live after a cc-skills release re-populates the versioned plugin cache
(or a manual cache mirror as a stopgap).

### Option B: Standalone hook in `~/.claude/settings.json`

A script registered directly in global settings.

**Rejected**: would double-fire alongside the plugin (itp-hooks already global) and lives
outside the versioned, validated plugin repo (the SSoT for hooks).

## Decision

Implement Option A: `pretooluse-git-worktree-guard.ts` + `git-worktree-guard-patterns.ts`,
registered in `hooks.json` **before** `pretooluse-pueue-wrap-guard.ts` (which must remain
the last PreToolUse entry per the iter-61 `updatedInput` invariant).

**Blocked:** `git checkout -b/-B/--branch`, `git switch -c/-C/--create/--force-create`,
`git branch <new>` (no list/delete/move flag + a name), `git-town hack|append|prepend`
(and `git town <sub>`), `gh pr checkout <n>` — including after `VAR=...` prefixes, git
global options (`-C`, `-c`, `--git-dir`), and `&&`/`;`/`|` chaining.

**Always allowed:** `git worktree add [-b]` (sanctioned path), switching/restoring existing
branches, branch list/delete/rename/config, read-only commands, and documentation contexts
(echo/printf/comment/grep, `gh issue|pr create|edit|comment`, `git commit|tag`).
`git stash branch` is allowed (rare).

**Escape hatch:** `ALLOW_BARE_BRANCH=1` prefix (env-var override). A `*-OK` comment marker
was deliberately avoided — the iter-107/110 marketplace marker-inventory audit strictly
governs `UPPER-KEBAB-OK` markers (registry + shared-helper migration required); an env-var
override keeps this guard out of that cohort.

The deny message offers the in-session `EnterWorktree` tool and the manual
`git worktree add ../<repo>-<slug> -b <branch>`.

## Consequences

- Branch creation is consistently routed through worktrees across all repos.
- Guardrail, not a sandbox: fails open; exotic creation paths may slip through by design.
- Activation requires a cc-skills release (versioned plugin cache); documented in the spoke
  `plugins/itp-hooks/docs/git-worktree-guard.md`.
- Tests: `pretooluse-git-worktree-guard.test.ts` (pure classifier + full-hook subprocess).
