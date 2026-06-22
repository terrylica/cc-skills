#!/usr/bin/env bun
/**
 * Pure detection logic for the git-worktree guard.
 *
 * Policy (operator directive 2026-06-22): every git branch must be created
 * INSIDE its own git worktree. Bare branch creation in the main checkout
 * (`git checkout -b`, `git switch -c`, `git branch <new>`, the git-town
 * branch-creating subcommands, and `gh pr checkout`) is blocked; the
 * sanctioned path is `git worktree add [-b <name>] <path>` or the harness
 * EnterWorktree tool.
 *
 * This module is PURE (no stdin/stdout) so it can be unit-tested directly.
 * The I/O wrapper lives in pretooluse-git-worktree-guard.ts.
 *
 * ADR: /docs/adr/2026-06-22-git-worktree-guard.md
 */

export interface BranchCreationVerdict {
  /** True when this command/segment creates a bare branch (must be blocked). */
  blocked: boolean;
  /** Which path triggered it (for the deny message + tests). */
  kind?: "git checkout -b" | "git switch -c" | "git branch" | "git-town" | "gh pr checkout";
  /** The offending segment, trimmed (for the deny message). */
  segment?: string;
  /** Best-effort branch name parsed from the segment (may be undefined). */
  branch?: string;
}

/**
 * `git branch` flags that mean "list / inspect / delete / move / copy / config"
 * rather than "create a new branch". If a `git branch` invocation carries any of
 * these, it is NOT a creation and must be allowed.
 */
const GIT_BRANCH_NON_CREATE_FLAGS = new Set([
  "-d", "-D", "--delete",
  "-m", "-M", "--move",
  "-c", "-C", "--copy",
  "-a", "--all",
  "-r", "--remotes",
  "-l", "--list",
  "-v", "-vv", "--verbose",
  "--show-current",
  "--merged", "--no-merged",
  "--contains", "--no-contains",
  "--points-at",
  "--edit-description",
  "--set-upstream-to", "--unset-upstream", "-u",
  "--sort", "--format", "--color", "--no-color", "--column", "--no-column",
  "-h", "--help",
]);

/** git-town subcommands that create a new branch. */
const GIT_TOWN_CREATE_SUBCOMMANDS = new Set(["hack", "append", "prepend"]);

/**
 * Split a compound shell command into individually-classifiable segments.
 * Breaks on &&, ||, ;, |, and newlines. Good enough for a guardrail — we do
 * not attempt full shell parsing (subshells, eval, aliases fail open).
 */
export function splitSegments(command: string): string[] {
  return command
    .split(/&&|\|\||[;|\n]/g)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

/**
 * Tokenize a single segment on whitespace. Naive (does not honor quotes), which
 * is acceptable: branch names with spaces are pathological and we only inspect
 * the leading verb/flags.
 */
function tokenize(segment: string): string[] {
  return segment.split(/\s+/g).filter((t) => t.length > 0);
}

/**
 * Drop leading `VAR=value` environment assignments so `FOO=1 git checkout -b x`
 * is still recognized as a git invocation. (The escape-hatch env var is handled
 * separately, in the I/O wrapper, before this runs.)
 */
function stripLeadingEnvAssignments(tokens: string[]): string[] {
  let i = 0;
  while (i < tokens.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[i])) {
    i++;
  }
  return tokens.slice(i);
}

/**
 * Skip git's global options that can appear before the subcommand, e.g.
 * `git -C /repo`, `git --git-dir=... `, `git -c key=val`. Returns the index of
 * the subcommand token (or tokens.length if none).
 */
function indexOfGitSubcommand(tokens: string[]): number {
  // tokens[0] === "git"; start scanning at 1.
  let i = 1;
  while (i < tokens.length) {
    const t = tokens[i];
    if (!t.startsWith("-")) break;
    // Options that consume the NEXT token as their value.
    if (t === "-C" || t === "-c" || t === "--git-dir" || t === "--work-tree" || t === "--namespace") {
      i += 2;
      continue;
    }
    // `--git-dir=...` style (value attached) or any other lone flag.
    i += 1;
  }
  return i;
}

/** Parse the first non-flag argument after a subcommand as the branch name. */
function firstNonFlagArg(tokens: string[], startIdx: number): string | undefined {
  for (let i = startIdx; i < tokens.length; i++) {
    if (!tokens[i].startsWith("-")) return tokens[i];
  }
  return undefined;
}

/** Classify a single already-trimmed segment. */
function classifySegment(segment: string): BranchCreationVerdict {
  const tokensRaw = tokenize(segment);
  const tokens = stripLeadingEnvAssignments(tokensRaw);
  if (tokens.length === 0) return { blocked: false };

  const cmd = tokens[0];

  // ---- gh pr checkout <n> -------------------------------------------------
  if (cmd === "gh") {
    if (tokens[1] === "pr" && tokens[2] === "checkout") {
      return { blocked: true, kind: "gh pr checkout", segment, branch: firstNonFlagArg(tokens, 3) };
    }
    return { blocked: false };
  }

  // ---- git-town (both `git-town <sub>` and `git town <sub>`) --------------
  if (cmd === "git-town") {
    if (tokens[1] && GIT_TOWN_CREATE_SUBCOMMANDS.has(tokens[1])) {
      return { blocked: true, kind: "git-town", segment, branch: firstNonFlagArg(tokens, 2) };
    }
    return { blocked: false };
  }

  if (cmd !== "git") return { blocked: false };

  // ---- git <global opts> <subcommand> ... ---------------------------------
  const subIdx = indexOfGitSubcommand(tokens);
  const sub = tokens[subIdx];
  if (!sub) return { blocked: false };

  // git town <sub> (subcommand form of git-town)
  if (sub === "town") {
    const townSub = tokens[subIdx + 1];
    if (townSub && GIT_TOWN_CREATE_SUBCOMMANDS.has(townSub)) {
      return { blocked: true, kind: "git-town", segment, branch: firstNonFlagArg(tokens, subIdx + 2) };
    }
    return { blocked: false };
  }

  // git worktree ... — the sanctioned path; ALWAYS allow (even `add -b <name>`).
  if (sub === "worktree") return { blocked: false };

  // git checkout -b/-B/--branch <name>
  if (sub === "checkout") {
    const rest = tokens.slice(subIdx + 1);
    const createsBranch = rest.some((t) => t === "-b" || t === "-B" || t === "--branch");
    if (createsBranch) {
      return { blocked: true, kind: "git checkout -b", segment, branch: branchAfterCreateFlag(rest) };
    }
    return { blocked: false };
  }

  // git switch -c/-C/--create/--force-create <name>
  if (sub === "switch") {
    const rest = tokens.slice(subIdx + 1);
    const createsBranch = rest.some(
      (t) => t === "-c" || t === "-C" || t === "--create" || t === "--force-create",
    );
    if (createsBranch) {
      return { blocked: true, kind: "git switch -c", segment, branch: branchAfterCreateFlag(rest) };
    }
    return { blocked: false };
  }

  // git branch <name> [start] — creation when a non-flag arg is present AND no
  // list/delete/move/copy/config flag is set.
  if (sub === "branch") {
    const rest = tokens.slice(subIdx + 1);
    const hasNonCreateFlag = rest.some((t) => {
      // Handle `--flag=value` forms.
      const base = t.split("=", 1)[0];
      return GIT_BRANCH_NON_CREATE_FLAGS.has(base);
    });
    if (hasNonCreateFlag) return { blocked: false };
    const name = firstNonFlagArg(rest, 0);
    if (name) {
      return { blocked: true, kind: "git branch", segment, branch: name };
    }
    return { blocked: false }; // bare `git branch` = list
  }

  return { blocked: false };
}

/** Find the branch name following the create flag (e.g. after `-b`). */
function branchAfterCreateFlag(rest: string[]): string | undefined {
  for (let i = 0; i < rest.length; i++) {
    const t = rest[i];
    if (t === "-b" || t === "-B" || t === "--branch" || t === "-c" || t === "-C" || t === "--create" || t === "--force-create") {
      // `--branch=name` attached form
      const eq = t.indexOf("=");
      if (eq !== -1) return t.slice(eq + 1);
      return rest[i + 1];
    }
    if (t.startsWith("--") && t.includes("=")) {
      const [flag, val] = t.split(/=(.*)/s);
      if (flag === "--branch" || flag === "--create") return val;
    }
  }
  return firstNonFlagArg(rest, 0);
}

/**
 * Classify a full (possibly compound) command. Returns the FIRST segment that
 * creates a bare branch, or `{ blocked: false }` if none do.
 */
export function classifyBranchCreation(command: string): BranchCreationVerdict {
  for (const segment of splitSegments(command)) {
    const verdict = classifySegment(segment);
    if (verdict.blocked) return verdict;
  }
  return { blocked: false };
}

/** Derive a friendly worktree suggestion from a parsed branch name. */
function suggestionFor(branch: string | undefined): { wtPath: string; branchArg: string } {
  const name = branch && branch.trim().length > 0 ? branch.trim() : "<branch>";
  const slug = name.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") || "branch";
  return { wtPath: `../<repo>-${slug}`, branchArg: name };
}

/** Build the Claude-visible deny message. */
export function buildDenyMessage(verdict: BranchCreationVerdict): string {
  const segment = verdict.segment ?? "(unknown)";
  const preview = segment.length > 100 ? segment.slice(0, 97) + "..." : segment;
  const { wtPath, branchArg } = suggestionFor(verdict.branch);

  return `[WORKTREE-GUARD] Bare branch creation blocked — branches must live in a git worktree.

BLOCKED (${verdict.kind ?? "branch creation"}): ${preview}

USE INSTEAD (pick one):
  • In-session:  the EnterWorktree tool  (cleanest — Claude Code manages the worktree)
  • Manual:      git worktree add ${wtPath} -b ${branchArg}
                 (then cd into ${wtPath} to work on the branch)

Why: a worktree keeps each branch in its own directory, so the main checkout
stays clean and branches never collide on disk.

Escape hatch (intentional bare branch — CI script, rebase temp, emergency hotfix):
  • prefix the command with  ALLOW_BARE_BRANCH=1`;
}
