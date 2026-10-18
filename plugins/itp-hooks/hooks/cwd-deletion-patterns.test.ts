/**
 * Tests for cwd-deletion-patterns.mjs (used by pretooluse-cwd-deletion-guard.ts).
 *
 * Run with: bun test plugins/itp-hooks/hooks/cwd-deletion-patterns.test.ts
 *
 * The false positive that prompted the rewrite (2026-10-17): a command that queued a pueue job with
 * `-w "$PWD"` and, separately, removed one report file with `rm -f` was denied as "would delete the
 * current working directory, target $(pwd)". `$PWD` was never an rm operand. Only an rm -r / rmdir /
 * mv-source operand that resolves to the cwd or a parent may match.
 */

import { describe, expect, test } from "bun:test";

import { detectCwdDeletion } from "./cwd-deletion-patterns.mjs";

const CWD = "/work/repo/sub";
const HOME = process.env.HOME ?? "/home/u";

const hit = (command: string, cwd = CWD) => detectCwdDeletion(command, cwd).detected;

describe("false positives that must pass", () => {
  test.each([
    ['pueue add -g g -w "$PWD" -- "python x.py" && rm -f reports/causal/x.json'],
    ['rm -f "$PWD/reports/x.json"'],
    ["rm -rf ./build dist *.egg-info"],
    ["rm -rf $(pwd)/node_modules"],
    ['rm -rf "${PWD}/.cache"'],
    ["rm -rf *"],
    ["rm -f ."],
    ['git commit -m "rm -rf $PWD is dangerous"'],
    ["echo 'rm -rf ..' # a mention"],
    ["cat > /tmp/clean.sh <<'EOF'\nrm -rf \"$PWD\"\nEOF"],
    ["ssh host 'rm -rf ..'"],
    ["cd /tmp/scratch && rm -rf build"],
    ["mv a.txt ."],
    ["rm -rf $UNKNOWN_DIR"],
  ])("allows %s", (command) => {
    expect(hit(command)).toBe(false);
  });
});

describe("true positives that must still be caught", () => {
  test.each([
    ["rm -rf ."],
    ["rm -rf ./"],
    ['rm -rf "$PWD"'],
    ["rm -rf $(pwd)"],
    ["rm -rf `pwd`"],
    ["rm -rf .."],
    ["rm -r ../"],
    ["rm --recursive --force /work/repo"],
    ["rm -fr /work"],
    ["rm -rf ../*"],
    ["rmdir ."],
    ["mv /work/repo /work/repo-old"],
    ["mv . ../renamed"],
    ["cd .. && rm -rf sub"],
    ["cd /tmp && rm -rf /work/repo/sub"],
    ["bash -c 'rm -rf ..'"],
    // Found in review (2026-10-17): an assignment, a cd inside bash -c, and mv -t.
    ['D=$PWD; rm -rf "$D"'],
    ["bash -c 'cd .. && rm -rf sub'"],
    ['mv -t /tmp "$PWD"'],
    ["rm -rf /work/repo && git clone https://example.invalid/r.git /work/repo"],
  ])("denies %s", (command) => {
    expect(hit(command)).toBe(true);
  });

  test("~ and $HOME resolve to the home directory", () => {
    expect(hit("rm -rf ~", `${HOME}/proj`)).toBe(true);
    expect(hit("rm -rf $HOME/proj", `${HOME}/proj`)).toBe(true);
    expect(hit("rm -rf ~/proj-other", `${HOME}/proj`)).toBe(false);
  });

  test("a git re-clone is labelled as one", () => {
    const r = detectCwdDeletion("rm -rf /work/repo && git clone u /work/repo", CWD);
    expect(r.detected).toBe(true);
    expect(r.isGitOperation).toBe(true);
  });

  test("the escape hatch still works", () => {
    expect(hit("rm -rf . # CWD-DELETE-OK")).toBe(false);
  });
});
