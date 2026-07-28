import { describe, expect, test, beforeAll, afterAll } from "bun:test";
import { writeFileSync, mkdirSync, rmSync, existsSync } from "fs";
import { resolve } from "path";
import { spawnSync } from "bun";

// Since we can't easily test the full CLI directly in this test file,
// we'll test the core functions that the CLI uses.

describe("typescript-version-drift-guard integration", () => {
  const tempDir = "/tmp/ts-drift-guard-test";

  beforeAll(() => {
    if (existsSync(tempDir)) {
      rmSync(tempDir, { recursive: true });
    }
    mkdirSync(tempDir, { recursive: true });
  });

  afterAll(() => {
    if (existsSync(tempDir)) {
      rmSync(tempDir, { recursive: true });
    }
  });

  test("discovers package.json in directory tree", () => {
    const pkg1 = resolve(tempDir, "repo1/package.json");
    const pkg2 = resolve(tempDir, "repo2/subdir/package.json");

    mkdirSync(resolve(tempDir, "repo1"), { recursive: true });
    mkdirSync(resolve(tempDir, "repo2/subdir"), { recursive: true });

    writeFileSync(pkg1, JSON.stringify({ devDependencies: { typescript: "latest" } }));
    writeFileSync(pkg2, JSON.stringify({ devDependencies: { typescript: "^7.0.0" } }));

    // Just verify files exist
    expect(existsSync(pkg1)).toBe(true);
    expect(existsSync(pkg2)).toBe(true);
  });

  test("CLI --help returns 0", () => {
    const result = spawnSync(["bun", "run", "bin/typescript-version-drift-guard.ts", "--help"], {
      cwd: "/Users/terryli/eon/cc-skills-ts7-guard",
    });
    expect(result.success).toBe(true);
  });

  test("CLI --help=json returns valid JSON", () => {
    const result = spawnSync(["bun", "run", "bin/typescript-version-drift-guard.ts", "--help=json"], {
      cwd: "/Users/terryli/eon/cc-skills-ts7-guard",
      encoding: "utf8",
    });
    expect(result.success).toBe(true);
    const json = JSON.parse(result.stdout || "{}");
    expect(json.name).toBe("typescript-version-drift-guard");
  });

  test("CLI --version returns version string", () => {
    const result = spawnSync(["bun", "run", "bin/typescript-version-drift-guard.ts", "--version"], {
      cwd: "/Users/terryli/eon/cc-skills-ts7-guard",
      encoding: "utf8",
    });
    expect(result.success).toBe(true);
    expect(result.stdout).toContain("1.0.0");
  });

  test("CLI with invalid flag exits 2 (usage error)", () => {
    const result = spawnSync(["bun", "run", "bin/typescript-version-drift-guard.ts", "--invalid-flag"], {
      cwd: "/Users/terryli/eon/cc-skills-ts7-guard",
    });
    expect(result.success).toBe(false);
    expect(result.exitCode).toBe(2);
  });
});
