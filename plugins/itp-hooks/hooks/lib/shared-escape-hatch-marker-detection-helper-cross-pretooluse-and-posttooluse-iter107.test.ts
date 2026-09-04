/**
 * Unit tests for the markdown-aware escape-hatch detection added for issue #106.
 *
 * The two pre-existing entry points (`detectEscapeHatchMarkerCoveringTargetSourceLine`
 * and `hasFileWideEscapeHatchMarkerInContent`) are pinned by the iter-107 bash
 * regression test in `tasks/tests/` and are deliberately NOT changed here — a
 * Bash command that contains a marker can only contain it because the operator
 * typed it, so plain substring matching stays correct for those callers.
 *
 * Every fixture assembles the marker at run time instead of spelling it. A file
 * about suppression tokens is the last place you want an accidental one.
 */

import { describe, expect, test } from "bun:test";
import {
  hasFileWideEscapeHatchMarkerInContent,
  hasMarkdownCommentInvokedEscapeHatchMarkerInMarkdownContent,
} from "./shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";

const MARKER = ["MD-HARD-WRAP", "OK"].join("-");
const TICK = "`";
const cfg = { markerNameTokenIncludingSuffix: MARKER };
const invoked = (content: string) =>
  hasMarkdownCommentInvokedEscapeHatchMarkerInMarkdownContent(content, cfg);

describe("invoking the hatch", () => {
  test("a one-line HTML comment", () => {
    expect(invoked(`<!-- ${MARKER} -->\n\nbody`)).toBe(true);
  });

  test("a one-line HTML comment carrying a reason", () => {
    expect(invoked(`<!-- ${MARKER}: the line breaks are the content -->\n\nbody`)).toBe(true);
  });

  test("a multi-line comment with the marker on its own line", () => {
    // The shape of ~/own/amonic's ADR: `<!--` alone, marker on line 2.
    expect(invoked(["<!--", `${MARKER}: house convention for ADRs in this dir.`, "-->", "", "body"].join("\n"))).toBe(
      true,
    );
  });

  test("a multi-line comment whose interior quotes code in backticks", () => {
    // The shape of ~/eon/ccmax-monitor's PROVENANCE.md.
    expect(
      invoked(
        [
          `<!-- ${MARKER}: git-ignored (${TICK}git check-ignore -v${TICK} →`,
          `     ${TICK}.git/info/exclude:15${TICK}), never pushed. -->`,
          "",
          "body",
        ].join("\n"),
      ),
    ).toBe(true);
  });

  test("an unterminated comment still counts, to end of file", () => {
    // Mirrors the fence scanner: an opener with no closer means the operator
    // meant everything after it to be a comment.
    expect(invoked(`<!--\n${MARKER}\n\nbody with no closer`)).toBe(true);
  });

  test("a stray unmatched backtick ABOVE the comment does not break it", () => {
    // The whole reason inline-code stripping is per line: a whole-file stripper
    // pairs this stray tick with the first tick inside the comment and eats the
    // opener. 19 of this repo's 1,094 tracked .md files carry an odd tick count.
    const content = [
      `A line with one stray tick: ${TICK}oops.`,
      "",
      `<!-- ${MARKER}: quoting ${TICK}a command${TICK} inside the reason. -->`,
    ].join("\n");
    expect(content.replace(/(`+)[\s\S]*?\1/g, " ")).not.toContain("<!--"); // the naive fix fails
    expect(invoked(content)).toBe(true); // the per-line one does not
  });
});

describe("merely mentioning the marker", () => {
  const mentions: Record<string, string> = {
    "bare in prose": `Override: add ${MARKER} to the file when the wrapping is deliberate.`,
    "in an inline-code span": `Escape hatch: ${TICK}${MARKER}${TICK}.`,
    "as a comment inside an inline-code span": `e.g. ${TICK}<!-- ${MARKER} -->${TICK}`,
    "in a table cell": `| ${TICK}${MARKER}${TICK} | Markdown hard-wrap reminder |`,
    "in a fenced code block": [TICK.repeat(3), `<!-- ${MARKER} -->`, TICK.repeat(3)].join("\n"),
    "in a tilde-fenced code block": ["~~~", `<!-- ${MARKER} -->`, "~~~"].join("\n"),
    "in a 4-space-indented code block": `Example:\n\n    <!-- ${MARKER} -->\n`,
    "in a tab-indented code block": `Example:\n\n\t<!-- ${MARKER} -->\n`,
    "in a heading": `## ${MARKER}`,
  };

  for (const [label, content] of Object.entries(mentions)) {
    test(`does not suppress: ${label}`, () => {
      // Each one DOES trip the old whole-file substring match — that is the bug.
      expect(hasFileWideEscapeHatchMarkerInContent(content, cfg)).toBe(true);
      expect(invoked(content)).toBe(false);
    });
  }

  test("an HTML comment that does not contain the marker", () => {
    expect(invoked("<!-- just a note -->\n\nbody")).toBe(false);
  });

  test("empty and marker-free content", () => {
    expect(invoked("")).toBe(false);
    expect(invoked("# Title\n\nbody")).toBe(false);
  });
});

describe("configuration knobs still apply", () => {
  test("case-sensitive by default", () => {
    expect(invoked(`<!-- ${MARKER.toLowerCase()} -->`)).toBe(false);
  });

  test("CASE_INSENSITIVE when asked", () => {
    expect(
      hasMarkdownCommentInvokedEscapeHatchMarkerInMarkdownContent(`<!-- ${MARKER.toLowerCase()} -->`, {
        ...cfg,
        caseSensitivityMode: "CASE_INSENSITIVE",
      }),
    ).toBe(true);
  });

  test("a minimum-reason gate rejects a bare marker and accepts a reasoned one", () => {
    const withGate = { ...cfg, requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10 };
    expect(hasMarkdownCommentInvokedEscapeHatchMarkerInMarkdownContent(`<!-- ${MARKER} -->`, withGate)).toBe(false);
    expect(
      hasMarkdownCommentInvokedEscapeHatchMarkerInMarkdownContent(
        `<!-- ${MARKER}: a genuinely stated reason -->`,
        withGate,
      ),
    ).toBe(true);
  });
});

describe("CRLF and offset bookkeeping", () => {
  test("a CRLF document behaves like an LF one", () => {
    expect(invoked(`# Title\r\n\r\n<!-- ${MARKER} -->\r\n\r\nbody`)).toBe(true);
  });

  test("the marker after a fence is still found (offsets survive blanking)", () => {
    const content = [
      TICK.repeat(3),
      "some code with a ` stray tick",
      TICK.repeat(3),
      "",
      `<!-- ${MARKER} -->`,
    ].join("\n");
    expect(invoked(content)).toBe(true);
  });
});
