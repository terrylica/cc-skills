/**
 * Tests for pretooluse-release-notes-extensiveness-guard.ts
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-release-notes-extensiveness-guard.test.ts
 *
 * Two layers:
 *   1. Pure unit tests against the classifier / measurers (fast, no subprocess).
 *   2. Subprocess tests through the real hook (stdin/JSON/deny wiring, fast-path,
 *      escape hatch, semantic-release commit inspection against a temp repo).
 */

import { describe, expect, it } from "bun:test";
import { execSync } from "child_process";
import { join } from "path";
import {
  classifyReleaseCommand,
  measureNotesExtensiveness,
  analyzeCommitBodies,
  inspectReleasableCommitBodies,
  parseGitLogRecords,
  type CommitRecord,
  type GitRunner,
} from "./release-notes-extensiveness-patterns.ts";

const HOOK_PATH = join(import.meta.dir, "pretooluse-release-notes-extensiveness-guard.ts");

// A genuinely extensive body: one ≥3-sentence narrative paragraph + ≥4 bullets.
const RICH_NOTES = `This release corrects the Garman-Klass volatility coefficient, which previously
double-counted the log-range term and inflated realized volatility on wide-range
bars. The fix restores parity with the reference implementation and re-tightens
the entropy skip threshold that had silently drifted over the last several
versions. Operators running the export pipeline should re-baseline their
volatility dashboards, since historical values will shift slightly downward.

- Fix Garman-Klass coefficient (#454)
- Unify entropy constants (#455)
- Name the entropy skip threshold explicitly (#456)
- Re-baseline exported volatility columns (#457)`;

interface HookResult {
  parsed: {
    hookSpecificOutput?: {
      permissionDecision: "allow" | "deny";
      permissionDecisionReason?: string;
    };
  } | null;
}

function runHook(command: string, toolName = "Bash"): HookResult {
  const input = JSON.stringify({ tool_name: toolName, tool_input: { command } });
  let stdout = "";
  try {
    stdout = execSync(`bun ${HOOK_PATH}`, { encoding: "utf-8", input, stdio: ["pipe", "pipe", "pipe"] }).trim();
  } catch (err: any) {
    stdout = err.stdout?.toString().trim() || "";
  }
  try {
    return { parsed: stdout ? JSON.parse(stdout) : null };
  } catch {
    return { parsed: null };
  }
}

const decision = (r: HookResult) => r.parsed?.hookSpecificOutput?.permissionDecision;

// ============================================================================
// Layer 1a: command classification
// ============================================================================

describe("classifyReleaseCommand", () => {
  it("detects gh release create with inline --notes", () => {
    const v = classifyReleaseCommand(`gh release create v1.2.3 --notes "fix stuff"`);
    expect(v.isRelease).toBe(true);
    expect(v.kind).toBe("gh-release-notes");
    expect(v.notesText).toBe("fix stuff");
  });

  it("detects gh release edit with --notes-file", () => {
    const v = classifyReleaseCommand(`gh release edit v1.2.3 --notes-file NOTES.md`);
    expect(v.kind).toBe("gh-release-notes");
    expect(v.notesFile).toBe("NOTES.md");
  });

  it("flags gh release with no notes at all as absent", () => {
    const v = classifyReleaseCommand(`gh release create v1.2.3`);
    expect(v.notesAbsent).toBe(true);
  });

  it("treats --generate-notes only as absent", () => {
    const v = classifyReleaseCommand(`gh release create v1.2.3 --generate-notes`);
    expect(v.notesAbsent).toBe(true);
  });

  it("treats command-substitution notes as unmeasurable", () => {
    const v = classifyReleaseCommand(`gh release create v1.2.3 --notes "$(cat NOTES.md)"`);
    expect(v.notesUnmeasurable).toBe(true);
  });

  it("detects annotated semver git tag message", () => {
    const v = classifyReleaseCommand(`git tag -a v2.0.0 -m "release"`);
    expect(v.kind).toBe("git-tag-message");
    expect(v.notesText).toBe("release");
  });

  it("ignores lightweight (non-annotated) tags", () => {
    expect(classifyReleaseCommand(`git tag v2.0.0`).isRelease).toBe(false);
  });

  it("ignores non-semver annotated tags", () => {
    expect(classifyReleaseCommand(`git tag -a nightly -m "x"`).isRelease).toBe(false);
  });

  it("detects semantic-release and mise release wrappers", () => {
    expect(classifyReleaseCommand(`npx semantic-release`).kind).toBe("semantic-release");
    expect(classifyReleaseCommand(`mise run release:full`).kind).toBe("semantic-release");
    expect(classifyReleaseCommand(`mise run release`).kind).toBe("semantic-release");
  });

  it("ignores unrelated git/gh commands", () => {
    expect(classifyReleaseCommand(`git status`).isRelease).toBe(false);
    expect(classifyReleaseCommand(`gh pr list`).isRelease).toBe(false);
  });
});

// ============================================================================
// Layer 1b: notes-text extensiveness
// ============================================================================

describe("measureNotesExtensiveness", () => {
  it("passes a narrative paragraph + bullets", () => {
    const m = measureNotesExtensiveness(RICH_NOTES);
    expect(m.ok).toBe(true);
    expect(m.hasNarrative).toBe(true);
    expect(m.hasPointForm).toBe(true);
  });

  it("blocks a terse one-liner", () => {
    const m = measureNotesExtensiveness("fix stuff");
    expect(m.ok).toBe(false);
  });

  it("blocks bullets-only (no narrative)", () => {
    const m = measureNotesExtensiveness("* fix a\n* fix b\n* fix c\n* fix d");
    expect(m.hasPointForm).toBe(true);
    expect(m.hasNarrative).toBe(false);
    expect(m.ok).toBe(false);
  });

  it("blocks narrative-only (no point form)", () => {
    const m = measureNotesExtensiveness(RICH_NOTES.split("\n\n")[0]);
    expect(m.hasNarrative).toBe(true);
    expect(m.hasPointForm).toBe(false);
    expect(m.ok).toBe(false);
  });
});

// ============================================================================
// Layer 1c: commit-body inspection
// ============================================================================

describe("analyzeCommitBodies", () => {
  const richBody =
    "The pool lock was held across the client yield, so a slow consumer could " +
    "starve every other ClickHouse caller for the whole duration of its query. " +
    "Release the lock before yielding the client and re-acquire it only for the " +
    "reclaim path, which is short and non-blocking. Adds a regression test that " +
    "reproduces the starvation under concurrent access and asserts fair hand-off " +
    "between competing callers, plus telemetry that surfaces lock-wait time so a " +
    "future regression is caught in monitoring rather than by a stalled export.";

  it("passes when a releasable commit has a rich body", () => {
    const records: CommitRecord[] = [
      { hash: "aaaaaaaa", subject: "fix(python): release pool lock", body: richBody },
    ];
    expect(analyzeCommitBodies(records).ok).toBe(true);
  });

  it("blocks thin releasable commits and lists them", () => {
    const records: CommitRecord[] = [
      { hash: "bbbbbbbb", subject: "fix(core): correct coefficient", body: "" },
      { hash: "cccccccc", subject: "feat(export): labels companions", body: "small" },
    ];
    const r = analyzeCommitBodies(records);
    expect(r.ok).toBe(false);
    expect(r.thinCommits.map((c) => c.hash)).toContain("bbbbbbbb");
  });

  it("allows when there are no releasable commits (chore-only)", () => {
    const records: CommitRecord[] = [
      { hash: "dddddddd", subject: "chore: bump deps", body: "" },
      { hash: "eeeeeeee", subject: "docs: fix typo", body: "" },
    ];
    expect(analyzeCommitBodies(records).ok).toBe(true);
  });

  it("treats a BREAKING CHANGE footer as releasable", () => {
    const records: CommitRecord[] = [
      { hash: "ffffffff", subject: "refactor: rework api", body: "BREAKING CHANGE: removed x" },
    ];
    expect(analyzeCommitBodies(records).releasableCount).toBe(1);
  });

  it("round-trips through parseGitLogRecords", () => {
    const raw = `h1\x1ffix: a\x1fbody one\x1eh2\x1ffeat: b\x1fbody two\x1e`;
    const recs = parseGitLogRecords(raw);
    expect(recs).toHaveLength(2);
    expect(recs[1].subject).toBe("feat: b");
  });
});

const FAILING_GIT: GitRunner = () => ({ ok: false, stdout: "" });

describe("inspectReleasableCommitBodies (injected runner)", () => {
  it("fails open when git errors", () => {
    expect(inspectReleasableCommitBodies("/nowhere", FAILING_GIT).ok).toBe(true);
  });
});

// ============================================================================
// Layer 2: subprocess through the real hook
// ============================================================================

describe("hook wiring", () => {
  it("denies a terse gh release", () => {
    const r = runHook(`gh release create v1.2.3 --notes "fix stuff"`);
    expect(decision(r)).toBe("deny");
    expect(r.parsed!.hookSpecificOutput?.permissionDecisionReason).toContain("[RELEASE-NOTES-GUARD]");
  });

  it("denies a notes-absent gh release", () => {
    expect(decision(runHook(`gh release create v1.2.3`))).toBe("deny");
  });

  it("allows a rich gh release", () => {
    const r = runHook(`gh release create v1.2.3 --notes "${RICH_NOTES}"`);
    expect(decision(r)).toBe("allow");
  });

  it("allows via the RELEASE-NOTES-OK escape hatch", () => {
    const r = runHook(`gh release create v1.2.3 --notes "x"  # RELEASE-NOTES-OK: pure dependency bump only`);
    expect(decision(r)).toBe("allow");
  });

  it("allows unrelated commands (fast-path)", () => {
    expect(decision(runHook(`git status`))).toBe("allow");
    expect(decision(runHook(`ls -la`))).toBe("allow");
  });

  it("allows unmeasurable command-substitution notes (fail-open)", () => {
    expect(decision(runHook(`gh release create v1.2.3 --notes "$(cat NOTES.md)"`))).toBe("allow");
  });

  it("allows non-Bash tools", () => {
    expect(decision(runHook(`gh release create v1.2.3`, "Read"))).toBe("allow");
  });
});
