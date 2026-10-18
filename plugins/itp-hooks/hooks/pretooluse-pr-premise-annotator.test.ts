/**
 * Tests for pretooluse-pr-premise-annotator.ts, against a fake `gh` on PATH (no network).
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-pr-premise-annotator.test.ts
 *
 * 2026-10-17: the hook denied an AskUserQuestion because an option named one of the operator's
 * own pull requests, demanding a `[#N: yours]` annotation. The incident it exists for (2026-09-06)
 * was an option asserting a REVIEW premise about another author's PR ("Review #656") that no review
 * request supported. That true positive must still be denied; the rest must pass.
 */

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const HOOK_PATH = join(import.meta.dir, "pretooluse-pr-premise-annotator.ts");
let root = "";
let fakePath = "";

beforeAll(() => {
  root = mkdtempSync(join(tmpdir(), "pr-premise-"));
  const bin = join(root, "bin");
  mkdirSync(bin);
  // #5 is mine, #6 and #7 are someone else's; nobody requested my review on either.
  writeFileSync(
    join(bin, "gh"),
    [
      "#!/bin/sh",
      'case "$*" in',
      '  "api user --jq .login") echo me ;;',
      '  "pr view 5 --json author,url") echo \'{"author":{"login":"me"},"url":"https://github.com/o/r/pull/5"}\' ;;',
      '  "pr view 6 --json author,url") echo \'{"author":{"login":"ceo"},"url":"https://github.com/o/r/pull/6"}\' ;;',
      '  "pr view 7 --json author,url") echo \'{"author":{"login":"ceo"},"url":"https://github.com/o/r/pull/7"}\' ;;',
      "  api\\ repos/o/r/issues/*/timeline*) echo false ;;",
      "  *) exit 1 ;;",
      "esac",
    ].join("\n") + "\n",
  );
  chmodSync(join(bin, "gh"), 0o755);
  fakePath = `${bin}:${process.env.PATH ?? ""}`;
});

afterAll(() => rmSync(root, { recursive: true, force: true }));

async function decide(options: Array<{ label: string; description: string }>): Promise<{ decision: string; reason: string }> {
  const proc = Bun.spawn(["bun", HOOK_PATH], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, PATH: fakePath },
  });
  proc.stdin.write(
    JSON.stringify({ tool_name: "AskUserQuestion", tool_input: { questions: [{ question: "Next?", options }] }, cwd: root }),
  );
  proc.stdin.end();
  const out = JSON.parse((await new Response(proc.stdout).text()).trim());
  await proc.exited;
  return {
    decision: out.hookSpecificOutput.permissionDecision,
    reason: out.hookSpecificOutput.permissionDecisionReason ?? "",
  };
}

describe("PR premise annotator", () => {
  test("an option naming my OWN PR is allowed, with or without review wording", async () => {
    expect((await decide([{ label: "Merge #5", description: "squash and delete the branch" }])).decision).toBe("allow");
    expect((await decide([{ label: "Mark #5 ready for review", description: "self-review recorded" }])).decision).toBe("allow");
  });

  test("an option naming another author's PR WITHOUT a review premise is allowed", async () => {
    expect((await decide([{ label: "Rebase #6 onto main", description: "conflicts in one file" }])).decision).toBe("allow");
  });

  test("TRUE POSITIVE: a review premise about another author's PR is denied with the annotation", async () => {
    const r = await decide([{ label: "Review #7", description: "waiting on my review" }]);
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("[#7: @ceo's, no review requested from you]");
  });

  test("the same option re-asked with the annotation converges to allow", async () => {
    const r = await decide([
      { label: "Review #7", description: "look at it — [#7: @ceo's, no review requested from you]" },
    ]);
    expect(r.decision).toBe("allow");
  });
});
