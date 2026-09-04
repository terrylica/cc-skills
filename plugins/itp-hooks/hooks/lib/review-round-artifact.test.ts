#!/usr/bin/env bun
/**
 * Case table + mutation harness for the review-round gate's pure core.
 *
 * THE BASELINE ASSERTION IS FIRST AND IS NOT DECORATION. On PR #508 a mutation harness reported
 * 18/18 kills that were all fabricated by a usage error: it never asserted the UNMUTATED baseline
 * was green, so every "kill" was the harness failing to run. Any mutation table without a baseline
 * check is measuring itself.
 */

import { describe, expect, test } from "bun:test";
import {
  classify,
  overrideReason,
  sha256,
  validateArtifact,
  type RepoFacts,
  type ReviewRoundArtifact,
} from "./review-round-artifact.ts";

const DIFF = "diff --git a/x b/x\n+one line\n";

function facts(overrides: Partial<RepoFacts> = {}): RepoFacts {
  return {
    headSha: "3b0cdfc7a1b2c3d4e5f60718293a4b5c6d7e8f90",
    baseSha: "e3acafc1000000000000000000000000000000aa",
    diffText: DIFF,
    changedPaths: ["src/a.ts", "src/b.ts"],
    ...overrides,
  };
}

function artifact(overrides: Partial<ReviewRoundArtifact> = {}): ReviewRoundArtifact {
  return {
    schema: 1,
    head_sha: facts().headSha,
    base_sha: facts().baseSha,
    diff_sha256: sha256(DIFF),
    recorded_at: "2026-09-04T00:00:00Z",
    files: [
      { path: "src/a.ts", verdict: "Checked the null path; the early return is unreachable." },
      { path: "src/b.ts", verdict: "New bound is per-panel and mutation-killed at this SHA." },
    ],
    ...overrides,
  };
}

describe("BASELINE", () => {
  test("an honest artifact against matching facts is accepted", () => {
    const result = validateArtifact(artifact(), facts());
    expect(result.failures).toEqual([]);
    expect(result.ok).toBe(true);
  });
});

describe("classify — commands that must be GATED", () => {
  const gated: [string, string][] = [
    ["gh pr ready 613", "pr-ready"],
    ["gh pr create --title x --body-file b.md", "pr-create"],
    ["/opt/homebrew/bin/gh pr ready 613", "pr-ready"],
    ["GH_ORGS=Eon-Labs gh pr ready 613", "pr-ready"],
    // A QUOTED assignment value containing a space. The inherited COMMAND_POSITION used `\S*` for
    // the value, which stops at the first space, so these did not match a command position at all
    // and the gate silently ALLOWED them — a total bypass available to anyone who quotes an env
    // var. It also made the gate's own override resolve to `allow` instead of `ask`. The unquoted
    // case above passes either way, which is exactly why this needs its own row.
    ['GH_ORGS="Eon Labs" gh pr ready 613', "pr-ready"],
    ["GH_ORGS='Eon Labs' gh pr create --title t --body-file b.md", "pr-create"],
    ["env GH_ORGS=x sudo gh pr ready 613", "pr-ready"],
    ["cd /tmp && gh pr ready 613", "pr-ready"],
    ["git push", "push"],
    ["git push --force-with-lease origin feat", "push"],
    ['gh pr comment 1 --body "line one\nline two"', "inline-body"],
    [`gh pr create --title t --body "${"x".repeat(301)}"`, "inline-body"],
    // ADDED BECAUSE A MUTATION SURVIVED, and it exposed a real bypass rather than a missing test.
    // `--draft` inside a quoted TITLE has whitespace on both sides, so a plain word-boundary flag
    // test matched it and silently exempted a non-draft PR. Flags are now tested with quoted spans
    // stripped. Without this case the whole `--draft` detection could be replaced by a bare
    // substring check and nothing would go red.
    ['gh pr create --title "add a --draft flag to signal" --body-file b.md', "pr-create"],
    ["gh pr create --title 'support --draft mode' --body-file b.md", "pr-create"],
  ];
  for (const [command, kind] of gated) {
    test(`${kind}: ${command.slice(0, 48)}`, () => {
      expect(classify(command).kind).toBe(kind as never);
    });
  }
});

describe("classify — commands that must be ALLOWED", () => {
  const allowed = [
    // A draft never enters the reviewer's queue, so it is not a review event.
    "gh pr create --draft --title x --body-file b.md",
    // --undo REMOVES work from the queue. Gating it would block the remedy the gate recommends.
    "gh pr ready 613 --undo",
    // The words appear inside an argument, not at a command position.
    'echo "then run gh pr ready 613"',
    'gh pr comment 1 --body "Rebased; CI green."',
    "gh pr list --author @me",
    "gh pr view 604 --json state",
    "git status",
    "git commit -m 'x'",
    "ls -la",
  ];
  for (const command of allowed) {
    test(`allowed: ${command.slice(0, 48)}`, () => {
      expect(classify(command).kind).toBeNull();
    });
  }
});

describe("override", () => {
  test("a 12+ char reason at the command head is accepted", () => {
    expect(overrideReason('REVIEW_ROUND_OK="urgent revert of a broken merge" gh pr ready 1')).toBe(
      "urgent revert of a broken merge",
    );
  });
  test("a short reason does not disarm the gate", () => {
    expect(overrideReason('REVIEW_ROUND_OK="short" gh pr ready 1')).toBeNull();
  });
  test("the token inside a --body does NOT disarm the gate", () => {
    // git-worktree-guard anchors its override loosely and this exact shape is a measured bypass
    // there: the token appearing anywhere in the command disarms it.
    expect(
      overrideReason('gh pr comment 1 --body "we set REVIEW_ROUND_OK=\\"because reasons here\\" earlier"'),
    ).toBeNull();
  });
  test("the token later in a compound command does not disarm it", () => {
    expect(overrideReason('cd /tmp && REVIEW_ROUND_OK="a good long reason" gh pr ready 1')).toBeNull();
  });
});

describe("validateArtifact — each structural rule can fail", () => {
  test("S0: a missing artifact DENIES rather than passing", () => {
    // The single most important line in the module: absence must never resolve to permission.
    const r = validateArtifact(null, facts());
    expect(r.ok).toBe(false);
    expect(r.failures[0]).toContain("no self-review record");
  });

  test("S1: a record from an earlier commit is rejected", () => {
    const r = validateArtifact(artifact({ head_sha: "0".repeat(40) }), facts());
    expect(r.ok).toBe(false);
    expect(r.failures.join(" ")).toContain("predates the code");
  });

  test("S1: a 7-char prefix of HEAD is NOT accepted", () => {
    const r = validateArtifact(artifact({ head_sha: facts().headSha.slice(0, 7) }), facts());
    expect(r.ok).toBe(false);
  });

  test("S2: an edit after recording invalidates the record", () => {
    const r = validateArtifact(artifact(), facts({ diffText: `${DIFF}+another line\n` }));
    expect(r.ok).toBe(false);
    expect(r.failures.join(" ")).toContain("diff has changed");
  });

  test("S3: a changed file with no verdict is rejected", () => {
    const r = validateArtifact(artifact(), facts({ changedPaths: ["src/a.ts", "src/b.ts", "src/c.ts"] }));
    expect(r.ok).toBe(false);
    expect(r.failures.join(" ")).toContain("no recorded verdict");
  });

  test("S3: a verdict for a file NOT in the diff is rejected", () => {
    // The subset direction. Without this, a record could name files it never examined.
    const r = validateArtifact(artifact(), facts({ changedPaths: ["src/a.ts"] }));
    expect(r.ok).toBe(false);
    expect(r.failures.join(" ")).toContain("not in the diff");
  });

  test("S4: a one-word verdict is rejected", () => {
    const a = artifact();
    a.files[0].verdict = "ok";
    const r = validateArtifact(a, facts());
    expect(r.ok).toBe(false);
    expect(r.failures.join(" ")).toContain("under 24 characters");
  });

  test("S5: the same verdict reused across files is rejected", () => {
    const a = artifact();
    a.files[1].verdict = a.files[0].verdict;
    const r = validateArtifact(a, facts());
    expect(r.ok).toBe(false);
    expect(r.failures.join(" ")).toContain("not distinct");
  });

  test("S5 does not fire on a single-file change", () => {
    const r = validateArtifact(
      artifact({ files: [{ path: "src/a.ts", verdict: "Only file; checked the boundary case." }] }),
      facts({ changedPaths: ["src/a.ts"] }),
    );
    expect(r.ok).toBe(true);
  });

  test("an unknown schema version is rejected", () => {
    const r = validateArtifact(artifact({ schema: 2 }), facts());
    expect(r.ok).toBe(false);
  });
});
