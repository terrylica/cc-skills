import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  repositoryDeclaresPythonVersion,
  tyProjectCheckArgs,
} from "./stop-ty-project-check-python-version-args";

function withTempProject(run: (cwd: string) => void): void {
  const cwd = mkdtempSync(join(tmpdir(), "stop-ty-python-version-"));
  try {
    run(cwd);
  } finally {
    rmSync(cwd, { recursive: true, force: true });
  }
}

describe("Stop-hook ty Python-version arguments", () => {
  test("uses Python 3.14 as the default when the repo has no version pin", () => {
    withTempProject((cwd) => {
      writeFileSync(join(cwd, "pyproject.toml"), "[project]\nname = 'demo'\n");

      expect(repositoryDeclaresPythonVersion(cwd)).toBe(false);
      expect(tyProjectCheckArgs(cwd)).toEqual([
        "ty",
        "check",
        ".",
        "--output-format",
        "concise",
        "--python-version",
        "3.14",
        "--exit-zero",
      ]);
    });
  });

  test("omits --python-version when pyproject.toml declares requires-python", () => {
    withTempProject((cwd) => {
      writeFileSync(join(cwd, "pyproject.toml"), "[project]\nrequires-python = '>=3.13'\n");

      expect(repositoryDeclaresPythonVersion(cwd)).toBe(true);
      expect(tyProjectCheckArgs(cwd)).toEqual([
        "ty",
        "check",
        ".",
        "--output-format",
        "concise",
        "--exit-zero",
      ]);
    });
  });

  test("omits --python-version when .python-version pins the repo", () => {
    withTempProject((cwd) => {
      writeFileSync(join(cwd, ".python-version"), "3.13.13\n");

      expect(repositoryDeclaresPythonVersion(cwd)).toBe(true);
      expect(tyProjectCheckArgs(cwd)).not.toContain("--python-version");
    });
  });

  test("omits --python-version when uv.lock records requires-python", () => {
    withTempProject((cwd) => {
      writeFileSync(join(cwd, "uv.lock"), "requires-python = '>=3.12'\n");

      expect(repositoryDeclaresPythonVersion(cwd)).toBe(true);
      expect(tyProjectCheckArgs(cwd)).not.toContain("--python-version");
    });
  });
});
