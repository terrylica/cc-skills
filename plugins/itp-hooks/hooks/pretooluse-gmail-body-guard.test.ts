import { describe, expect, it } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  buildBodyReminder,
  detectBodyIssues,
  detectHardWraps,
  detectLiteralMarkdown,
  isGmailDraftCommand,
  parseGmailDraftBodies,
} from "./lib/gmail-body-detector.ts";

const HOOK_PATH = join(import.meta.dir, "pretooluse-gmail-body-guard.ts");

// ── Fixtures ──────────────────────────────────────────────────────────────

const WRAPPED_PARAGRAPH = [
  "We are CPC, a Canadian logistics operator evaluating enterprise Android handhelds as the",
  "platform for an in-house agent-driven device-management and data-capture stack right now.",
].join("\n");

const SINGLE_LINE_PARAGRAPH =
  "We are CPC, a Canadian logistics operator evaluating enterprise Android handhelds as the platform for an in-house agent-driven device-management and data-capture stack right now.";

const CLEAN_ONE_LINE_LIST = [
  "- First item stated fully on a single line that is quite long here and ends properly.",
  "- Second item also stated fully on a single long line here, ending cleanly as well too.",
].join("\n");

const FENCED_CODE = [
  "```",
  "some code line one that is quite long and continues without any terminator here yes",
  "**not bold** and `not code` inside a fence should be ignored entirely here as well",
  "```",
].join("\n");

// ── Hard-wrap detection ─────────────────────────────────────────────────────

describe("detectHardWraps", () => {
  it("flags a paragraph hard-wrapped mid-sentence", () => {
    expect(detectHardWraps(WRAPPED_PARAGRAPH).length).toBe(1);
  });
  it("passes a single unbroken paragraph", () => {
    expect(detectHardWraps(SINGLE_LINE_PARAGRAPH)).toEqual([]);
  });
  it("passes a clean one-line-per-item list", () => {
    expect(detectHardWraps(CLEAN_ONE_LINE_LIST)).toEqual([]);
  });
});

// ── Literal-markdown detection ──────────────────────────────────────────────

describe("detectLiteralMarkdown", () => {
  it("flags **bold**", () => {
    expect(detectLiteralMarkdown("We are **CPC**, a logistics operator.")).toEqual([
      { line: 1, kind: "bold", sample: "**CPC**" },
    ]);
  });
  it("flags `inline code`", () => {
    expect(detectLiteralMarkdown("Run `gmail draft` to start.").map((m) => m.kind)).toEqual(["code"]);
  });
  it("flags [text](url) links", () => {
    expect(detectLiteralMarkdown("See [our docs](https://x.com/y).").map((m) => m.kind)).toEqual(["link"]);
  });
  it("flags # headings and | tables |", () => {
    expect(detectLiteralMarkdown("# Overview").map((m) => m.kind)).toEqual(["heading"]);
    expect(detectLiteralMarkdown("| # | Item | Qty |").map((m) => m.kind)).toEqual(["table"]);
  });
  it("does NOT flag single-char *italic* / _italic_", () => {
    expect(detectLiteralMarkdown("Please review the *draft* and _final_ today.")).toEqual([]);
  });
  it("does NOT flag a dunder identifier like __init__", () => {
    expect(detectLiteralMarkdown("Call the __init__ method during setup.")).toEqual([]);
  });
  it("does NOT flag bare URLs or parenthetical URLs (no markdown link syntax)", () => {
    expect(detectLiteralMarkdown("See https://x.com or (https://y.com) for details.")).toEqual([]);
  });
  it("skips markdown inside fenced code blocks", () => {
    expect(detectLiteralMarkdown(FENCED_CODE)).toEqual([]);
  });
  it("flags __bold phrase__ that is not a bare identifier", () => {
    expect(detectLiteralMarkdown("This is __really important__ to note.").map((m) => m.kind)).toEqual(["bold"]);
  });
});

// ── Combined + command parsing ──────────────────────────────────────────────

describe("detectBodyIssues", () => {
  it("reports a markdown-only body (single line, no wrap)", () => {
    const b = detectBodyIssues("We are **CPC**, evaluating handhelds on one unbroken line here.");
    expect(b.wraps).toEqual([]);
    expect(b.markdown.length).toBe(1);
  });
  it("is clean for plain single-line prose", () => {
    const b = detectBodyIssues(SINGLE_LINE_PARAGRAPH);
    expect(b.wraps).toEqual([]);
    expect(b.markdown).toEqual([]);
  });
});

describe("isGmailDraftCommand / parseGmailDraftBodies", () => {
  it("recognizes draft invocations and extracts bodies", () => {
    expect(isGmailDraftCommand('gmail draft --to a@b.com --body "hi"')).toBe(true);
    expect(isGmailDraftCommand("gmail list -n 10")).toBe(false);
    const p = parseGmailDraftBodies('gmail draft --to a@b.com --body "hello" --body-file ./b.txt');
    expect(p.inline).toEqual(["hello"]);
    expect(p.bodyFilePaths).toEqual(["./b.txt"]);
  });
  it("does not confuse --body with --body-file", () => {
    const p = parseGmailDraftBodies("gmail draft --to a@b.com --body-file ./email.txt");
    expect(p.inline).toEqual([]);
    expect(p.bodyFilePaths).toEqual(["./email.txt"]);
  });
});

describe("buildBodyReminder", () => {
  it("covers both wrap and markdown with header + escape hatch", () => {
    const issues = detectBodyIssues(`${WRAPPED_PARAGRAPH}\n\nWe are **CPC**.`);
    const msg = buildBodyReminder([{ label: "--body", issues }]);
    expect(msg).toContain("[GMAIL-BODY-GUARD]");
    expect(msg).toContain("HARD-WRAP");
    expect(msg).toContain("RAW MARKDOWN");
    expect(msg).toContain("GMAIL-BODY-OK");
  });
});

// ── Hook end-to-end (spawned) ───────────────────────────────────────────────

interface HookDecision {
  hookSpecificOutput: { permissionDecision: "allow" | "deny" | "ask"; permissionDecisionReason?: string };
}

async function runHook(payload: object): Promise<HookDecision> {
  const proc = Bun.spawn(["bun", HOOK_PATH], { stdin: "pipe", stdout: "pipe", stderr: "pipe" });
  proc.stdin.write(JSON.stringify(payload));
  proc.stdin.end();
  const out = await new Response(proc.stdout).text();
  await proc.exited;
  return JSON.parse(out.trim()) as HookDecision;
}

const bashPayload = (command: string) => ({ tool_name: "Bash", tool_input: { command } });

describe("hook process (spawned end-to-end)", () => {
  const dir = mkdtempSync(join(tmpdir(), "gmail-body-guard-"));

  it("denies a wrapped inline --body", async () => {
    const cmd = `gmail draft --to a@b.com --subject Hi --body "${WRAPPED_PARAGRAPH}"`;
    const d = await runHook(bashPayload(cmd));
    expect(d.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(d.hookSpecificOutput.permissionDecisionReason).toContain("[GMAIL-BODY-GUARD]");
  });

  it("denies a single-line body that contains raw markdown", async () => {
    const cmd = `gmail draft --to a@b.com --subject Hi --body "We are **CPC**, evaluating handhelds on one line."`;
    const d = await runHook(bashPayload(cmd));
    expect(d.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(d.hookSpecificOutput.permissionDecisionReason).toContain("RAW MARKDOWN");
  });

  it("allows a clean single-line plain-prose --body", async () => {
    const cmd = `gmail draft --to a@b.com --subject Hi --body "${SINGLE_LINE_PARAGRAPH}"`;
    expect((await runHook(bashPayload(cmd))).hookSpecificOutput.permissionDecision).toBe("allow");
  });

  it("allows when GMAIL-BODY-OK escape hatch is present", async () => {
    const cmd = `gmail draft --body "${WRAPPED_PARAGRAPH}" # GMAIL-BODY-OK`;
    expect((await runHook(bashPayload(cmd))).hookSpecificOutput.permissionDecision).toBe("allow");
  });

  it("denies a wrapped --body-file and names the file", async () => {
    const fixture = join(dir, "wrapped-body.txt");
    writeFileSync(fixture, WRAPPED_PARAGRAPH);
    try {
      const d = await runHook(bashPayload(`gmail draft --to a@b.com --body-file ${fixture}`));
      expect(d.hookSpecificOutput.permissionDecision).toBe("deny");
      expect(d.hookSpecificOutput.permissionDecisionReason).toContain(fixture);
    } finally {
      rmSync(fixture, { force: true });
    }
  });

  it("allows a missing --body-file (fail-open)", async () => {
    const d = await runHook(bashPayload("gmail draft --to a@b.com --body-file /no/such/file.txt"));
    expect(d.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  it("allows a non-draft gmail command and a non-Bash tool", async () => {
    expect((await runHook(bashPayload("gmail list -n 10"))).hookSpecificOutput.permissionDecision).toBe("allow");
    const w = await runHook({ tool_name: "Write", tool_input: { file_path: "/x.md" } });
    expect(w.hookSpecificOutput.permissionDecision).toBe("allow");
  });
});
