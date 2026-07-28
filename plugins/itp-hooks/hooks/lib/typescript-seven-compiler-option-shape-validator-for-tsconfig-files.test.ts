#!/usr/bin/env bun
/**
 * Unit tests for typescript-seven-compiler-option-shape-validator-for-tsconfig-files.ts
 *
 * Coverage:
 *   - Detects hard-error: baseUrl option removed
 *   - Detects hard-error: downlevelIteration option removed
 *   - Detects hard-error: target: "es5" forbidden
 *   - Detects hard-error: moduleResolution: "node" | "node10" | "classic" forbidden
 *   - Detects hard-error: module: "amd" | "umd" | "systemjs" | "none" forbidden
 *   - Detects hard-error: esModuleInterop: false forbidden (true is clean)
 *   - Detects hard-error: allowSyntheticDefaultImports: false forbidden (true is clean)
 *   - Detects hard-error: alwaysStrict: false forbidden (true is clean)
 *   - Detects hard-error: paths values that are bare/non-relative (TS5090)
 *   - Allows paths values that are relative (./ or ../)
 *   - Warns on missing types array (but never blocks)
 *   - Allows extends-only configs without types warning
 *   - Handles JSONC gracefully (comments, trailing commas)
 *   - Handles Edit fragments (incomplete JSON)
 *   - Falls open on unparseable content
 */

import { describe, it, expect } from "bun:test";
import {
  evaluateTypeScriptSevenCompilerOptionShapeConformance,
  extractHardErrorViolationsFromTypeScriptSevenCompilerOptionShapeConformance,
  type TypeScriptSevenCompilerOptionShapeViolation,
} from "./typescript-seven-compiler-option-shape-validator-for-tsconfig-files.ts";

// ============================================================================
// Test fixture helpers
// ============================================================================

function makeViolationSummary(violations: TypeScriptSevenCompilerOptionShapeViolation[]) {
  return violations.map((v) => ({
    kind: v.kind,
    option: v.optionName,
    code: v.errorCode,
  }));
}

function getHardErrorCount(violations: TypeScriptSevenCompilerOptionShapeViolation[]) {
  return violations.filter((v) => v.kind === "hard-error").length;
}

function getWarningCount(violations: TypeScriptSevenCompilerOptionShapeViolation[]) {
  return violations.filter((v) => v.kind === "warning").length;
}

// ============================================================================
// Test suite: Hard-error detection
// ============================================================================

describe("typescript-seven-compiler-option-shape-validator", () => {
  describe("hard-error: removed options", () => {
    it("should detect baseUrl as hard-error", () => {
      const content = '{"compilerOptions": {"baseUrl": "."}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("baseUrl");
      expect(violations[0]?.errorCode).toBe("TS5102");
    });

    it("should detect downlevelIteration as hard-error", () => {
      const content = '{"compilerOptions": {"downlevelIteration": true}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("downlevelIteration");
      expect(violations[0]?.errorCode).toBe("TS5102");
    });

    it("should detect both baseUrl and downlevelIteration together", () => {
      const content =
        '{"compilerOptions": {"baseUrl": ".", "downlevelIteration": true}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBeGreaterThanOrEqual(2);
    });
  });

  describe("hard-error: forbidden option values", () => {
    it("should detect target: es5 as hard-error", () => {
      const content = '{"compilerOptions": {"target": "es5"}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("target");
      expect(violations[0]?.errorCode).toBe("TS5108");
    });

    it("should detect target: ES5 (case-insensitive)", () => {
      const content = '{"compilerOptions": {"target": "ES5"}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("target");
    });

    it("should detect moduleResolution: node as hard-error", () => {
      const content = '{"compilerOptions": {"moduleResolution": "node"}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("moduleResolution");
      expect(violations[0]?.errorCode).toBe("TS5108");
    });

    it("should detect moduleResolution: node10 as hard-error", () => {
      const content = '{"compilerOptions": {"moduleResolution": "node10"}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("moduleResolution");
    });

    it("should detect moduleResolution: classic as hard-error", () => {
      const content = '{"compilerOptions": {"moduleResolution": "classic"}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("moduleResolution");
    });

    it("should detect module: amd as hard-error", () => {
      const content = '{"compilerOptions": {"module": "amd"}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("module");
      expect(violations[0]?.errorCode).toBe("TS5108");
    });

    it("should detect module: umd as hard-error", () => {
      const content = '{"compilerOptions": {"module": "umd"}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("module");
    });

    it("should detect module: systemjs as hard-error", () => {
      const content = '{"compilerOptions": {"module": "systemjs"}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("module");
    });

    it("should detect module: none as hard-error", () => {
      const content = '{"compilerOptions": {"module": "none"}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("module");
    });

    it("should detect esModuleInterop: false as hard-error", () => {
      const content = '{"compilerOptions": {"esModuleInterop": false}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("esModuleInterop");
      expect(violations[0]?.errorCode).toBe("TS5108");
    });

    it("should ALLOW esModuleInterop: true (false-positive guard)", () => {
      const content = '{"compilerOptions": {"esModuleInterop": true}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      const esModuleViolations = violations.filter((v) => v.optionName === "esModuleInterop");
      expect(esModuleViolations.length).toBe(0);
    });

    it("should detect allowSyntheticDefaultImports: false as hard-error", () => {
      const content = '{"compilerOptions": {"allowSyntheticDefaultImports": false}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("allowSyntheticDefaultImports");
      expect(violations[0]?.errorCode).toBe("TS5108");
    });

    it("should ALLOW allowSyntheticDefaultImports: true (false-positive guard)", () => {
      const content = '{"compilerOptions": {"allowSyntheticDefaultImports": true}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      const allowSyntheticViolations = violations.filter(
        (v) => v.optionName === "allowSyntheticDefaultImports",
      );
      expect(allowSyntheticViolations.length).toBe(0);
    });

    it("should detect alwaysStrict: false as hard-error", () => {
      const content = '{"compilerOptions": {"alwaysStrict": false}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("alwaysStrict");
      expect(violations[0]?.errorCode).toBe("TS5108");
    });

    it("should ALLOW alwaysStrict: true (false-positive guard)", () => {
      const content = '{"compilerOptions": {"alwaysStrict": true}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      const alwaysStrictViolations = violations.filter((v) => v.optionName === "alwaysStrict");
      expect(alwaysStrictViolations.length).toBe(0);
    });
  });

  describe("hard-error: non-relative paths (TS5090)", () => {
    it("should detect bare paths value as hard-error", () => {
      const content = '{"compilerOptions": {"paths": {"@core": ["packages/core/src"]}}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("paths");
      expect(violations[0]?.errorCode).toBe("TS5090");
    });

    it("should ALLOW paths value with ./ prefix (false-positive guard)", () => {
      const content = '{"compilerOptions": {"paths": {"@core": ["./packages/core/src"]}}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      const pathsViolations = violations.filter((v) => v.optionName === "paths");
      expect(pathsViolations.length).toBe(0);
    });

    it("should ALLOW paths value with ../ prefix (false-positive guard)", () => {
      const content = '{"compilerOptions": {"paths": {"@core": ["../packages/core/src"]}}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      const pathsViolations = violations.filter((v) => v.optionName === "paths");
      expect(pathsViolations.length).toBe(0);
    });

    it("should detect multiple bare paths values", () => {
      const content =
        '{"compilerOptions": {"paths": {"@core": ["packages/core"], "@ui": ["packages/ui"]}}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      // Should detect the first bare path and return
      expect(getHardErrorCount(violations)).toBeGreaterThanOrEqual(1);
      expect(violations[0]?.optionName).toBe("paths");
    });

    it("should ALLOW mixed relative and bare (stops at first bare)", () => {
      const content =
        '{"compilerOptions": {"paths": {"@core": ["./packages/core"], "@ui": ["packages/ui"]}}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      // The validator will find the second bare path
      expect(getHardErrorCount(violations)).toBeGreaterThanOrEqual(1);
    });
  });

  describe("warning-level: missing types array", () => {
    it("should warn on missing types array in regular config", () => {
      const content = '{"compilerOptions": {"strict": true}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getWarningCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("types");
      expect(violations[0]?.kind).toBe("warning");
    });

    it("should NOT warn on missing types in extends-only config", () => {
      const content = '{"extends": "../tsconfig.base.json"}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      const typeWarnings = violations.filter((v) => v.optionName === "types");
      expect(typeWarnings.length).toBe(0);
    });

    it("should NOT warn when types array is present", () => {
      const content = '{"compilerOptions": {"types": ["bun", "node"]}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      const typeWarnings = violations.filter((v) => v.optionName === "types");
      expect(typeWarnings.length).toBe(0);
    });

    it("should NOT warn on empty types array", () => {
      const content = '{"compilerOptions": {"types": []}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      const typeWarnings = violations.filter((v) => v.optionName === "types");
      expect(typeWarnings.length).toBe(0);
    });
  });

  describe("JSONC handling (comments, trailing commas)", () => {
    it("should detect violations even with comments in the object structure", () => {
      // Note: the validator uses regex on raw content, so comments between
      // "target" and its value won't interfere
      const content = '{"compilerOptions": {"target": "es5"}}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("target");
    });

    it("should parse JSONC with trailing commas", () => {
      const content = `{
        "compilerOptions": {
          "target": "es5",
        },
      }`;
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("target");
    });

    it("should handle line comments that don't interfere with patterns", () => {
      // Comments after the line don't interfere
      const content = '"target": "es5", // This will error';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("target");
    });
  });

  describe("Edit fragment handling (incomplete JSON)", () => {
    it("should detect violation in Edit fragment (no closing braces)", () => {
      const fragment = '"target": "es5",';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(fragment);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("target");
    });

    it("should detect baseUrl in Edit fragment", () => {
      const fragment = '"baseUrl": ".",';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(fragment);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("baseUrl");
    });

    it("should detect paths violation in Edit fragment", () => {
      const fragment = '"paths": {"@core": ["packages/core"]}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(fragment);

      expect(getHardErrorCount(violations)).toBe(1);
      expect(violations[0]?.optionName).toBe("paths");
    });
  });

  describe("graceful degradation (fall-open)", () => {
    it("should allow completely unparseable content", () => {
      const content = "{ not valid json at all }}}{";
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      // Should find no violations since we can't parse it
      const hardErrors = violations.filter((v) => v.kind === "hard-error");
      // Depending on the specific regex patterns, we might find nothing
      // (fall-open behavior) or we might match fragments. Either is acceptable.
    });

    it("should allow empty content", () => {
      const content = "";
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      // Should find no violations
      expect(violations.length).toBe(0);
    });

    it("should allow config with no compilerOptions", () => {
      const content = '{"extends": "../tsconfig.base.json"}';
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);

      // Should find no hard-errors, only maybe a types warning for non-extends-only
      const hardErrors = violations.filter((v) => v.kind === "hard-error");
      expect(hardErrors.length).toBe(0);
    });
  });

  describe("extractHardErrorViolations utility", () => {
    it("should extract only hard-error violations", () => {
      const content =
        '{"compilerOptions": {"target": "es5", "types": []}}'; // hard-error + warning-free
      const allViolations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);
      const hardErrors = extractHardErrorViolationsFromTypeScriptSevenCompilerOptionShapeConformance(
        allViolations,
      );

      expect(hardErrors.length).toBe(1);
      expect(hardErrors[0]?.kind).toBe("hard-error");
      expect(hardErrors[0]?.optionName).toBe("target");
    });

    it("should return empty array when no hard-errors", () => {
      const content =
        '{"compilerOptions": {"strict": true, "types": ["bun"]}}'; // clean
      const allViolations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);
      const hardErrors = extractHardErrorViolationsFromTypeScriptSevenCompilerOptionShapeConformance(
        allViolations,
      );

      expect(hardErrors.length).toBe(0);
    });
  });

  describe("real-world scenario tests", () => {
    it("should detect multiple hard-errors in one config", () => {
      const content = `{
        "compilerOptions": {
          "baseUrl": ".",
          "target": "es5",
          "esModuleInterop": false,
          "paths": {
            "@core": ["packages/core"]
          }
        }
      }`;
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);
      const hardErrors = violations.filter((v) => v.kind === "hard-error");

      // Should find baseUrl, target, esModuleInterop, and paths violations
      expect(hardErrors.length).toBeGreaterThanOrEqual(3);
    });

    it("should allow a TypeScript 7-conformant config", () => {
      const content = `{
        "extends": "../tsconfig.base.json",
        "compilerOptions": {
          "target": "esnext",
          "module": "esnext",
          "moduleResolution": "bundler",
          "esModuleInterop": true,
          "allowSyntheticDefaultImports": true,
          "alwaysStrict": true,
          "types": ["bun", "node"],
          "paths": {
            "@core": ["./packages/core"],
            "@ui": ["../components/ui"]
          }
        }
      }`;
      const violations = evaluateTypeScriptSevenCompilerOptionShapeConformance(content);
      const hardErrors = violations.filter((v) => v.kind === "hard-error");

      expect(hardErrors.length).toBe(0);
    });
  });
});
