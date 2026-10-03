import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TY_PROJECT_CHECK_ARGS, tyPerFileCheckArgs } from "./stop-ty-project-check-args";

const tyAvailable = Bun.spawnSync(["which", "ty"]).exitCode === 0;

function checkWithPin(pinFile: string, pinContent: string): string {
  const cwd = mkdtempSync(join(tmpdir(), "stop-ty-args-"));
  try {
    writeFileSync(join(cwd, pinFile), pinContent);
    // PEP 695 `type` statement: valid on 3.12+, a syntax error on 3.10.
    writeFileSync(join(cwd, "a.py"), "type X = int\n");
    // Isolate from the caller: an active venv/conda env and a user-level ty.toml
    // (XDG_CONFIG_HOME) are both legitimate version sources for ty, and either
    // would make these assertions depend on the machine running them.
    const env: Record<string, string | undefined> = { ...process.env, XDG_CONFIG_HOME: cwd };
    delete env.VIRTUAL_ENV;
    delete env.CONDA_PREFIX;
    const run = Bun.spawnSync([...TY_PROJECT_CHECK_ARGS], { cwd, env, stdout: "pipe", stderr: "pipe" });
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

describe("PostToolUse per-file ty arguments (#157)", () => {
  test("never forces --python-version, and the hook builds its argv from this helper", () => {
    const argv = tyPerFileCheckArgs("/repo/pkg/mod.py");
    expect(argv).toEqual(["ty", "check", "/repo/pkg/mod.py", "--output-format", "concise"]);
    expect(argv).not.toContain("--python-version");
    expect(argv).not.toContain("--target-version");
    const hookSource = readFileSync(join(import.meta.dir, "..", "posttooluse-ty-type-check.ts"), "utf8");
    expect(hookSource).toContain("tyPerFileCheckArgs(filePath)");
    expect(hookSource).not.toContain('"--python-version"');
  });
});
