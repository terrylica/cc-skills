import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TY_PROJECT_CHECK_ARGS } from "./stop-ty-project-check-args";

const tyAvailable = Bun.spawnSync(["which", "ty"]).exitCode === 0;

function checkWithPin(pinFile: string, pinContent: string): string {
  const cwd = mkdtempSync(join(tmpdir(), "stop-ty-args-"));
  try {
    writeFileSync(join(cwd, pinFile), pinContent);
    // PEP 695 `type` statement: valid on 3.12+, a syntax error on 3.10.
    writeFileSync(join(cwd, "a.py"), "type X = int\n");
    const run = Bun.spawnSync([...TY_PROJECT_CHECK_ARGS], { cwd, stdout: "pipe", stderr: "pipe" });
    return run.stdout.toString() + run.stderr.toString();
  } finally {
    rmSync(cwd, { recursive: true, force: true });
  }
}

describe("Stop-hook ty arguments (#157)", () => {
  test("never forces --python-version, so the repo's pin wins", () => {
    expect(TY_PROJECT_CHECK_ARGS).not.toContain("--python-version");
    expect(TY_PROJECT_CHECK_ARGS).not.toContain("--target-version");
    expect(TY_PROJECT_CHECK_ARGS).toContain("--exit-zero");
  });

  test.skipIf(!tyAvailable)("honours project.requires-python", () => {
    const out = checkWithPin("pyproject.toml", '[project]\nname = "d"\nversion = "0"\nrequires-python = ">=3.10"\n');
    expect(out).toContain("Python 3.10");
  });

  test.skipIf(!tyAvailable)("honours ty.toml [environment] python-version", () => {
    const out = checkWithPin("ty.toml", '[environment]\npython-version = "3.10"\n');
    expect(out).toContain("Python 3.10");
  });

  test.skipIf(!tyAvailable)("defaults to 3.14 when nothing is pinned", () => {
    const out = checkWithPin("README", "no pin\n");
    expect(out).toContain("All checks passed");
  });
});
