#!/usr/bin/env bun
/**
 * PreToolUse hook: Git Worktree Guard
 *
 * Enforces the standing practice that every git branch is created INSIDE its
 * own git worktree. Blocks bare branch creation in the main checkout:
 *   - git checkout -b / -B / --branch
 *   - git switch   -c / -C / --create / --force-create
 *   - git branch <new-name> [start-point]
 *   - git-town hack | append | prepend   (and the `git town <sub>` form)
 *   - gh pr checkout <n>
 *
 * ALWAYS allowed: `git worktree add ...` (the sanctioned path), switching to /
 * restoring existing branches, branch list/delete/rename/config, and read-only
 * commands. Documentation/echo/comment/commit-message mentions are exempt.
 *
 * Escape hatch: prefix with ALLOW_BARE_BRANCH=1 (operator-chosen env-var
 * override) for an intentional bare branch — CI script, rebase temp branch,
 * emergency hotfix.
 *
 * Fail-open: any parse/logic error allows the command (never blocks real work).
 *
 * ADR: /docs/adr/2026-06-22-git-worktree-guard.md
 * Spoke: plugins/itp-hooks/docs/git-worktree-guard.md
 */

import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { classifyBranchCreation, buildDenyMessage } from "./git-worktree-guard-patterns.ts";

const HOOK_NAME = "git-worktree-guard";

/** Operator-chosen env-var override for an intentional bare branch. */
const BARE_BRANCH_OVERRIDE_ENV = /\bALLOW_BARE_BRANCH=1\b/;

/** Fast-path keywords: if none present, no branch-creating tool is involved. */
const FAST_PATH_KEYWORDS = ["git", "gh"];

/**
 * Exception contexts where a branch-creation-looking string is documentation,
 * not an actual operation. Mirrors pretooluse-uv-enforcement-guard's isException.
 */
function isException(command: string): boolean {
  const lower = command.toLowerCase();

  // Operator override (intentional bare branch).
  if (BARE_BRANCH_OVERRIDE_ENV.test(command)) return true;

  // Pure documentation / output contexts.
  if (/^\s*(echo|printf)\s/i.test(lower)) return true;
  if (/^\s*#/.test(command)) return true;
  if (/^\s*(grep|egrep|fgrep|rg|ag|ack)\b/i.test(lower)) return true;

  // Free-text argument contexts that commonly mention git verbs as prose.
  if (/\bgh\s+(issue|pr)\s+(create|edit|comment)\b/i.test(lower)) return true;
  if (/\bgit\s+(commit|tag)\b/i.test(lower)) return true;

  return false;
}

async function main() {
  const input = await parseStdinOrAllow("GIT-WORKTREE-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";
  if (!command.trim()) {
    allow();
    return;
  }

  // NOTE: no isReadOnly() short-circuit here — the shared helper treats
  // `git branch` as read-only (it usually lists), which would mask the
  // creating form `git branch <new>`. The classifier below already allows
  // every non-create pattern, so the short-circuit was redundant anyway.

  // Fast path: nothing git/gh-related → allow.
  const lower = command.toLowerCase();
  if (!FAST_PATH_KEYWORDS.some((kw) => lower.includes(kw))) {
    allow();
    return;
  }

  // Documentation / escape-hatch contexts.
  if (isException(command)) {
    allow();
    return;
  }

  const verdict = classifyBranchCreation(command);
  if (verdict.blocked) {
    deny(buildDenyMessage(verdict));
    return;
  }

  allow();
}

main().catch((err) => {
  trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
  allow();
});
