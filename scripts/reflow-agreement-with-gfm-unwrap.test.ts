/**
 * Two unwrappers exist in this marketplace. This file is why that is allowed.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  The boundary
 * ════════════════════════════════════════════════════════════════════════
 *
 *   scripts/reflow-release-notes.ts          → the PUBLISH path
 *     `reflowMarkdown()` converts commit bodies into a release body. Wired into
 *     release.config.cjs. Emits a trailing newline and collapses blank runs,
 *     because it produces a whole document.
 *
 *   plugins/itp-hooks/hooks/lib/gfm-unwrap.ts → the REPAIR path
 *     `unwrapGfmParagraphs()` repairs an arbitrary body the hard-wrap guard has
 *     already rejected. It additionally handles blockquotes and CJK joins, and
 *     it asserts content preservation and THROWS rather than return a body
 *     whose characters changed — because it is pointed at published documents
 *     that quote regulators and named people.
 *
 * They are not merged because the publish path is load-bearing for every release
 * in this repository and rewriting it to gain two features it does not need
 * would be a poor trade. But two implementations of one transformation drift,
 * and drift is exactly the failure this marketplace keeps recording.
 *
 * So: they must AGREE on everything both of them claim to handle. Where they
 * deliberately differ, that difference is asserted too — a documented,
 * test-pinned difference is a decision; an undocumented one is a bug waiting.
 */

import { describe, expect, test } from "bun:test";
import { reflowMarkdown } from "./reflow-release-notes.ts";
import { unwrapGfmParagraphs } from "../plugins/itp-hooks/hooks/lib/gfm-unwrap.ts";
import { detectHardWraps } from "../plugins/itp-hooks/hooks/lib/hard-wrap-detector.ts";

/** Compare ignoring the trailing-newline convention the publish path adds. */
const same = (a: string, b: string) => a.replace(/\s+$/, "") === b.replace(/\s+$/, "");

const SHARED_CASES: readonly [string, string][] = [
  ["a wrapped paragraph", "A paragraph that was wrapped\nat a column by a formatter."],
  ["two paragraphs", "First para line one\nline two\n\nSecond para line one\nline two"],
  ["a wrapped bullet", "- a bullet whose text was wrapped\n  onto a second line"],
  ["sibling bullets", "- first bullet\n- second bullet"],
  ["an ordered list", "1. wrapped ordered\n   item text"],
  ["a fenced block", "```bash\nline one\nline two\n```"],
  ["a table", "| a | b |\n| --- | --- |\n| 1 | 2 |"],
  ["a heading over prose", "# Title\nprose under it\n\n---"],
  [
    "a hand-aligned block (the v27.0.1 incident)",
    "  alpha        maps to one\n  beta         maps to two\n  gamma        maps to three",
  ],
];

describe("the two unwrappers agree on every case both handle", () => {
  test.each(SHARED_CASES)("%s", (_name, input) => {
    expect(same(reflowMarkdown(input), unwrapGfmParagraphs(input))).toBe(true);
  });
});

describe("and both leave the detector with nothing to report", () => {
  test.each(SHARED_CASES)("%s", (_name, input) => {
    expect(detectHardWraps(reflowMarkdown(input))).toEqual([]);
    expect(detectHardWraps(unwrapGfmParagraphs(input))).toEqual([]);
  });
});

describe("documented, deliberate differences", () => {
  test("only the repair path unwraps a hard-wrapped blockquote", () => {
    const quoted = [
      "> Incorporate before the first activity that should legally or commercially",
      "> belong to the company, and not one day earlier than that.",
    ].join("\n");
    // Publish path: leaves it alone (a release body rarely wraps a quote).
    expect(reflowMarkdown(quoted).trim().split("\n")).toHaveLength(2);
    // Repair path: joins it, because a published comment quotes sources constantly.
    expect(unwrapGfmParagraphs(quoted).split("\n")).toHaveLength(1);
  });

  test("only the repair path joins CJK without inserting a space", () => {
    const chinese = "我愿意介绍所有客户，但前提是我们的方案\n已经足够完整成熟。";
    expect(unwrapGfmParagraphs(chinese)).toBe("我愿意介绍所有客户，但前提是我们的方案已经足够完整成熟。");
    expect(reflowMarkdown(chinese)).toContain("方案 已经");
  });

  /**
   * Found BY this agreement test on the day it was written, which is the whole
   * argument for having it.
   *
   * `reflowMarkdown` pushes standalone lines through `.replace(/\s+$/, "")`, so
   * an author's two-space hard break — the one explicit way markdown has of
   * saying "break here on purpose" — is deleted on the way to a release body.
   *
   * Left as-is rather than fixed, deliberately and narrowly: GitHub renders
   * release bodies with `breaks: true`, so the newline still becomes a `<br>`
   * and the published page is identical either way. It is only wrong on a
   * renderer that honours CommonMark strictly. The repair path preserves it
   * because the bodies it touches are read in more places than GitHub.
   *
   * If `reflowMarkdown` ever feeds a non-GitHub renderer, this becomes a defect
   * and this test is where that is written down.
   */
  test("the publish path deletes an explicit two-space break; the repair path keeps it", () => {
    const src = "line one keeps its break  \nline two";
    expect(reflowMarkdown(src)).not.toContain("break  \n");
    expect(unwrapGfmParagraphs(src)).toContain("break  \n");
  });

  test("only the repair path refuses to return a body whose content changed", () => {
    const { assertContentPreserved } = require("../plugins/itp-hooks/hooks/lib/gfm-unwrap.ts");
    expect(() => assertContentPreserved("five or six", "five or seven")).toThrow(/CONTENT CHANGED/);
  });
});
