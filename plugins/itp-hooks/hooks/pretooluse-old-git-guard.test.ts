/**
 * Tests for pretooluse-old-git-guard and its detector.
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-old-git-guard.test.ts
 *
 * Two layers:
 *   1. The pure detector with a stubbed resolver (no subprocess).
 *   2. The real hook over stdin/stdout, with stub `git` binaries on PATH that report a chosen
 *      version, so the verdict does not depend on which git this machine has.
 */

import { afterAll, describe, expect, it } from "bun:test";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  GIT_CONFIG_HOOKS_MIN_VERSION,
  type GitResolver,
  findHookFiringGitInvocations,
  findOldGitInvocations,
  gitSubcommand,
  parseGitVersion,
} from "./lib/old-git-detector.ts";

const HOOK_PATH = join(import.meta.dir, "pretooluse-old-git-guard.ts");
const SESSIONSTART_PATH = join(import.meta.dir, "sessionstart-git-version-check.sh");

// ============================================================================
// Layer 1: detector
// ============================================================================

function stubResolver(onPath: string | undefined, versions: Record<string, string>): GitResolver {
  return { whichGit: () => onPath, versionOf: (p) => versions[p] };
}

const OLD = "git version 2.50.1 (Apple Git-155)";
const NEW = "git version 2.56.0";

describe("gitSubcommand", () => {
  it.each([
    [["commit", "-m", "x"], "commit"],
    [["-C", "repo", "commit"], "commit"],
    [["-c", "user.name=x", "push"], "push"],
    [["--git-dir=/r/.git", "rebase"], "rebase"],
    [["--no-pager", "-C", "x", "log"], "log"],
    [["--version"], undefined],
  ])("%p → %p", (args, sub) => {
    expect(gitSubcommand(args as string[])).toBe(sub as string | undefined);
  });
});

describe("findHookFiringGitInvocations", () => {
  it.each([
    "git commit -m x",
    "/usr/bin/git commit -m x",
    "git -C some/dir commit -m x",
    "git push origin main",
    "git merge feature",
    "git rebase origin/main",
    "git cherry-pick abc123",
    "git am < patch.mbox",
    "cd repo && git commit -am x",
    "sudo -u bob git push",
    "env FOO=1 git commit -m x",
    "bash -c 'git commit -m x'",
  ])("finds %p", (cmd) => {
    expect(findHookFiringGitInvocations(cmd).length).toBe(1);
  });

  it.each([
    "git status",
    "git log --oneline -5",
    "git diff HEAD~1",
    "git fetch origin",
    "git show HEAD",
    "/usr/bin/git status",
    "git -C x log",
    "echo 'git commit -m x'",
    "# git commit",
    "grep -rn 'git push' docs/",
    "ssh host 'git commit -m x'",
    "gh pr create --title 'git commit fix'",
    "git commit-tree abc",
  ])("ignores %p", (cmd) => {
    expect(findHookFiringGitInvocations(cmd)).toEqual([]);
  });
});

describe("findOldGitInvocations", () => {
  it("blocks an explicit /usr/bin/git commit that reports 2.50", () => {
    const r = stubResolver("/opt/homebrew/bin/git", { "/usr/bin/git": OLD, "/opt/homebrew/bin/git": NEW });
    const f = findOldGitInvocations("/usr/bin/git commit -m x", r);
    expect(f.length).toBe(1);
    expect(f[0].explicitPath).toBe(true);
    expect(f[0].resolved.path).toBe("/usr/bin/git");
  });
  it("allows plain git when the git on PATH is >= 2.54", () => {
    const r = stubResolver("/opt/homebrew/bin/git", { "/opt/homebrew/bin/git": NEW });
    expect(findOldGitInvocations("git commit -m x", r)).toEqual([]);
  });
  it("blocks plain git when the git on PATH is 2.50", () => {
    const r = stubResolver("/usr/bin/git", { "/usr/bin/git": OLD });
    const f = findOldGitInvocations("git -C repo commit -m x", r);
    expect(f.length).toBe(1);
    expect(f[0].explicitPath).toBe(false);
  });
  it("fails open when the version cannot be read", () => {
    expect(findOldGitInvocations("git commit -m x", stubResolver("/x/git", {}))).toEqual([]);
    expect(findOldGitInvocations("git commit -m x", stubResolver(undefined, {}))).toEqual([]);
  });
  it("does not probe for read-only commands", () => {
    let probed = false;
    const r: GitResolver = { whichGit: () => "/usr/bin/git", versionOf: () => {
        probed = true;
        return OLD;
      },
    };
    expect(findOldGitInvocations("git status && git log", r)).toEqual([]);
    expect(probed).toBe(false);
  });
});

describe("parseGitVersion", () => {
  it("parses Apple and Homebrew forms", () => {
    expect(parseGitVersion(OLD)).toEqual([2, 50]);
    expect(parseGitVersion(NEW)).toEqual([2, 56]);
    expect(parseGitVersion("nonsense")).toBeUndefined();
  });
});

// ============================================================================
// Layer 2: the real hook with stub git binaries
// ============================================================================

const scratch = mkdtempSync(join(tmpdir(), "old-git-guard-test-"));
afterAll(() => rmSync(scratch, { recursive: true, force: true }));

function stubGitDir(name: string, versionLine: string): string {
  const dir = join(scratch, name);
  mkdirSync(dir, { recursive: true });
  const bin = join(dir, "git");
  writeFileSync(bin, `#!/bin/sh\necho '${versionLine}'\n`);
  chmodSync(bin, 0o755);
  return dir;
}

const OLD_DIR = stubGitDir("old", OLD);
const NEW_DIR = stubGitDir("new", NEW);

let sessionCounter = 0;

async function runHook(command: string, pathDirs: string[], toolName = "Bash") {
  const proc = Bun.spawn([process.execPath, HOOK_PATH], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, PATH: [...pathDirs, "/bin"].join(":") },
  });
  proc.stdin.write(
    JSON.stringify({ tool_name: toolName, tool_input: { command }, session_id: `old-git-test-${process.pid}-${sessionCounter++}` }),
  );
  await proc.stdin.end();
  const stdout = await new Response(proc.stdout).text();
  await proc.exited;
  const out = JSON.parse(stdout).hookSpecificOutput;
  return { decision: out.permissionDecision as string, reason: (out.permissionDecisionReason ?? "") as string };
}

describe("hook — real stdin/stdout", () => {
  it("blocks an explicit path to an old git, naming reason and fix", async () => {
    const r = await runHook(`${OLD_DIR}/git commit -m x`, [NEW_DIR]);
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("[OLD-GIT GUARD]");
    expect(r.reason).toContain("git >= 2.54");
    expect(r.reason).toContain("/opt/homebrew/bin/git");
    expect(r.reason).toContain("named explicitly");
  });

  it("allows plain git commit when the git on PATH is 2.56", async () => {
    expect((await runHook("git commit -m x", [NEW_DIR])).decision).toBe("allow");
  });

  it("blocks plain git commit when the git on PATH reports 2.50", async () => {
    const r = await runHook("git commit -m x", [OLD_DIR]);
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("first on PATH");
  });

  it("handles git -C <dir> commit", async () => {
    expect((await runHook("git -C some/repo commit -m x", [OLD_DIR])).decision).toBe("deny");
    expect((await runHook("git -C some/repo commit -m x", [NEW_DIR])).decision).toBe("allow");
  });

  it.each(["git status", "git log -3", "git diff", "git fetch", "git show HEAD"])(
    "allows read-only %p even with an old git",
    async (cmd) => {
      expect((await runHook(cmd, [OLD_DIR])).decision).toBe("allow");
    },
  );

  it("honours OLD-GIT-OK with a reason, and refuses a bare marker", async () => {
    const ok = await runHook("git commit -m x # OLD-GIT-OK: scratch repo with no gates", [OLD_DIR]);
    expect(ok.decision).toBe("allow");
    const bare = await runHook("git commit -m x # OLD-GIT-OK", [OLD_DIR]);
    expect(bare.decision).toBe("deny");
  });

  it("ignores non-Bash tools", async () => {
    expect((await runHook("git commit", [OLD_DIR], "Write")).decision).toBe("allow");
  });

  it.skipIf(process.platform !== "darwin" || !parseGitVersion(Bun.spawnSync(["/usr/bin/git", "--version"]).stdout.toString()))(
    "blocks /usr/bin/git commit on this Mac when Apple's git is below the floor",
    async () => {
      const v = parseGitVersion(Bun.spawnSync(["/usr/bin/git", "--version"]).stdout.toString())!;
      const below = v[0] < 2 || (v[0] === 2 && v[1] < 54);
      const r = await runHook("/usr/bin/git commit -m x", [NEW_DIR]);
      expect(r.decision).toBe(below ? "deny" : "allow");
    },
  );
});

// ============================================================================
// SessionStart companion
// ============================================================================

function runSessionStart(pathDirs: string[]): string {
  const r = Bun.spawnSync(["/bin/bash", SESSIONSTART_PATH], {
    env: { ...process.env, PATH: [...pathDirs, "/bin", "/usr/bin"].join(":") },
    stdout: "pipe",
  });
  expect(r.exitCode).toBe(0);
  return r.stdout.toString();
}

describe("sessionstart-git-version-check.sh", () => {
  it("warns when the git first on PATH is below the floor", () => {
    const out = runSessionStart([OLD_DIR]);
    expect(out).toContain("older than 2.54");
    expect(out).toContain("/opt/homebrew/bin/git");
  });
  it("is silent when the git first on PATH is new enough", () => {
    expect(runSessionStart([NEW_DIR])).toBe("");
  });
  it("uses the same floor as the detector", () => {
    const sh = readFileSync(SESSIONSTART_PATH, "utf8");
    expect(sh).toContain(`MIN_MAJOR=${GIT_CONFIG_HOOKS_MIN_VERSION[0]}`);
    expect(sh).toContain(`MIN_MINOR=${GIT_CONFIG_HOOKS_MIN_VERSION[1]}`);
  });
});
