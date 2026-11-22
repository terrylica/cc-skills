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

import { afterAll, describe, expect, it, setDefaultTimeout } from "bun:test";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  GIT_CONFIG_HOOKS_MIN_VERSION,
  type GitResolver,
  findHookFiringGitInvocations,
  findOldGitInvocations,
  gitSubcommand,
  parseConfigHooksProbe,
  parseGitVersion,
} from "./lib/old-git-detector.ts";
import { oldGitFix } from "./pretooluse-old-git-guard.ts";

// The stdin/stdout tests spawn the hook, which spawns a stub git. Under a loaded machine (2026-11-01, full suite)
// the hook's 2 s version probe timed out, the guard failed open and "deny" came back "allow"; the test passed alone.
// The hook's probe limit is raised for these runs only (ITP_OLD_GIT_PROBE_TIMEOUT_MS), and so is bun's test timeout.
setDefaultTimeout(30_000);

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

describe("config-based hooks decide whether an old git matters", () => {
  it("parses the git config probe: none, some, unknown", () => {
    expect(parseConfigHooksProbe(1, "")).toBe(false);
    expect(parseConfigHooksProbe(0, "hook.vocab.event pre-commit\n")).toBe(true);
    expect(parseConfigHooksProbe(0, "HOOK.Vocab.EVENT pre-commit\n")).toBe(true);
    expect(parseConfigHooksProbe(0, "git version 2.50.1\n")).toBeUndefined();
    expect(parseConfigHooksProbe(128, "")).toBeUndefined();
    expect(parseConfigHooksProbe(null, "")).toBeUndefined();
  });
  it("an old git with no config-based hook is allowed; unknown still counts", () => {
    const base = stubResolver("/usr/bin/git", { "/usr/bin/git": OLD });
    expect(findOldGitInvocations("git commit -m x", { ...base, configHooksDefined: () => false })).toEqual([]);
    expect(findOldGitInvocations("git commit -m x", { ...base, configHooksDefined: () => true }).length).toBe(1);
    expect(findOldGitInvocations("git commit -m x", { ...base, configHooksDefined: () => undefined }).length).toBe(1);
  });
  it("names Homebrew on macOS and a newer git package elsewhere", () => {
    expect(oldGitFix("2.54", "darwin")).toContain("/opt/homebrew/bin/git");
    expect(oldGitFix("2.54", "linux")).not.toContain("homebrew");
    expect(oldGitFix("2.54", "linux")).toContain("install git >= 2.54");
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

/** An old git that answers `git config --get-regexp` as a real one does: exit 1 with no key, or the key it holds. */
function stubOldGitWithConfig(name: string, hookLine: string | undefined): string {
  const dir = join(scratch, name);
  mkdirSync(dir, { recursive: true });
  const bin = join(dir, "git");
  const config = hookLine === undefined ? "exit 1" : `echo '${hookLine}'; exit 0`;
  writeFileSync(bin, `#!/bin/sh\nif [ "$1" = config ]; then ${config}; fi\necho '${OLD}'\n`);
  chmodSync(bin, 0o755);
  return dir;
}
const OLD_NO_HOOKS_DIR = stubOldGitWithConfig("old-no-hooks", undefined);
const OLD_WITH_HOOKS_DIR = stubOldGitWithConfig("old-with-hooks", "hook.vocab.event pre-commit");

let sessionCounter = 0;

async function runHook(command: string, pathDirs: string[], toolName = "Bash", cwd?: string) {
  const proc = Bun.spawn([process.execPath, HOOK_PATH], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, PATH: [...pathDirs, "/bin"].join(":"), ITP_OLD_GIT_PROBE_TIMEOUT_MS: "20000" },
  });
  proc.stdin.write(
    JSON.stringify({
      tool_name: toolName,
      tool_input: { command },
      session_id: `old-git-test-${process.pid}-${sessionCounter++}`,
      ...(cwd ? { cwd } : {}),
    }),
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
    expect(r.reason).toContain(oldGitFix("2.54"));
    expect(r.reason).toContain("named explicitly");
  });

  it("allows an old git when its config defines no config-based hook, and blocks it when one is defined", async () => {
    expect((await runHook("git commit -m x", [OLD_NO_HOOKS_DIR])).decision).toBe("allow");
    expect((await runHook("git push", [OLD_NO_HOOKS_DIR])).decision).toBe("allow");
    expect((await runHook("git commit -m x", [OLD_WITH_HOOKS_DIR])).decision).toBe("deny");
  });

  it.each(["git -C other commit -m x", "git --git-dir=other/.git commit -m x", "cd other && git commit -m x", "GIT_DIR=o/.git git commit -m x"])(
    "does not trust the cwd probe when git may run in another repository: %p",
    async (cmd) => {
      expect((await runHook(cmd, [OLD_NO_HOOKS_DIR])).decision).toBe("deny");
    },
  );

  it("keeps the deny when the hook's cwd no longer exists (a removed worktree)", async () => {
    const gone = join(scratch, "removed-worktree");
    expect((await runHook("git commit -m x", [OLD_NO_HOOKS_DIR], "Bash", gone)).decision).toBe("deny");
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
    expect(out).toContain(process.platform === "darwin" ? "/opt/homebrew/bin/git" : "Install git >= 2.54");
  });
  it("is silent for an old git whose config defines no config-based hook, and warns when one is defined", () => {
    expect(runSessionStart([OLD_NO_HOOKS_DIR])).toBe("");
    expect(runSessionStart([OLD_WITH_HOOKS_DIR])).toContain("older than 2.54");
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
