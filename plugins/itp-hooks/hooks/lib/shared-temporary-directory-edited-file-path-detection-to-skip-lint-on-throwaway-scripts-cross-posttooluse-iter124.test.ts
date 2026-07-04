#!/usr/bin/env bun
/**
 * Tests for the iter-124 temporary-directory edited-file-path detector that
 * lets PostToolUse lint/type-check subhooks skip throwaway scratch scripts.
 */

import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import {
  bashCommandWritesThrowawayScriptIntoTemporaryScratchDirectory as bashWritesTemp,
  isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts as isTemp,
} from "./shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";

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

describe("bash temp-write detector — FIRES on throwaway-into-temp shapes", () => {
  test.each([
    `cat > /tmp/audit17.sh <<'EOF'\necho hi\nEOF`,
    `cat >>/tmp/log.txt`,
    `printf '%s' "$x" > /tmp/foo`,
    `echo done 1>/tmp/out.log`,
    `make 2>&1 &> /tmp/build.log`,
    `cat foo | tee /tmp/copy.txt`,
    `cat foo | tee -a /tmp/copy.txt`,
    `f=$(mktemp) && echo hi > "$f"`,
    `cat > "$TMPDIR/scratch.sh" <<'EOF'\nx\nEOF`,
    `cat > \${TMPDIR}/scratch.sh`,
    `tee /dev/shm/quick.sh < in`,
  ])("classifies %s as a temp write", (cmd) => {
    expect(bashWritesTemp(cmd)).toBe(true);
  });
});

describe("bash temp-write detector — SILENT on durable / non-write commands", () => {
  test.each([
    `chmod +x /tmp/audit17.sh && /tmp/audit17.sh`, // references /tmp but writes nothing
    `cat > /Users/me/proj/notify.sh <<'EOF'\nx\nEOF`, // durable write target
    `echo hi > ./out.log`, // relative durable target
    `ls -la && git status`, // no write at all
    `grep foo /tmp/data.txt`, // reads from /tmp, no write redirect
  ])("classifies %s as NOT a temp write", (cmd) => {
    expect(bashWritesTemp(cmd)).toBe(false);
  });

  test("fail-safe: empty / undefined / null → false", () => {
    expect(bashWritesTemp("")).toBe(false);
    expect(bashWritesTemp(undefined)).toBe(false);
    expect(bashWritesTemp(null)).toBe(false);
  });
});
