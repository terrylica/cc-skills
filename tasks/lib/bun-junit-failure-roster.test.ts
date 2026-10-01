import { describe, expect, test } from "bun:test";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { failingTestcases, formatRoster } from "./bun-junit-failure-roster";

const WRAPPER =
  "test-marketplace-bun-unit-suite-for-tracked-typescript-and-mjs-tests-excluding-live-browser-integration.sh";
const TASKS = join(import.meta.dir, "..");

const SAMPLE = `<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="bun test" tests="3" failures="1">
  <testsuite name="a.test.ts" file="a.test.ts">
    <testcase name="ok" classname="" file="a.test.ts" line="2" assertions="1" />
  </testsuite>
  <testsuite name="sub/b.test.ts" file="sub/b.test.ts">
    <testsuite name="grp" file="sub/b.test.ts" line="2">
      <testcase name="fails &amp; &quot;quotes&quot;" classname="grp" file="sub/b.test.ts" line="7" assertions="1">
        <failure type="AssertionError" message="x">AssertionError</failure>
      </testcase>
      <testcase name="skipped" classname="grp" file="sub/b.test.ts" line="9"><skipped /></testcase>
    </testsuite>
  </testsuite>
</testsuites>`;

describe("bun JUnit failure roster (#143)", () => {
  test("names the FILE and line of each failing test, and nothing else", () => {
    const failing = failingTestcases(SAMPLE);
    expect(failing.length).toBe(1);
    expect(formatRoster(failing)).toEqual(['BUN-UNIT-FAIL sub/b.test.ts:7 — grp > fails & "quotes"']);
  });

  test("no roster line can be mistaken for bun's `N pass` / `N fail` count that preflight greps", () => {
    for (const line of formatRoster(failingTestcases(SAMPLE))) {
      expect(/^[\s]*[0-9]+ (pass|fail)/.test(line)).toBe(false);
    }
  });

  test("a failing run still exits non-zero through the wrapper, and prints the roster", () => {
    const repo = mkdtempSync(join(tmpdir(), "bun-unit-roster-"));
    try {
      mkdirSync(join(repo, "tasks", "lib"), { recursive: true });
      copyFileSync(join(TASKS, WRAPPER), join(repo, "tasks", WRAPPER));
      copyFileSync(join(TASKS, "lib", "bun-junit-failure-roster.ts"), join(repo, "tasks", "lib", "bun-junit-failure-roster.ts"));
      // The wrapper must hand tests an EMPTY git template dir, so fixture repos never run the
      // developer's global hooks (2026-10-01). If it stops doing so, this "passing" test fails.
      writeFileSync(
        join(repo, "pass.test.ts"),
        'import {test,expect} from "bun:test";\nimport {readdirSync} from "node:fs";\n' +
          'test("ok", () => { const d = process.env.GIT_TEMPLATE_DIR ?? ""; expect(d.length > 0 && readdirSync(d).length === 0).toBe(true); });\n',
      );
      writeFileSync(join(repo, "boom.test.ts"), 'import {test,expect} from "bun:test";\n\ntest("boom", () => expect(1).toBe(2));\n');
      for (const args of [["init", "-q"], ["add", "pass.test.ts", "boom.test.ts"]]) {
        expect(Bun.spawnSync(["git", ...args], { cwd: repo }).exitCode).toBe(0);
      }
      const run = Bun.spawnSync(["bash", join(repo, "tasks", WRAPPER)], { cwd: repo, stdout: "pipe", stderr: "pipe" });
      const stdout = run.stdout.toString();
      expect(run.exitCode).not.toBe(0);
      expect(stdout.includes("BUN-UNIT-FAIL boom.test.ts:3 — boom")).toBe(true);
      expect(run.stderr.toString().includes("BUN-UNIT-FAIL boom.test.ts:3")).toBe(true);
      expect(stdout.includes("pass.test.ts:")).toBe(false);
    } finally {
      rmSync(repo, { recursive: true, force: true });
    }
  });
});
