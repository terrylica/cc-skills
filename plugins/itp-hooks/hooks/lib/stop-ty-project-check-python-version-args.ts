import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const DEFAULT_PYTHON_VERSION = "3.14";

export function repositoryDeclaresPythonVersion(cwd: string): boolean {
  if (nonEmptyFileExists(join(cwd, ".python-version"))) {
    return true;
  }

  if (fileContainsRequiresPython(join(cwd, "pyproject.toml"))) {
    return true;
  }

  if (fileContainsRequiresPython(join(cwd, "uv.lock"))) {
    return true;
  }

  return false;
}

export function tyProjectCheckArgs(cwd: string): string[] {
  const args = ["ty", "check", ".", "--output-format", "concise"];

  // Python 3.14 is the default policy, but a repository's own Python pin wins.
  // When a version is declared, omit --python-version so ty can resolve it from
  // the project configuration instead of being forced to the default.
  if (!repositoryDeclaresPythonVersion(cwd)) {
    args.push("--python-version", DEFAULT_PYTHON_VERSION);
  }

  args.push("--exit-zero");
  return args;
}

function nonEmptyFileExists(path: string): boolean {
  try {
    return existsSync(path) && readFileSync(path, "utf8").trim().length > 0;
  } catch {
    return false;
  }
}

function fileContainsRequiresPython(path: string): boolean {
  try {
    if (!existsSync(path)) {
      return false;
    }

    const content = readFileSync(path, "utf8");
    return /^\s*requires-python\s*=\s*["'][^"']+["']/m.test(content);
  } catch {
    return false;
  }
}
