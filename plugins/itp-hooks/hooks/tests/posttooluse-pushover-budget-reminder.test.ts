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
import {
  detectPushoverMessageConstruction,
  evaluatePushoverHookInput,
} from "../posttooluse-pushover-budget-reminder.ts";

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

/**
 * The temp-dir skip (iter-124) lives in evaluatePushoverHookInput(), the
 * input-level seam main() actually calls — the pure detectPushoverMessage…
 * detector never sees tool_input.file_path. These tests drive that seam
 * directly, mirroring how Claude Code feeds the hook a full tool input.
 */
describe("Pushover budget detector — temp-dir skip (iter-124)", () => {
  const PUSHOVER_SEND =
    `curl -s --form-string "token=$T" --form-string "user=$U" ` +
    `--form-string "message=hi" https://api.pushover.net/1/messages.json`;

  const pushoverWrite = (filePath: string) => ({
    tool_name: "Write",
    tool_input: { file_path: filePath, content: PUSHOVER_SEND },
  });

  test("fires on a Write to a durable project path (control)", () => {
    expect(evaluatePushoverHookInput(pushoverWrite("/Users/me/proj/notify.sh")).matched).toBe(true);
  });

  test("stays silent on a Write to a /tmp throwaway script", () => {
    expect(evaluatePushoverHookInput(pushoverWrite("/tmp/audit17.sh")).matched).toBe(false);
  });

  test("stays silent on a Write under /private/var/folders (macOS TMPDIR)", () => {
    expect(
      evaluatePushoverHookInput(pushoverWrite("/private/var/folders/ab/cd/T/scratch.sh")).matched,
    ).toBe(false);
  });

  test("Bash sends to no temp target still fire", () => {
    expect(
      evaluatePushoverHookInput({ tool_name: "Bash", tool_input: { command: PUSHOVER_SEND } }).matched,
    ).toBe(true);
  });

  test("Write to a test/fixture file is exempt", () => {
    expect(evaluatePushoverHookInput(pushoverWrite("/Users/me/proj/notify.test.ts")).matched).toBe(false);
    expect(evaluatePushoverHookInput(pushoverWrite("/Users/me/proj/fixtures/send.sh")).matched).toBe(false);
  });

  test("Bash heredoc writing a throwaway script into /tmp is exempt", () => {
    const cmd = `cat > /tmp/notify.sh <<'EOF'\n${PUSHOVER_SEND}\nEOF`;
    expect(evaluatePushoverHookInput({ tool_name: "Bash", tool_input: { command: cmd } }).matched).toBe(
      false,
    );
  });

  test("Bash heredoc writing a durable script still fires (control)", () => {
    const cmd = `cat > /Users/me/proj/notify.sh <<'EOF'\n${PUSHOVER_SEND}\nEOF`;
    expect(evaluatePushoverHookInput({ tool_name: "Bash", tool_input: { command: cmd } }).matched).toBe(
      true,
    );
  });
});
