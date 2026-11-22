// SECRET-SCAN-OK: synthetic fixtures for the secret-detection guard under test; no value here
// was ever issued by any provider. Each is hand-built to match a shape and nothing more.

import { describe, expect, test } from "bun:test";
import {
  explainPiiFindings,
  findPiiFindings,
  isPublishingPush,
} from "./pretooluse-pii-push-gate.ts";

const labels = (lines: string[], vis: "PUBLIC" | "PRIVATE" | "UNKNOWN") =>
  findPiiFindings(lines, vis).map((f) => f.label);

describe("secrets block regardless of visibility", () => {
  // The whole point of separating severities: a private repo is a legitimate home for
  // identity detail and never a legitimate home for a live credential.
  const cases: Array<[string, string]> = [
    ["GitHub token", "token = ghp_SYNTHETICfixtureNOTAREALtoken12345"],
    ["OpenAI-style key", 'OPENAI_KEY="sk-SYNTHETICfixtureNOTAREALkey1234"'],
    ["AWS access key id", "aws_access_key_id = AKIASYNTHETICNOTREAL"],
    ["Slack token", "SLACK=xoxb-000SYNTHETIC-fixtureNOTAREAL"],
    [
      "Telegram bot token",
      "BOT=1234567890:AAsynthetic_fixture_value_never_issued_x",
    ],
    ["private key block", "-----BEGIN OPENSSH PRIVATE KEY-----"],
  ];

  for (const [label, line] of cases) {
    test(`${label} blocks in a PRIVATE repo`, () => {
      expect(labels([line], "PRIVATE")).toContain(label);
    });
  }
});

describe("identity detail is visibility-dependent", () => {
  const identityLines = [
    "cd /Users/someone/projects/thing",
    "contact: person@example.org",
    "ssh 100.101.102.103",
    "router at 192.168.1.1",
  ];

  test("blocks when the repo is PUBLIC", () => {
    expect(findPiiFindings(identityLines, "PUBLIC").length).toBeGreaterThan(0);
  });

  // Measured 2026-09-20: applying the public policy to a private sole-owner repo produced
  // six DO-NOT-PUSH findings on content that repo exists to store.
  test("passes when the repo is PRIVATE", () => {
    expect(findPiiFindings(identityLines, "PRIVATE")).toEqual([]);
  });

  // An unknown-visibility repo scanned under the private policy would pass identity detail
  // silently, and the failure would only surface once published.
  test("UNKNOWN is treated as PUBLIC, not as PRIVATE", () => {
    expect(findPiiFindings(identityLines, "UNKNOWN").length).toBeGreaterThan(0);
  });
});

describe("placeholders are not findings", () => {
  // A gate that fires on its own documentation teaches people to reach for the escape hatch
  // by reflex, which is strictly worse than having no gate.
  test("documentation-shaped values pass", () => {
    const docs = [
      'password: "your-password-here"',
      "api_key = <YOUR_API_KEY>",
      // Escaped inside a template literal on purpose: the two characters "${" ARE the
      // fixture, and in a plain string a linter reads them as a mistyped placeholder.
      `token: "\${GITHUB_TOKEN}"`,
      "secret = changeme12345",
      "access_token: EXAMPLE_TOKEN_VALUE",
    ];
    expect(
      findPiiFindings(docs, "PUBLIC").filter((f) => f.severity === "secret"),
    ).toEqual([]);
  });

  test("but a real-looking assignment still blocks", () => {
    expect(labels(['password: "Tr0ub4dor&3xKcd9uPPer"'], "PUBLIC")).toContain(
      "credential assignment",
    );
  });

  test("the word alone in prose is not a finding", () => {
    expect(findPiiFindings(["the password is rotated quarterly"], "PUBLIC")).toEqual([]);
  });
});

describe("push detection", () => {
  test("recognises a plain push", () => {
    expect(isPublishingPush("git push origin main")).toBe(true);
    expect(isPublishingPush("git push --force-with-lease")).toBe(true);
    expect(isPublishingPush("git -C /repo push")).toBe(true);
  });

  // --dry-run publishes nothing; blocking it would block the safest way to inspect a push.
  test("ignores a dry run", () => {
    expect(isPublishingPush("git push --dry-run origin main")).toBe(false);
  });

  test("ignores non-push git commands", () => {
    expect(isPublishingPush("git status")).toBe(false);
    expect(isPublishingPush("git log --oneline")).toBe(false);
  });

  // Documented rather than fixed: the detector reads a command string, so a push named
  // inside an echo is indistinguishable from one being run. It errs toward scanning,
  // which costs a diff read and never costs a leak.
  test("a mention inside a string is treated as a push (accepted over-match)", () => {
    expect(isPublishingPush("echo 'remember to git push later'")).toBe(true);
  });
});

describe("reporting", () => {
  test("one finding per label, so a large diff stays readable", () => {
    const many = Array.from({ length: 500 }, (_, i) => `/Users/someone/file${i}`);
    expect(findPiiFindings(many, "PUBLIC")).toHaveLength(1);
  });

  test("secrets are ordered before identity detail", () => {
    const mixed = [
      "/Users/someone/x",
      "token = ghp_SYNTHETICfixtureNOTAREALtoken12345",
    ];
    expect(findPiiFindings(mixed, "PUBLIC")[0]?.severity).toBe("secret");
  });

  test("explanation names the escape hatch and the rotation duty", () => {
    const text = explainPiiFindings(
      findPiiFindings(["token = ghp_SYNTHETICfixtureNOTAREALtoken12345"], "PUBLIC"),
      "PUBLIC",
    );
    expect(text).toContain("PII-GATE-OK");
    expect(text).toContain("Rotate the credential FIRST");
  });

  test("explanation tells a private repo how to stop being asked", () => {
    const text = explainPiiFindings(
      findPiiFindings(["/Users/someone/x"], "UNKNOWN"),
      "UNKNOWN",
    );
    expect(text).toContain("claude-pii-visibility");
    // The reason `gh` is not simply called by the hook must travel with the advice,
    // or the next maintainer will "simplify" it back into the hook.
    expect(text).toContain("process storms");
  });
});

describe("empty and irrelevant input", () => {
  test("no added lines yields no findings", () => {
    expect(findPiiFindings([], "PUBLIC")).toEqual([]);
  });

  test("ordinary code yields no findings", () => {
    expect(
      findPiiFindings(
        ["export function add(a: number, b: number) { return a + b }"],
        "PUBLIC",
      ),
    ).toEqual([]);
  });
});

// ── What a push publishes: measured on real repositories ──────────────────────────────────────
// Each case builds a throwaway repository with a bare "origin", so the range is the one git itself
// resolves. Values are synthetic markers, not personal detail.
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach } from "bun:test";
import { addedLinesOfPatchLog, pushedAddedLines } from "./pretooluse-pii-push-gate.ts";

const scratch: string[] = [];
afterEach(() => {
  for (const d of scratch.splice(0)) rmSync(d, { recursive: true, force: true });
});

function repoWithOrigin(): { dir: string; git: (...args: string[]) => string } {
  const root = mkdtempSync(join(tmpdir(), "pii-range-"));
  scratch.push(root);
  const dir = join(root, "work");
  const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
  const run = (cwd: string, args: string[]) => {
    const r = spawnSync("git", ["-c", "core.hooksPath=/dev/null", "-c", "user.email=t@example.invalid", "-c", "user.name=t", ...args], { cwd, env, encoding: "utf8" });
    if (r.status !== 0) throw new Error(`git ${args.join(" ")}: ${r.stderr}`);
    return r.stdout.trim();
  };
  run(root, ["init", "-q", "--bare", "origin.git"]);
  run(root, ["init", "-q", "-b", "main", "work"]);
  run(dir, ["remote", "add", "origin", join(root, "origin.git")]);
  const git = (...args: string[]) => run(dir, args);
  return { dir, git };
}
const write = (dir: string, file: string, text: string) => writeFileSync(join(dir, file), text);

describe("pushedAddedLines measures what the push newly publishes", () => {
  test("a file main deleted after the branch point is not reported as added", () => {
    const { dir, git } = repoWithOrigin();
    write(dir, "old.txt", "MARK-DELETED-ON-MAIN\n");
    git("add", "."), git("commit", "-qm", "base"), git("push", "-q", "origin", "main");
    git("checkout", "-q", "-b", "feat", "--track", "origin/main");
    git("checkout", "-q", "main"), git("rm", "-q", "old.txt"), git("commit", "-qm", "drop"), git("push", "-q", "origin", "main");
    git("checkout", "-q", "feat"), write(dir, "new.txt", "MARK-BRANCH-LINE\n"), git("add", "."), git("commit", "-qm", "feat");
    git("fetch", "-q", "origin");
    expect(pushedAddedLines(dir)).toEqual(["MARK-BRANCH-LINE"]);
  });

  test("merging a published main reports only the branch's own lines and the resolution", () => {
    const { dir, git } = repoWithOrigin();
    write(dir, "a.txt", "base\n");
    git("add", "."), git("commit", "-qm", "base"), git("push", "-q", "origin", "main");
    git("checkout", "-q", "-b", "feat"), write(dir, "a.txt", "MARK-OURS\n"), git("commit", "-qam", "ours"), git("push", "-q", "-u", "origin", "feat");
    git("checkout", "-q", "main"), write(dir, "a.txt", "MARK-THEIRS\n"), write(dir, "m.txt", "MARK-MAIN-ONLY\n");
    git("add", "."), git("commit", "-qm", "theirs"), git("push", "-q", "origin", "main");
    git("checkout", "-q", "feat");
    spawnSync("git", ["-c", "core.hooksPath=/dev/null", "merge", "-q", "main"], { cwd: dir, encoding: "utf8" }); // conflicts
    write(dir, "a.txt", "MARK-RESOLVED\n");
    git("add", "."), git("commit", "-qm", "merge main");
    expect(pushedAddedLines(dir)).toEqual(["MARK-RESOLVED"]);
  });

  test("a value added and removed again inside the push range is still reported", () => {
    const { dir, git } = repoWithOrigin();
    write(dir, "a.txt", "base\n");
    git("add", "."), git("commit", "-qm", "base"), git("push", "-q", "-u", "origin", "main");
    write(dir, "a.txt", "MARK-TRANSIENT\n"), git("commit", "-qam", "add");
    write(dir, "a.txt", "base\n"), git("commit", "-qam", "revert");
    expect(pushedAddedLines(dir)).toContain("MARK-TRANSIENT");
  });

  test("with no remote there is nothing to measure against", () => {
    const { dir, git } = repoWithOrigin();
    git("remote", "remove", "origin");
    expect(pushedAddedLines(dir)).toBeNull();
  });
});

describe("addedLinesOfPatchLog", () => {
  test("a combined diff keeps only lines new against every parent", () => {
    const patch = ["diff --cc a.txt", "--- a/a.txt", "+++ b/a.txt", "@@@ -1,1 -1,1 +1,1 @@@", "+ from-ours", " +from-theirs", "++resolved", "++++ starts-with-plus"].join("\n");
    expect(addedLinesOfPatchLog(patch)).toEqual(["resolved", "++ starts-with-plus"]);
  });
  test("a file header's +++ line is not content, a hunk line starting +++ is", () => {
    const patch = ["diff --git a/x b/x", "--- a/x", "+++ b/x", "@@ -0,0 +1,2 @@", "+one", "+++two"].join("\n");
    expect(addedLinesOfPatchLog(patch)).toEqual(["one", "++two"]);
  });
});
