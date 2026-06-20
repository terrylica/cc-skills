/**
 * Tests for posttooluse-readme-pypi-links.ts activation gate.
 *
 * Run with: bun test plugins/itp-hooks/hooks/posttooluse-readme-pypi-links.test.ts
 *
 * Pins the iter-124 temp-dir exemption (2026-06-20): the relative-link nudge
 * fires only on a durable root-level README.md, never a throwaway temp copy.
 */

import { describe, expect, it } from "bun:test";
import { isReadmePypiEligibleTarget } from "./posttooluse-readme-pypi-links.ts";

describe("readme-pypi-links activation gate", () => {
  it("fires on a durable root-level README.md", () => {
    expect(isReadmePypiEligibleTarget("Write", "/Users/me/proj/README.md", "/Users/me/proj")).toBe(true);
  });

  it("fires for Edit and MultiEdit too", () => {
    expect(isReadmePypiEligibleTarget("Edit", "/Users/me/proj/README.md", "/Users/me/proj")).toBe(true);
    expect(isReadmePypiEligibleTarget("MultiEdit", "/Users/me/proj/README.md", "/Users/me/proj")).toBe(
      true,
    );
  });

  it("skips a throwaway README.md in /tmp even when it is the cwd root (iter-124)", () => {
    expect(isReadmePypiEligibleTarget("Write", "/tmp/README.md", "/tmp")).toBe(false);
  });

  it("skips a non-root README.md (subdirectory)", () => {
    expect(isReadmePypiEligibleTarget("Write", "/Users/me/proj/docs/README.md", "/Users/me/proj")).toBe(
      false,
    );
  });

  it("skips non-Write/Edit/MultiEdit tools", () => {
    expect(isReadmePypiEligibleTarget("Bash", "/Users/me/proj/README.md", "/Users/me/proj")).toBe(false);
  });
});
