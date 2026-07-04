/**
 * Tests for pretooluse-git-worktree-guard.ts
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-git-worktree-guard.test.ts
 *
 * Two layers:
 *   1. Pure unit tests against classifyBranchCreation() (fast, no subprocess).
 *   2. Subprocess tests through the real hook (verifies stdin/JSON/deny wiring,
 *      fast-path, isReadOnly, and the escape hatches).
 */

import { describe, expect, it } from "bun:test";
import { execSync } from "child_process";
import { join } from "path";
import { classifyBranchCreation } from "./git-worktree-guard-patterns.ts";

const HOOK_PATH = join(import.meta.dir, "pretooluse-git-worktree-guard.ts");

interface HookResult {
  stdout: string;
  parsed: {
    hookSpecificOutput?: {
      hookEventName: string;
      permissionDecision: "allow" | "deny";
      permissionDecisionReason?: string;
    };
  } | null;
}

function runHook(command: string, toolName = "Bash"): HookResult {
  const input = JSON.stringify({ tool_name: toolName, tool_input: { command } });
  let stdout = "";
  try {
    stdout = execSync(`bun ${HOOK_PATH}`, {
      encoding: "utf-8",
      input,
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch (err: any) {
    stdout = err.stdout?.toString().trim() || "";
  }
  let parsed = null;
  if (stdout) {
    try {
      parsed = JSON.parse(stdout);
    } catch {
      /* not JSON */
    }
  }
  return { stdout, parsed };
}

function expectDeny(result: HookResult): void {
  expect(result.parsed).not.toBeNull();
  expect(result.parsed!.hookSpecificOutput?.permissionDecision).toBe("deny");
  expect(result.parsed!.hookSpecificOutput?.permissionDecisionReason).toContain("[WORKTREE-GUARD]");
}

function expectAllow(result: HookResult): void {
  expect(result.parsed).not.toBeNull();
  expect(result.parsed!.hookSpecificOutput?.permissionDecision).toBe("allow");
}

// ============================================================================
// Layer 1: pure classifier
// ============================================================================

describe("classifyBranchCreation — BLOCK", () => {
  const blocked: Array<[string, string]> = [
    ["git checkout -b feature/x", "git checkout -b feature/x"],
    ["git checkout -B feature/x", "git checkout -B"],
    ["git checkout --branch feature/x", "git checkout --branch"],
    ["git switch -c feature/x", "git switch -c"],
    ["git switch -C feature/x", "git switch -C"],
    ["git switch --create feature/x", "git switch --create"],
    ["git switch --force-create feature/x", "git switch --force-create"],
    ["git branch newfeat", "git branch <new>"],
    ["git branch newfeat origin/main", "git branch <new> <start>"],
    ["git -C /repo checkout -b feature/x", "git -C global option"],
    ["git --git-dir=/r/.git switch -c x", "git --git-dir global option"],
    ["git town hack feature/x", "git town hack"],
    ["git-town append feature/x", "git-town append"],
    ["git-town prepend feature/x", "git-town prepend"],
    ["gh pr checkout 123", "gh pr checkout"],
    ["cd /tmp && git checkout -b feature/x", "chained &&"],
    ["FOO=bar git checkout -b x", "leading env assignment"],
  ];
  for (const [cmd, label] of blocked) {
    it(`blocks: ${label}`, () => {
      expect(classifyBranchCreation(cmd).blocked).toBe(true);
    });
  }
});

describe("classifyBranchCreation — ALLOW", () => {
  const allowed: Array<[string, string]> = [
    ["git worktree add ../wt -b feature/x", "worktree add -b (sanctioned)"],
    ["git worktree add ../wt", "worktree add (no branch)"],
    ["git checkout main", "switch to existing branch"],
    ["git checkout -- file.txt", "restore file"],
    ["git checkout .", "restore all"],
    ["git switch main", "switch to existing"],
    ["git branch", "bare list"],
    ["git branch -d oldfeat", "delete"],
    ["git branch -D oldfeat", "force delete"],
    ["git branch -m old new", "rename"],
    ["git branch --show-current", "info"],
    ["git branch -a", "list all"],
    ["git branch --list 'feat/*'", "list glob"],
    ["git branch --set-upstream-to=origin/main", "config upstream"],
    ["git status", "status"],
    ["git log --oneline", "log"],
    ["git town sync", "non-create git-town subcommand"],
    ["git-town sync", "non-create git-town"],
    ["gh pr view 123", "gh non-checkout"],
    ["ls -la", "non-git command"],
  ];
  for (const [cmd, label] of allowed) {
    it(`allows: ${label}`, () => {
      expect(classifyBranchCreation(cmd).blocked).toBe(false);
    });
  }
});

// ============================================================================
// Layer 2: full hook (stdin → JSON decision)
// ============================================================================

describe("hook — deny", () => {
  it("denies git checkout -b", () => expectDeny(runHook("git checkout -b feature/x")));
  it("denies git switch -c", () => expectDeny(runHook("git switch -c feature/x")));
  it("denies git branch <new>", () => expectDeny(runHook("git branch newfeat")));
  it("denies git -C ... checkout -b", () => expectDeny(runHook("git -C /repo checkout -b f")));
  it("denies git town hack", () => expectDeny(runHook("git town hack f")));
  it("denies git-town append", () => expectDeny(runHook("git-town append f")));
  it("denies gh pr checkout", () => expectDeny(runHook("gh pr checkout 123")));
  it("denies chained create", () => expectDeny(runHook("cd /tmp && git checkout -b f")));
});

describe("hook — allow", () => {
  it("allows git worktree add -b", () => expectAllow(runHook("git worktree add ../wt -b feature/x")));
  it("allows git worktree add", () => expectAllow(runHook("git worktree add ../wt")));
  it("allows checkout existing branch", () => expectAllow(runHook("git checkout main")));
  it("allows checkout -- file", () => expectAllow(runHook("git checkout -- file.txt")));
  it("allows switch existing", () => expectAllow(runHook("git switch main")));
  it("allows branch list", () => expectAllow(runHook("git branch")));
  it("allows branch delete", () => expectAllow(runHook("git branch -d old")));
  it("allows branch rename", () => expectAllow(runHook("git branch -m old new")));
  it("allows status", () => expectAllow(runHook("git status")));
  it("allows non-git command", () => expectAllow(runHook("ls -la")));
});

describe("hook — exceptions & escape hatches", () => {
  it("allows echo mentioning checkout -b", () =>
    expectAllow(runHook('echo "use git checkout -b x"')));
  it("allows comment line", () => expectAllow(runHook("# git checkout -b x")));
  it("allows commit message mentioning checkout -b", () =>
    expectAllow(runHook('git commit -m "document git checkout -b usage"')));
  it("allows env-var escape hatch", () =>
    expectAllow(runHook("ALLOW_BARE_BRANCH=1 git checkout -b f")));
  it("allows non-Bash tool", () => expectAllow(runHook("git checkout -b f", "Write")));
});
