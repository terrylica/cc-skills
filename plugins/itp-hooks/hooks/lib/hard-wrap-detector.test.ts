import { describe, expect, it } from "bun:test";
import { detectHardWraps } from "./hard-wrap-detector.ts";

// ── Test fixtures ─────────────────────────────────────────────────────────

const WRAPPED_PARAGRAPH_100_COLS = [
  "We are CPC, a Canadian logistics operator evaluating enterprise Android handhelds as the",
  "platform for an in-house agent-driven device-management and data-capture stack right now.",
].join("\n");

const SINGLE_LINE_PARAGRAPH =
  "We are CPC, a Canadian logistics operator evaluating enterprise Android handhelds as the platform for an in-house agent-driven device-management and data-capture stack right now.";

const CLEAN_ONE_LINE_PER_BULLET_LIST = [
  "- First item stated fully on a single line that is quite long here and ends properly.",
  "- Second item also stated fully on a single long line here, ending cleanly as well too.",
].join("\n");

const FENCED_CODE_WITH_SHORT_LINES = [
  "```typescript",
  "function hello() {",
  "  console.log('short')",
  "}",
  "```",
].join("\n");

const TABLE_WITH_SHORT_LINES = [
  "| Header | Value |",
  "| ------ | ----- |",
  "| Short  | Yes   |",
].join("\n");

const WRAPPED_BULLET_CONTINUATION = [
  "- This is a long bullet point that is intentionally wrapped at a fixed column width",
  "  and continues on the next line, which should be flagged as a wrap.",
].join("\n");

const PARAGRAPH_WITH_TERMINATOR = [
  "We are CPC, a Canadian logistics operator evaluating enterprise Android handhelds as a",
  "platform for device management. Next sentence starts here on the new line.",
].join("\n");

const BLOCKQUOTE_MULTILINE = [
  "> This is a blockquote.",
  "> It continues on the next line.",
].join("\n");

const HEADING_AND_PARAGRAPH = [
  "# My Heading",
  "This paragraph is one long line without any wrapping that goes on and on until the end.",
].join("\n");

const YAML_FRONT_MATTER_AND_PARA = [
  "---",
  "title: Test",
  "---",
  "This paragraph is one long line without wrapping that continues here.",
].join("\n");

// ── Test suite ────────────────────────────────────────────────────────────

describe("detectHardWraps", () => {
  it("flags a paragraph hard-wrapped mid-sentence at ~80 cols", () => {
    const issues = detectHardWraps(WRAPPED_PARAGRAPH_100_COLS);
    expect(issues.length).toBe(1);
    expect(issues[0]?.line).toBe(1);
    expect(issues[0]?.width).toBeGreaterThan(50);
  });

  it("passes a single unbroken paragraph line", () => {
    expect(detectHardWraps(SINGLE_LINE_PARAGRAPH)).toEqual([]);
  });

  it("passes a clean one-line-per-bullet list", () => {
    expect(detectHardWraps(CLEAN_ONE_LINE_PER_BULLET_LIST)).toEqual([]);
  });

  it("passes fenced code blocks with short lines", () => {
    expect(detectHardWraps(FENCED_CODE_WITH_SHORT_LINES)).toEqual([]);
  });

  it("passes markdown tables with short lines", () => {
    expect(detectHardWraps(TABLE_WITH_SHORT_LINES)).toEqual([]);
  });

  it("flags a wrapped bullet continuation line", () => {
    const issues = detectHardWraps(WRAPPED_BULLET_CONTINUATION);
    expect(issues.length).toBe(1);
    expect(issues[0]?.line).toBe(1); // Line 1 "ends open" and is ~80+ chars
  });

  it("does NOT flag a line that ends with a terminator (. ! ? : ;)", () => {
    // When line A ends with a period/terminator, it's the natural end of a sentence
    // and the wrap is intentional (not mid-sentence).
    const cleanTerminated = [
      "This is a complete sentence that ends with a period here.",
      "This is the next sentence that starts on a new line.",
    ].join("\n");
    expect(detectHardWraps(cleanTerminated)).toEqual([]);
  });

  it("passes blockquote lines (intentional line breaks)", () => {
    expect(detectHardWraps(BLOCKQUOTE_MULTILINE)).toEqual([]);
  });

  it("passes headings and subsequent paragraphs", () => {
    expect(detectHardWraps(HEADING_AND_PARAGRAPH)).toEqual([]);
  });

  it("passes YAML front matter with long lines", () => {
    expect(detectHardWraps(YAML_FRONT_MATTER_AND_PARA)).toEqual([]);
  });

  it("passes YAML front matter and subsequent paragraph", () => {
    expect(detectHardWraps(YAML_FRONT_MATTER_AND_PARA)).toEqual([]);
  });

  it("respects minWrapWidth option (does not flag short lines)", () => {
    const mediumWrapped = [
      "This is a line that is about 55 characters and ends open",
      "and continues on the next line without terminator here.",
    ].join("\n");
    // Default minWrapWidth is 50, so a ~55-char line should be flagged
    expect(detectHardWraps(mediumWrapped).length).toBeGreaterThan(0);
    // With minWrapWidth set to 60, this line is NOT flagged (55 < 60)
    expect(detectHardWraps(mediumWrapped, { minWrapWidth: 60 }).length).toBe(0);
  });

  it("handles \\r\\n line endings (Windows)", () => {
    const windowsWrapped = WRAPPED_PARAGRAPH_100_COLS.replace(/\n/g, "\r\n");
    expect(detectHardWraps(windowsWrapped).length).toBe(1);
  });

  it("flags multiple hard-wraps in a multiline prose block", () => {
    const multipleWraps = [
      "This is the first paragraph that is wrapped at a fixed column width right here",
      "and continues to the next line without a terminator dot.",
      "This is another paragraph also wrapped at a fixed column width somewhere",
      "and it also continues to the next line without proper termination.",
    ].join("\n");
    const issues = detectHardWraps(multipleWraps);
    expect(issues.length).toBe(2);
    expect(issues[0]?.line).toBe(1);
    expect(issues[1]?.line).toBe(3);
  });
});
