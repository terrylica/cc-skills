/**
 * Tests for the GitHub hard-wrap guard.
 *
 * Every test spawns the real hook and asserts its decision. A test that only
 * re-asserts a property of its own fixture proves nothing about the guard.
 *
 * The load-bearing fixture is REAL_V240_OPENING: the verbatim opening of the
 * terrylica/quantml v2.4.0 release notes as published — the body that shipped
 * hard-wrapped and made this guard necessary. If the guard ever stops denying
 * that text, it has stopped doing its job.
 */

import { describe, expect, it } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const HOOK_PATH = join(import.meta.dir, "pretooluse-github-hard-wrap-guard.ts");

// ── Fixtures ──────────────────────────────────────────────────────────────

/** Verbatim from the published quantml v2.4.0 body — prose wrapped at ~100 columns. */
const REAL_V240_OPENING = [
  "This release is about closing loops that were left open on purpose, and discovering that two of them",
  "were load-bearing. Three items had been written down as rules and never built — a floor that would",
  "have caught a silent index collapse, a hub list everyone knew was stale, and a shared reader for a",
  "pattern duplicated forty-three times.",
].join("\n");

/** The same prose, one line per paragraph — what should have been published. */
const REFLOWED_V240_OPENING =
  "This release is about closing loops that were left open on purpose, and discovering that two of them were load-bearing. Three items had been written down as rules and never built — a floor that would have caught a silent index collapse, a hub list everyone knew was stale, and a shared reader for a pattern duplicated forty-three times.";

/** Structural markdown that must never be mistaken for a prose wrap. */
const STRUCTURAL_MARKDOWN = [
  "## What changed",
  "",
  "The stage now halts when a source kind had inputs available and contributed zero chunks, which is the check that would have caught the regression at the moment it happened.",
  "",
  "- The dedup tool would have deleted the processed copy of a duplicate, because it preferred the long-form URL",
  "- `getCached` wrapped the strict reader in a catch returning null, reinstating the swallow it exists to remove",
  "",
  "| Stage | Chunks |",
  "| ----- | ------ |",
  "| 10    | 476    |",
  "",
  "```ts",
  "const winner = selectSurvivingCopy(group, (dir) => totalEvidenceForDirectory(dir))",
  "if (!winner) throw new Error('a group always has a survivor')",
  "```",
].join("\n");

// ── Harness ───────────────────────────────────────────────────────────────

interface HookDecision {
  hookSpecificOutput: {
    permissionDecision: "allow" | "deny" | "ask";
    permissionDecisionReason?: string;
  };
}

async function runHook(command: string): Promise<HookDecision> {
  const proc = Bun.spawn(["bun", HOOK_PATH], { stdin: "pipe", stdout: "pipe", stderr: "pipe" });
  proc.stdin.write(JSON.stringify({ tool_name: "Bash", tool_input: { command } }));
  proc.stdin.end();
  const out = await new Response(proc.stdout).text();
  await proc.exited;
  return JSON.parse(out.trim()) as HookDecision;
}

const decisionOf = async (command: string) =>
  (await runHook(command)).hookSpecificOutput.permissionDecision;

const dir = mkdtempSync(join(tmpdir(), "github-hard-wrap-guard-"));

// ── The regression ────────────────────────────────────────────────────────

describe("the v2.4.0 regression", () => {
  it("denies the release body that actually shipped hard-wrapped", async () => {
    const d = await runHook(`gh release create v2.4.0 --notes "${REAL_V240_OPENING}"`);
    expect(d.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(d.hookSpecificOutput.permissionDecisionReason).toContain("[GH-HARD-WRAP-GUARD]");
  });

  it("allows the same prose reflowed to one line per paragraph", async () => {
    expect(await decisionOf(`gh release create v2.4.0 --notes "${REFLOWED_V240_OPENING}"`)).toBe(
      "allow",
    );
  });

  it("denies it through --notes-file and names the file", async () => {
    const fixture = join(dir, "wrapped-notes.md");
    writeFileSync(fixture, REAL_V240_OPENING);
    const d = await runHook(`gh release edit v2.4.0 --notes-file ${fixture}`);
    expect(d.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(d.hookSpecificOutput.permissionDecisionReason).toContain(fixture);
  });

  it("allows a reflowed --notes-file", async () => {
    const fixture = join(dir, "reflowed-notes.md");
    writeFileSync(fixture, REFLOWED_V240_OPENING);
    expect(await decisionOf(`gh release edit v2.4.0 --notes-file ${fixture}`)).toBe("allow");
  });
});

// ── Every guarded surface ─────────────────────────────────────────────────

describe("guarded surfaces", () => {
  const surfaces: readonly [string, string][] = [
    ["gh issue create", `gh issue create --title T --body "${REAL_V240_OPENING}"`],
    ["gh issue edit", `gh issue edit 1 --body "${REAL_V240_OPENING}"`],
    ["gh issue comment", `gh issue comment 1 -b "${REAL_V240_OPENING}"`],
    ["gh pr create", `gh pr create --title T -b "${REAL_V240_OPENING}"`],
    ["gh pr edit", `gh pr edit 1 --body "${REAL_V240_OPENING}"`],
    ["gh pr comment", `gh pr comment 1 -b "${REAL_V240_OPENING}"`],
  ];
  for (const [name, command] of surfaces) {
    it(`denies hard-wrapped prose on ${name}`, async () => {
      expect(await decisionOf(command)).toBe("deny");
    });
  }
});

// ── Not guarded, on purpose ───────────────────────────────────────────────

describe("git objects are out of scope", () => {
  /**
   * 72-column wrapping is the correct convention for a git message, and a git
   * object is not a GFM surface. The reflow belongs at the publish boundary,
   * which the `gh release` tests above already cover.
   */
  it("allows an annotated tag whose message is hard-wrapped", async () => {
    expect(await decisionOf(`git tag -a v2.4.0 -m "${REAL_V240_OPENING}"`)).toBe("allow");
  });

  it("allows a commit whose body is hard-wrapped", async () => {
    expect(await decisionOf(`git commit -m "${REAL_V240_OPENING}"`)).toBe("allow");
  });
});

// ── False positives ───────────────────────────────────────────────────────

describe("does not fire on newlines that carry meaning", () => {
  it("allows headings, lists, a table and a fenced block", async () => {
    expect(await decisionOf(`gh release create v1 --notes "${STRUCTURAL_MARKDOWN}"`)).toBe("allow");
  });

  it("allows an unrelated command", async () => {
    expect(await decisionOf(`gh repo view --json name`)).toBe("allow");
  });

  /**
   * The guard must match its verb as an adjacent token sequence. Matching `gh`
   * and `release create` as independent substrings makes any command that
   * MENTIONS the pattern a match — which is how the sibling extensiveness guard
   * blocked a heredoc whose prose quoted the command it watches for.
   */
  it("allows a command that merely writes about the guarded command", async () => {
    const prose = `The guard denies gh release create when the body is wrapped, and the\nreason is that GFM turns every newline into a break element.`;
    expect(await decisionOf(`cat >> notes.md <<'EOF'\n${prose}\nEOF`)).toBe("allow");
  });

  it("allows grepping for the guarded command", async () => {
    expect(await decisionOf(`grep -rn "gh release create" docs/`)).toBe("allow");
  });

  it("allows a non-Bash tool", async () => {
    const proc = Bun.spawn(["bun", HOOK_PATH], { stdin: "pipe", stdout: "pipe", stderr: "pipe" });
    proc.stdin.write(JSON.stringify({ tool_name: "Read", tool_input: { file_path: "/tmp/x" } }));
    proc.stdin.end();
    const out = await new Response(proc.stdout).text();
    await proc.exited;
    expect(JSON.parse(out.trim()).hookSpecificOutput.permissionDecision).toBe("allow");
  });

  it("allows a --notes-file that does not exist rather than blocking", async () => {
    expect(await decisionOf(`gh release create v1 --notes-file ${join(dir, "absent.md")}`)).toBe(
      "allow",
    );
  });
});

// ── Escape hatch ──────────────────────────────────────────────────────────

describe("escape hatch", () => {
  it("allows hard-wrapped notes when GH-HARD-WRAP-OK is present", async () => {
    expect(
      await decisionOf(`gh release create v1 --notes "${REAL_V240_OPENING}" # GH-HARD-WRAP-OK`),
    ).toBe("allow");
  });

  it("is case-sensitive, so a lowercase marker does not open the gate", async () => {
    expect(
      await decisionOf(`gh release create v1 --notes "${REAL_V240_OPENING}" # gh-hard-wrap-ok`),
    ).toBe("deny");
  });
});
