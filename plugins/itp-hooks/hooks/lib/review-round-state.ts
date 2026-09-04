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
import { createHash } from "node:crypto";
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
    const root = git(["rev-parse", "--show-toplevel"], cwd).trim();
    const headSha = git(["rev-parse", "HEAD"], cwd).trim();
    // Working tree INCLUDED: `git diff <base>` (no `..HEAD`) spans committed and uncommitted work,
    // so an artifact cannot be satisfied by recording a pass and then editing before pushing.
    let diffText = git(["diff", base], cwd);
    const tracked = git(["diff", "--name-only", base], cwd)
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean);

    // UNTRACKED FILES ARE PART OF THE CHANGE, and `git diff` cannot see them.
    //
    // Found by using the gate on itself: recording a self-review for this very commit was REFUSED
    // because the new test file was not in `git diff --name-only`, so the gate considered a verdict
    // for it to be a verdict for a file that is not in the diff. The failure was cosmetic; what it
    // exposed was not. A brand-new file was exempt from the requirement entirely, and because the
    // S2 diff hash also could not see it, an entire new module could be added AFTER recording a
    // pass without invalidating the record. New files are precisely where unreviewed code lives.
    //
    // `--exclude-standard` honours .gitignore, so build output and caches stay out. `--full-name`
    // forces repo-root-relative paths to match `git diff --name-only`, which is root-relative
    // regardless of cwd; without it, running from a subdirectory produced two different spellings
    // of the same file and the set comparison failed for a reason that had nothing to do with review.
    const untracked = git(["ls-files", "--others", "--exclude-standard", "--full-name"], cwd)
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean);

    // Hash the CONTENT rather than inlining it: a new file may be binary or large, and all the
    // artifact needs is a value that changes when the file changes.
    for (const rel of untracked.toSorted()) {
      let digest = "unreadable";
      try {
        digest = createHash("sha256").update(readFileSync(join(root, rel))).digest("hex");
      } catch {
        // Unreadable is still recorded, and recorded DISTINCTLY, so it cannot silently look
        // identical to a readable file or vanish from the hash.
      }
      diffText += `\n--- untracked ${rel} ${digest}\n`;
    }

    const changedPaths = [...new Set([...tracked, ...untracked])].toSorted();
    return { headSha, baseSha: base, diffText, changedPaths };
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------------------------
// Stores
// ---------------------------------------------------------------------------------------------

/**
 * ONE spelling of the on-disk key, used by BOTH stores.
 *
 * They disagreed before: the artifact path sanitised the branch name while the reviewable list
 * stored it raw, so `feat/x` and `feat_x` were one branch to the artifact store and two to the
 * reviewable store. `String.replace` with a string pattern also substitutes only the FIRST match,
 * so a slug containing two slashes was mangled. Both are latent today and neither is a defect
 * anyone would find by reading the call sites -- which is the argument for having one function.
 */
function repoDir(id: RepoIdentity): string {
  return join(STATE_ROOT, id.slug.replaceAll("/", "__"));
}

/**
 * INJECTIVE, which the original was not. Collapsing every unsafe character to `_` maps `feat/x` and
 * `feat_x` onto one key, so two live branches shared one artifact and one reviewable record -- a
 * self-review recorded on one silently satisfied the gate on the other. Percent-escaping is
 * reversible, so distinct branches keep distinct keys, including a branch perversely named
 * `feat%2Fx` (the `%` is itself escaped).
 */
function branchKey(id: RepoIdentity): string {
  return id.branch.replace(
    /[^A-Za-z0-9._-]/g,
    (ch) => `%${ch.charCodeAt(0).toString(16).toUpperCase().padStart(2, "0")}`,
  );
}

function artifactPath(id: RepoIdentity): string {
  return join(repoDir(id), `${branchKey(id)}.json`);
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
 * Branches this gate has watched become reviewable, each ANCHORED TO THE COMMIT it was shown at.
 *
 * This is how `git push` gating knows a branch is in front of a human WITHOUT asking GitHub. It is
 * populated when the gate ALLOWS a `pr create`/`pr ready`, which is the only moment the transition
 * is observable locally.
 *
 * THE ANCHOR IS THE POINT, and the first version did not have one. It stored bare branch NAMES and
 * had no code path that ever removed one -- no expiry, no TTL, no unmark. The bit therefore
 * survived the PR merging, the PR closing, the branch being deleted, and the same branch name being
 * created again months later for unrelated work. A gate whose scope is "only once a review is
 * pending" was in fact binding "forever, once a review was ever pending, even on a different
 * branch that happens to share a name".
 *
 * Recording the sha and requiring it to still be an ancestor of HEAD fixes all four with one local
 * predicate. A recreated branch of the same name does not descend from the old sha, so it reads as
 * not-reviewable; a deleted-and-restored branch likewise. `--undo` is handled separately and
 * explicitly, because converting back to draft is a real transition rather than a divergence.
 *
 * IT MUST STAY LOCAL. `gh pr view --json state` would answer this exactly, and it is precisely the
 * call this gate cannot make: a PreToolUse hook that times out does not block, so a network probe
 * resolves to ALLOW whenever GitHub is slow.
 *
 * TWO HONEST HOLES, stated rather than hidden. (1) A PR opened outside this gate -- web UI, `gh
 * api`, or a session with hooks disabled -- is never recorded, so pushes to it are unmetered.
 * (2) A PR opened through the REVIEW_ROUND_OK override is also never recorded, because the override
 * path returns `ask` and stops before the mark is written. Marking there was considered and
 * rejected: `ask` means the operator may still decline, and a mark written for a command that was
 * then declined would gate every later push to a branch that has no PR at all -- a false positive
 * with no remedy, which is the failure mode that gets a guard switched off.
 */
export interface ReviewableRecord {
  readonly branch: string;
  readonly sha: string;
  readonly at: string;
}

interface ReviewableStore {
  readonly schema: 2;
  readonly branches: ReviewableRecord[];
}

function reviewablePath(id: RepoIdentity): string {
  return join(repoDir(id), "reviewable-branches.json");
}

function readReviewableStore(id: RepoIdentity): ReviewableRecord[] {
  const path = reviewablePath(id);
  if (!existsSync(path)) return [];
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8"));
    // A v1 store was a bare string[] with no sha. There is no honest migration -- the commit it was
    // reviewed at is simply not recorded -- and inventing one (e.g. treating HEAD as the anchor)
    // would silently re-arm a stale mark. Discard it: the worst case is one unmetered push, which
    // is strictly better than an un-expirable gate, and the gate re-marks on the next `pr ready`.
    if (!parsed || !Array.isArray(parsed.branches)) return [];
    return parsed.branches.filter(
      (r: unknown): r is ReviewableRecord =>
        typeof r === "object" &&
        r !== null &&
        typeof (r as ReviewableRecord).branch === "string" &&
        typeof (r as ReviewableRecord).sha === "string",
    );
  } catch {
    return [];
  }
}

function writeReviewableStore(id: RepoIdentity, branches: ReviewableRecord[]): void {
  const path = reviewablePath(id);
  mkdirSync(dirname(path), { recursive: true });
  const store: ReviewableStore = { schema: 2, branches };
  writeFileSync(path, `${JSON.stringify(store, null, 2)}\n`);
}

/** True when `sha` is an ancestor of HEAD. False on any git failure -- unknown must not gate. */
function stillDescendsFrom(sha: string, cwd: string): boolean {
  try {
    git(["merge-base", "--is-ancestor", sha, "HEAD"], cwd);
    return true;
  } catch {
    return false;
  }
}

export function isBranchReviewable(id: RepoIdentity): boolean {
  const record = readReviewableStore(id).find((r) => r.branch === branchKey(id));
  if (!record) return false;
  return stillDescendsFrom(record.sha, id.root);
}

export function markBranchReviewable(id: RepoIdentity, sha: string): void {
  const key = branchKey(id);
  const others = readReviewableStore(id).filter((r) => r.branch !== key);
  writeReviewableStore(id, [...others, { branch: key, sha, at: new Date().toISOString() }]);
}

/** Drop the mark: the branch has left the review queue (`gh pr ready --undo`). */
export function unmarkBranchReviewable(id: RepoIdentity): void {
  const key = branchKey(id);
  const current = readReviewableStore(id);
  const remaining = current.filter((r) => r.branch !== key);
  if (remaining.length !== current.length) writeReviewableStore(id, remaining);
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
