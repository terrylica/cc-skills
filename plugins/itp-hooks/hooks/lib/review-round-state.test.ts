#!/usr/bin/env bun
/**
 * The reviewable-branch lifecycle, against REAL git repositories.
 *
 * WHY THIS FILE EXISTS. The gate shipped with tests for its pure classifier and validator and none
 * at all for this state machine, and every defect it is now being fixed for lived here: the mark was
 * never cleared by anything, `gh pr ready --undo` silently did not clear it despite a comment saying
 * it removed work from the queue, the two stores disagreed on how to spell a branch name, and a
 * recreated branch inherited the mark of the deleted one. None of those are visible from the pure
 * functions, which is precisely why testing only the pure functions found none of them.
 *
 * These use real `git init` repositories rather than a mocked git, because the fix turns on
 * `git merge-base --is-ancestor` actually behaving like git.
 */

import { afterEach, describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync, mkdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  STATE_ROOT,
  baseRefCandidates,
  collectFacts,
  identifyRepo,
  isBranchReviewable,
  markBranchReviewable,
  unmarkBranchReviewable,
} from "./review-round-state.ts";

const created: string[] = [];

function sh(args: string[], cwd: string): string {
  return execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
}

/** A throwaway repo with one commit on `main`, and no origin so the slug is the directory name. */
function makeRepo(prefix: string): { dir: string; slug: string } {
  const dir = mkdtempSync(join(tmpdir(), `rrs-${prefix}-`));
  created.push(dir);
  sh(["init", "-q", "-b", "main"], dir);
  sh(["config", "user.email", "t@e.st"], dir);
  sh(["config", "user.name", "t"], dir);
  writeFileSync(join(dir, "a.txt"), "one\n");
  sh(["add", "-A"], dir);
  sh(["commit", "-qm", "base"], dir);
  return { dir, slug: dir.split("/").pop() as string };
}

function commit(dir: string, text: string): void {
  writeFileSync(join(dir, "a.txt"), text);
  sh(["add", "-A"], dir);
  sh(["commit", "-qm", "work"], dir);
}

function idOf(dir: string) {
  const id = identifyRepo(dir);
  if (id === null) throw new Error(`identifyRepo returned null for ${dir}`);
  return id;
}

afterEach(() => {
  for (const dir of created.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
    rmSync(join(STATE_ROOT, dir.split("/").pop() as string), { recursive: true, force: true });
  }
});

describe("BASELINE", () => {
  test("an honest mark makes the branch reviewable", () => {
    const { dir } = makeRepo("baseline");
    sh(["checkout", "-qb", "feature"], dir);
    commit(dir, "one\ntwo\n");
    const id = idOf(dir);

    expect(isBranchReviewable(id)).toBe(false); // nothing recorded yet
    markBranchReviewable(id, sh(["rev-parse", "HEAD"], dir).trim());
    expect(isBranchReviewable(id)).toBe(true);
  });
});

describe("the mark expires instead of lasting forever", () => {
  test("committing further on the SAME branch keeps it reviewable", () => {
    // The review is still pending; new commits are exactly the fix rounds the gate meters.
    const { dir } = makeRepo("forward");
    sh(["checkout", "-qb", "feature"], dir);
    commit(dir, "one\ntwo\n");
    const id = idOf(dir);
    markBranchReviewable(id, sh(["rev-parse", "HEAD"], dir).trim());

    commit(dir, "one\ntwo\nthree\n");
    expect(isBranchReviewable(id)).toBe(true);
  });

  test("a RECREATED branch of the same name does NOT inherit the mark", () => {
    // The defect this replaced: the store held bare branch names forever, so deleting a merged
    // branch and later creating an unrelated one with the same name produced a branch that was
    // "reviewable" from its first push, with no PR in existence.
    const { dir } = makeRepo("reuse");
    sh(["checkout", "-qb", "feature"], dir);
    commit(dir, "one\ntwo\n");
    const id = idOf(dir);
    markBranchReviewable(id, sh(["rev-parse", "HEAD"], dir).trim());
    expect(isBranchReviewable(id)).toBe(true);

    sh(["checkout", "-q", "main"], dir);
    sh(["branch", "-qD", "feature"], dir);
    sh(["checkout", "-qb", "feature"], dir); // same NAME, different history
    commit(dir, "unrelated\n");

    expect(isBranchReviewable(idOf(dir))).toBe(false);
  });

  test("a mark from an unrelated commit does not apply", () => {
    const { dir } = makeRepo("unrelated");
    sh(["checkout", "-qb", "feature"], dir);
    commit(dir, "one\ntwo\n");
    const id = idOf(dir);
    // A sha that exists but is not an ancestor of HEAD.
    sh(["checkout", "-q", "main"], dir);
    sh(["checkout", "-qb", "sidebranch"], dir);
    commit(dir, "side\n");
    const sideSha = sh(["rev-parse", "HEAD"], dir).trim();
    sh(["checkout", "-q", "feature"], dir);

    markBranchReviewable(id, sideSha);
    expect(isBranchReviewable(idOf(dir))).toBe(false);
  });

  test("a sha that no longer exists reads as not reviewable, and does not throw", () => {
    const { dir } = makeRepo("missing");
    sh(["checkout", "-qb", "feature"], dir);
    commit(dir, "one\ntwo\n");
    markBranchReviewable(idOf(dir), "0".repeat(40));
    expect(isBranchReviewable(idOf(dir))).toBe(false);
  });
});

describe("leaving the queue", () => {
  test("unmark clears it", () => {
    const { dir } = makeRepo("undo");
    sh(["checkout", "-qb", "feature"], dir);
    commit(dir, "one\ntwo\n");
    const id = idOf(dir);
    markBranchReviewable(id, sh(["rev-parse", "HEAD"], dir).trim());
    expect(isBranchReviewable(id)).toBe(true);

    unmarkBranchReviewable(id);
    expect(isBranchReviewable(id)).toBe(false);
  });

  test("unmark leaves OTHER branches' marks intact", () => {
    // A blanket "clear the store" would pass the test above and silently unmeter every other
    // in-flight PR in the same repository.
    const { dir } = makeRepo("undo-scope");
    sh(["checkout", "-qb", "alpha"], dir);
    commit(dir, "alpha\n");
    const alpha = idOf(dir);
    markBranchReviewable(alpha, sh(["rev-parse", "HEAD"], dir).trim());

    sh(["checkout", "-q", "main"], dir);
    sh(["checkout", "-qb", "beta"], dir);
    commit(dir, "beta\n");
    const beta = idOf(dir);
    markBranchReviewable(beta, sh(["rev-parse", "HEAD"], dir).trim());

    unmarkBranchReviewable(beta);
    expect(isBranchReviewable(beta)).toBe(false);

    sh(["checkout", "-q", "alpha"], dir);
    expect(isBranchReviewable(idOf(dir))).toBe(true);
  });

  test("an explicit branch overrides the identity's own, in BOTH directions", () => {
    // THE MEASURED DEFECT, pinned. `gh pr ready --undo 666` names a PR that is usually not the
    // branch of the directory it is typed in; the identity's branch came from cwd, so five
    // re-drafts run from one worktree cleared that worktree's mark five times and none of the
    // five correct ones. Asserting only that beta clears would still pass on the old code when
    // cwd happened to BE beta -- so alpha's survival is asserted too, and cwd is deliberately
    // parked on alpha, the branch that must NOT change.
    const { dir } = makeRepo("undo-explicit");
    sh(["checkout", "-qb", "alpha"], dir);
    commit(dir, "alpha\n");
    const alpha = idOf(dir);
    markBranchReviewable(alpha, sh(["rev-parse", "HEAD"], dir).trim());

    sh(["checkout", "-q", "main"], dir);
    sh(["checkout", "-qb", "beta"], dir);
    commit(dir, "beta\n");
    markBranchReviewable(idOf(dir), sh(["rev-parse", "HEAD"], dir).trim());

    sh(["checkout", "-q", "alpha"], dir);
    unmarkBranchReviewable(idOf(dir), "beta");

    expect(isBranchReviewable(idOf(dir))).toBe(true); // cwd's branch untouched
    sh(["checkout", "-q", "beta"], dir);
    expect(isBranchReviewable(idOf(dir))).toBe(false); // the NAMED branch cleared
  });

  test("unmarking a branch that was never marked is a no-op, not a crash", () => {
    const { dir } = makeRepo("undo-absent");
    sh(["checkout", "-qb", "feature"], dir);
    commit(dir, "one\ntwo\n");
    expect(() => unmarkBranchReviewable(idOf(dir))).not.toThrow();
    expect(isBranchReviewable(idOf(dir))).toBe(false);
  });
});

function factsOf(dir: string) {
  const f = collectFacts(dir);
  if (f === null) throw new Error("collectFacts returned null");
  return f;
}

describe("a new file is part of the change", () => {
  test("an untracked file appears in changedPaths", () => {
    // `git diff` cannot see untracked files, so before this the gate exempted every newly-added
    // file from the self-review requirement entirely — the files most likely to contain code
    // nobody has read. Found by running the gate's own CLI on the commit that introduced it.
    const { dir } = makeRepo("untracked");
    sh(["checkout", "-qb", "feature"], dir);
    commit(dir, "one\ntwo\n");
    writeFileSync(join(dir, "brand-new.ts"), "export const x = 1;\n");

    expect(factsOf(dir).changedPaths).toContain("brand-new.ts");
  });

  test("editing an untracked file changes the diff hash", () => {
    // Without this, a pass could be recorded and an entire new module added afterwards while the
    // record stayed valid — S2 would not notice, because S2 hashes a diff the file is absent from.
    const { dir } = makeRepo("untracked-hash");
    sh(["checkout", "-qb", "feature"], dir);
    commit(dir, "one\ntwo\n");
    writeFileSync(join(dir, "brand-new.ts"), "export const x = 1;\n");
    const before = factsOf(dir).diffText;

    writeFileSync(join(dir, "brand-new.ts"), "export const x = 2;\n");
    expect(factsOf(dir).diffText).not.toBe(before);
  });

  test("a gitignored file is NOT treated as part of the change", () => {
    // Build output and caches must not demand a verdict, or the gate fires constantly on work
    // nobody wrote — the profile of a guard that gets switched off.
    const { dir } = makeRepo("ignored");
    sh(["checkout", "-qb", "feature"], dir);
    writeFileSync(join(dir, ".gitignore"), "junk/\n");
    sh(["add", "-A"], dir);
    sh(["commit", "-qm", "ignore"], dir);
    mkdirSync(join(dir, "junk"), { recursive: true });
    writeFileSync(join(dir, "junk", "out.bin"), "generated\n");

    expect(factsOf(dir).changedPaths.some((p) => p.startsWith("junk/"))).toBe(false);
  });
});

describe("store robustness", () => {
  test("a legacy v1 array store is discarded rather than trusted or crashed on", () => {
    // v1 held bare names and no sha. There is no honest migration -- the reviewed commit simply was
    // not recorded -- and inventing one would re-arm a mark that can never expire.
    const { dir, slug } = makeRepo("legacy");
    sh(["checkout", "-qb", "feature"], dir);
    commit(dir, "one\ntwo\n");
    const path = join(STATE_ROOT, slug, "reviewable-branches.json");
    mkdirSync(join(STATE_ROOT, slug), { recursive: true });
    writeFileSync(path, JSON.stringify(["feature"], null, 2));

    expect(isBranchReviewable(idOf(dir))).toBe(false);
  });

  test("an unparseable store reads as not reviewable rather than throwing", () => {
    const { dir, slug } = makeRepo("corrupt");
    sh(["checkout", "-qb", "feature"], dir);
    commit(dir, "one\ntwo\n");
    mkdirSync(join(STATE_ROOT, slug), { recursive: true });
    writeFileSync(join(STATE_ROOT, slug, "reviewable-branches.json"), "{ not json");

    expect(isBranchReviewable(idOf(dir))).toBe(false);
  });

  test("re-marking replaces the anchor rather than accumulating duplicates", () => {
    const { dir, slug } = makeRepo("remark");
    sh(["checkout", "-qb", "feature"], dir);
    commit(dir, "one\ntwo\n");
    const id = idOf(dir);
    markBranchReviewable(id, sh(["rev-parse", "HEAD"], dir).trim());
    commit(dir, "one\ntwo\nthree\n");
    const second = sh(["rev-parse", "HEAD"], dir).trim();
    markBranchReviewable(id, second);

    const store = JSON.parse(
      readFileSync(join(STATE_ROOT, slug, "reviewable-branches.json"), "utf8"),
    );
    expect(store.branches.length).toBe(1);
    expect(store.branches[0].sha).toBe(second);
  });

  test("a slash-bearing branch name round-trips", () => {
    // Both stores must agree on the key. They did not: the artifact path sanitised the name while
    // the reviewable list stored it raw.
    const { dir } = makeRepo("slashes");
    sh(["checkout", "-qb", "fix/2026-09-04/nested"], dir);
    commit(dir, "one\ntwo\n");
    const id = idOf(dir);
    expect(id.branch).toBe("fix/2026-09-04/nested");

    markBranchReviewable(id, sh(["rev-parse", "HEAD"], dir).trim());
    expect(isBranchReviewable(idOf(dir))).toBe(true);
    unmarkBranchReviewable(id);
    expect(isBranchReviewable(idOf(dir))).toBe(false);
  });

  test("`feat/x` and `feat_x` are DISTINCT branches to the store", () => {
    // The original key collapsed every unsafe character to `_`, mapping these two live branches
    // onto one record -- so marking one marked the other, and a self-review recorded against one
    // satisfied the gate on the other. A round-trip test cannot see this: a consistently-wrong key
    // round-trips perfectly. Only two branches that COLLIDE under the old scheme can.
    // THE ANCESTRY MUST NOT RESCUE THE TEST. A first version created the two branches as siblings
    // off main, and it passed even with the collision restored -- because the sha anchor rejected
    // the borrowed record independently, so the test proved the anchor works, not that the keys
    // differ. It survived its own mutation and I nearly kept it.
    //
    // Making `feat/x` a DESCENDANT of `feat_x` removes that second line of defence: the borrowed
    // sha IS an ancestor of HEAD, so the anchor says yes and only a distinct key can say no.
    const { dir } = makeRepo("collide");
    sh(["checkout", "-qb", "feat_x"], dir);
    commit(dir, "underscored\n");
    const underscored = idOf(dir);
    markBranchReviewable(underscored, sh(["rev-parse", "HEAD"], dir).trim());
    expect(isBranchReviewable(underscored)).toBe(true);

    sh(["checkout", "-qb", "feat/x"], dir); // branches FROM feat_x, so it descends from that sha
    commit(dir, "slashed\n");

    expect(isBranchReviewable(idOf(dir))).toBe(false);
  });
});

describe("the base is the REMOTE's branch, whatever the remote is called (2026-10-17)", () => {
  // Reported: a repository whose only remote is `github` had no `origin/main`, so the gate fell back
  // to the LOCAL `main`, days behind, and demanded verdicts for nine files the PR never touched.
  function remoteNamedGithubWithStaleLocalMain(prefix: string): { work: string } {
    const bare = mkdtempSync(join(tmpdir(), `rrs-${prefix}-bare-`));
    created.push(bare);
    sh(["init", "-q", "--bare", "-b", "main"], bare);

    const seed = mkdtempSync(join(tmpdir(), `rrs-${prefix}-seed-`));
    created.push(seed);
    sh(["clone", "-q", bare, seed], seed);
    sh(["config", "user.email", "t@e.st"], seed);
    sh(["config", "user.name", "t"], seed);
    writeFileSync(join(seed, "a.txt"), "one\n");
    sh(["add", "-A"], seed);
    sh(["commit", "-qm", "base"], seed);
    sh(["push", "-q", "origin", "HEAD:main"], seed);

    const work = mkdtempSync(join(tmpdir(), `rrs-${prefix}-work-`));
    created.push(work);
    sh(["clone", "-q", "-o", "github", bare, work], work);
    sh(["config", "user.email", "t@e.st"], work);
    sh(["config", "user.name", "t"], work);

    // Others land two files on the remote's main; the local `main` in `work` is never updated.
    writeFileSync(join(seed, "landed-1.txt"), "x\n");
    writeFileSync(join(seed, "landed-2.txt"), "y\n");
    sh(["add", "-A"], seed);
    sh(["commit", "-qm", "landed elsewhere"], seed);
    sh(["push", "-q", "origin", "HEAD:main"], seed);
    sh(["checkout", "-q", "-b", "develop"], seed);
    writeFileSync(join(seed, "develop-only.txt"), "z\n");
    sh(["add", "-A"], seed);
    sh(["commit", "-qm", "develop"], seed);
    sh(["push", "-q", "origin", "develop"], seed);

    sh(["fetch", "-q", "github"], work);
    sh(["checkout", "-q", "-b", "feature", "github/main"], work);
    writeFileSync(join(work, "feature.txt"), "mine\n");
    sh(["add", "-A"], work);
    sh(["commit", "-qm", "feature"], work);
    return { work };
  }

  test("only the branch's own files are changed, measured against github/*", () => {
    const { work } = remoteNamedGithubWithStaleLocalMain("github-remote");
    const facts = factsOf(work);
    expect(facts.changedPaths).toEqual(["feature.txt"]);
    expect(facts.baseRef?.startsWith("github/")).toBe(true);
  });

  test("an explicit base (a stacked PR's baseRefName) is measured against <remote>/<base>", () => {
    const { work } = remoteNamedGithubWithStaleLocalMain("explicit-base");
    // A stacked branch cut from develop: its own change is stacked.txt alone.
    sh(["checkout", "-q", "-b", "stacked", "github/develop"], work);
    writeFileSync(join(work, "stacked.txt"), "on top of develop\n");
    sh(["add", "-A"], work);
    sh(["commit", "-qm", "stacked"], work);

    const againstDevelop = collectFacts(work, "develop");
    expect(againstDevelop?.baseRef).toBe("github/develop");
    expect(againstDevelop?.changedPaths).toEqual(["stacked.txt"]);
    // Control: against the default branch, develop's own commit would be demanded too.
    expect(factsOf(work).changedPaths).toEqual(["develop-only.txt", "stacked.txt"]);
  });

  test("an explicit base with no ref anywhere falls back to the default branch, not to null", () => {
    const { work } = remoteNamedGithubWithStaleLocalMain("missing-base");
    const facts = collectFacts(work, "no-such-branch");
    expect(facts).not.toBeNull();
    expect(facts?.changedPaths).toEqual(["feature.txt"]);
  });

  test("candidate order: remote refs before local branches", () => {
    const { work } = remoteNamedGithubWithStaleLocalMain("order");
    const candidates = baseRefCandidates(work);
    expect(candidates.indexOf("refs/remotes/github/HEAD")).toBeLessThan(candidates.indexOf("refs/heads/main"));
  });
});

describe("repoSlugOf reads every form a remote URL or gh -R takes", () => {
  test("owner/repo, https, ssh, scp-style with a host alias, .git and trailing slash", () => {
    const { repoSlugOf } = require("./review-round-state.ts") as typeof import("./review-round-state.ts");
    expect(repoSlugOf("Acme/Other")).toBe("acme/other");
    expect(repoSlugOf("https://github.com/acme/other")).toBe("acme/other");
    expect(repoSlugOf("https://github.com/acme/other.git/")).toBe("acme/other");
    expect(repoSlugOf("git@github.com:acme/other.git")).toBe("acme/other");
    expect(repoSlugOf("git@github.com-terrylica:acme/other.git")).toBe("acme/other");
    expect(repoSlugOf("ssh://git@github.com/acme/other.git")).toBe("acme/other");
    expect(repoSlugOf("other")).toBeNull();
  });
});
