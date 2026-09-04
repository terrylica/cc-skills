#!/usr/bin/env bun
/**
 * Local, network-free state for the review-round gate: git facts, the artifact store, and the
 * record of which branches have been shown to a reviewer.
 *
 * EVERY CALL HERE IS LOCAL AND BOUNDED. `git rev-parse`, `git diff`, and reads of two small JSON
 * files. No `gh`, no network. That is not a stylistic preference: a PreToolUse hook that times out
 * does NOT block, so a network dependency turns this gate into one that silently allows whenever
 * GitHub is slow. `process-storm-CLAUDE.md` is also explicit that `gh` inside a blocking hook needs
 * PID-specific timeout and kill discipline; the cheapest way to satisfy that rule is to have no
 * `gh` call at all.
 */

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";

import type { RepoFacts, ReviewRoundArtifact } from "./review-round-artifact.ts";

const GIT_TIMEOUT_MS = 3000;

export const STATE_ROOT = join(homedir(), ".claude", "state", "review-round-gate");

function git(args: string[], cwd: string): string {
  return execFileSync("git", args, {
    cwd,
    encoding: "utf8",
    timeout: GIT_TIMEOUT_MS,
    maxBuffer: 64 * 1024 * 1024,
    stdio: ["ignore", "pipe", "ignore"],
  });
}

export interface RepoIdentity {
  readonly slug: string;
  readonly branch: string;
  readonly root: string;
}

/** null when cwd is not a git repository, or is in a detached/unborn state we cannot key on. */
export function identifyRepo(cwd: string): RepoIdentity | null {
  try {
    const root = git(["rev-parse", "--show-toplevel"], cwd).trim();
    const branch = git(["rev-parse", "--abbrev-ref", "HEAD"], cwd).trim();
    if (!root || !branch || branch === "HEAD") return null;
    // Slug from the remote when there is one, so two worktrees of the same repo share state.
    let slug = root.split("/").pop() ?? "repo";
    try {
      const url = git(["remote", "get-url", "origin"], cwd).trim();
      const m = url.match(/[:/]([^/:]+\/[^/]+?)(?:\.git)?$/);
      if (m) slug = m[1].toLowerCase();
    } catch {
      // No origin. The directory name is a fine key for a local-only repo.
    }
    return { slug, branch, root };
  } catch {
    return null;
  }
}

/**
 * The base commit this branch is measured against.
 *
 * Falls back through the common default-branch spellings. If none resolves, the caller gets null
 * and the gate must fail OPEN -- a repository with no discoverable base is not one this gate can
 * make a judgement about, and blocking every push there would be a false positive with no remedy.
 */
export function resolveBase(cwd: string): string | null {
  for (const ref of ["origin/main", "origin/master", "main", "master"]) {
    try {
      const merged = git(["merge-base", ref, "HEAD"], cwd).trim();
      if (merged) return merged;
    } catch {
      // try the next spelling
    }
  }
  return null;
}

export function collectFacts(cwd: string): RepoFacts | null {
  const base = resolveBase(cwd);
  if (base === null) return null;
  try {
    const headSha = git(["rev-parse", "HEAD"], cwd).trim();
    // Working tree INCLUDED: `git diff <base>` (no `..HEAD`) spans committed and uncommitted work,
    // so an artifact cannot be satisfied by recording a pass and then editing before pushing.
    const diffText = git(["diff", base], cwd);
    const changedPaths = git(["diff", "--name-only", base], cwd)
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean);
    return { headSha, baseSha: base, diffText, changedPaths };
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------------------------
// Stores
// ---------------------------------------------------------------------------------------------

function artifactPath(id: RepoIdentity): string {
  const safeBranch = id.branch.replace(/[^A-Za-z0-9._-]/g, "_");
  return join(STATE_ROOT, id.slug.replace("/", "__"), `${safeBranch}.json`);
}

export function readArtifact(id: RepoIdentity): ReviewRoundArtifact | null {
  const path = artifactPath(id);
  if (!existsSync(path)) return null;
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8"));
    if (typeof parsed !== "object" || parsed === null) return null;
    return parsed as ReviewRoundArtifact;
  } catch {
    // Unparseable is NOT the same as absent, but both must deny; returning null routes both to S0.
    return null;
  }
}

export function writeArtifact(id: RepoIdentity, artifact: ReviewRoundArtifact): string {
  const path = artifactPath(id);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(artifact, null, 2)}\n`);
  return path;
}

/**
 * Branches this gate has watched become reviewable.
 *
 * This is how `git push` gating knows a branch is in front of a human WITHOUT asking GitHub. It is
 * populated when the gate ALLOWS a `pr create`/`pr ready`, which is the only moment the transition
 * is observable locally.
 *
 * THE HONEST HOLE, stated rather than hidden: a PR opened outside this gate -- through the web UI,
 * `gh api`, or a session with hooks disabled -- is never recorded, so pushes to it are unmetered.
 * That is a real gap and it is why the gate's message says what it cannot see.
 */
function reviewableePath(id: RepoIdentity): string {
  return join(STATE_ROOT, id.slug.replace("/", "__"), "reviewable-branches.json");
}

export function isBranchReviewable(id: RepoIdentity): boolean {
  const path = reviewableePath(id);
  if (!existsSync(path)) return false;
  try {
    const list = JSON.parse(readFileSync(path, "utf8"));
    return Array.isArray(list) && list.includes(id.branch);
  } catch {
    return false;
  }
}

export function markBranchReviewable(id: RepoIdentity): void {
  const path = reviewableePath(id);
  mkdirSync(dirname(path), { recursive: true });
  let list: string[] = [];
  if (existsSync(path)) {
    try {
      const parsed = JSON.parse(readFileSync(path, "utf8"));
      if (Array.isArray(parsed)) list = parsed.filter((x) => typeof x === "string");
    } catch {
      list = [];
    }
  }
  if (!list.includes(id.branch)) {
    list.push(id.branch);
    writeFileSync(path, `${JSON.stringify(list, null, 2)}\n`);
  }
}

/** Append-only audit of every override, so bypass is countable rather than invisible. */
export function recordOverride(id: RepoIdentity, kind: string, reason: string, command: string): void {
  const path = join(STATE_ROOT, "overrides.jsonl");
  mkdirSync(dirname(path), { recursive: true });
  const line = JSON.stringify({
    at: new Date().toISOString(),
    repo: id.slug,
    branch: id.branch,
    kind,
    reason,
    command: command.slice(0, 400),
  });
  try {
    const prior = existsSync(path) ? readFileSync(path, "utf8") : "";
    writeFileSync(path, `${prior}${line}\n`);
  } catch {
    // An audit failure must never block the operator's command.
  }
}
