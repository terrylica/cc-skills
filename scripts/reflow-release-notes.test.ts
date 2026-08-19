/**
 * Tests for the release-notes reflow.
 *
 * These assert against the SHIPPED functions, imported from the module under test. The doctrine's
 * stated failure mode is a reflow that folds paragraphs correctly while leaving bullets broken, so
 * the wrapped-LIST-ITEM cases below are the ones that actually matter — a suite that only checked
 * paragraphs would pass against exactly the bug the doctrine warns about.
 */
import { describe, it, expect } from "bun:test";
import { reflowMarkdown, isAlreadyFlat, normalizeForCompare } from "./reflow-release-notes.ts";

describe("reflowMarkdown — paragraphs", () => {
  it("folds a wrapped paragraph onto one line", () => {
    const wrapped = "A paragraph that was\nwrapped at a column\nby a formatter.\n";
    expect(reflowMarkdown(wrapped).trim()).toBe("A paragraph that was wrapped at a column by a formatter.");
  });

  it("keeps blank lines as the ONLY paragraph separator", () => {
    const src = "First para line one\nline two\n\nSecond para line one\nline two\n";
    expect(reflowMarkdown(src).trim()).toBe("First para line one line two\n\nSecond para line one line two");
  });

  it("leaves already-flat prose byte-identical in content", () => {
    const flat = "One long line that was never wrapped and should survive untouched.\n";
    expect(normalizeForCompare(reflowMarkdown(flat))).toBe(normalizeForCompare(flat));
  });
});

describe("reflowMarkdown — LIST ITEMS (the case everyone misses)", () => {
  it("folds a wrapped bullet back onto its marker", () => {
    const src = "- a bullet whose text was\n  wrapped onto a second line\n";
    expect(reflowMarkdown(src).trim()).toBe("- a bullet whose text was wrapped onto a second line");
  });

  it("does NOT merge two separate bullets", () => {
    // The failure this guards: treating every non-blank line as joinable would glue the list into
    // one bullet, which is a worse corruption than the wrapping it was trying to fix.
    const src = "- first bullet\n- second bullet\n";
    expect(reflowMarkdown(src).trim()).toBe("- first bullet\n- second bullet");
  });

  it("handles ordered lists and the * / + markers", () => {
    expect(reflowMarkdown("1. wrapped ordered\n   item text\n").trim()).toBe("1. wrapped ordered item text");
    expect(reflowMarkdown("* star bullet\n  tail\n").trim()).toBe("* star bullet tail");
    expect(reflowMarkdown("+ plus bullet\n  tail\n").trim()).toBe("+ plus bullet tail");
  });

  it("starts a new block at a heading that follows a list", () => {
    const src = "- bullet with\n  a tail\n\n## Heading\n";
    expect(reflowMarkdown(src).trim()).toBe("- bullet with a tail\n\n## Heading");
  });
});

describe("reflowMarkdown — structure that must survive verbatim", () => {
  it("never touches fenced code", () => {
    const src = "```bash\nline one\nline two\n```\n";
    expect(reflowMarkdown(src).trim()).toBe("```bash\nline one\nline two\n```");
  });

  it("keeps table rows one per line", () => {
    const src = "| a | b |\n| --- | --- |\n| 1 | 2 |\n";
    expect(reflowMarkdown(src).trim()).toBe("| a | b |\n| --- | --- |\n| 1 | 2 |");
  });

  it("keeps headings and horizontal rules standalone", () => {
    const src = "# Title\nprose under it\n\n---\n";
    expect(reflowMarkdown(src).trim()).toBe("# Title\nprose under it\n\n---");
  });

  it("respects an explicit two-space hard break", () => {
    // A trailing double space is markdown's deliberate line break; folding it would destroy intent.
    const src = "line with break  \nnext line\n";
    expect(reflowMarkdown(src)).toContain("line with break\n");
  });
});

describe("isAlreadyFlat — the gate used by the publisher", () => {
  it("is false for wrapped prose and true after reflowing it", () => {
    const wrapped = "some prose that was\nwrapped\n";
    expect(isAlreadyFlat(wrapped)).toBe(false);
    expect(isAlreadyFlat(reflowMarkdown(wrapped))).toBe(true);
  });

  it("is false for a wrapped BULLET even when every paragraph is flat", () => {
    // Mutation-style guard: this is precisely the state a paragraph-only reflow would call clean.
    const src = "A flat paragraph.\n\n- a bullet that was\n  wrapped\n";
    expect(isAlreadyFlat(src)).toBe(false);
  });

  it("ignores a trailing-newline difference, which GitHub adds on stored bodies", () => {
    const body = "Flat line.\n";
    expect(isAlreadyFlat(`${body}\n\n`)).toBe(true);
  });
});

/**
 * Hand-aligned blocks.
 *
 * CommonMark says an indented-by-less-than-four block is ordinary paragraph text, so the
 * reflow was joining aligned rows into one line — correct markdown, wrong output. Found on
 * v27.0.1, whose commit body maps eleven redacted identifiers in a 2-space-indented table
 * that reflowed into a single ~500-character line.
 */
describe("reflowMarkdown — hand-aligned blocks", () => {
  const TABLE = ["  alpha      -> one", "  beta       -> two", "  gamma-long -> three"].join("\n");

  it("preserves an indented mapping table row-by-row", () => {
    expect(reflowMarkdown(`${TABLE}\n`).trimEnd()).toBe(TABLE);
  });

  it("still folds the prose around the table", () => {
    const src = `Intro that was\nwrapped.\n\n${TABLE}\n\nOutro that was\nwrapped.\n`;
    const out = reflowMarkdown(src);
    expect(out).toContain("Intro that was wrapped.");
    expect(out).toContain("Outro that was wrapped.");
    expect(out).toContain(TABLE);
  });

  it("does NOT strand a wrapped bullet continuation, which is merely indented", () => {
    // The false positive this pattern is narrowed to avoid: indentation alone must not
    // preserve a line, or every wrapped bullet stays broken — the exact bug the reflow exists
    // to fix. A continuation has no internal run of 2+ spaces, so it still folds.
    const src = "- a bullet that was\n  wrapped onto the next line\n";
    expect(reflowMarkdown(src).trimEnd()).toBe("- a bullet that was wrapped onto the next line");
  });

  it("treats an indented line with aligned columns as a table, not bullet prose", () => {
    const src = "- a bullet\n\n  key        value\n  other      thing\n";
    const out = reflowMarkdown(src);
    expect(out).toContain("  key        value\n  other      thing");
  });

  it("leaves a fenced block alone regardless, since fences already win", () => {
    const src = "```\n  a    b\n  c    d\n```\n";
    expect(reflowMarkdown(src).trimEnd()).toBe(src.trimEnd());
  });
});
