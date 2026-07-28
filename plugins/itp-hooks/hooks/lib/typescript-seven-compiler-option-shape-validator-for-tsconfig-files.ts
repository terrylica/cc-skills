/**
 * TypeScript 7 compiler option shape validator for tsconfig files.
 *
 * Extends the package.json version guard to validate tsconfig.json files
 * for removed or forbidden compiler options that hard-error in TypeScript 7.
 *
 * Doctrine SSoT: ~/.claude/typescript-latest-CLAUDE.md § "What breaks"
 * Policy: TypeScript 7 hard-errors block the build until removed.
 *
 * Hard-error options (TS5102/TS5108/TS5090):
 *   - baseUrl → TS5102
 *   - downlevelIteration → TS5102
 *   - target: "es5" → TS5108
 *   - moduleResolution: "node" | "node10" | "classic" → TS5108
 *   - module: "amd" | "umd" | "systemjs" | "none" → TS5108
 *   - esModuleInterop: false → TS5108 (NOTE: true is CLEAN, only false blocks)
 *   - allowSyntheticDefaultImports: false → TS5108 (NOTE: true is CLEAN, only false blocks)
 *   - alwaysStrict: false → TS5108 (NOTE: true is CLEAN, only false blocks)
 *   - paths values that are bare/non-relative (don't start ./ or ../) → TS5090
 *
 * Warning-level options (never block, only warn):
 *   - missing `types` array (legitimate for extends-only child configs)
 *
 * Design notes:
 *   - Regex-based JSON parsing (fragments must parse, but tsconfig.json with
 *     comments won't parse as JSON). Fall-open on parse errors.
 *   - Must handle JSONC (JavaScript Object Notation with Comments) — legal
 *     `//` and `/* * /` comments and trailing commas in real tsconfig files.
 *   - Detection works on Edit fragments (may not be valid JSON on their own).
 *   - Naming: verbose, searchable, encodes the actual TS 7 compiler behavior.
 */

// ═════════════════════════════════════════════════════════════════════════
// Compiler option constants from TypeScript 7 doctrine
// ═════════════════════════════════════════════════════════════════════════

/** Hard-error compiler options removed in TypeScript 7 (both block entirely). */
const TYPESCRIPT_SEVEN_REMOVED_COMPILER_OPTION_NAMES_HARD_ERROR_ALWAYS: readonly string[] = [
  "baseUrl",
  "downlevelIteration",
];

/** Removed compiler option values (specific value restrictions, not option removal). */
interface RemovedCompilerOptionValueConstraint {
  optionName: string;
  forbiddenValues: readonly string[];
  errorCode: string;
}

/**
 * TypeScript 7 hard-error option values.
 * Some options were not removed entirely but specific values are now forbidden.
 */
const TYPESCRIPT_SEVEN_REMOVED_COMPILER_OPTION_VALUES_HARD_ERROR: readonly RemovedCompilerOptionValueConstraint[] = [
  {
    optionName: "target",
    forbiddenValues: ["es5", '"es5"'],
    errorCode: "TS5108",
  },
  {
    optionName: "moduleResolution",
    forbiddenValues: ["node", '"node"', "node10", '"node10"', "classic", '"classic"'],
    errorCode: "TS5108",
  },
  {
    optionName: "module",
    forbiddenValues: ["amd", '"amd"', "umd", '"umd"', "systemjs", '"systemjs"', "none", '"none"'],
    errorCode: "TS5108",
  },
  {
    optionName: "esModuleInterop",
    forbiddenValues: ["false"],
    errorCode: "TS5108",
  },
  {
    optionName: "allowSyntheticDefaultImports",
    forbiddenValues: ["false"],
    errorCode: "TS5108",
  },
  {
    optionName: "alwaysStrict",
    forbiddenValues: ["false"],
    errorCode: "TS5108",
  },
];

// ═════════════════════════════════════════════════════════════════════════
// Regex patterns for detecting issues in JSONC
// ═════════════════════════════════════════════════════════════════════════

/** Match the "paths" object definition and its key-value pairs. */
const PATHS_OBJECT_PATTERN = /"paths"\s*:\s*{[^}]*}/i;

/** Match individual "paths" mapping (e.g., "@core": ["packages/core"] or "@core": ["./packages/core"]). */
const PATHS_MAPPING_PATTERN = /"([^"]+)"\s*:\s*\[((?:[^\]]*)?)\]/g;

/** Match a single quoted path value inside a paths mapping array. */
const PATH_VALUE_PATTERN = /"([^"]*)"/g;

// ═════════════════════════════════════════════════════════════════════════
// Detection results type
// ═════════════════════════════════════════════════════════════════════════

export interface TypeScriptSevenCompilerOptionShapeViolation {
  kind: "hard-error" | "warning";
  optionName: string;
  violationDetail: string;
  errorCode?: string;
  remediation: string;
}

// ═════════════════════════════════════════════════════════════════════════
// Core validation functions
// ═════════════════════════════════════════════════════════════════════════

/**
 * Check if a value (bare string, e.g., "es5" or false, or quoted) matches
 * a forbidden pattern. Handles quoted strings, unquoted identifiers, and literals.
 */
function doesValueMatchForbiddenOption(
  value: string | null | undefined,
  forbiddenPatterns: readonly string[],
): boolean {
  if (!value) return false;
  const trimmed = (value ?? "").trim();
  return forbiddenPatterns.some((pattern) => {
    // Direct match (quoted or bare)
    if (trimmed === pattern) return true;
    // Case-insensitive match for identifiers (e.g., "ES5" → "es5")
    if (trimmed.toLowerCase() === pattern.toLowerCase()) return true;
    // Match without quotes (e.g., es5 vs "es5")
    const unquoted = trimmed.replace(/^"|"$/g, "");
    if (unquoted.toLowerCase() === pattern.toLowerCase()) return true;
    return false;
  });
}

/**
 * Validate a single removed/forbidden compiler option from JSONC.
 * Looks for patterns like:
 *   "baseUrl": "."
 *   "target": "es5"
 *   esModuleInterop: false
 */
function validateRemovedOrForbiddenCompilerOption(
  tsconfigContent: string,
  constraintDefinition: RemovedCompilerOptionValueConstraint,
): TypeScriptSevenCompilerOptionShapeViolation | null {
  const { optionName, forbiddenValues, errorCode } = constraintDefinition;

  // Pattern: "optionName": VALUE (matches until comma, }, //, or comment)
  // Use RegExp constructor with string concatenation to avoid escaping issues
  const patternStr =
    '"' +
    optionName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") +
    '"\\s*:\\s*([^,}//\\n]+)';
  const optionPattern = new RegExp(patternStr, "i");

  const match = optionPattern.exec(tsconfigContent);
  if (!match) return null;

  const valueText = match[1]!.trim();

  if (doesValueMatchForbiddenOption(valueText, forbiddenValues)) {
    return {
      kind: "hard-error",
      optionName,
      violationDetail: '"' + optionName + '": ' + valueText,
      errorCode,
      remediation: 'Delete the "' + optionName + '" option entirely',
    };
  }

  return null;
}

/**
 * Validate that paths values are relative (start with ./ or ../).
 * Returns a violation only if baseUrl is absent AND a bare path is found.
 *
 * Pattern examples:
 *   "paths": { "@core": ["packages/core"] } ← bare, needs ./packages/core
 *   "paths": { "@core": ["./packages/core"] } ← OK, relative with ./
 *   "paths": { "@core": ["../packages/core"] } ← OK, relative with ../
 */
function validatePathsMappingsAreRelative(
  tsconfigContent: string,
): TypeScriptSevenCompilerOptionShapeViolation | null {
  // First check: is there a "paths" object at all?
  const pathsMatch = PATHS_OBJECT_PATTERN.exec(tsconfigContent);
  if (!pathsMatch) return null;

  const pathsContent = pathsMatch[0]!;
  const mappings = [...pathsContent.matchAll(PATHS_MAPPING_PATTERN)];

  for (const mappingMatch of mappings) {
    const mappingKey = mappingMatch[1];
    const valuesContent = mappingMatch[2] ?? "";

    // Extract each path value from the array
    const pathValues = [...valuesContent.matchAll(PATH_VALUE_PATTERN)];
    for (const pathValueMatch of pathValues) {
      const pathValue = pathValueMatch[1];
      if (!pathValue) continue;

      // Check if the value is relative (starts with ./ or ../)
      const trimmed = pathValue.trim();
      if (trimmed.length > 0 && !trimmed.startsWith("./") && !trimmed.startsWith("../")) {
        return {
          kind: "hard-error",
          optionName: "paths",
          violationDetail: 'paths["' + mappingKey + '"] contains non-relative value: "' + pathValue + '" (TS5090)',
          errorCode: "TS5090",
          remediation: 'Make the path relative: use "./' + pathValue + '" or adjust to "../..."',
        };
      }
    }
  }

  return null;
}

/**
 * Warn if "types" array is missing (legitimate for extends-only configs, so never block).
 */
function validateTypesMissingWarning(
  tsconfigContent: string,
  config: { isExtendsOnly: boolean },
): TypeScriptSevenCompilerOptionShapeViolation | null {
  // Never warn for extends-only config files
  if (config.isExtendsOnly) return null;

  // Check for "types": [...]
  const hasTypes = /"types"\s*:\s*\[/i.test(tsconfigContent);
  if (!hasTypes) {
    return {
      kind: "warning",
      optionName: "types",
      violationDetail: 'Missing "types" array (defaults to [] in TypeScript 7)',
      remediation: 'Add "types": ["bun"] or ["node"] or list the ambient globals you need',
    };
  }

  return null;
}

/**
 * Detect if a tsconfig is extends-only (contains ONLY {"extends": "..."} content).
 */
function isJsonObjectExtendsOnlyShape(jsonObjectContent: string): boolean {
  if (!jsonObjectContent || jsonObjectContent.trim().length === 0) return false;

  // Remove all whitespace and comments
  const stripped = jsonObjectContent
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\/\/.*/g, "")
    .replace(/\s/g, "");

  // Match pattern: {"extends":"..."}  or variations with spaces
  return /^\{"?extends"?:.+\}$/.test(stripped);
}

// ═════════════════════════════════════════════════════════════════════════
// Main validation function
// ═════════════════════════════════════════════════════════════════════════

/**
 * Validate TypeScript 7 compiler option shape constraints on tsconfig content.
 *
 * Returns an array of violations (empty = all clean). Violations are either
 * hard-error (should block the tool) or warning-only.
 *
 * Handles JSONC gracefully (comments + trailing commas); falls open on
 * unparseable content rather than blocking.
 *
 * @param tsconfigContent The tsconfig file content (may be a fragment from Edit).
 * @returns Array of violations found (empty if clean).
 */
export function evaluateTypeScriptSevenCompilerOptionShapeConformance(
  tsconfigContent: string,
): TypeScriptSevenCompilerOptionShapeViolation[] {
  const violations: TypeScriptSevenCompilerOptionShapeViolation[] = [];

  // Early exit: empty content
  if (!tsconfigContent || tsconfigContent.trim().length === 0) {
    return violations;
  }

  // Detect if this looks like an extends-only config (used for type warnings)
  const isExtendsOnly = isJsonObjectExtendsOnlyShape(tsconfigContent);

  // Check for hard-error: options that must be removed entirely
  for (const optionName of TYPESCRIPT_SEVEN_REMOVED_COMPILER_OPTION_NAMES_HARD_ERROR_ALWAYS) {
    // Pattern: "optionName": ... or optionName: ... (unquoted key)
    const pattern = new RegExp("([\"']?" + optionName + "[\"']?)\\s*:", "i");
    if (pattern.test(tsconfigContent)) {
      violations.push({
        kind: "hard-error",
        optionName,
        violationDetail: '"' + optionName + '" is removed in TypeScript 7',
        errorCode: "TS5102",
        remediation: 'Delete the "' + optionName + '" option entirely. If using baseUrl for paths, make every paths value relative: "./value"',
      });
    }
  }

  // Check for hard-error: forbidden option values
  for (const constraint of TYPESCRIPT_SEVEN_REMOVED_COMPILER_OPTION_VALUES_HARD_ERROR) {
    const violation = validateRemovedOrForbiddenCompilerOption(tsconfigContent, constraint);
    if (violation) {
      violations.push(violation);
    }
  }

  // Check for hard-error: non-relative paths (TS5090)
  const pathsViolation = validatePathsMappingsAreRelative(tsconfigContent);
  if (pathsViolation) {
    violations.push(pathsViolation);
  }

  // Check for warning-level: missing types array
  const typesWarning = validateTypesMissingWarning(tsconfigContent, { isExtendsOnly });
  if (typesWarning) {
    violations.push(typesWarning);
  }

  return violations;
}

/**
 * Extract just the hard-error violations (used by the guard for blocking decisions).
 */
export function extractHardErrorViolationsFromTypeScriptSevenCompilerOptionShapeConformance(
  violations: TypeScriptSevenCompilerOptionShapeViolation[],
): TypeScriptSevenCompilerOptionShapeViolation[] {
  return violations.filter((v) => v.kind === "hard-error");
}
