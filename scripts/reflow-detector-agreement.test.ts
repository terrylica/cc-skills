/**
 * The fixer and the checker must agree.
 *
 * Two things now state the "what counts as a hard wrap" rule:
 *
 *   - scripts/reflow-release-notes.ts   — REPAIRS a body on cc-skills' own publish path
 *   - plugins/itp-hooks/hooks/lib/hard-wrap-detector.ts — BLOCKS a wrapped body on any
 *     `gh release|issue|pr` command, in any repository
 *
 * They are deliberately separate: one rewrites text, the other reports on it, and merging
 * them would trade a real risk against a cosmetic one. What must NOT happen is the two
 * drifting apart — a reflow the guard still rejects would make the repo's own release path
 * unrunnable, and a wrap the reflow leaves behind that the guard cannot see would let the
 * v2.4.0 class of defect through again.
 *
 * So this pins the contract between them, in one direction that matters:
 *
 *     detectHardWraps(reflowMarkdown(anything)) === []
 *
 * If either side changes its idea of a structural element, this fails.
 */

import { describe, expect, it } from "bun:test";
import { reflowMarkdown, isAlreadyFlat } from "./reflow-release-notes.ts";
import { detectHardWraps } from "../plugins/itp-hooks/hooks/lib/hard-wrap-detector.ts";

/** Verbatim from the quantml v2.4.0 body as it was first published — wrapped at ~100 columns. */
const REAL_V240_BODY = [
  "This release is about closing loops that were left open on purpose, and discovering that two of them",
  "were load-bearing. Three items had been written down as rules and never built — a floor that would",
  "have caught a silent index collapse, a hub list everyone knew was stale, and a shared reader for a",
  "pattern duplicated forty-three times. Building them was supposed to be housekeeping.",
  "",
  "### Added",
  "",
  "- **`pipeline/shared/json_file_reader.ts`** — the one home for reading JSON off disk, and the",
  "  counterpart to the existing atomic writer. `readRequiredJsonFile` (missing is a bug),",
  "  `readOptionalJsonFile` (missing is legitimate, corrupt never is).",
  "- **`selectSurvivingCopy`** — the dedup tool's survivor rule, extracted and exported. 8 tests,",
  "  including the regression.",
  "",
  "### Verification",
  "",
  "`moon run repo:typecheck repo:test` clean: 826 tests across 55 files, 0 failures. Stage 01 exercised",
  "live against the real archive.",
].join("\n");

/** Words survive a reflow; only the newlines between them are meant to change. */
const wordCount = (s: string): number => s.split(/\s+/).filter(Boolean).length;

const CORPUS: readonly [string, string][] = [
  ["the real v2.4.0 body", REAL_V240_BODY],
  [
    "a bare wrapped paragraph",
    "We are evaluating enterprise handhelds as the platform for an in-house\nagent-driven device-management stack, and the decision is not obvious.",
  ],
  [
    "a wrapped bullet, the case everyone misses",
    "- This bullet was wrapped at a fixed column width and its tail belongs\n  to the same item rather than starting a new block.",
  ],
  [
    "a heading immediately above wrapped prose",
    "## What changed\n\nThe stage now halts when a source kind had inputs available and\ncontributed zero chunks to the index.",
  ],
  [
    "a table followed by wrapped prose",
    "| Stage | Chunks |\n| ----- | ------ |\n| 10    | 476    |\n\nThe counts above are re-derived on every build rather than\ncarried forward from the previous report.",
  ],
  [
    "a fenced block whose contents must not be touched",
    "```ts\nconst winner = selectSurvivingCopy(group, byEvidence)\nif (!winner) throw new Error('a group always has a survivor')\n```\n\nAnd some prose after the fence that happens to be wrapped\nacross two lines here.",
  ],
  [
    "a blockquote above wrapped prose",
    "> Absent is not the same as broken.\n\nThe distinction is not stylistic — it is the shape of the trap where a\nloader read one of two files and reported the two cases identically.",
  ],
];

describe("reflowMarkdown output always satisfies detectHardWraps", () => {
  for (const [name, wrapped] of CORPUS) {
    it(`leaves no detectable wrap in ${name}`, () => {
      expect(detectHardWraps(reflowMarkdown(wrapped))).toEqual([]);
    });
  }
});

describe("the corpus is load-bearing", () => {
  /**
   * Without this, every case above would pass if `detectHardWraps` returned `[]` for
   * everything. At least the prose cases must be wrapped in the first place.
   */
  it("the real v2.4.0 body is detected as wrapped BEFORE reflowing", () => {
    expect(detectHardWraps(REAL_V240_BODY).length).toBeGreaterThan(0);
  });

  it("the real v2.4.0 body is not already flat", () => {
    expect(isAlreadyFlat(REAL_V240_BODY)).toBe(false);
  });
});

describe("reflowing is idempotent and does not disturb clean text", () => {
  it("a second reflow changes nothing", () => {
    const once = reflowMarkdown(REAL_V240_BODY);
    expect(reflowMarkdown(once)).toBe(once);
  });

  it("already-flat text is passed through and stays undetected", () => {
    const flat = reflowMarkdown(REAL_V240_BODY);
    expect(isAlreadyFlat(flat)).toBe(true);
    expect(detectHardWraps(flat)).toEqual([]);
  });

  it("reflowing loses no words", () => {
    expect(wordCount(reflowMarkdown(REAL_V240_BODY))).toBe(wordCount(REAL_V240_BODY));
  });
});
