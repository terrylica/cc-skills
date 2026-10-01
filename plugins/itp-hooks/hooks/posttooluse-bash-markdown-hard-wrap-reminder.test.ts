import { describe, expect, it } from "bun:test";
import { mkdtempSync, realpathSync, utimesSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import {
  buildBashMarkdownHardWrapReminder,
  candidateMarkdownFiles,
  commandDirectories,
  evaluateCandidates,
  markdownPathsMentioned,
} from "./posttooluse-bash-markdown-hard-wrap-reminder.ts";

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

/**
 * A throwaway repo OUTSIDE the temp-dir scratch exclusion would be ideal, but every writable test
 * location is under the OS temp dir, which the hook deliberately skips. So candidate discovery is
 * tested through its parts, and evaluation through evaluateCandidates, which applies no path filter.
 */
function repo(files: Record<string, string> = {}): string {
  const dir = realpathSync(mkdtempSync(join(tmpdir(), "md-bash-watch-")));
  git(dir, "init", "-q", "-b", "main");
  git(dir, "config", "user.email", "t@example.com");
  git(dir, "config", "user.name", "t");
  writeFileSync(join(dir, "seed.txt"), "x");
  for (const [p, c] of Object.entries(files)) writeFileSync(join(dir, p), c);
  git(dir, "add", "-A");
  git(dir, "commit", "-q", "-m", "seed");
  return dir;
}

describe("markdownPathsMentioned", () => {
  it("finds quoted, unquoted, redirected and home-relative .md paths", () => {
    const cmd = `cat > docs/a.md <<'EOF'\nx\nEOF\npython3 fix.py "~/notes/b.markdown" ../c.md && echo done`;
    expect(markdownPathsMentioned(cmd).toSorted()).toEqual(["../c.md", "docs/a.md", "~/notes/b.markdown"].toSorted());
  });

  it("finds nothing in a command that names no Markdown", () => {
    expect(markdownPathsMentioned("bun test && git status")).toEqual([]);
  });
});

describe("commandDirectories", () => {
  it("includes the cwd, every cd target and git -C", () => {
    expect(commandDirectories("cd /a && cd b && git -C c status", "/x")).toEqual(["/x", "/a", "/a/b", "/a/b/c"]);
  });

  it("expands ~", () => {
    expect(commandDirectories("cd ~/proj", "/x")).toContain(join(homedir(), "proj"));
  });
});

describe("evaluateCandidates", () => {
  it("REPORTS a wrap a shell command added to a tracked file", () => {
    const dir = repo({ "doc.md": UNWRAPPED });
    writeFileSync(join(dir, "doc.md"), `${UNWRAPPED}\n${OTHER_WRAPPED}`);
    const { reports } = evaluateCandidates([join(dir, "doc.md")], {});
    expect(reports).toHaveLength(1);
    expect(reports[0].wraps).toHaveLength(1);
  });

  it("REPORTS every wrap in a new untracked file", () => {
    const dir = repo();
    writeFileSync(join(dir, "new.md"), WRAPPED);
    expect(evaluateCandidates([join(dir, "new.md")], {}).reports).toHaveLength(1);
  });

  it("is SILENT when the command left legacy wraps as they were", () => {
    const dir = repo({ "old.md": WRAPPED });
    writeFileSync(join(dir, "old.md"), `# Heading\n\n${WRAPPED}`);
    expect(evaluateCandidates([join(dir, "old.md")], {}).reports).toEqual([]);
  });

  it("is SILENT for one-line-per-paragraph prose", () => {
    const dir = repo();
    writeFileSync(join(dir, "new.md"), UNWRAPPED);
    expect(evaluateCandidates([join(dir, "new.md")], {}).reports).toEqual([]);
  });

  it("judges each content once: the second call with the returned cache is silent", () => {
    const dir = repo();
    writeFileSync(join(dir, "new.md"), WRAPPED);
    const first = evaluateCandidates([join(dir, "new.md")], {});
    expect(first.reports).toHaveLength(1);
    expect(evaluateCandidates([join(dir, "new.md")], first.judged).reports).toEqual([]);
    // …until the content changes again
    writeFileSync(join(dir, "new.md"), `${WRAPPED}\n${OTHER_WRAPPED}`);
    expect(evaluateCandidates([join(dir, "new.md")], first.judged).reports).toHaveLength(1);
  });

  it("honours the per-file HTML-comment escape", () => {
    const dir = repo();
    writeFileSync(join(dir, "v.md"), `<!-- MD-HARD-WRAP-OK: verse -->\n\n${WRAPPED}`);
    expect(evaluateCandidates([join(dir, "v.md")], {}).reports).toEqual([]);
  });
});

describe("candidateMarkdownFiles", () => {
  it("skips files in the temp scratch area and files not modified recently", () => {
    const dir = repo();
    const p = join(dir, "new.md");
    writeFileSync(p, WRAPPED);
    // Under the OS temp dir: excluded as scratch, by design.
    expect(candidateMarkdownFiles(`cat > ${p}`, dir)).toEqual([]);
    const old = (Date.now() - 60 * 60 * 1000) / 1000;
    utimesSync(p, old, old);
    expect(candidateMarkdownFiles(`cat > ${p}`, dir, Date.now())).toEqual([]);
  });
});

describe("buildBashMarkdownHardWrapReminder", () => {
  it("names the file and the repair tool", () => {
    const dir = repo();
    writeFileSync(join(dir, "new.md"), WRAPPED);
    const { reports } = evaluateCandidates([join(dir, "new.md")], {});
    const msg = buildBashMarkdownHardWrapReminder(reports);
    expect(msg).toContain("new.md");
    expect(msg).toContain("scripts/gfm-unwrap.ts");
  });
});
