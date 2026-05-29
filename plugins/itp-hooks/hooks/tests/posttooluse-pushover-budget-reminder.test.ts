#!/usr/bin/env bun
/**
 * Fixture-backed regression tests for the Pushover budget reminder detector.
 *
 * The 51 fixtures under ./pushover-budget-fixtures/ were generated and
 * adversarially verified by a multi-subagent spike workflow (Python / Go /
 * TypeScript / Bash; positive / negative / edge categories). Each fixture
 * carries an `expected` verdict (DETECT | NO_DETECT) in manifest.json.
 *
 * The detector trades recall for precision on a few documented edge cases
 * (dynamic-URL-via-variable, library-instantiation split across variable
 * scope) that genuinely require AST-level analysis. Those are listed in
 * KNOWN_ACCEPTABLE_MISSES so the suite stays honest (no silent caps): a miss
 * outside that allowlist fails the suite, and a fixture that STOPS missing is
 * flagged so the allowlist can shrink.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";
import { detectPushoverMessageConstruction } from "../posttooluse-pushover-budget-reminder.ts";

const FIXTURE_DIR = join(import.meta.dir, "pushover-budget-fixtures");

interface ManifestEntry {
  language: string;
  filename: string;
  relPath: string;
  expected: "DETECT" | "NO_DETECT";
  category: "positive" | "negative" | "edge";
  rationale: string;
}

const manifest = JSON.parse(
  readFileSync(join(FIXTURE_DIR, "manifest.json"), "utf-8"),
) as ManifestEntry[];

/**
 * DETECT fixtures the detector intentionally misses (needs AST-level analysis).
 * Each requires a one-line justification. Keep this list as small as possible.
 */
const KNOWN_ACCEPTABLE_MISSES: Record<string, string> = {
  // (currently empty — the import-anchor rule recovered the node-pushover /
  //  pushover-notifications scope-split cases the upstream workflow could not.)
};

describe("Pushover budget detector — fixture verdicts", () => {
  for (const entry of manifest) {
    const shouldDetect = entry.expected === "DETECT";
    test(`[${entry.language}/${entry.category}] ${entry.filename} → ${entry.expected}`, () => {
      const content = readFileSync(join(FIXTURE_DIR, entry.relPath), "utf-8");
      const { matched } = detectPushoverMessageConstruction(content);

      if (!shouldDetect) {
        // Negatives must NEVER fire (zero false positives — non-negotiable).
        expect(matched).toBe(false);
        return;
      }

      if (entry.relPath in KNOWN_ACCEPTABLE_MISSES) {
        // Documented acceptable miss — assert it still misses so the
        // allowlist can be pruned if the detector improves.
        expect(matched).toBe(false);
        return;
      }

      expect(matched).toBe(true);
    });
  }
});

describe("Pushover budget detector — escape hatch & guards", () => {
  test("PUSHOVER-BUDGET-OK suppresses an otherwise-detected send", () => {
    const send = `curl -s --form-string "token=$T" --form-string "user=$U" \\
      --form-string "message=hi" https://api.pushover.net/1/messages.json`;
    expect(detectPushoverMessageConstruction(send).matched).toBe(true);
    expect(
      detectPushoverMessageConstruction(send + "\n# PUSHOVER-BUDGET-OK terse alert").matched,
    ).toBe(false);
  });

  test("empty / non-pushover text does not match", () => {
    expect(detectPushoverMessageConstruction("").matched).toBe(false);
    expect(
      detectPushoverMessageConstruction(`curl -d "message=hi" https://example.com/api`).matched,
    ).toBe(false);
    expect(
      detectPushoverMessageConstruction(`const payload = { title: "x", message: "y" };`).matched,
    ).toBe(false);
  });

  test("endpoint mentioned only in a comment does not match", () => {
    expect(
      detectPushoverMessageConstruction(
        `# POST to https://api.pushover.net/1/messages.json with token and message`,
      ).matched,
    ).toBe(false);
  });
});
