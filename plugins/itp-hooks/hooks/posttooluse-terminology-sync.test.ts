/**
 * Tests for posttooluse-terminology-sync.ts activation gate.
 *
 * Run with: bun test plugins/itp-hooks/hooks/posttooluse-terminology-sync.test.ts
 *
 * Pins the iter-124 temp-dir exemption (2026-06-20): the terminology scan/sync
 * fires only on a durable project CLAUDE.md, never a throwaway temp copy, and
 * never the global GLOSSARY.md (handled by glossary-sync).
 */

import { describe, expect, it } from "bun:test";
import { isTerminologySyncEligibleTarget } from "./posttooluse-terminology-sync.ts";

describe("terminology-sync activation gate", () => {
  it("fires on a durable project CLAUDE.md", () => {
    expect(isTerminologySyncEligibleTarget("Write", "/Users/me/proj/CLAUDE.md")).toBe(true);
  });

  it("fires on a nested project CLAUDE.md", () => {
    expect(isTerminologySyncEligibleTarget("Edit", "/Users/me/eon/proj/sub/CLAUDE.md")).toBe(true);
  });

  it("skips a throwaway CLAUDE.md in /tmp (iter-124)", () => {
    expect(isTerminologySyncEligibleTarget("Write", "/tmp/CLAUDE.md")).toBe(false);
  });

  it("skips a throwaway CLAUDE.md under /private/var/folders (macOS TMPDIR)", () => {
    expect(isTerminologySyncEligibleTarget("Edit", "/private/var/folders/ab/cd/T/CLAUDE.md")).toBe(false);
  });

  it("skips the global GLOSSARY.md (handled by glossary-sync)", () => {
    expect(isTerminologySyncEligibleTarget("Write", "/Users/me/.claude/docs/GLOSSARY.md")).toBe(false);
  });

  it("skips a non-CLAUDE.md file", () => {
    expect(isTerminologySyncEligibleTarget("Write", "/Users/me/proj/README.md")).toBe(false);
  });

  it("skips non-Write/Edit tools", () => {
    expect(isTerminologySyncEligibleTarget("Bash", "/Users/me/proj/CLAUDE.md")).toBe(false);
  });
});
