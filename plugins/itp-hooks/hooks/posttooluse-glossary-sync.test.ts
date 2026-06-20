/**
 * Tests for posttooluse-glossary-sync.ts activation gate.
 *
 * Run with: bun test plugins/itp-hooks/hooks/posttooluse-glossary-sync.test.ts
 *
 * Pins the iter-124 temp-dir exemption (2026-06-20): the hook syncs only the
 * durable global GLOSSARY.md and never a throwaway copy dropped in a temp dir.
 */

import { describe, expect, it } from "bun:test";
import { isGlossarySyncEligibleTarget } from "./posttooluse-glossary-sync.ts";

describe("glossary-sync activation gate", () => {
  it("fires on a durable global GLOSSARY.md Write", () => {
    expect(isGlossarySyncEligibleTarget("Write", "/Users/me/.claude/docs/GLOSSARY.md")).toBe(true);
  });

  it("fires on a durable global GLOSSARY.md Edit", () => {
    expect(isGlossarySyncEligibleTarget("Edit", "/Users/me/.claude/docs/GLOSSARY.md")).toBe(true);
  });

  it("skips a throwaway copy in /tmp (iter-124)", () => {
    expect(isGlossarySyncEligibleTarget("Write", "/tmp/.claude/docs/GLOSSARY.md")).toBe(false);
  });

  it("skips a throwaway copy under /private/var/folders (macOS TMPDIR)", () => {
    expect(
      isGlossarySyncEligibleTarget("Edit", "/private/var/folders/ab/cd/T/.claude/docs/GLOSSARY.md"),
    ).toBe(false);
  });

  it("skips a project-local GLOSSARY.md (not the global one)", () => {
    expect(isGlossarySyncEligibleTarget("Write", "/Users/me/proj/GLOSSARY.md")).toBe(false);
  });

  it("skips non-Write/Edit tools", () => {
    expect(isGlossarySyncEligibleTarget("Bash", "/Users/me/.claude/docs/GLOSSARY.md")).toBe(false);
  });
});
