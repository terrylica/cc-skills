import { describe, expect, test } from "bun:test";
import {
  evaluateTypeScriptVersionSpecifier,
  findTypeScriptDependencySpecifiersInPackageJsonText,
  isBlockingTypeScriptVersionSpecifierVerdict,
  MINIMUM_ALLOWED_TYPESCRIPT_MAJOR_VERSION,
} from "./typescript-version-specifier-minimum-major-policy-evaluator.ts";

describe("evaluateTypeScriptVersionSpecifier — conformant", () => {
  for (const specifier of ["latest", "next", "beta", "rc", "*", "", "LATEST"]) {
    test(`dist-tag "${specifier}" is conformant`, () => {
      expect(evaluateTypeScriptVersionSpecifier(specifier).kind).toBe("conformant");
    });
  }

  for (const specifier of ["7.0.2", "^7.0.2", "~7.1.0", ">=7", "7.x", "v7.0.0", "8.0.0", "^7"]) {
    test(`"${specifier}" meets the major-${MINIMUM_ALLOWED_TYPESCRIPT_MAJOR_VERSION} floor`, () => {
      const verdict = evaluateTypeScriptVersionSpecifier(specifier);
      expect(verdict.kind).toBe("conformant");
      expect(isBlockingTypeScriptVersionSpecifierVerdict(verdict)).toBe(false);
    });
  }

  test("union where every branch is >= 7 is conformant", () => {
    expect(evaluateTypeScriptVersionSpecifier("^7 || ^8").kind).toBe("conformant");
  });
});

describe("evaluateTypeScriptVersionSpecifier — legacy (must block)", () => {
  for (const specifier of ["5.9.3", "^5.6.0", "~6.0.2", "6.x", ">=5", "v5.1.2", "5", "6.0.0"]) {
    test(`"${specifier}" is legacy`, () => {
      const verdict = evaluateTypeScriptVersionSpecifier(specifier);
      expect(verdict.kind).toBe("legacy");
      expect(isBlockingTypeScriptVersionSpecifierVerdict(verdict)).toBe(true);
    });
  }

  test("union admitting a pre-7 branch is legacy (conservative)", () => {
    const verdict = evaluateTypeScriptVersionSpecifier("^6 || ^7");
    expect(verdict.kind).toBe("legacy");
    if (verdict.kind === "legacy") expect(verdict.detectedMajorVersion).toBe(6);
  });

  test("npm: alias to a legacy range is legacy", () => {
    expect(evaluateTypeScriptVersionSpecifier("npm:typescript@5.9.3").kind).toBe("legacy");
  });
});

describe("evaluateTypeScriptVersionSpecifier — sanctioned compat alias", () => {
  // The whole point of the verdict union: this string contains "6" but is the
  // policy-prescribed escape route for compiler-embedding tooling.
  for (const specifier of [
    "npm:@typescript/typescript6@^6.0.2",
    "npm:@typescript/typescript6@6.0.2",
    "npm:@typescript/typescript6",
  ]) {
    test(`"${specifier}" is allowed`, () => {
      const verdict = evaluateTypeScriptVersionSpecifier(specifier);
      expect(verdict.kind).toBe("sanctioned-compat-alias");
      expect(isBlockingTypeScriptVersionSpecifierVerdict(verdict)).toBe(false);
    });
  }
});

describe("evaluateTypeScriptVersionSpecifier — deprecated native preview", () => {
  test("@typescript/native-preview is blocked", () => {
    const verdict = evaluateTypeScriptVersionSpecifier("npm:@typescript/native-preview@7.0.0-dev.20260707.2");
    expect(verdict.kind).toBe("deprecated-native-preview");
    expect(isBlockingTypeScriptVersionSpecifierVerdict(verdict)).toBe(true);
  });
});

describe("evaluateTypeScriptVersionSpecifier — unresolvable fails OPEN", () => {
  for (const specifier of [
    "workspace:*",
    "catalog:",
    "file:../local-typescript",
    "link:../ts",
    "github:microsoft/TypeScript",
    "https://example.invalid/ts.tgz",
    "git+ssh://git@example.invalid/ts.git",
  ]) {
    test(`"${specifier}" is allowed (cannot be judged)`, () => {
      const verdict = evaluateTypeScriptVersionSpecifier(specifier);
      expect(verdict.kind).toBe("unresolvable");
      expect(isBlockingTypeScriptVersionSpecifierVerdict(verdict)).toBe(false);
    });
  }
});

describe("findTypeScriptDependencySpecifiersInPackageJsonText", () => {
  test("finds the dep in a full package.json", () => {
    const found = findTypeScriptDependencySpecifiersInPackageJsonText(
      JSON.stringify({ devDependencies: { typescript: "^5.6.0", "@types/bun": "latest" } }, null, 2),
    );
    expect(found).toEqual([{ dependencyName: "typescript", specifier: "^5.6.0" }]);
  });

  test("finds the dep in a bare Edit fragment that is NOT valid JSON", () => {
    // This is the case a JSON.parse-based implementation silently passes.
    const found = findTypeScriptDependencySpecifiersInPackageJsonText('    "typescript": "5.9.3",');
    expect(found).toEqual([{ dependencyName: "typescript", specifier: "5.9.3" }]);
  });

  test("finds both halves of the dual-install alias", () => {
    const found = findTypeScriptDependencySpecifiersInPackageJsonText(
      JSON.stringify({
        devDependencies: {
          "@typescript/native": "npm:typescript@latest",
          typescript: "npm:@typescript/typescript6@^6.0.2",
        },
      }),
    );
    expect(found).toHaveLength(2);
    // Neither half may block: one is current, the other is the sanctioned alias.
    for (const { specifier } of found) {
      expect(isBlockingTypeScriptVersionSpecifierVerdict(evaluateTypeScriptVersionSpecifier(specifier))).toBe(false);
    }
  });

  test("ignores unrelated deps that merely contain the word typescript", () => {
    const found = findTypeScriptDependencySpecifiersInPackageJsonText(
      JSON.stringify({ devDependencies: { "typescript-eslint": "^8.0.0", "@types/node": "^24" } }),
    );
    expect(found).toEqual([]);
  });

  test("returns empty for text with no typescript dep", () => {
    expect(findTypeScriptDependencySpecifiersInPackageJsonText('{"name":"x"}')).toEqual([]);
  });
});
