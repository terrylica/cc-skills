#!/usr/bin/env bun
/**
 * PreToolUse hook: Python __init__.py / __init__.pyi Top-Level Definition Monolith Guard (iter-89 orchestrator-inlined)
 *
 * NOTE ON FILENAME-vs-ALGORITHM NAMING DRIFT (surfaced by iter-89 adversarial audit):
 * The filename `pretooluse-pyi-stub-guard.ts` and the historical itp-hooks
 * CLAUDE.md row described this as ".pyi stub file signature validation",
 * but the actual algorithm validates that Python `__init__.py` AND
 * `__init__.pyi` files contain ONLY re-exports (no top-level class/def
 * definitions) — enforcing the "thin __init__ layer" idiom from PEP 561 +
 * clean-package-structure best practice. The filename is preserved for
 * backward-compat (downstream installations may have entries pointing at
 * this path); the more-precise classifier name `classifyInitFileTopLevelDefinitionMonolithGuardForOrchestrator`
 * encodes the actual algorithm per the user's "verbose, specific,
 * searchable, distinctive names" rule. Re-export wrapper
 * `classifyPyiStubGuardForOrchestrator` is also exported solely to maintain
 * the existing 5-subhook naming pattern (`classify<HookFilenamePrefix>ForOrchestrator`)
 * for consistency with the iter-84/85/86/87/88 migration cohort.
 *
 * Enforced policy:
 *   __init__.py / __init__.pyi files MUST be thin re-export layers.
 *   Top-level `class Foo:`, `def foo(...)`, `@overload`-decorated defs are
 *   blocked unless the file content includes the `# INIT-MONOLITH-OK`
 *   escape-hatch comment.
 *
 * Plan Mode: NOT explicitly skipped (algorithm is cheap and edit-time only;
 * if planning a structural refactor that legitimately moves a class into an
 * __init__.py, use the escape-hatch comment).
 *
 * Iter-89 dual-use contract (mirrors iter-85/86/87/88 migrations):
 *   - Standalone CLI mode (preserved for backward-compat + direct testing):
 *     `bun pretooluse-pyi-stub-guard.ts < payload.json` runs main() under
 *     `import.meta.main` guard.
 *   - Orchestrator-inlined mode (NEW owner of the Write|Edit hooks.json slot):
 *     The orchestrator imports `classifyPyiStubGuardForOrchestrator` and
 *     invokes it directly in the single bun process. Conforms to
 *     PreToolUseSubhookContract.
 */

import {
  parseStdinOrAllow,
  deny,
  allow,
  trackHookError,
  type PreToolUseInput,
} from "./pretooluse-helpers.ts";
import {
  ALLOW_DECISION,
  denyDecision,
  type PreToolUseSubhookDecision,
} from "./lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";

// ============================================================================
// Configuration
// ============================================================================

const PYI_STUB_GUARD_HOOK_NAME = "INIT-STRUCTURE-GUARD";

/**
 * The ratio above which a Write payload is considered a legitimate re-export
 * index that incidentally contains a few annotated class/def definitions
 * (typical pattern: `from .x import A as A; class _ReExportedSentinel: ...`).
 * Applied ONLY to Write (not Edit) because Edit's `new_string` is partial
 * content and the ratio would be misleading.
 */
const REEXPORT_DOMINATED_INIT_PY_FILE_IMPORTS_TO_MEANINGFUL_LINES_RATIO_THRESHOLD = 0.7;

/**
 * Maximum number of violation lines to surface in the deny message. Cap
 * prevents pathological monolith __init__.py files (hundreds of defs) from
 * flooding the deny payload past Claude Code's reason-display window.
 */
const PYI_STUB_GUARD_VIOLATION_SAMPLE_CAP = 5;

/**
 * Patterns that indicate top-level Python DEFINITIONS — explicitly NOT
 * permitted at the top level of an __init__.py / __init__.pyi.
 *
 * The pattern test runs AFTER an indented-line filter (line.startsWith(" "|"\t")),
 * so these regexes do not need to anchor against indentation.
 */
const PYTHON_TOP_LEVEL_DEFINITION_REGEX_PATTERNS: Array<{ pattern: RegExp; label: string }> = [
  { pattern: /^class\s+\w+[\s(:]/, label: "class definition" },
  { pattern: /^(?:async\s+)?def\s+\w+\s*\(/, label: "function definition" },
  { pattern: /^@(?:overload|dataclass_transform|final)/, label: "decorator (implies definition)" },
];

/**
 * Function names that are legitimate __init__.py boilerplate per PEP 562
 * and idiomatic Python packaging. These are exempted from the
 * "function definition" pattern when scanning __init__.py (NOT .pyi —
 * stubs have stricter rules per PEP 561).
 */
const INIT_PY_EXEMPT_BOILERPLATE_FUNCTION_NAMES = new Set([
  "__getattr__",        // PEP 562 lazy-import pattern
  "__dir__",            // Custom dir() for package
  "__init_subclass__",
  "_lazy_import",       // Common lazy-import helper name (community idiom)
]);

// ============================================================================
// Detection Functions
// ============================================================================

/** Check if a function-definition line targets an exempt __init__.py boilerplate name. */
function lineDefinesExemptInitPyBoilerplateFunction(line: string): boolean {
  for (const exemptName of INIT_PY_EXEMPT_BOILERPLATE_FUNCTION_NAMES) {
    if (line.includes(`def ${exemptName}(`)) return true;
  }
  return false;
}

/**
 * Scan Python content for top-level definitions. Returns violation strings
 * (label + sliced line, max 80 chars) up to PYI_STUB_GUARD_VIOLATION_SAMPLE_CAP.
 * Honors triple-quote docstring state so docstring text doesn't false-positive.
 */
function findTopLevelDefinitionViolationsInPythonInitFileContent(
  content: string,
  isPyiStubFile: boolean,
): string[] {
  const lines = content.split("\n");
  const violations: string[] = [];
  let insideTripleQuoteDocstringBlock = false;

  for (const line of lines) {
    const trimmedRightWhitespace = line.trimEnd();
    if (trimmedRightWhitespace === "") continue;

    const tripleDoubleQuoteOccurrenceCount = (trimmedRightWhitespace.match(/"""/g) || []).length;
    const tripleSingleQuoteOccurrenceCount = (trimmedRightWhitespace.match(/'''/g) || []).length;
    const totalTripleQuoteOccurrencesOnLine = tripleDoubleQuoteOccurrenceCount + tripleSingleQuoteOccurrenceCount;

    if (insideTripleQuoteDocstringBlock) {
      if (totalTripleQuoteOccurrencesOnLine % 2 === 1) {
        insideTripleQuoteDocstringBlock = false;
      }
      continue;
    }

    if (totalTripleQuoteOccurrencesOnLine > 0) {
      if (totalTripleQuoteOccurrencesOnLine % 2 === 1) {
        insideTripleQuoteDocstringBlock = true;
      }
      continue;
    }

    if (trimmedRightWhitespace.startsWith("#")) continue;
    // Indented lines are not top-level; skip
    if (line.startsWith(" ") || line.startsWith("\t")) continue;

    for (const { pattern, label } of PYTHON_TOP_LEVEL_DEFINITION_REGEX_PATTERNS) {
      if (pattern.test(trimmedRightWhitespace)) {
        if (!isPyiStubFile && label === "function definition" && lineDefinesExemptInitPyBoilerplateFunction(trimmedRightWhitespace)) {
          break;
        }
        violations.push(`  ${label}: ${trimmedRightWhitespace.slice(0, 80)}`);
        break;
      }
    }

    if (violations.length >= PYI_STUB_GUARD_VIOLATION_SAMPLE_CAP) break;
  }

  return violations;
}

/**
 * Returns {isInitPackageInitFile, isPyiStubFile} for a target file path.
 * - `__init__.pyi` → {true, true}   (stub file under stricter PEP 561 rules)
 * - `__init__.py`  → {true, false}  (runtime package init)
 * - anything else  → {false, false} (fastpath skip)
 */
function classifyPythonInitFilePathSuffix(filePath: string): {
  isInitPackageInitFile: boolean;
  isPyiStubFile: boolean;
} {
  if (filePath.endsWith("__init__.pyi")) return { isInitPackageInitFile: true, isPyiStubFile: true };
  if (filePath.endsWith("__init__.py")) return { isInitPackageInitFile: true, isPyiStubFile: false };
  return { isInitPackageInitFile: false, isPyiStubFile: false };
}

/**
 * Apply the "re-export-dominated" heuristic ONLY to Write payloads (Edit's
 * partial content makes the ratio meaningless). Returns true if the file is
 * mostly imports and should be allowed despite minor definition findings.
 */
function isLikelyReExportDominatedInitPyFileWriteContent(content: string): boolean {
  const meaningfulLines = content.split("\n").filter(
    (l) => l.trim() !== "" && !l.trim().startsWith("#"),
  );
  if (meaningfulLines.length === 0) return false;
  const importLines = meaningfulLines.filter(
    (l) => l.trim().startsWith("from ") || l.trim().startsWith("import "),
  );
  const importsToMeaningfulRatio = importLines.length / meaningfulLines.length;
  return importsToMeaningfulRatio > REEXPORT_DOMINATED_INIT_PY_FILE_IMPORTS_TO_MEANINGFUL_LINES_RATIO_THRESHOLD;
}

/** Build the "where to put it instead" guidance text shown in the deny message. */
function buildInitFileMonolithRefactoringGuidance(isPyiStubFile: boolean, displayFileType: string): string {
  if (isPyiStubFile) {
    return [
      "**PEP 561 best practice**: Place type definitions in per-module .pyi files:",
      "  - constants.pyi (next to constants.py)",
      "  - models.pyi (next to models.py)",
      "",
      `${displayFileType} should only contain re-exports:`,
      "  from .module import Name as Name",
    ].join("\n");
  }
  return [
    "**Clean package structure**: Place definitions in dedicated modules:",
    "  - class MyModel → models.py (not __init__.py)",
    "  - def helper() → utils.py or helpers.py (not __init__.py)",
    "",
    `${displayFileType} should only contain:`,
    "  - Re-exports: from .module import Name",
    "  - __all__ list",
    "  - __getattr__ for lazy imports",
    "  - __version__ assignment",
  ].join("\n");
}

// ============================================================================
// Pure classifier (iter-89 orchestrator-inlineable contract)
// ============================================================================

/**
 * Pure classifier conforming to PreToolUseSubhookClassifierFunction.
 *
 * Algorithm: scan Write/Edit payload content of any `__init__.py` /
 * `__init__.pyi` file for top-level class/def/decorator definitions
 * (with docstring-state tracking, exempt-boilerplate carve-out for .py,
 * and a re-export-dominated-write heuristic). DENY on hit unless the
 * `# INIT-MONOLITH-OK` escape-hatch comment is present in content.
 *
 * Short-circuit order (cheap → expensive):
 *   1. tool_name not Write/Edit → ALLOW
 *   2. file path not __init__.py/.pyi suffix → ALLOW (O(1) endsWith fastpath)
 *   3. no content → ALLOW
 *   4. content contains escape-hatch comment → ALLOW
 *   5. scan content → if violations + (Edit OR not re-export-dominated) → DENY
 *   6. all clean → ALLOW
 *
 * MUST NOT call allow()/deny() or touch stdin/stdout/process.exit.
 */
export async function classifyInitFileTopLevelDefinitionMonolithGuardForOrchestrator(
  input: PreToolUseInput,
): Promise<PreToolUseSubhookDecision> {
  const { tool_name, tool_input } = input;

  if (tool_name !== "Write" && tool_name !== "Edit") {
    return ALLOW_DECISION;
  }

  const filePath = (tool_input?.file_path as string) || "";
  const { isInitPackageInitFile, isPyiStubFile } = classifyPythonInitFilePathSuffix(filePath);

  if (!isInitPackageInitFile) {
    return ALLOW_DECISION;
  }

  // For Write: check `content`. For Edit: check `new_string` (the proposed replacement).
  const content = tool_name === "Write"
    ? ((tool_input?.content as string) || "")
    : ((tool_input?.new_string as string) || "");

  if (!content) {
    return ALLOW_DECISION;
  }

  // Escape hatch
  if (content.includes("# INIT-MONOLITH-OK")) {
    return ALLOW_DECISION;
  }

  const violations = findTopLevelDefinitionViolationsInPythonInitFileContent(content, isPyiStubFile);
  if (violations.length === 0) {
    return ALLOW_DECISION;
  }

  // Re-export-dominated heuristic — Write only (Edit's partial new_string is misleading)
  if (tool_name === "Write" && isLikelyReExportDominatedInitPyFileWriteContent(content)) {
    return ALLOW_DECISION;
  }

  const displayFileType = isPyiStubFile ? "__init__.pyi" : "__init__.py";
  const violationListAsText = violations.join("\n");
  const guidance = buildInitFileMonolithRefactoringGuidance(isPyiStubFile, displayFileType);

  const message = [
    `[${PYI_STUB_GUARD_HOOK_NAME}] ${displayFileType} should be a thin re-export layer, not contain definitions.`,
    "",
    `Found ${violations.length} top-level definition(s):`,
    violationListAsText,
    "",
    guidance,
    "",
    "**To override**: Add `# INIT-MONOLITH-OK` comment to the file content.",
  ].join("\n");

  return denyDecision(message);
}

/**
 * Backward-compat re-export. The orchestrator registry imports the classifier
 * under the `classifyPyiStubGuardForOrchestrator` name to keep symmetric naming
 * with the other 5 inlined subhooks (`classify<FilenamePrefix>ForOrchestrator`),
 * while the true algorithm-encoding name above is what should be read
 * for understanding the actual policy.
 */
export const classifyPyiStubGuardForOrchestrator = classifyInitFileTopLevelDefinitionMonolithGuardForOrchestrator;

// ============================================================================
// Standalone main (backward-compat for direct CLI invocation)
// ============================================================================

async function main(): Promise<void> {
  const input = await parseStdinOrAllow(PYI_STUB_GUARD_HOOK_NAME);
  if (!input) return;

  const decision = await classifyInitFileTopLevelDefinitionMonolithGuardForOrchestrator(input);
  switch (decision.kind) {
    case "deny":
      return deny(decision.reason ?? "(no reason given)");
    case "ask":
      // Standalone CLI has no `ask` helper analog → fall through to deny
      // so the user still sees the blocking message. Orchestrator path
      // handles `ask` correctly via belt-and-suspenders.
      return deny(decision.reason ?? "(no reason given)");
    default:
      return allow();
  }
}

// import.meta.main is true only for the entry-point script; when the orchestrator
// imports classifyPyiStubGuardForOrchestrator, this branch does NOT fire.
if (import.meta.main) {
  main().catch((err: unknown) => {
    trackHookError("pretooluse-pyi-stub-guard", err instanceof Error ? err.message : String(err));
    allow();
  });
}
