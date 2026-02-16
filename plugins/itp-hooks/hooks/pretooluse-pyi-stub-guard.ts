#!/usr/bin/env bun
/**
 * PreToolUse hook: Python __init__ Structure Guard
 *
 * Enforces thin __init__ files for Python packages.
 * Prevents monolithic __init__.py and __init__.pyi files by blocking
 * Write/Edit operations that add class/function DEFINITIONS.
 *
 * __init__.py / __init__.pyi should ONLY contain:
 *   - Re-exports: from .module import Name (as Name)
 *   - __all__, __version__, __getattr__ (init boilerplate)
 *   - Lazy import machinery
 *
 * Actual definitions belong in dedicated modules:
 *   - models.py (not __init__.py)
 *   - constants.pyi (not __init__.pyi)
 *
 * Escape hatch: # INIT-MONOLITH-OK comment in content
 *
 * Applies to: Any Python repository (not project-specific)
 */

import { parseStdinOrAllow, allow, deny, trackHookError } from "./pretooluse-helpers.ts";

const HOOK_NAME = "INIT-STRUCTURE-GUARD";

/**
 * Patterns that indicate DEFINITIONS (not allowed in __init__ files):
 * - class Foo: / class Foo(Base):
 * - def foo(  /  async def foo(
 * - @overload / @dataclass_transform / @final
 *
 * We look for these at the TOP LEVEL (not indented), which distinguishes
 * definitions from re-exports like `from .module import Name as Name`.
 */
const DEFINITION_PATTERNS: Array<{ pattern: RegExp; label: string }> = [
  // class Foo: or class Foo(Bar):  — top-level (not indented)
  { pattern: /^class\s+\w+[\s(:]/, label: "class definition" },
  // def foo(  or  async def foo(  — top-level
  { pattern: /^(?:async\s+)?def\s+\w+\s*\(/, label: "function definition" },
  // @overload / @dataclass_transform etc. at top level (decorators for definitions)
  { pattern: /^@(?:overload|dataclass_transform|final)/, label: "decorator (implies definition)" },
];

/**
 * Function names that are legitimate __init__.py boilerplate.
 * These are standard Python patterns for package initialization
 * and should not trigger the guard.
 */
const INIT_PY_EXEMPT_FUNCTIONS = new Set([
  "__getattr__",    // Lazy import pattern (PEP 562)
  "__dir__",        // Custom dir() for package
  "__init_subclass__",
  "_lazy_import",   // Common lazy import helper name
]);

/**
 * Check if a function definition line is exempt __init__.py boilerplate.
 */
function isExemptFunction(line: string): boolean {
  for (const name of INIT_PY_EXEMPT_FUNCTIONS) {
    if (line.includes(`def ${name}(`)) return true;
  }
  return false;
}

/**
 * Find top-level definitions in content.
 * Returns the offending lines (up to 5) for the denial message.
 */
function findDefinitions(content: string, isPyi: boolean): string[] {
  const lines = content.split("\n");
  const violations: string[] = [];

  // Track if we're inside a docstring (triple-quote block)
  let inDocstring = false;

  for (const line of lines) {
    const trimmed = line.trimEnd();

    // Skip empty lines
    if (trimmed === "") continue;

    // Track triple-quote docstrings
    const tripleDoubleCount = (trimmed.match(/"""/g) || []).length;
    const tripleSingleCount = (trimmed.match(/'''/g) || []).length;
    const tripleCount = tripleDoubleCount + tripleSingleCount;

    if (inDocstring) {
      if (tripleCount % 2 === 1) {
        inDocstring = false;
      }
      continue;
    }

    if (tripleCount > 0) {
      if (tripleCount % 2 === 1) {
        inDocstring = true;
      }
      continue;
    }

    // Skip comments
    if (trimmed.startsWith("#")) continue;

    // Skip indented lines (only check top-level definitions)
    if (line.startsWith(" ") || line.startsWith("\t")) continue;

    // Check each definition pattern
    for (const { pattern, label } of DEFINITION_PATTERNS) {
      if (pattern.test(trimmed)) {
        // For .py files, exempt standard __init__ boilerplate functions
        if (!isPyi && label === "function definition" && isExemptFunction(trimmed)) {
          break;
        }
        violations.push(`  ${label}: ${trimmed.slice(0, 80)}`);
        break;
      }
    }

    // Stop early if we have enough examples
    if (violations.length >= 5) break;
  }

  return violations;
}

/**
 * Check if the file is a __init__.py or __init__.pyi.
 * Returns { isInit: boolean, isPyi: boolean }.
 */
function classifyFile(filePath: string): { isInit: boolean; isPyi: boolean } {
  if (filePath.endsWith("__init__.pyi")) return { isInit: true, isPyi: true };
  if (filePath.endsWith("__init__.py")) return { isInit: true, isPyi: false };
  return { isInit: false, isPyi: false };
}

async function main() {
  const input = await parseStdinOrAllow(HOOK_NAME);
  if (!input) return;

  const { tool_name, tool_input } = input;

  // Only check Write and Edit tools
  if (tool_name !== "Write" && tool_name !== "Edit") {
    allow();
    return;
  }

  const filePath = tool_input.file_path || "";
  const { isInit, isPyi } = classifyFile(filePath);

  // Only check __init__.py and __init__.pyi files
  if (!isInit) {
    allow();
    return;
  }

  // Determine the content to check
  // For Write: check `content`
  // For Edit: check `new_string` (the replacement text)
  const content = tool_name === "Write"
    ? (tool_input.content || "")
    : (tool_input.new_string || "");

  if (!content) {
    allow();
    return;
  }

  // Escape hatch: allow if content contains the opt-out comment
  if (content.includes("# INIT-MONOLITH-OK")) {
    allow();
    return;
  }

  const violations = findDefinitions(content, isPyi);

  if (violations.length === 0) {
    allow();
    return;
  }

  // For Write: also check if it's mostly re-exports (heuristic).
  // If >70% of meaningful lines are imports, it's a re-export index
  // that happens to have a few annotations — allow it.
  if (tool_name === "Write") {
    const meaningfulLines = content.split("\n").filter(
      (l) => l.trim() !== "" && !l.trim().startsWith("#")
    );
    const importLines = meaningfulLines.filter((l) =>
      l.trim().startsWith("from ") || l.trim().startsWith("import ")
    );
    if (meaningfulLines.length > 0 && importLines.length / meaningfulLines.length > 0.7) {
      allow();
      return;
    }
  }

  const fileType = isPyi ? "__init__.pyi" : "__init__.py";
  const violationList = violations.join("\n");

  const guidance = isPyi
    ? `**PEP 561 best practice**: Place type definitions in per-module .pyi files:
  - constants.pyi (next to constants.py)
  - models.pyi (next to models.py)

${fileType} should only contain re-exports:
  from .module import Name as Name`
    : `**Clean package structure**: Place definitions in dedicated modules:
  - class MyModel → models.py (not __init__.py)
  - def helper() → utils.py or helpers.py (not __init__.py)

${fileType} should only contain:
  - Re-exports: from .module import Name
  - __all__ list
  - __getattr__ for lazy imports
  - __version__ assignment`;

  deny(
    `[${HOOK_NAME}] ${fileType} should be a thin re-export layer, not contain definitions.

Found ${violations.length} top-level definition(s):
${violationList}

${guidance}

**To override**: Add \`# INIT-MONOLITH-OK\` comment to the file content.`
  );
}

main().catch((err) => {
  trackHookError("pretooluse-pyi-stub-guard", err instanceof Error ? err.message : String(err));
  allow(); // Fail-open
});
