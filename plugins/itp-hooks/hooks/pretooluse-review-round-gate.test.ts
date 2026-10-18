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
import { chmodSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
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
  hookSpecificOutput: { permissionDecision: "allow" | "deny" | "ask"; permissionDecisionReason?: string };
}

async function runHook(command: string, cwd: string, env?: Record<string, string>): Promise<HookDecision> {
  const proc = Bun.spawn(["bun", HOOK_PATH], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    env: env === undefined ? process.env : { ...process.env, ...env },
  });
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

/**
 * A directory holding a fake `gh` that prints `stdout` and exits `code`, prepended to PATH.
 *
 * The number path of `gh pr ready N` asks GitHub for the PR's head and base. A test that reached
 * the network would fail on a plane, so the lookup is answered by a stub with the same output shape
 * as `gh pr view N --json headRefName,baseRefName`.
 */
function fakeGh(stdout: string, code = 0): Record<string, string> {
  const dir = mkdtempSync(join(tmpdir(), "rrg-fakegh-"));
  created.push(dir);
  const bin = join(dir, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "gh"), `#!/bin/sh\nprintf '%s' '${stdout}'\nexit ${code}\n`);
  chmodSync(join(bin, "gh"), 0o755);
  return { PATH: `${bin}:${process.env.PATH ?? ""}` };
}

describe("the gate measures the directory the COMMAND runs in (2026-10-17)", () => {
  // Reported from a session standing in the main checkout: `cd <worktree> && gh pr ready N` was
  // denied after `review-round-cli.ts record` had been run in that worktree, because the gate read
  // HEAD and branch from the session's cwd. Every allow below has a control that still denies.
  test("cd <worktree> && gh pr ready is allowed when the worktree's head is recorded", async () => {
    const { main, worktree } = reviewedBranchInAWorktree("cd-ready");
    const decision = await runHook(`cd ${worktree} && gh pr ready`, main);
    expect(decision.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("cd <worktree> && gh pr create is allowed when the worktree's head is recorded", async () => {
    const { main, worktree } = reviewedBranchInAWorktree("cd-create");
    const decision = await runHook(`cd "${worktree}" && gh pr create --title t --body-file /tmp/b.md`, main);
    expect(decision.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("control: an edit after the record is denied, and the deny says what it measured", async () => {
    const { main, worktree } = reviewedBranchInAWorktree("cd-edited");
    writeFileSync(join(worktree, "a.txt"), "changed after review\n");
    const decision = await runHook(`cd ${worktree} && gh pr ready`, main);
    expect(decision.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(decision.hookSpecificOutput.permissionDecisionReason).toContain(`Measured: ${realpathSync(worktree)} on feature`); // macOS: /var is /private/var
  });

  test("a directory the text cannot resolve ($VAR) falls back to the session cwd and is denied", async () => {
    const { main } = reviewedBranchInAWorktree("cd-var");
    const decision = await runHook("cd $WT && gh pr ready", main);
    expect(decision.hookSpecificOutput.permissionDecision).toBe("deny");
  });

  test("gh pr ready <branch> from the main checkout measures that branch's worktree", async () => {
    const { main } = reviewedBranchInAWorktree("ready-branch");
    const decision = await runHook("gh pr ready feature", main);
    expect(decision.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("gh pr ready <number> resolves the PR's head branch to its worktree", async () => {
    const { main } = reviewedBranchInAWorktree("ready-number");
    const env = fakeGh('{"headRefName":"feature","baseRefName":"main"}');
    const decision = await runHook("gh pr ready 7", main, env);
    expect(decision.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("control: a failed PR lookup changes nothing, so the session cwd (main) is measured and denied", async () => {
    const { main } = reviewedBranchInAWorktree("ready-number-fail");
    const decision = await runHook("gh pr ready 7", main, fakeGh("", 1));
    expect(decision.hookSpecificOutput.permissionDecision).toBe("deny");
  });

  test("git -C <worktree> push is metered on the worktree's branch", async () => {
    // TRUE POSITIVE that the old gate missed: the branch in the worktree is in front of a reviewer
    // and its head has moved past the record, but measured from the main checkout (`main`, never
    // marked) the push was allowed unmetered.
    const { main, worktree } = reviewedBranchInAWorktree("dash-c-push");
    const id = identifyRepo(worktree);
    if (id === null) throw new Error("identifyRepo returned null");
    markBranchReviewable(id, sh(["rev-parse", "HEAD"], worktree).trim());
    writeFileSync(join(worktree, "a.txt"), "unreviewed follow-up\n");
    sh(["commit", "-qam", "follow-up"], worktree);

    expect((await runHook(`git -C ${worktree} push`, main)).hookSpecificOutput.permissionDecision).toBe("deny");
    // Control: the same push from the main checkout, without -C, concerns `main`, which is not marked.
    expect((await runHook("git push", main)).hookSpecificOutput.permissionDecision).toBe("allow");
  });

  test("a gh command quoted inside a heredoc body is data, not a gated command", async () => {
    // Found while writing these tests: a heredoc whose BODY contained the text of a `gh pr ready`
    // command was classified as one and denied, from a directory with nothing to submit.
    const { main } = reviewedBranchInAWorktree("heredoc");
    const command = ["cat > /tmp/notes.txt <<'EOF'", "then run: cd wt && gh pr ready 12", "EOF"].join("\n");
    expect((await runHook(command, main)).hookSpecificOutput.permissionDecision).toBe("allow");
  });
});
