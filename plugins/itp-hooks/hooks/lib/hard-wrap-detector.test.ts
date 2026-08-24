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

// ── Markdown constructs whose line breaks are structural ────────────────────
//
// This detector began life scanning Gmail bodies, which are plain prose. Wiring
// it to `gh release`/`issue`/`pr` bodies put it in front of FULL markdown for
// the first time, and every construct below was a false positive — a DENY on
// legitimate text, which is a worse failure than missing a wrap.

describe("does not flag constructs whose newlines carry meaning", () => {
  const structural: readonly [string, string][] = [
    [
      "a setext heading underlined with =",
      "A Release That Closes Several Long Standing Loops In The Pipeline\n=================================================================\n\nBody.",
    ],
    [
      "a setext heading underlined with -",
      "A Release That Closes Several Long Standing Loops In The Pipeline\n----------------------------------------------------------------\n\nBody.",
    ],
    [
      "stacked link reference definitions",
      "[spec]: https://example.com/a/very/long/path/to/the/specification/document\n[impl]: https://example.com/another/quite/long/path/to/the/implementation",
    ],
    [
      "stacked footnote definitions",
      "[^1]: A fairly long footnote body explaining the first point in detail here\n[^2]: Another fairly long footnote body explaining the second point in detail",
    ],
    [
      "a raw HTML block",
      "<details>\n<summary>A fairly long summary line that goes past the fifty char mark</summary>\n<p>Content</p>\n</details>",
    ],
    [
      "an indented code block",
      "Example:\n\n    const aVeryLongVariableNameHere = computeSomethingImportant(withArgs)\n    const anotherVeryLongVariableName = computeSomethingElse(withMoreArgs)",
    ],
    [
      "a thematic break between two paragraphs",
      "A paragraph that runs long enough to pass the width threshold comfortably\n\n---\n\nAnother paragraph that also runs long enough to pass the width threshold.",
    ],
  ];

  for (const [name, text] of structural) {
    it(`passes ${name}`, () => {
      expect(detectHardWraps(text)).toEqual([]);
    });
  }
});

// ── CJK ─────────────────────────────────────────────────────────────────────

describe("CJK prose", () => {
  /**
   * Two bugs met here. A Chinese sentence ends on `。`, which was not in the
   * terminator set, so every correct sentence looked open-ended. And width was
   * measured in code points, so a paragraph wrapped at 72 DISPLAY columns
   * measured 36 — under minWrapWidth, therefore invisible. The two cancelled
   * out into "CJK is never flagged either way", which reads as working.
   */
  const wrappedMidClause =
    "这是一个关于量化研究的说明介绍了我们如何处理微信公众号的文章存档流程并且\n补充了对应的回归测试以防止再次出现同类问题。";

  const properlyTerminated =
    "这是关于量化研究的说明介绍我们如何处理微信公众号文章存档流程的完整方案。\n本次发布修复了若干与图片转写相关的缺陷并补充了对应的回归测试用例。";

  it("flags a Chinese paragraph wrapped mid-clause", () => {
    expect(detectHardWraps(wrappedMidClause).length).toBe(1);
  });

  it("reports the wrap in DISPLAY columns, not code points", () => {
    // 36 characters of CJK occupy 72 terminal columns.
    expect(detectHardWraps(wrappedMidClause)[0]?.width).toBe(72);
  });

  it("passes Chinese sentences that each end on a full-width stop", () => {
    expect(detectHardWraps(properlyTerminated)).toEqual([]);
  });

  it("treats other CJK clause terminators as closing a line", () => {
    for (const stop of ["！", "？", "；", "："]) {
      const text = `这是关于量化研究的说明介绍我们如何处理微信公众号文章存档的方案${stop}\n本次发布修复了若干与图片转写相关的缺陷并补充了回归测试用例。`;
      expect(detectHardWraps(text)).toEqual([]);
    }
  });
});

// ── Badge / link-only rows (2026-08-22) ──────────────────────────────────────
//
// The ONE systematic false-positive class measured over this marketplace's
// 1,114 tracked .md files: 87 of 3,389 detections were consecutive badge rows.
// Each row is wide, ends on `)` rather than a clause terminator, and is
// followed by another badge row — so every "prose that wraps" heuristic fires
// on a construct that contains no prose at all.

describe("link-only lines are structural, not wrapped prose", () => {
  const BADGE_BLOCK = [
    "[![Plugins](https://img.shields.io/badge/plugins-36-green.svg)](#plugins)",
    "[![Version](https://img.shields.io/github/package-json/v/terrylica/cc-skills.svg)](./CHANGELOG.md)",
    "[![License](https://img.shields.io/badge/license-MIT-yellow.svg)](./LICENSE)",
  ].join("\n");

  it("does not flag a run of linked shields.io badges", () => {
    expect(detectHardWraps(BADGE_BLOCK)).toEqual([]);
  });

  it("does not flag plain link-only nav rows", () => {
    const nav = [
      "[Installation Guide](./docs/installation-and-first-run-walkthrough.md)",
      "[Plugin Authoring Reference](./docs/plugin-authoring-reference.md)",
    ].join("\n");
    expect(detectHardWraps(nav)).toEqual([]);
  });

  it("does not flag prose that is followed by a badge row", () => {
    const text = [
      "This marketplace ships a large number of plugins covering many workflows here",
      "[![Plugins](https://img.shields.io/badge/plugins-36-green.svg)](#plugins)",
    ].join("\n");
    expect(detectHardWraps(text)).toEqual([]);
  });

  it("STILL flags prose that merely contains a link", () => {
    const text = [
      "See [the installation guide](./docs/install.md) for the full walkthrough of every",
      "supported platform, including the Apple Silicon notes that most people need first.",
    ].join("\n");
    expect(detectHardWraps(text)).toHaveLength(1);
  });
});

// ── Nested bullets (2026-08-22) ──────────────────────────────────────────────
//
// A sub-bullet's wrapped tail is indented 4+ spaces, which isIndentedCodeBlock
// matched — so every line of a nested bullet was read as code and skipped, and
// hard-wrapped sub-bullets were invisible to all four consumers. They reached a
// published GitHub release page looking like a column of short lines.

describe("nested list items are prose, not indented code", () => {
  const NESTED_RELEASE_NOTE = [
    "- **gates:** G1.3 no longer reports its own blindness as a failed release",
    "",
    "  - `github_release` is now tri-state. A 2xx or an AUTHENTICATED 4xx is an",
    "    observation; an unauthenticated 401/403/404, any 5xx, or a transport",
    "    failure is not, and is marked `indeterminate`.",
    "  - The exit code stays non-zero for indeterminate. A gate that could not",
    "    verify must not be green; the distinction belongs in the message, not",
    "    in the exit status.",
  ].join("\n");

  it("flags wrapped sub-bullets in release-note shaped markdown", () => {
    expect(detectHardWraps(NESTED_RELEASE_NOTE).length).toBeGreaterThan(0);
  });

  it("flags a wrapped THIRD-level bullet too", () => {
    const deep = [
      "- top",
      "  - second",
      "    - The third level item is also wrapped at a fixed column right here",
      "      and continues onto the following line, which must still be caught.",
    ].join("\n");
    expect(detectHardWraps(deep)).toHaveLength(1);
  });

  it("flags a wrapped ORDERED sub-item", () => {
    const ordered = [
      "1. top",
      "   1. The nested ordered item is wrapped at a fixed column right here so",
      "      that it continues onto the following line and must be detected.",
    ].join("\n");
    expect(detectHardWraps(ordered)).toHaveLength(1);
  });

  it("leaves nested bullets alone when each is one unbroken line", () => {
    const clean = [
      "- **gates:** G1.3 no longer reports its own blindness as a failed release.",
      "",
      "  - `github_release` is now tri-state, and an unauthenticated 404 is marked indeterminate.",
      "  - The exit code stays non-zero for indeterminate, because a gate that could not verify is not green.",
    ].join("\n");
    expect(detectHardWraps(clean)).toEqual([]);
  });

  it("STILL treats a genuine indented code block (no list context) as code", () => {
    const code = [
      "Run the following to reproduce the failure:",
      "",
      "    const aVeryLongVariableNameHere = computeSomething(argument, other)",
      "    const anotherLongVariableName = computeSomethingElse(argument, more)",
    ].join("\n");
    expect(detectHardWraps(code)).toEqual([]);
  });

  it("closes the list context on dedent, so following code is still code", () => {
    const mixed = [
      "- a bullet item",
      "",
      "Back to a paragraph at column zero which ends the list context entirely.",
      "",
      "    const aVeryLongVariableNameHere = computeSomething(argument, other)",
      "    const anotherLongVariableName = computeSomethingElse(argument, more)",
    ].join("\n");
    expect(detectHardWraps(mixed)).toEqual([]);
  });
});

// ── Blockquotes: invisible to this detector until 2026-08-24 ──────────────

describe("hard-wrapped blockquotes", () => {
  it("flags a wrapped blockquote (every continuation line looked structural before)", () => {
    const quoted = [
      "> Incorporate before the first activity that should legally, commercially or tax-wise",
      "> belong to the company, and not one day earlier than that point in time.",
    ].join("\n");
    expect(detectHardWraps(quoted).length).toBeGreaterThan(0);
  });

  it("does not flag the same quote reflowed to one line", () => {
    const quoted =
      "> Incorporate before the first activity that should legally, commercially or tax-wise belong to the company.";
    expect(detectHardWraps(quoted)).toEqual([]);
  });

  it("does not flag the quote OPENING — a depth change is structural", () => {
    const text = [
      "Here is a lead-in sentence that is easily long enough to look like a wrapped line",
      "> and here the blockquote begins, which is a new block and not a continuation.",
    ].join("\n");
    expect(detectHardWraps(text)).toEqual([]);
  });

  it("does not flag a bulleted list inside a blockquote", () => {
    const text = [
      "> - the first quoted bullet, long enough that its width passes the threshold easily",
      "> - the second quoted bullet, also long enough to pass the width threshold here",
    ].join("\n");
    expect(detectHardWraps(text)).toEqual([]);
  });

  it("does not flag across a nesting change", () => {
    const text = [
      "> an outer quote line long enough to be measured for a wrap at this width here",
      "> > a nested quote line, which is a different block and not a continuation of it",
    ].join("\n");
    expect(detectHardWraps(text)).toEqual([]);
  });

  it("does not flag across a bare `>` paragraph separator", () => {
    const text = [
      "> the first quoted paragraph, long enough to be measured for a wrap at this width",
      ">",
      "> the second quoted paragraph, also long enough to be measured at this width here",
    ].join("\n");
    expect(detectHardWraps(text)).toEqual([]);
  });
});

// ── Over-blocking: the false positives that get a guard deleted ───────────

describe("must NOT be reported as hard wraps", () => {
  it("a stack of bare source URLs", () => {
    const text = [
      "https://www.canada.ca/en/revenue-agency/services/tax/technical-information/income-tax.html",
      "https://www.ontario.ca/page/connect-ministry-finance-office-advisory-services-branch.html",
    ].join("\n");
    expect(detectHardWraps(text)).toEqual([]);
  });

  it("an autolink in angle brackets", () => {
    const text = [
      "<https://www.insurancecouncilofbc.com/licensee-directory/individual-search-page>",
      "<https://www.insurancecouncilofbc.com/licensee-directory/agency-search-landing>",
    ].join("\n");
    expect(detectHardWraps(text)).toEqual([]);
  });

  it("a signature block written with explicit two-space hard breaks", () => {
    const text = [
      "Terry Li, on behalf of the research repository for this venture  ",
      "Vancouver, British Columbia, Canada, and reachable at the address below  ",
      "Sent because the Ministry's contact page names Advisory Services",
    ].join("\n");
    expect(detectHardWraps(text)).toEqual([]);
  });

  it("a backslash hard break", () => {
    const text = [
      "The first line of an address block that is comfortably past the width floor \\",
      "the second line of that same address block, also past the width floor here",
    ].join("\n");
    expect(detectHardWraps(text)).toEqual([]);
  });

  it("a pipe-less GFM table", () => {
    const text = [
      "Programme                                   | Cash in | Cash out",
      "------------------------------------------- | ------- | --------",
      "Riipen Level UP, the only genuinely free one | $0      | $0",
      "SWPP through any one of the four channels    | $5,000  | $13,000",
    ].join("\n");
    expect(detectHardWraps(text)).toEqual([]);
  });

  it("but a genuinely wrapped paragraph beside a URL line is still caught", () => {
    const text = [
      "https://www.canada.ca/en/revenue-agency/services/tax/technical-information.html",
      "",
      "This paragraph really is hard wrapped at a fixed column and must still be",
      "reported, because exempting URLs must not exempt the prose around them.",
    ].join("\n");
    expect(detectHardWraps(text).length).toBeGreaterThan(0);
  });
});
