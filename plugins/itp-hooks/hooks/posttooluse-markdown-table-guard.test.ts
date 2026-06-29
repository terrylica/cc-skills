import { describe, expect, it } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  evaluateMarkdownTableContent,
  isMarkdownTableGuardEligibleTarget,
} from "./posttooluse-markdown-table-guard.ts";

const HOOK_PATH = join(import.meta.dir, "posttooluse-markdown-table-guard.ts");

const BROKEN_TABLE = `## Selector map

| Step | Selector |
| ---- | -------- |
| Expiration open | \`button\` name \`/days \\( | No expiration | Custom | Expiration/i\` |
| Name | input[name] |
`;

const VALID_TABLE = `| File | Role |
| ---- | ---- |
| pat.mjs | CLI: \`login \\| doctor \\| create\`. |
`;

/** Spawn the hook with a PostToolUse payload; return trimmed stdout. */
async function runHook(payload: object): Promise<string> {
  const proc = Bun.spawn(["bun", HOOK_PATH], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  proc.stdin.write(JSON.stringify(payload));
  proc.stdin.end();
  const out = await new Response(proc.stdout).text();
  await proc.exited;
  return out.trim();
}

describe("isMarkdownTableGuardEligibleTarget (pure gate)", () => {
  it("accepts a .md Write/Edit/MultiEdit", () => {
    expect(isMarkdownTableGuardEligibleTarget("Write", "/repo/a.md")).toBe(true);
    expect(isMarkdownTableGuardEligibleTarget("Edit", "/repo/a.markdown")).toBe(true);
    expect(isMarkdownTableGuardEligibleTarget("MultiEdit", "/repo/a.md")).toBe(true);
  });
  it("rejects non-md files and non-edit tools", () => {
    expect(isMarkdownTableGuardEligibleTarget("Edit", "/repo/a.ts")).toBe(false);
    expect(isMarkdownTableGuardEligibleTarget("Bash", "/repo/a.md")).toBe(false);
  });
  it("rejects a .md file inside a temp scratch dir", () => {
    expect(isMarkdownTableGuardEligibleTarget("Write", "/tmp/scratch.md")).toBe(false);
  });
});

describe("evaluateMarkdownTableContent (pure eval)", () => {
  it("returns a reminder for a broken table", () => {
    const r = evaluateMarkdownTableContent("/repo/CLAUDE.md", BROKEN_TABLE);
    expect(r).toContain("[MD-TABLE-GUARD]");
    expect(r).toContain("L5");
  });
  it("returns null for a correctly-escaped table", () => {
    expect(evaluateMarkdownTableContent("/repo/CLAUDE.md", VALID_TABLE)).toBeNull();
  });
  it("returns null when MD-TABLE-OK suppresses a broken table", () => {
    const suppressed = `<!-- MD-TABLE-OK -->\n\n${BROKEN_TABLE}`;
    expect(evaluateMarkdownTableContent("/repo/CLAUDE.md", suppressed)).toBeNull();
  });
  it("returns null for an info-only file (short row, no error)", () => {
    const infoOnly = "| a | b | c |\n| - | - | - |\n| 1 | 2 |\n";
    expect(evaluateMarkdownTableContent("/repo/CLAUDE.md", infoOnly)).toBeNull();
  });
});

describe("hook process (spawned end-to-end)", () => {
  const dir = mkdtempSync(join(tmpdir(), "md-table-guard-"));

  it("emits {decision:block} for a broken .md (non-temp path)", async () => {
    // The hook exempts temp dirs, so place the fixture under a non-temp path
    // by writing it into the plugin's own tree.
    const fixture = join(import.meta.dir, "tests", ".hook-itest-broken.md");
    writeFileSync(fixture, BROKEN_TABLE);
    try {
      const out = await runHook({ tool_name: "Edit", tool_input: { file_path: fixture } });
      const parsed = JSON.parse(out);
      expect(parsed.decision).toBe("block");
      expect(parsed.reason).toContain("[MD-TABLE-GUARD]");
    } finally {
      rmSync(fixture, { force: true });
    }
  });

  it("emits nothing for a clean .md", async () => {
    const fixture = join(import.meta.dir, "tests", ".hook-itest-clean.md");
    writeFileSync(fixture, VALID_TABLE);
    try {
      const out = await runHook({ tool_name: "Edit", tool_input: { file_path: fixture } });
      expect(out).toBe("");
    } finally {
      rmSync(fixture, { force: true });
    }
  });

  it("emits nothing for a .md inside a temp dir (scratch exempt)", async () => {
    const fixture = join(dir, "scratch.md");
    writeFileSync(fixture, BROKEN_TABLE);
    const out = await runHook({ tool_name: "Write", tool_input: { file_path: fixture } });
    expect(out).toBe("");
  });

  it("emits nothing for a non-md file", async () => {
    const out = await runHook({ tool_name: "Edit", tool_input: { file_path: "/repo/a.ts" } });
    expect(out).toBe("");
  });
});
