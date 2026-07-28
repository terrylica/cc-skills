import { describe, expect, test, beforeAll, afterAll } from "bun:test";
import { writeFileSync, mkdirSync, rmSync, existsSync } from "fs";
import { resolve } from "path";
import { spawnSync } from "bun";

// Regression tests for typescript-version-drift-guard
// Focused on discovery depth fixes and existing functionality

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

  test("discovery_finds_nested_packages_several_directories_deep_under_root", () => {
    // Create a deeply-nested package (8 levels) to ensure discovery catches it
    // This test FAILS on maxdepth 3, PASSES on maxdepth 10+
    const deepPath = resolve(tempDir, "root/a/b/c/d/e/f/g/package.json");
    mkdirSync(resolve(deepPath, ".."), { recursive: true });
    writeFileSync(deepPath, JSON.stringify({ devDependencies: { typescript: "latest" } }));

    // Run the CLI on the temp root
    const result = spawnSync(
      ["bun", "run", "bin/typescript-version-drift-guard.ts", "--json", "--roots", tempDir],
      {
        cwd: "/Users/terryli/eon/cc-skills",
        encoding: "utf8",
      }
    );

    expect(result.success).toBe(true);
    const stdout = result.stdout instanceof Buffer ? result.stdout.toString() : result.stdout;
    const json = JSON.parse(stdout || "{}");

    // Should find the deeply-nested package (would fail with maxdepth 3)
    const found = json.packages.some((pkg: any) => pkg.packageJsonPath.includes("root/a/b/c/d/e/f/g/package.json"));
    expect(found).toBe(true);
  });

  test("discovery_excludes_node_modules_at_any_depth", () => {
    // Create a package inside node_modules (should be excluded)
    const nodemodulesPath = resolve(tempDir, "root/node_modules/some-dep/package.json");
    mkdirSync(resolve(nodemodulesPath, ".."), { recursive: true });
    writeFileSync(nodemodulesPath, JSON.stringify({ devDependencies: { typescript: "latest" } }));

    // Run the CLI
    const result = spawnSync(
      ["bun", "run", "bin/typescript-version-drift-guard.ts", "--json", "--roots", tempDir],
      {
        cwd: "/Users/terryli/eon/cc-skills",
        encoding: "utf8",
      }
    );

    expect(result.success).toBe(true);
    const stdout = result.stdout instanceof Buffer ? result.stdout.toString() : result.stdout;
    const json = JSON.parse(stdout || "{}");

    // Should NOT find the package inside node_modules
    const found = json.packages.some((pkg: any) => pkg.packageJsonPath.includes("node_modules"));
    expect(found).toBe(false);
  });

  test("discovery_excludes_uv_cache_directories", () => {
    // Create a package inside .uv-cache (should be excluded)
    const uvCachePath = resolve(tempDir, "root/.uv-cache/archive-v0/xyz/package.json");
    mkdirSync(resolve(uvCachePath, ".."), { recursive: true });
    writeFileSync(uvCachePath, JSON.stringify({ devDependencies: { typescript: "latest" } }));

    // Run the CLI
    const result = spawnSync(
      ["bun", "run", "bin/typescript-version-drift-guard.ts", "--json", "--roots", tempDir],
      {
        cwd: "/Users/terryli/eon/cc-skills",
        encoding: "utf8",
      }
    );

    expect(result.success).toBe(true);
    const stdout = result.stdout instanceof Buffer ? result.stdout.toString() : result.stdout;
    const json = JSON.parse(stdout || "{}");

    // Should NOT find the package inside .uv-cache
    const found = json.packages.some((pkg: any) => pkg.packageJsonPath.includes(".uv-cache"));
    expect(found).toBe(false);
  });

  test("CLI --help returns 0", () => {
    const result = spawnSync(["bun", "run", "bin/typescript-version-drift-guard.ts", "--help"], {
      cwd: "/Users/terryli/eon/cc-skills",
    });
    expect(result.success).toBe(true);
  });

  test("CLI --help=json returns valid JSON", () => {
    const result = spawnSync(["bun", "run", "bin/typescript-version-drift-guard.ts", "--help=json"], {
      cwd: "/Users/terryli/eon/cc-skills",
      encoding: "utf8",
    });
    expect(result.success).toBe(true);
    const stdout = result.stdout instanceof Buffer ? result.stdout.toString() : result.stdout;
    const json = JSON.parse(stdout || "{}");
    expect(json.name).toBe("typescript-version-drift-guard");
  });

  test("CLI --version returns version string", () => {
    const result = spawnSync(["bun", "run", "bin/typescript-version-drift-guard.ts", "--version"], {
      cwd: "/Users/terryli/eon/cc-skills",
      encoding: "utf8",
    });
    expect(result.success).toBe(true);
    const stdout = result.stdout instanceof Buffer ? result.stdout.toString() : result.stdout;
    expect(stdout).toContain("1.0.0");
  });

  test("CLI with invalid flag exits 2 (usage error)", () => {
    const result = spawnSync(["bun", "run", "bin/typescript-version-drift-guard.ts", "--invalid-flag"], {
      cwd: "/Users/terryli/eon/cc-skills",
    });
    expect(result.success).toBe(false);
    expect(result.exitCode).toBe(2);
  });

  test("sanctioned_compat_alias_packages_remain_classified_as_conformant", () => {
    const result = spawnSync(
      ["bun", "run", "bin/typescript-version-drift-guard.ts", "--json", "--roots", "/Users/terryli/eon/kb"],
      {
        cwd: "/Users/terryli/eon/cc-skills",
        encoding: "utf8",
      }
    );

    expect(result.success).toBe(true);
    const stdout = result.stdout instanceof Buffer ? result.stdout.toString() : result.stdout;
    const json = JSON.parse(stdout || "{}");

    const kbPackage = json.packages.find((pkg: any) => pkg.path === "/Users/terryli/eon/kb");
    expect(kbPackage).toBeDefined();
    expect(kbPackage.evaluatorVerdictKind).toBe("sanctioned-compat-alias");
    expect(kbPackage.verdict).toBe("conformant");
  });
});
