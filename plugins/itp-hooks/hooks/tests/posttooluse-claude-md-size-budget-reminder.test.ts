/**
 * Tests for the CLAUDE.md size-budget subhook
 * (posttooluse-claude-md-size-budget-reminder.ts).
 *
 * The headline regression: the hook must count CHARACTERS, not bytes. A CJK
 * CLAUDE.md that is over 40k BYTES but under the 36k-char warn threshold must
 * stay SILENT (pre-fix it byte-counted and false-alarmed "OVER limit").
 *
 * Tests call the pure classifier directly (no subprocess) and write fixtures
 * to a temp dir.
 */

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator,
  classifyClaudeMdSizeBudgetForPostToolUseOrchestrator,
} from "../posttooluse-claude-md-size-budget-reminder.ts";

let ROOT: string;

/** Write `content` to <ROOT>/<subdir>/<name> and return the absolute path. */
function fixture(subdir: string, name: string, content: string): string {
  const dir = join(ROOT, subdir);
  mkdirSync(dir, { recursive: true });
  const p = join(dir, name);
  writeFileSync(p, content, "utf8");
  return p;
}

function writeInput(filePath: string, toolName = "Write") {
  return { tool_name: toolName, tool_input: { file_path: filePath } };
}

beforeAll(() => {
  ROOT = mkdtempSync(join(tmpdir(), "claude-md-size-test-"));
});
afterAll(() => {
  rmSync(ROOT, { recursive: true, force: true });
});

describe("classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator", () => {
  test("APPROACHING: 37k-char ASCII CLAUDE.md → additional_context (⚠)", async () => {
    const p = fixture("approaching", "CLAUDE.md", "x".repeat(37_000));
    const d = await classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator(writeInput(p));
    expect(d.kind).toBe("additional_context");
    if (d.kind === "additional_context") {
      expect(d.message).toContain("⚠");
      expect(d.message).toContain("37,000 chars");
    }
  });

  test("OVER: 41k-char ASCII CLAUDE.md → additional_context (⛔)", async () => {
    const p = fixture("over", "CLAUDE.md", "x".repeat(41_000));
    const d = await classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator(writeInput(p, "Edit"));
    expect(d.kind).toBe("additional_context");
    if (d.kind === "additional_context") {
      expect(d.message).toContain("⛔");
      expect(d.message).toContain("OVER");
    }
  });

  test("SMALL: 1k-char CLAUDE.md → noop", async () => {
    const p = fixture("small", "CLAUDE.md", "x".repeat(1_000));
    const d = await classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator(writeInput(p));
    expect(d.kind).toBe("noop");
  });

  // ── The headline regression ────────────────────────────────────────────
  test("CJK silent: 30k chars but 90k BYTES → noop (bytes would have false-alarmed)", async () => {
    const content = "中".repeat(30_000); // 30k chars, 90k UTF-8 bytes
    const p = fixture("cjk-silent", "CLAUDE.md", content);
    expect(Buffer.byteLength(content, "utf8")).toBeGreaterThan(40_000); // would trip a byte guard
    const d = await classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator(writeInput(p));
    expect(d.kind).toBe("noop"); // but it's only 30k CHARS → correctly silent
  });

  test("CJK over: 45k chars (135k bytes) → additional_context (⛔), reports char count", async () => {
    const p = fixture("cjk-over", "CLAUDE.md", "中".repeat(45_000));
    const d = await classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator(writeInput(p));
    expect(d.kind).toBe("additional_context");
    if (d.kind === "additional_context") {
      expect(d.message).toContain("45,000 chars"); // chars, not the 135k byte count
    }
  });

  test("wrong basename: principles-CLAUDE.md at 41k chars → noop", async () => {
    const p = fixture("spoke", "principles-CLAUDE.md", "x".repeat(41_000));
    const d = await classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator(writeInput(p));
    expect(d.kind).toBe("noop");
  });

  test("wrong tool: Read on a 41k CLAUDE.md → noop", async () => {
    const p = fixture("readtool", "CLAUDE.md", "x".repeat(41_000));
    const d = await classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator(writeInput(p, "Read"));
    expect(d.kind).toBe("noop");
  });

  test("escape hatch: 41k chars + CLAUDE-MD-SIZE-OK marker → noop", async () => {
    const content = "x".repeat(41_000) + "\n<!-- CLAUDE-MD-SIZE-OK -->\n";
    const p = fixture("escaped", "CLAUDE.md", content);
    const d = await classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator(writeInput(p));
    expect(d.kind).toBe("noop");
  });

  test("MultiEdit honored: 41k CLAUDE.md via MultiEdit → additional_context", async () => {
    const p = fixture("multiedit", "CLAUDE.md", "x".repeat(41_000));
    const d = await classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator(writeInput(p, "MultiEdit"));
    expect(d.kind).toBe("additional_context");
  });

  test("relative file_path resolved via cwd → fires (not a silent miss)", async () => {
    fixture("relcwd", "CLAUDE.md", "x".repeat(41_000));
    const d = await classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator({
      tool_name: "Write",
      tool_input: { file_path: "CLAUDE.md" },
      cwd: join(ROOT, "relcwd"),
    });
    expect(d.kind).toBe("additional_context");
  });

  test("missing file → noop (fail-open)", async () => {
    const d = await classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator(
      writeInput(join(ROOT, "nope", "CLAUDE.md")),
    );
    expect(d.kind).toBe("noop");
  });

  test("alias is the same function", () => {
    expect(classifyClaudeMdSizeBudgetForPostToolUseOrchestrator).toBe(
      classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator,
    );
  });
});
