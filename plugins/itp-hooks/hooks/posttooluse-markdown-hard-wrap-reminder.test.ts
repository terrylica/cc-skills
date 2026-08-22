import { describe, expect, it } from "bun:test";
import {
  buildMarkdownHardWrapReminder,
  classifyMarkdownHardWrapReminderForPostToolUseOrchestrator,
  detectNetNewMarkdownHardWraps,
  isMarkdownHardWrapReminderEligibleTarget,
} from "./posttooluse-markdown-hard-wrap-reminder.ts";
import type { PostToolUseInput } from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";

// ── Fixtures ─────────────────────────────────────────────────────────────────

const MD = "/Users/terryli/eon/cc-skills/docs/some-note.md";

/** Two lines, first breaking mid-sentence at ~86 cols — a real hard wrap. */
const WRAPPED = [
  "The orchestrator aggregates every context-injecting subhook into one Bun process so",
  "the per-edit cold-start cost is paid once instead of fifteen separate times.",
].join("\n");

/** Same prose, rewritten as one line — the shape we want authors to produce. */
const UNWRAPPED =
  "The orchestrator aggregates every context-injecting subhook into one Bun process so the per-edit cold-start cost is paid once instead of fifteen separate times.";

/** A reword INSIDE the already-wrapped paragraph: wrap count is unchanged. */
const WRAPPED_REWORDED = [
  "The orchestrator aggregates every context-injecting subhook into ONE Bun process so",
  "the per-edit cold-start cost is paid once instead of fifteen separate times.",
].join("\n");

const write = (file_path: string, content: string): PostToolUseInput => ({
  tool_name: "Write",
  tool_input: { file_path, content },
});

const edit = (file_path: string, old_string: string, new_string: string): PostToolUseInput => ({
  tool_name: "Edit",
  tool_input: { file_path, old_string, new_string },
});

const multiEdit = (
  file_path: string,
  edits: Array<{ old_string: string; new_string: string }>,
): PostToolUseInput => ({
  tool_name: "MultiEdit",
  tool_input: { file_path, edits } as PostToolUseInput["tool_input"],
});

const fires = async (input: PostToolUseInput): Promise<boolean> =>
  (await classifyMarkdownHardWrapReminderForPostToolUseOrchestrator(input)).kind ===
  "additional_context";

// ── Activation gate ──────────────────────────────────────────────────────────

describe("isMarkdownHardWrapReminderEligibleTarget", () => {
  it("accepts .md and .markdown on every file-edit tool", () => {
    for (const tool of ["Write", "Edit", "MultiEdit"]) {
      expect(isMarkdownHardWrapReminderEligibleTarget(tool, MD)).toBe(true);
      expect(isMarkdownHardWrapReminderEligibleTarget(tool, "/a/README.markdown")).toBe(true);
    }
  });

  it("rejects non-markdown files and non-edit tools", () => {
    expect(isMarkdownHardWrapReminderEligibleTarget("Write", "/a/main.ts")).toBe(false);
    expect(isMarkdownHardWrapReminderEligibleTarget("Bash", MD)).toBe(false);
    expect(isMarkdownHardWrapReminderEligibleTarget("Read", MD)).toBe(false);
    expect(isMarkdownHardWrapReminderEligibleTarget("Write", "")).toBe(false);
  });

  it("exempts throwaway scratch copies in a temp directory", () => {
    expect(isMarkdownHardWrapReminderEligibleTarget("Write", "/tmp/scratch-note.md")).toBe(false);
  });
});

// ── Net-new semantics: the load-bearing behaviour ────────────────────────────

describe("net-new detection", () => {
  it("fires when an Edit INTRODUCES a wrapped paragraph", async () => {
    expect(await fires(edit(MD, "", WRAPPED))).toBe(true);
  });

  it("stays SILENT when an Edit rewords inside an already-wrapped paragraph", async () => {
    // The single most important case: 17% of this repo's .md files are already
    // hard-wrapped, and touching that legacy debt must not nag.
    expect(await fires(edit(MD, WRAPPED, WRAPPED_REWORDED))).toBe(false);
  });

  it("stays SILENT when an Edit REPAIRS a wrap (count decreases)", async () => {
    expect(await fires(edit(MD, WRAPPED, UNWRAPPED))).toBe(false);
  });

  it("stays SILENT when an Edit adds unwrapped prose", async () => {
    expect(await fires(edit(MD, "", UNWRAPPED))).toBe(false);
  });

  it("fires when only a LATER edit of a MultiEdit adds a wrap", async () => {
    const input = multiEdit(MD, [
      { old_string: "alpha", new_string: "beta" },
      { old_string: "", new_string: UNWRAPPED },
      { old_string: "", new_string: WRAPPED },
    ]);
    expect(await fires(input)).toBe(true);
  });

  it("stays SILENT for a MultiEdit where no edit increases the count", async () => {
    const input = multiEdit(MD, [
      { old_string: "alpha", new_string: "beta" },
      { old_string: WRAPPED, new_string: WRAPPED_REWORDED },
    ]);
    expect(await fires(input)).toBe(false);
  });

  it("fires on a Write of wrapped content and not on unwrapped", async () => {
    // Write has no before-state at PostToolUse time, so any wrap is reported.
    expect(await fires(write(MD, WRAPPED))).toBe(true);
    expect(await fires(write(MD, UNWRAPPED))).toBe(false);
  });
});

// ── Structural markdown must not be mistaken for prose ───────────────────────

describe("structural markdown stays silent", () => {
  const cases: Record<string, string> = {
    "fenced code": ["```ts", "const aLongIdentifierName = compute(", "  argument,", ")", "```"].join(
      "\n",
    ),
    table: ["| Hook | Matcher |", "| ---- | ------- |", "| a    | Write   |"].join("\n"),
    "badge rows": [
      "[![Plugins](https://img.shields.io/badge/plugins-36-green.svg)](#plugins)",
      "[![License](https://img.shields.io/badge/license-MIT-yellow.svg)](./LICENSE)",
    ].join("\n"),
    "one line per bullet": [
      "- The first bullet is stated fully on a single line and ends with a period here.",
      "- The second bullet is likewise stated fully on one single line, ending cleanly.",
    ].join("\n"),
  };

  for (const [label, content] of Object.entries(cases)) {
    it(`does not fire on ${label}`, async () => {
      expect(await fires(write(MD, content))).toBe(false);
    });
  }
});

// ── Escape hatch + fail-open ─────────────────────────────────────────────────

describe("escape hatch and robustness", () => {
  it("MD-HARD-WRAP-OK suppresses the reminder", async () => {
    const suppressed = `<!-- MD-HARD-WRAP-OK -->\n\n${WRAPPED}`;
    expect(await fires(write(MD, suppressed))).toBe(false);
    expect(await fires(edit(MD, "", suppressed))).toBe(false);
  });

  it("is case-sensitive — a lowercase marker does not suppress", async () => {
    expect(await fires(write(MD, `<!-- md-hard-wrap-ok -->\n\n${WRAPPED}`))).toBe(true);
  });

  it("returns noop rather than throwing on malformed input", async () => {
    const malformed = { tool_name: "Edit", tool_input: {} } as PostToolUseInput;
    expect(await fires(malformed)).toBe(false);
    const noToolInput = { tool_name: "Write" } as unknown as PostToolUseInput;
    expect(await fires(noToolInput)).toBe(false);
  });

  it("detectNetNewMarkdownHardWraps reports the wraps it found", () => {
    const wraps = detectNetNewMarkdownHardWraps(edit(MD, "", WRAPPED));
    expect(wraps).toHaveLength(1);
    expect(wraps[0].line).toBe(1);
    expect(wraps[0].width).toBeGreaterThan(50);
  });
});

// ── Reminder text ────────────────────────────────────────────────────────────

describe("buildMarkdownHardWrapReminder", () => {
  const message = buildMarkdownHardWrapReminder(MD, detectNetNewMarkdownHardWraps(write(MD, WRAPPED)));

  it("names the file, the marker, and the reflow tool", () => {
    expect(message).toContain(MD);
    expect(message).toContain("MD-HARD-WRAP-OK");
    expect(message).toContain("reflow-release-notes.ts");
  });

  it("does NOT claim a repository .md renders broken (GFM spec 6.13)", () => {
    // The reminder must stay honest: soft breaks collapse to a space in a repo
    // .md; the <br> breakage is confined to release/issue/PR/comment surfaces.
    expect(message).toContain("renders fine");
    expect(message).toContain("release notes");
  });

  it("caps the listed wraps so the aggregate reason cannot blow up", () => {
    const many = Array.from({ length: 40 }, (_, i) => ({
      line: i + 1,
      width: 90,
      nextPreview: "continuation",
    }));
    const capped = buildMarkdownHardWrapReminder(MD, many);
    expect(capped).toContain("…and 37 more.");
    expect(capped.split("\n").filter((l) => l.startsWith("  L")).length).toBe(3);
  });
});

// ── Whole-file context (2026-08-22 fence false-positive fix) ─────────────────
//
// An Edit fragment lifted from INSIDE a fenced code block carries no ``` marker,
// so scanning the fragment alone reads shell commands as wrapped prose. Passing
// the post-edit file gives the fence scanner the state it needs, and the
// before-state is reconstructed by undoing the edit.

describe("whole-file context", () => {
  const CMD = [
    "bun scripts/reflow-release-notes.ts < file.md > file.new.md && mv file.new.md file.md",
    "bun scripts/reflow-release-notes.ts --check < file.md",
  ].join("\n");

  const fileWithFence = (body: string) =>
    ["# Probe", "", body, "", "```bash", CMD, "```", ""].join("\n");

  it("does NOT flag two shell lines edited inside a bash fence", () => {
    const after = fileWithFence("Some intro prose that is short.");
    const input = edit(MD, "old command here", CMD);
    expect(detectNetNewMarkdownHardWraps(input, after)).toEqual([]);
  });

  it("flags the fragment as prose when the file is UNREADABLE (fallback path)", () => {
    // Documents the degradation: without whole-file context the fence is
    // invisible, so the fallback is best-effort, not equivalent.
    const input = edit(MD, "old command here", CMD);
    expect(detectNetNewMarkdownHardWraps(input, null).length).toBeGreaterThan(0);
  });

  it("still flags genuine wrapped prose in a file that also has a fence", () => {
    const after = fileWithFence(WRAPPED);
    const input = edit(MD, "placeholder", WRAPPED);
    const wraps = detectNetNewMarkdownHardWraps(input, after);
    expect(wraps).toHaveLength(1);
    expect(wraps[0].line).toBe(3); // whole-file line number, not fragment-relative
  });

  it("reports ONLY the wraps this edit added, not the file's pre-existing ones", () => {
    const legacy = [
      "Existing wrapped prose that was already in this file before the edit ran here",
      "and continues onto a second line that nobody is proposing to fix right now.",
    ].join("\n");
    const after = [legacy, "", WRAPPED].join("\n");
    const wraps = detectNetNewMarkdownHardWraps(edit(MD, "placeholder", WRAPPED), after);
    expect(wraps).toHaveLength(1);
    expect(wraps[0].nextPreview).toContain("per-edit cold-start");
  });

  it("stays silent when the edit only reworded an existing wrapped paragraph", () => {
    const after = fileWithFence(WRAPPED_REWORDED);
    const input = edit(MD, WRAPPED, WRAPPED_REWORDED);
    expect(detectNetNewMarkdownHardWraps(input, after)).toEqual([]);
  });

  it("undoes MultiEdit replacements in reverse order", () => {
    const after = ["# Probe", "", "alpha-final", "", WRAPPED, ""].join("\n");
    const input = multiEdit(MD, [
      { old_string: "alpha", new_string: "alpha-final" },
      { old_string: "placeholder", new_string: WRAPPED },
    ]);
    expect(detectNetNewMarkdownHardWraps(input, after)).toHaveLength(1);
  });

  it("honours MD-HARD-WRAP-OK found anywhere in the file, not just the fragment", () => {
    const after = ["<!-- MD-HARD-WRAP-OK -->", "", WRAPPED].join("\n");
    expect(detectNetNewMarkdownHardWraps(edit(MD, "placeholder", WRAPPED), after)).toEqual([]);
  });
});

// ── Adversarial-review fixes (2026-08-22) ────────────────────────────────────

describe("replace_all is honoured when undoing an edit", () => {
  it("undoes EVERY occurrence so the before-state is not left half-new", () => {
    // replace_all rewrote both placeholders. Undoing only the first would leave
    // one wrapped paragraph in the "before", halving the measured delta.
    const after = ["# Doc", "", WRAPPED, "", "## Section", "", WRAPPED, ""].join("\n");
    const input: PostToolUseInput = {
      tool_name: "Edit",
      tool_input: {
        file_path: MD,
        old_string: "PLACEHOLDER",
        new_string: WRAPPED,
        replace_all: true,
      } as PostToolUseInput["tool_input"],
    };
    expect(detectNetNewMarkdownHardWraps(input, after)).toHaveLength(2);
  });

  it("without replace_all, only the first occurrence is undone", () => {
    const after = ["# Doc", "", WRAPPED, "", "## Section", "", WRAPPED, ""].join("\n");
    const input = edit(MD, "PLACEHOLDER", WRAPPED);
    expect(detectNetNewMarkdownHardWraps(input, after)).toHaveLength(1);
  });
});

describe("nested bullets reach the hook", () => {
  const NESTED = [
    "  - `github_release` is now tri-state. A 2xx or an AUTHENTICATED 4xx is an",
    "    observation; an unauthenticated 401/403/404, any 5xx, or a transport",
    "    failure is not, and is marked `indeterminate`.",
  ].join("\n");

  it("fires on a Write of hard-wrapped sub-bullets", async () => {
    expect(await fires(write(MD, NESTED))).toBe(true);
  });

  it("stays silent when the same sub-bullets are one line each", async () => {
    const clean = [
      "  - `github_release` is now tri-state, and an unauthenticated 404 is marked indeterminate.",
      "  - The exit code stays non-zero for indeterminate, because a gate that could not verify is not green.",
    ].join("\n");
    expect(await fires(write(MD, clean))).toBe(false);
  });
});
