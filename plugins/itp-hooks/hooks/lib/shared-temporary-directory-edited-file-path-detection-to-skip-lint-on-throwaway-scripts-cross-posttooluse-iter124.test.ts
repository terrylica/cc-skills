#!/usr/bin/env bun
/**
 * Tests for the iter-124 temporary-directory edited-file-path detector that
 * lets PostToolUse lint/type-check subhooks skip throwaway scratch scripts.
 */

import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts as isTemp } from "./shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";

describe("temp-path detector — static temp roots", () => {
  test.each([
    "/tmp/scratch.py",
    "/tmp/nested/dir/foo.ts",
    "/private/tmp/throwaway.js",
    "/var/folders/ab/cdef/T/scratch.py",
    "/private/var/folders/ab/cdef/T/scratch.py",
    "/dev/shm/quick.ts",
  ])("classifies %s as temporary", (p) => {
    expect(isTemp(p)).toBe(true);
  });
});

describe("temp-path detector — real project files are NOT temporary", () => {
  test.each([
    "/Users/terryli/eon/cc-skills/plugins/itp-hooks/hooks/foo.ts",
    "/home/user/project/main.py",
    "/repo/tmpl/template.ts", // dir merely starts with "tmp" — must NOT match
    "/var/foldersX/not-temp.py", // boundary: not /var/folders
    "/opt/tmp-like/app.js",
  ])("classifies %s as NOT temporary", (p) => {
    expect(isTemp(p)).toBe(false);
  });
});

describe("temp-path detector — fail-safe inputs", () => {
  test("empty / undefined / null → false", () => {
    expect(isTemp("")).toBe(false);
    expect(isTemp(undefined)).toBe(false);
    expect(isTemp(null)).toBe(false);
  });

  test("relative paths → false (temp dirs are absolute)", () => {
    expect(isTemp("tmp/foo.py")).toBe(false);
    expect(isTemp("./scratch.ts")).toBe(false);
  });
});

describe("temp-path detector — honors live $TMPDIR", () => {
  const original = process.env.TMPDIR;
  beforeEach(() => {
    process.env.TMPDIR = "/var/folders/zz/abc123/T/";
  });
  afterEach(() => {
    if (original === undefined) delete process.env.TMPDIR;
    else process.env.TMPDIR = original;
  });

  test("file under $TMPDIR is temporary", () => {
    expect(isTemp("/var/folders/zz/abc123/T/scratch.py")).toBe(true);
  });

  test("file under /private realpath twin of $TMPDIR is temporary", () => {
    expect(isTemp("/private/var/folders/zz/abc123/T/scratch.py")).toBe(true);
  });
});
