import { describe, expect, it } from "bun:test";
import { mkdirSync, mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  buildCommitHardWrapDenial,
  evaluateGitCommit,
  findGitCommitInvocations,
  parseNameStatusZ,
} from "./pretooluse-markdown-commit-hard-wrap-guard.ts";
import { netNewMarkdownHardWraps, readGitBlobs } from "./lib/markdown-net-new-hard-wraps.ts";

const WRAPPED = [
  "The orchestrator aggregates every context-injecting subhook into one Bun process so",
  "the per-edit cold-start cost is paid once instead of fifteen separate times.",
  "",
].join("\n");
const UNWRAPPED =
  "The orchestrator aggregates every context-injecting subhook into one Bun process so the per-edit cold-start cost is paid once instead of fifteen separate times.\n";
const OTHER_WRAPPED = [
  "A second paragraph that somebody wrapped by hand at roughly eighty-five columns wide,",
  "so that its continuation lands on a separate line and the renderer cannot reflow it.",
  "",
].join("\n");

function git(cwd: string, ...args: string[]): void {
  const p = Bun.spawnSync(["git", ...args], { cwd, stdout: "pipe", stderr: "pipe" });
  if (p.exitCode !== 0) throw new Error(`git ${args.join(" ")}: ${p.stderr.toString()}`);
}

function repo(files: Record<string, string> = {}): string {
  const dir = realpathSync(mkdtempSync(join(tmpdir(), "md-commit-guard-")));
  git(dir, "init", "-q", "-b", "main");
  git(dir, "config", "user.email", "t@example.com");
  git(dir, "config", "user.name", "t");
  writeFileSync(join(dir, "seed.txt"), "x");
  for (const [p, c] of Object.entries(files)) writeFileSync(join(dir, p), c);
  git(dir, "add", "-A");
  git(dir, "commit", "-q", "-m", "seed");
  return dir;
}

describe("findGitCommitInvocations", () => {
  it("follows cd and git -C, and reads -a out of a cluster", () => {
    const inv = findGitCommitInvocations("cd /a/b && git -C sub commit -am 'msg' && git status", "/x");
    expect(inv).toEqual([{ dir: "/a/b/sub", all: true, pathspecs: [] }]);
  });

  it("does not take the -m value or an -a inside the message as flags or paths", () => {
    const inv = findGitCommitInvocations(`git commit -m "fix -a thing" docs/x.md`, "/r");
    expect(inv).toEqual([{ dir: "/r", all: false, pathspecs: ["docs/x.md"] }]);
  });

  it("ignores a commit that is only MENTIONED (quoted text, a grep)", () => {
    expect(findGitCommitInvocations(`grep -n "git commit" notes.txt`, "/r")).toEqual([]);
    expect(findGitCommitInvocations("echo 'run git commit later'", "/r")).toEqual([]);
  });

  it("finds a commit inside bash -c", () => {
    expect(findGitCommitInvocations(`bash -c 'git commit -q -m x'`, "/r")).toHaveLength(1);
  });
});

describe("parseNameStatusZ", () => {
  it("keeps added/modified/renamed Markdown and drops deletions and non-Markdown", () => {
    const out = ["M", "a.md", "A", "b.MD", "D", "c.md", "M", "x.ts", "R087", "old.md", "new.md", ""].join("\0");
    expect(parseNameStatusZ(out)).toEqual([
      { beforePath: "a.md", path: "a.md" },
      { beforePath: null, path: "b.MD" },
      { beforePath: "old.md", path: "new.md" },
    ]);
  });
});

describe("evaluateGitCommit — the index against HEAD", () => {
  it("DENIES a staged new file containing a hard wrap", () => {
    const dir = repo();
    writeFileSync(join(dir, "new.md"), WRAPPED);
    git(dir, "add", "new.md");
    const { reports } = evaluateGitCommit({ dir, all: false, pathspecs: [] });
    expect(reports.map((r) => r.path)).toEqual(["new.md"]);
  });

  it("ALLOWS a staged file written as one line per paragraph", () => {
    const dir = repo();
    writeFileSync(join(dir, "new.md"), UNWRAPPED);
    git(dir, "add", "new.md");
    expect(evaluateGitCommit({ dir, all: false, pathspecs: [] }).reports).toEqual([]);
  });

  it("ALLOWS a change that leaves legacy wraps exactly as they were (net-new only)", () => {
    const dir = repo({ "old.md": WRAPPED });
    writeFileSync(join(dir, "old.md"), `# Title\n\n${WRAPPED}`);
    git(dir, "add", "old.md");
    expect(evaluateGitCommit({ dir, all: false, pathspecs: [] }).reports).toEqual([]);
  });

  it("DENIES a wrap added next to a legacy one, and reports only the new one", () => {
    const dir = repo({ "old.md": WRAPPED });
    writeFileSync(join(dir, "old.md"), `${WRAPPED}\n${OTHER_WRAPPED}`);
    git(dir, "add", "old.md");
    const { reports } = evaluateGitCommit({ dir, all: false, pathspecs: [] });
    expect(reports).toHaveLength(1);
    expect(reports[0].wraps).toHaveLength(1);
    expect(reports[0].wraps[0].nextPreview).toContain("so that its continuation");
  });

  it("checks what is STAGED, not the working tree", () => {
    const dir = repo();
    writeFileSync(join(dir, "doc.md"), UNWRAPPED);
    git(dir, "add", "doc.md");
    writeFileSync(join(dir, "doc.md"), WRAPPED); // unstaged, not part of this commit
    expect(evaluateGitCommit({ dir, all: false, pathspecs: [] }).reports).toEqual([]);
  });

  it("honours the per-file HTML-comment escape", () => {
    const dir = repo();
    writeFileSync(join(dir, "poem.md"), `<!-- MD-HARD-WRAP-OK: verse -->\n\n${WRAPPED}`);
    git(dir, "add", "poem.md");
    expect(evaluateGitCommit({ dir, all: false, pathspecs: [] }).reports).toEqual([]);
  });

  it("works from a subdirectory and on the first commit of a repo", () => {
    const dir = realpathSync(mkdtempSync(join(tmpdir(), "md-commit-guard-empty-")));
    git(dir, "init", "-q", "-b", "main");
    mkdirSync(join(dir, "docs"));
    writeFileSync(join(dir, "docs", "a.md"), WRAPPED);
    git(dir, "add", "docs/a.md");
    const { reports } = evaluateGitCommit({ dir: join(dir, "docs"), all: false, pathspecs: [] });
    expect(reports.map((r) => r.path)).toEqual(["docs/a.md"]);
  });

  it("is silent outside a repository", () => {
    const dir = mkdtempSync(join(tmpdir(), "md-commit-guard-norepo-"));
    expect(evaluateGitCommit({ dir, all: false, pathspecs: [] }).reports).toEqual([]);
  });
});

describe("evaluateGitCommit — -a and pathspecs read the working tree", () => {
  it("-a DENIES an unstaged tracked change that adds a wrap", () => {
    const dir = repo({ "doc.md": UNWRAPPED });
    writeFileSync(join(dir, "doc.md"), `${UNWRAPPED}\n${OTHER_WRAPPED}`);
    expect(evaluateGitCommit({ dir, all: true, pathspecs: [] }).reports).toHaveLength(1);
    expect(evaluateGitCommit({ dir, all: false, pathspecs: [] }).reports).toEqual([]);
  });

  it("a pathspec commit checks exactly the named paths", () => {
    const dir = repo({ "a.md": UNWRAPPED, "b.md": UNWRAPPED });
    writeFileSync(join(dir, "a.md"), OTHER_WRAPPED);
    writeFileSync(join(dir, "b.md"), OTHER_WRAPPED);
    const { reports } = evaluateGitCommit({ dir, all: false, pathspecs: ["b.md"] });
    expect(reports.map((r) => r.path)).toEqual(["b.md"]);
  });
});

describe("shared lib", () => {
  it("netNewMarkdownHardWraps: a new file counts every wrap; an unchanged one counts none", () => {
    expect(netNewMarkdownHardWraps(null, WRAPPED)).toHaveLength(1);
    expect(netNewMarkdownHardWraps(WRAPPED, WRAPPED)).toEqual([]);
  });

  it("readGitBlobs reads several blobs in one process and maps a missing one to null", () => {
    const dir = repo({ "a.md": "alpha\n", "b.md": "beta\n" });
    const blobs = readGitBlobs(dir, ["HEAD:a.md", "HEAD:nope.md", "HEAD:b.md"]);
    expect(blobs.get("HEAD:a.md")).toBe("alpha\n");
    expect(blobs.get("HEAD:nope.md")).toBeNull();
    expect(blobs.get("HEAD:b.md")).toBe("beta\n");
  });
});

describe("buildCommitHardWrapDenial", () => {
  it("names the file, the repair tool and both escapes", () => {
    const msg = buildCommitHardWrapDenial([{ path: "docs/a.md", wraps: netNewMarkdownHardWraps(null, WRAPPED) }], false);
    expect(msg).toContain("docs/a.md");
    expect(msg).toContain("scripts/gfm-unwrap.ts");
    expect(msg).toContain("<!-- MD-HARD-WRAP-OK: why -->");
  });
});

function runHook(command: string, cwd: string): string {
  const p = Bun.spawnSync(["bun", join(import.meta.dir, "pretooluse-markdown-commit-hard-wrap-guard.ts")], {
    stdin: Buffer.from(JSON.stringify({ tool_name: "Bash", tool_input: { command }, cwd })),
    stdout: "pipe",
  });
  return JSON.parse(p.stdout.toString()).hookSpecificOutput.permissionDecision as string;
}

describe("hook process end to end", () => {
  it("denies the wrapped commit, allows it with the command escape, allows a clean one", () => {
    const dir = repo();
    writeFileSync(join(dir, "n.md"), WRAPPED);
    git(dir, "add", "n.md");
    expect(runHook("git commit -m add", dir)).toBe("deny");
    expect(runHook("git commit -m 'add (MD-HARD-WRAP-OK: quoted verse)'", dir)).toBe("allow");
    expect(runHook("git status", dir)).toBe("allow");
  });
});
