#!/usr/bin/env bun
/**
 * The gate's WIRING, end to end, against real git repositories.
 *
 * WHY A THIRD TEST FILE. `review-round-artifact.test.ts` covers the pure classifier and
 * `review-round-state.test.ts` covers the store, and both were green on 2026-09-08 while the gate
 * unmarked the wrong branch on every `gh pr ready --undo <n>` it saw. The defect was entirely in
 * the join between them -- the gate read the branch from cwd and never looked at the argument the
 * command carried -- so no test of either half could see it. This file exercises the hook as the
 * harness runs it: a JSON payload on stdin, a decision on stdout, and the on-disk state read back
 * afterwards.
 *
 * Deliberately branch-NAME targets only. `gh pr ready --undo 666` needs a live `gh pr view` to
 * resolve, and a test that reaches the network is a test that fails on a plane; the number path's
 * behaviour on failure (change nothing) is asserted here instead, which is the branch that matters.
 */

import { afterEach, describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

import {
  STATE_ROOT,
  identifyRepo,
  isBranchReviewable,
  markBranchReviewable,
} from "./lib/review-round-state.ts";

const HOOK_PATH = join(dirname(import.meta.path), "pretooluse-review-round-gate.ts");

interface HookDecision {
  hookSpecificOutput: { permissionDecision: "allow" | "deny" | "ask" };
}

async function runHook(command: string, cwd: string): Promise<HookDecision> {
  const proc = Bun.spawn(["bun", HOOK_PATH], { stdin: "pipe", stdout: "pipe", stderr: "pipe" });
  proc.stdin.write(JSON.stringify({ tool_name: "Bash", tool_input: { command }, cwd }));
  proc.stdin.end();
  const out = await new Response(proc.stdout).text();
  await proc.exited;
  return JSON.parse(out.trim()) as HookDecision;
}

const created: string[] = [];

function sh(args: string[], cwd: string): string {
  return execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
}

/** A repo with `alpha` and `beta` both marked reviewable, left standing on `alpha`. */
function twoMarkedBranches(prefix: string): string {
  const dir = mkdtempSync(join(tmpdir(), `rrg-${prefix}-`));
  created.push(dir);
  sh(["init", "-q", "-b", "main"], dir);
  sh(["config", "user.email", "t@e.st"], dir);
  sh(["config", "user.name", "t"], dir);
  writeFileSync(join(dir, "a.txt"), "base\n");
  sh(["add", "-A"], dir);
  sh(["commit", "-qm", "base"], dir);

  for (const branch of ["alpha", "beta"]) {
    sh(["checkout", "-q", "main"], dir);
    sh(["checkout", "-qb", branch], dir);
    writeFileSync(join(dir, "a.txt"), `${branch}\n`);
    sh(["add", "-A"], dir);
    sh(["commit", "-qm", branch], dir);
    const id = identifyRepo(dir);
    if (id === null) throw new Error("identifyRepo returned null");
    markBranchReviewable(id, sh(["rev-parse", "HEAD"], dir).trim());
  }

  sh(["checkout", "-q", "alpha"], dir);
  return dir;
}

function reviewableOn(dir: string, branch: string): boolean {
  sh(["checkout", "-q", branch], dir);
  const id = identifyRepo(dir);
  if (id === null) throw new Error("identifyRepo returned null");
  return isBranchReviewable(id);
}

afterEach(() => {
  for (const dir of created.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
    rmSync(join(STATE_ROOT, dir.split("/").pop() as string), { recursive: true, force: true });
  }
});

describe("gh pr ready --undo unmarks the branch it NAMES", () => {
  test("a named branch is cleared and cwd's branch is left alone", async () => {
    // The 2026-09-08 incident in one assertion pair. Standing on alpha, re-drafting beta: the old
    // code cleared alpha (fail-open -- alpha's pushes stop being metered while it is still in front
    // of a reviewer) and left beta marked (false positive). Both halves are asserted, because
    // checking only that beta cleared would have passed on the old code whenever cwd was beta.
    const dir = twoMarkedBranches("named");
    const decision = await runHook("gh pr ready --undo beta", dir);

    expect(decision.hookSpecificOutput.permissionDecision).toBe("allow");
    expect(reviewableOn(dir, "alpha")).toBe(true);
    expect(reviewableOn(dir, "beta")).toBe(false);
  });

  test("the bare form still means the current branch", async () => {
    // `gh` itself falls back to the current branch with no positional argument, so the gate must
    // too. Removing the fallback would be the inverse defect.
    const dir = twoMarkedBranches("bare");
    const decision = await runHook("gh pr ready --undo", dir);

    expect(decision.hookSpecificOutput.permissionDecision).toBe("allow");
    expect(reviewableOn(dir, "alpha")).toBe(false);
    expect(reviewableOn(dir, "beta")).toBe(true);
  });

  test("a PR NUMBER that cannot be resolved changes NOTHING", async () => {
    // THIS IS THE CASE A MUTANT SURVIVED ON. The first version of this file asserted the
    // change-nothing rule through `$PR` and claimed in its comment that the substitution "never
    // resolves" -- it does: a non-numeric, non-URL target is treated as a literal branch name and
    // returned as-is, so the resolver never produced null and the null branch of the gate was
    // never executed. The test passed for an unrelated reason (unmarking a branch nobody marked is
    // a no-op), and a mutant that falls back to cwd's branch on failure lived through it.
    //
    // These repos have no origin, so `gh pr view 999999` fails immediately and offline -- no
    // network, no auth, deterministic on a plane.
    const dir = twoMarkedBranches("unresolvable-number");
    const decision = await runHook("gh pr ready --undo 999999", dir);

    expect(decision.hookSpecificOutput.permissionDecision).toBe("allow");
    expect(reviewableOn(dir, "alpha")).toBe(true);
    expect(reviewableOn(dir, "beta")).toBe(true);
  });

  test("a shell substitution is passed through as a branch name and hits nothing", async () => {
    // Kept for what it genuinely pins: `$PR` reaches the store as the literal branch name `$PR`,
    // which nothing has marked, so no mark moves and nothing throws. It does NOT exercise the
    // resolver's failure path -- the test above does.
    const dir = twoMarkedBranches("substitution");
    const decision = await runHook("gh pr ready --undo $PR", dir);

    expect(decision.hookSpecificOutput.permissionDecision).toBe("allow");
    expect(reviewableOn(dir, "alpha")).toBe(true);
    expect(reviewableOn(dir, "beta")).toBe(true);
  });

  test("-R's value is not mistaken for the target", async () => {
    // `-R owner/name` consumes the next word. Reading it as the PR would send the resolver looking
    // for a branch called `example-org/research-repo`, which fails, and beta would keep its mark.
    const dir = twoMarkedBranches("repo-flag");
    const decision = await runHook("gh pr ready -R example-org/research-repo --undo beta", dir);

    expect(decision.hookSpecificOutput.permissionDecision).toBe("allow");
    expect(reviewableOn(dir, "alpha")).toBe(true);
    expect(reviewableOn(dir, "beta")).toBe(false);
  });
});

/**
 * A branch checked out in its own worktree, with a self-review recorded there, while the "session"
 * stands in the main checkout on `main`. Returns both paths.
 */
function reviewedBranchInAWorktree(prefix: string): { main: string; worktree: string } {
  const main = mkdtempSync(join(tmpdir(), `rrg-${prefix}-main-`));
  const worktree = `${main}-wt`;
  created.push(main, worktree);
  sh(["init", "-q", "-b", "main"], main);
  sh(["config", "user.email", "t@e.st"], main);
  sh(["config", "user.name", "t"], main);
  writeFileSync(join(main, "a.txt"), "base\n");
  sh(["add", "-A"], main);
  sh(["commit", "-qm", "base"], main);
  sh(["worktree", "add", "-q", worktree, "-b", "feature"], main);
  writeFileSync(join(worktree, "a.txt"), "feature\n");
  sh(["add", "-A"], worktree);
  sh(["commit", "-qm", "feature"], worktree);
  execFileSync(
    "bun",
    [join(dirname(import.meta.path), "lib", "review-round-cli.ts"), "record", "--file", "a.txt=checked the one-line change"],
    { cwd: worktree, stdio: ["ignore", "ignore", "ignore"] },
  );
  return { main, worktree };
}

describe("gh pr create --head measures the named branch's worktree, not cwd", () => {
  // 2026-09-28, example-org/relay-monitor#133: the record existed at the pushed commit in the
  // worktree, the session stood in the main checkout on `main`, and the gate denied because it
  // measured `main`. Each case below has its control, because an allow alone would also pass on a
  // gate that simply stopped checking.
  test("a reviewed branch named by --head is allowed from the main checkout", async () => {
    const { main } = reviewedBranchInAWorktree("head");
    const decision = await runHook("gh pr create --head feature --title t --body-file /tmp/b.md", main);
    expect(decision.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("control: the same command WITHOUT --head is still measured on cwd and denied", async () => {
    const { main } = reviewedBranchInAWorktree("nohead");
    const decision = await runHook("gh pr create --title t --body-file /tmp/b.md", main);
    expect(decision.hookSpecificOutput.permissionDecision).toBe("deny");
  });

  test("control: an UNREVIEWED branch named by --head is still denied", async () => {
    const { main, worktree } = reviewedBranchInAWorktree("unreviewed");
    // A change after the record invalidates it: the gate must now see the worktree's new diff.
    writeFileSync(join(worktree, "a.txt"), "changed after review\n");
    const decision = await runHook("gh pr create --head feature --title t --body-file /tmp/b.md", main);
    expect(decision.hookSpecificOutput.permissionDecision).toBe("deny");
  });

  test("a --head with no local worktree falls back to cwd, never widening what is allowed", async () => {
    const { main } = reviewedBranchInAWorktree("noworktree");
    const decision = await runHook("gh pr create --head some-other-branch --title t --body-file /tmp/b.md", main);
    expect(decision.hookSpecificOutput.permissionDecision).toBe("deny");
  });
});
