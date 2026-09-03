/**
 * Tests for the PR-review citation-evidence guard.
 *
 * THE FALSE-POSITIVE TESTS ARE THE IMPORTANT HALF.
 *
 * A guard that fires on "LGTM", "rebased onto main", a one-line question, or a PR description gets
 * switched off within a week, and then it protects nothing. Every `allow` case below is therefore
 * load-bearing: it is the evidence that the guard is narrow enough to survive. The positive cases
 * only show it can fire at all.
 */

import { describe, expect, test } from "bun:test";
import {
  findCitationGaps,
  hasVerbatimQuote,
  targetsAPrReviewSurface,
} from "./pretooluse-pr-citation-evidence-guard.ts";

const body = (text: string) => ({ label: "--body (inline)", text });

describe("surface scoping", () => {
  test.each([
    ["gh pr comment 12 --body 'x'", true],
    ["gh pr review 12 --approve -b 'x'", true],
    ["gh api repos/o/r/pulls/12/comments -f body='x'", true],
    ["gh api repos/o/r/pulls/12/reviews -f body='x'", true],
    ["gh api repos/o/r/issues/12/comments -f body='x'", true],
    // Real command positions: after a separator, and behind env assignments or a wrapper.
    ["cd /tmp && gh pr comment 12 --body 'x'", true],
    ["set -e; gh pr review 12 -b 'x'", true],
    ["GH_TOKEN=abc gh pr comment 12 --body 'x'", true],
    ["env GH_HOST=github.com gh pr comment 12 --body 'x'", true],
    ["make notes | gh pr comment 12 --body-file -", true],
  ])("covers %s", (cmd, want) => {
    expect(targetsAPrReviewSurface(cmd as string)).toBe(want);
  });

  test.each([
    // A PR description is authored BEFORE review; it is not a resolution OF review feedback.
    ["gh pr create --title t --body 'this is the idiomatic approach'", false],
    ["gh pr edit 12 --body 'this is the idiomatic approach'", false],
    ["gh issue comment 12 --body 'this is best practice'", false],
    ["gh release create v1 --notes 'the canonical approach'", false],
    ["git commit -m 'use the idiomatic form'", false],
    // Merely MENTIONING the command must not match — writing this very documentation, or grepping.
    // `gh` here sits mid-sentence inside a quoted string, not at a command position.
    ["echo 'we should run gh pr review later'", false],
    ["grep -r 'gh pr comment' plugins/", false],
    ["git commit -m 'document the gh pr review guard'", false],
  ])("does not cover %s", (cmd, want) => {
    expect(targetsAPrReviewSurface(cmd as string)).toBe(want);
  });
});

describe("fires — a normative claim with no source at all", () => {
  test("best practice, no URL", () => {
    const f = findCitationGaps(body("Switched to a context manager; this is best practice."));
    expect(f?.kind).toBe("normative-claim-without-source");
    expect(f?.detail).toContain("best practice");
  });

  test("state of the art, no URL", () => {
    expect(findCitationGaps(body("This is the state-of-the-art way to do it."))?.kind).toBe(
      "normative-claim-without-source",
    );
  });

  test("names every claim it found, so the author can see the whole ask", () => {
    const f = findCitationGaps(body("This is best practice and the idiomatic form."));
    expect(f?.detail).toContain("best practice");
    expect(f?.detail).toContain("idiomatic");
  });
});

describe("fires — a source with no verbatim quote", () => {
  test("URL present, nothing quoted", () => {
    const f = findCitationGaps(
      body("This is the idiomatic approach — see https://peps.python.org/pep-0343/ for details."),
    );
    expect(f?.kind).toBe("source-without-verbatim-quote");
    expect(f?.detail).toContain("1 URL");
  });

  test("a bare symbol in backticks is NOT a quote", () => {
    // Without the length floor this case would pass and condition 2 would be unreachable.
    const f = findCitationGaps(
      body("Idiomatic per https://peps.python.org/pep-0343/ — use `with` here."),
    );
    expect(f?.kind).toBe("source-without-verbatim-quote");
  });
});

describe("allows — the cases that decide whether this guard survives", () => {
  test.each([
    "LGTM",
    "Rebased onto main.",
    "Done — pushed as abc1234.",
    "Why does this need a lock?",
    "Fixed the typo, thanks.",
    "This is faster: 1.2s vs 4.8s on the same input.", // a measurement claim, not an authority claim
    "Moved the guard after the checksum short-circuit as you suggested.",
  ])("no normative claim: %s", (text) => {
    expect(findCitationGaps(body(text as string))).toBeNull();
  });

  test("a normative claim WITH a URL and a blockquote passes", () => {
    const text = [
      "This is the idiomatic form. From PEP 343:",
      "",
      "> The with statement is intended to make it easier to use try/finally blocks.",
      "",
      "https://peps.python.org/pep-0343/",
    ].join("\n");
    expect(findCitationGaps(body(text))).toBeNull();
  });

  test("a fenced block counts as a quote", () => {
    const text = [
      "Best practice per the spec — https://example.org/spec",
      "```",
      "Implementations shall reject a message whose length field exceeds the frame.",
      "```",
    ].join("\n");
    expect(findCitationGaps(body(text))).toBeNull();
  });

  test("a long inline-code span counts as a quote", () => {
    const text =
      'Idiomatic — https://example.org/doc says "the receiver must not retry a rejected frame".';
    expect(findCitationGaps(body(text))).toBeNull();
  });
});

describe("hasVerbatimQuote", () => {
  test("an empty blockquote marker is not a quote", () => {
    expect(hasVerbatimQuote("> ")).toBe(false);
  });

  test("a short blockquote is not a quote", () => {
    expect(hasVerbatimQuote("> yes")).toBe(false);
  });

  test("a long blockquote is", () => {
    expect(hasVerbatimQuote("> the receiver must not retry a rejected frame")).toBe(true);
  });

  test("an empty fenced block is not", () => {
    expect(hasVerbatimQuote("```\n\n```")).toBe(false);
  });

  test("curly quotes are recognised, since a rendered page yields them", () => {
    expect(hasVerbatimQuote("“the receiver must not retry a rejected frame”")).toBe(true);
  });
});

describe("NEGATIVE CONTROL — the detector must be capable of BOTH answers on near-identical input", () => {
  /**
   * A guard tested only on inputs it rejects has not been shown to discriminate. These two bodies
   * differ by ONE added blockquote; the verdict must flip. If both ever return the same answer,
   * the predicate has gone constant and every assertion above is decoration.
   */
  const withoutQuote = "This is the idiomatic approach — https://peps.python.org/pep-0343/";
  const withQuote = `${withoutQuote}\n\n> The with statement is intended to make it easier to use try/finally blocks.`;

  test("the pair discriminates", () => {
    const a = findCitationGaps(body(withoutQuote));
    const b = findCitationGaps(body(withQuote));
    expect(a).not.toBeNull();
    expect(b).toBeNull();
    expect(a?.kind).toBe("source-without-verbatim-quote");
  });
});
