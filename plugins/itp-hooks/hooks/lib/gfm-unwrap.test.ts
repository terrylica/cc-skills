/**
 * Tests for the GFM paragraph unwrapper.
 *
 * The organising principle: every test that asserts "this gets joined" is
 * paired with the mutation that proves the joiner CAN fail — an unexercised
 * check is not yet a check. The round-trip tests are the strongest: unwrapping
 * anything must leave the hard-wrap detector with nothing to report.
 */

import { describe, expect, test } from "bun:test";
import { detectHardWraps } from "./hard-wrap-detector.ts";
import {
  assertContentPreserved,
  normalizeForContentComparison,
  unwrapGfmParagraphs,
  unwrapGfmParagraphsDetailed,
} from "./gfm-unwrap.ts";

describe("unwrapGfmParagraphs — the core join", () => {
  test("joins a hard-wrapped prose paragraph into one line", () => {
    const input = [
      "Tony, the first answer had a hole in it. No grants because there is no company is",
      "circular, so you would incorporate if there were a reason. I re-ran the question",
      "assuming a BC corporation exists today with a business number.",
    ].join("\n");
    const out = unwrapGfmParagraphs(input);
    expect(out.split("\n")).toHaveLength(1);
    expect(out).toContain("hole in it. No grants");
    expect(out).toContain("circular, so you would");
  });

  test("preserves the blank line between two paragraphs", () => {
    const input = [
      "First paragraph that has been hard wrapped at a fixed column width and",
      "continues onto a second line here.",
      "",
      "Second paragraph that has also been hard wrapped at a fixed column and",
      "continues onto a second line too.",
    ].join("\n");
    const out = unwrapGfmParagraphs(input);
    expect(out.split("\n")).toHaveLength(3);
    expect(out.split("\n")[1]).toBe("");
  });

  test("reports how many joins it performed, and zero on already-flat text", () => {
    const flat = "This paragraph is already one single unbroken line and needs no repair at all.";
    expect(unwrapGfmParagraphsDetailed(flat).joinsPerformed).toBe(0);
    expect(unwrapGfmParagraphsDetailed("a wrapped line here\nand its continuation").joinsPerformed).toBe(1);
  });
});

describe("what must never be joined", () => {
  test("fenced code keeps every line break", () => {
    const input = ["```bash", "gh issue comment 8 \\", "  --body-file /tmp/x.md", "```"].join("\n");
    expect(unwrapGfmParagraphs(input)).toBe(input);
  });

  test("a table keeps one row per line", () => {
    const input = [
      "| Programme | Cash in | Cash out |",
      "| --------- | ------- | -------- |",
      "| Level UP  | $0      | $0       |",
    ].join("\n");
    expect(unwrapGfmParagraphs(input)).toBe(input);
  });

  test("headings are never absorbed into the paragraph below", () => {
    const input = [
      "## What actually opens if the company exists",
      "One thing is genuinely free, and everything else costs more than it pays in",
      "the first year of operating.",
    ].join("\n");
    const out = unwrapGfmParagraphs(input).split("\n");
    expect(out[0]).toBe("## What actually opens if the company exists");
    expect(out).toHaveLength(2);
  });

  test("each list item stays on its own line", () => {
    const input = [
      "- The first item, which has been hard wrapped and continues onto the",
      "  next line as a continuation of the same item.",
      "- The second item.",
    ].join("\n");
    const out = unwrapGfmParagraphs(input).split("\n");
    expect(out).toHaveLength(2);
    expect(out[0].startsWith("- The first item")).toBe(true);
    expect(out[0]).toContain("next line as a continuation");
    expect(out[1]).toBe("- The second item.");
  });

  test("an intentional markdown hard break (two trailing spaces) survives", () => {
    const input = "A line the author deliberately broke here with two spaces  \nand its next line.";
    const out = unwrapGfmParagraphs(input);
    expect(out.split("\n")).toHaveLength(2);
  });

  test("a trailing backslash hard break survives", () => {
    const input = "A line the author deliberately broke with a backslash here \\\nand its next line.";
    expect(unwrapGfmParagraphs(input).split("\n")).toHaveLength(2);
  });

  test("YAML front matter is untouched", () => {
    const input = ["---", "source: a sweep", "generated_at: 2026-08-24", "---", "", "Body text."].join("\n");
    expect(unwrapGfmParagraphs(input)).toBe(input);
  });

  test("a thematic break separates, it does not absorb", () => {
    const input = ["Some prose that is long enough to look like a wrapped paragraph line.", "", "---", "", "More prose."].join("\n");
    expect(unwrapGfmParagraphs(input)).toBe(input);
  });
});

describe("blockquotes — the case the DETECTOR misses entirely", () => {
  test("a hard-wrapped blockquote is joined and keeps exactly one marker", () => {
    const input = [
      "> Incorporate before the first activity that should legally, commercially or",
      "> tax-wise belong to the company.",
    ].join("\n");
    const out = unwrapGfmParagraphs(input);
    expect(out.split("\n")).toHaveLength(1);
    expect(out.startsWith("> ")).toBe(true);
    expect(out.match(/>/g)).toHaveLength(1);
    expect(out).toContain("commercially or tax-wise belong");
  });

  test("a bare `>` line separates two quoted paragraphs and is preserved", () => {
    const input = ["> First quoted paragraph wrapped here", "> onto a second line.", ">", "> Second quoted paragraph."].join("\n");
    const out = unwrapGfmParagraphs(input).split("\n");
    expect(out).toHaveLength(3);
    expect(out[1]).toBe(">");
  });

  test("quoted and unquoted lines are never merged across the boundary", () => {
    const input = ["> A quoted line that is long enough to look wrapped and open", "Ordinary prose immediately after the quote."].join("\n");
    const out = unwrapGfmParagraphs(input).split("\n");
    expect(out).toHaveLength(2);
    expect(out[0].startsWith(">")).toBe(true);
    expect(out[1].startsWith(">")).toBe(false);
  });
});

describe("CJK — a space between two Chinese characters is a content change", () => {
  test("joins two Chinese lines with NO inserted space", () => {
    const input = ["我愿意介绍所有客户，但前提是我们的方案、流程和对外材料", "已经足够完整成熟；在那之前，我不会贸然向客户推荐。"].join("\n");
    const out = unwrapGfmParagraphs(input);
    expect(out).toBe("我愿意介绍所有客户，但前提是我们的方案、流程和对外材料已经足够完整成熟；在那之前，我不会贸然向客户推荐。");
    expect(out).not.toContain("材料 已经");
  });

  test("still inserts a space when one side of the join is Latin", () => {
    const input = ["目前都没有使用 HSA", "PHSP 的客户大约五到六家。"].join("\n");
    expect(unwrapGfmParagraphs(input)).toBe("目前都没有使用 HSA PHSP 的客户大约五到六家。");
  });
});

describe("the content-preservation invariant", () => {
  test("normalisation ignores blockquote markers and whitespace only", () => {
    expect(normalizeForContentComparison("> a\n> b")).toBe(normalizeForContentComparison("> a b"));
    expect(normalizeForContentComparison("a  b")).toBe("a b");
  });

  test("assertContentPreserved throws when a character is dropped", () => {
    expect(() => assertContentPreserved("the quick brown fox", "the quick brown")).toThrow(/CONTENT CHANGED/);
  });

  test("assertContentPreserved throws when a character is added", () => {
    expect(() => assertContentPreserved("five or six", "five or seven")).toThrow(/CONTENT CHANGED/);
  });

  test("assertContentPreserved accepts a pure rewrap", () => {
    expect(() => assertContentPreserved("one two\nthree four", "one two three four")).not.toThrow();
  });

  test("the CJK allowance is NARROW — a space lost between CJK and Latin is still caught", () => {
    // Allowed: the join point is CJK on both sides.
    expect(() => assertContentPreserved("材料\n已经", "材料已经")).not.toThrow();
    // Not allowed: one side is Latin, so the space is real content.
    expect(() => assertContentPreserved("使用 HSA", "使用HSA")).toThrow(/CONTENT CHANGED/);
    expect(() => assertContentPreserved("HSA PHSP", "HSAPHSP")).toThrow(/CONTENT CHANGED/);
  });

  test("the CJK allowance cannot hide a DELETED Chinese character", () => {
    expect(() => assertContentPreserved("五六家公司", "五家公司")).toThrow(/CONTENT CHANGED/);
  });

  test("every unwrap in this suite preserved content by construction", () => {
    const corpus = [
      "Plain wrapped prose over\ntwo lines.",
      "- item one wrapped\n  onto a continuation\n- item two",
      "> quoted and wrapped\n> across two lines",
      "| a | b |\n| - | - |",
      "```\ncode\nblock\n```",
      "中文换行测试\n第二行内容。",
    ];
    for (const text of corpus) {
      expect(() => assertContentPreserved(text, unwrapGfmParagraphs(text))).not.toThrow();
    }
  });
});

describe("round trip — the detector must find nothing after an unwrap", () => {
  const wrapped = [
    "## Second pass",
    "",
    "Tony, the first answer had a hole in it. No grants because there is no company is",
    "circular, so you would incorporate if there were a reason. So I re-ran the whole",
    "question on the assumption that a BC corporation exists today.",
    "",
    "> Incorporate before the first activity that should legally, commercially or",
    "> tax-wise belong to the company, and no earlier than that point.",
    "",
    "- The seven thousand dollar tier is dead, and every delivery partner now reads a",
    "  flat fifty percent to five thousand dollars instead.",
    "- Financial services is not excluded from the programme at all.",
    "",
    "| Programme | Cash |",
    "| --------- | ---- |",
    "| Level UP  | $0   |",
  ].join("\n");

  test("the fixture really is hard wrapped before the fix", () => {
    expect(detectHardWraps(wrapped).length).toBeGreaterThan(0);
  });

  test("and the detector reports nothing after it", () => {
    expect(detectHardWraps(unwrapGfmParagraphs(wrapped))).toEqual([]);
  });

  test("unwrapping is idempotent", () => {
    const once = unwrapGfmParagraphs(wrapped);
    expect(unwrapGfmParagraphs(once)).toBe(once);
  });

  test("the table and the code structure survived the round trip", () => {
    const out = unwrapGfmParagraphs(wrapped);
    expect(out).toContain("| Programme | Cash |");
    expect(out).toContain("| Level UP  | $0   |");
  });
});
