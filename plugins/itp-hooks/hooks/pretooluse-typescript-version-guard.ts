#!/usr/bin/env bun
/**
 * PreToolUse hook: TypeScript Version Guard (iter-92 orchestrator-inlined)
 *
 * Blocks Write/Edit on package.json files that would introduce or declare
 * a TypeScript version below 7.x (the Go-native tsc era). TypeScript 7 is
 * 8-12x faster for full builds and ~13x faster for time-to-first-error.
 *
 * Doctrine SSoT: ~/.claude/typescript-latest-CLAUDE.md
 * Policy: "typescript": "latest" + commit lockfile. Never a 5.x/6.x pin.
 * The ONE sanctioned exception is compiler-EMBEDDING tooling (Volar family,
 * Angular templates, typescript-eslint, ts-morph) which uses the dual-install
 * alias "typescript": "npm:@typescript/typescript6@^6.0.2" + "@typescript/native":
 * "npm:typescript@latest" — because TS 7.0 ships NO programmatic API until 7.1.
 *
 * Detection scopes (only when basename === "package.json"):
 *   1. Write with legacy "typescript" or "@typescript/*" entry → DENY
 *   2. Edit with proposed fragment containing legacy "typescript" entry → DENY
 *   3. Sanctioned @typescript/typescript6 compat alias → ALLOW (explicit pass-through)
 *   4. Latest / dist-tags / unresolvable protocols → ALLOW (fail-open)
 *
 * Skip: non-package.json files, node_modules paths, MultiEdit (staged-migration
 * convention), plan mode.
 *
 * Escape hatch: ALLOW-LEGACY-TS file-wide marker. Iter-15 fix: for Edit, read
 * the file from disk asynchronously — proposed content may NOT contain the marker,
 * but the on-disk file might (when targeting a region that doesn't span the marker).
 *
 * Iter-92 dual-use contract (mirrors iter-85/86/87/88/89/90/91):
 *   - Standalone CLI mode (preserved for backward-compat + direct testing):
 *     `bun pretooluse-typescript-version-guard.ts < payload.json` runs main()
 *     under the `import.meta.main` guard, reads stdin, emits allow/deny to stdout.
 *   - Orchestrator-inlined mode (NEW owner of the Write|Edit hooks.json slot):
 *     The orchestrator imports `classifyTypeScriptVersionGuardForOrchestrator`
 *     and invokes it directly inside the single bun process — no per-subhook
 *     bun cold-start cost. The classifier MUST conform to the
 *     PreToolUseSubhookContract: pure async function, no stdin/stdout/exit
 *     side-effects, returns a PreToolUseSubhookDecision object.
 *
 * ADR: ~/.claude/typescript-latest-CLAUDE.md § "Enforcement"
 */

import {
  allow,
  deny,
  parseStdinOrAllow,
  isPlanMode,
  createHookLogger,
  type PreToolUseInput,
} from "./pretooluse-helpers.ts";
import { trackHookError } from "./lib/hook-error-tracker.ts";
import {
  ALLOW_DECISION,
  denyDecision,
  isFileEditToolNameHonoredByPreToolUseBlockingSubhook,
  type PreToolUseSubhookDecision,
} from "./lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";
import {
  findTypeScriptDependencySpecifiersInPackageJsonText,
  evaluateTypeScriptVersionSpecifier,
  isBlockingTypeScriptVersionSpecifierVerdict,
} from "./lib/typescript-version-specifier-minimum-major-policy-evaluator.ts";
import {
  hasFileWideEscapeHatchMarkerInContent,
  type EscapeHatchMarkerDetectionConfiguration,
} from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import {
  evaluateTypeScriptSevenCompilerOptionShapeConformance,
  extractHardErrorViolationsFromTypeScriptSevenCompilerOptionShapeConformance,
} from "./lib/typescript-seven-compiler-option-shape-validator-for-tsconfig-files.ts";

// ============================================================================
// Configuration
// ============================================================================

const TYPESCRIPT_VERSION_GUARD_HOOK_NAME = "TYPESCRIPT-VERSION-GUARD";

/** Escape hatch marker configuration (file-wide scope, case-sensitive). */
const TYPESCRIPT_VERSION_GUARD_ALLOW_LEGACY_TS_ESCAPE_HATCH_CONFIGURATION: Pick<
  EscapeHatchMarkerDetectionConfiguration,
  "markerNameTokenIncludingSuffix" | "caseSensitivityMode"
> = {
  markerNameTokenIncludingSuffix: "ALLOW-LEGACY-TS",
  caseSensitivityMode: "CASE_SENSITIVE",
};

// ============================================================================
// Pure classifier (iter-92 orchestrator-inlineable contract)
// ============================================================================

const logger = createHookLogger("TYPESCRIPT-VERSION-GUARD");

/**
 * Pure classifier conforming to PreToolUseSubhookClassifierFunction.
 *
 * Identical logic to the standalone main() below, but factored out so the
 * iter-84 in-process orchestrator can invoke it directly without subprocess-
 * spawning this file (which would cost a full bun cold-start per Write|Edit
 * and defeat the orchestrator's purpose — iter-80 measured ~44ms floor).
 *
 * MUST NOT call allow()/deny() or touch stdin/stdout/process.exit. Returns
 * a decision object that the caller (standalone main OR orchestrator)
 * translates to the appropriate Claude Code response shape.
 *
 * Short-circuit order (cheap → expensive):
 *   1. tool_name not Write/Edit → ALLOW
 *   2. file_path basename is NOT "package.json" → ALLOW
 *   3. file_path contains "node_modules" → ALLOW
 *   4. MultiEdit → ALLOW (staged-migration convention)
 *   5. Plan mode → ALLOW
 *   6. content escape-hatch present → ALLOW
 *   7. Edit AND existing on-disk file contains escape hatch (iter-15 fix) → ALLOW
 *   8. Find TypeScript dependencies + evaluate each → DENY if ANY block
 *   9. all clean → ALLOW
 */
export async function classifyTypeScriptVersionGuardForOrchestrator(
  input: PreToolUseInput,
): Promise<PreToolUseSubhookDecision> {
  const { tool_name, tool_input = {} } = input;

  // Iter-102: route through canonical contract helper
  if (!isFileEditToolNameHonoredByPreToolUseBlockingSubhook(tool_name)) {
    return ALLOW_DECISION;
  }

  // Iter-102 staged-migration short-circuit: MultiEdit payload-shape
  // adaptation is iter-103+ per-classifier work. Preserves status quo.
  if (tool_name === "MultiEdit") {
    return ALLOW_DECISION;
  }

  const filePath = (tool_input.file_path as string) || "";

  // Check both package.json and tsconfig files
  const fileName = filePath.split("/").pop() || "";
  const isPackageJson = fileName === "package.json";
  const isTsconfigFile = fileName === "tsconfig.json" || /^tsconfig(\.[^/]+)?\.json$/i.test(fileName);

  if (!isPackageJson && !isTsconfigFile) {
    return ALLOW_DECISION;
  }

  // Skip node_modules
  if (filePath.includes("node_modules")) {
    return ALLOW_DECISION;
  }

  // Early exit: Skip in plan mode
  const planContext = isPlanMode(input, { checkPermission: true, checkPath: true });
  if (planContext.inPlanMode) {
    logger.debug("Skipping TypeScript version check in plan mode", {
      hook_event: "PreToolUse",
      tool_name,
      trace_id: input.tool_use_id,
      reason: planContext.reason,
      permission_mode: planContext.permissionMode,
    });
    return ALLOW_DECISION;
  }

  const proposedContent = ((tool_input.content as string) || (tool_input.new_string as string) || "");

  // Early exit: Escape hatch comment present in proposed content
  if (hasFileWideEscapeHatchMarkerInContent(proposedContent, TYPESCRIPT_VERSION_GUARD_ALLOW_LEGACY_TS_ESCAPE_HATCH_CONFIGURATION)) {
    logger.debug("TypeScript version check skipped via ALLOW-LEGACY-TS marker in proposed content", {
      file: filePath,
    });
    return ALLOW_DECISION;
  }

  // Iter-15 fix preserved: Edit may target a region NOT containing the marker, but
  // the file on disk has it. We're already gated by filename + non-node_modules
  // so the file read is rare; cost is acceptable.
  if (tool_name === "Edit" && filePath) {
    try {
      const existingFileContent = await Bun.file(filePath).text();
      if (hasFileWideEscapeHatchMarkerInContent(existingFileContent, TYPESCRIPT_VERSION_GUARD_ALLOW_LEGACY_TS_ESCAPE_HATCH_CONFIGURATION)) {
        logger.debug("TypeScript version check skipped via ALLOW-LEGACY-TS marker in on-disk file", {
          file: filePath,
        });
        return ALLOW_DECISION;
      }
    } catch {
      // File doesn't exist or unreadable — fall through to normal check
    }
  }

  // ========================================================================
  // TSCONFIG validation (if this is a tsconfig file)
  // ========================================================================
  if (isTsconfigFile) {
    const tsconfigViolations = evaluateTypeScriptSevenCompilerOptionShapeConformance(proposedContent);
    const hardErrors = extractHardErrorViolationsFromTypeScriptSevenCompilerOptionShapeConformance(tsconfigViolations);

    if (hardErrors.length > 0) {
      const denyReasonLines = [
        `[${TYPESCRIPT_VERSION_GUARD_HOOK_NAME}] TypeScript 7 compiler option violation in ${fileName}`,
        "",
        "TypeScript 7 removed or forbade several compiler options that now cause hard compile errors (TS5102, TS5108, TS5090).",
        "",
        "Violations found:",
        ...hardErrors.map((v) => {
          const code = v.errorCode ? `(${v.errorCode})` : "";
          return `  • ${v.optionName} ${code}: ${v.violationDetail}`;
        }),
        "",
        "Fixes required:",
        ...hardErrors.map((v) => `  • ${v.remediation}`),
        "",
        "Complete migration guide: ~/.claude/typescript-latest-CLAUDE.md § 'What breaks'",
      ];

      const denyReason = denyReasonLines.join("\n");
      return denyDecision(denyReason);
    }

    // All hard-errors passed; allow the edit
    return ALLOW_DECISION;
  }

  // ========================================================================
  // PACKAGE.JSON validation (if this is a package.json file)
  // ========================================================================
  const dependencySpecifiers = findTypeScriptDependencySpecifiersInPackageJsonText(proposedContent);

  if (dependencySpecifiers.length === 0) {
    // No TypeScript dependencies found — OK
    return ALLOW_DECISION;
  }

  // Evaluate each specifier; collect blocking verdicts
  const blockingVerdicts: {
    dependencyName: string;
    specifier: string;
    verdict: ReturnType<typeof evaluateTypeScriptVersionSpecifier>;
  }[] = [];

  for (const { dependencyName, specifier } of dependencySpecifiers) {
    // Special case: @typescript/native-preview is ALWAYS deprecated,
    // regardless of the version specifier (the evaluator's check relies on
    // the specifier containing the package name, which doesn't happen when
    // we pass bare version ranges from package.json parsing).
    if (dependencyName === "@typescript/native-preview") {
      blockingVerdicts.push({
        dependencyName,
        specifier,
        verdict: {
          kind: "deprecated-native-preview",
          rationale: `"${dependencyName}" is FROZEN and deprecated now that TypeScript 7 ships the native compiler as \`tsc\` itself. Use \`typescript@latest\` (nightlies: \`typescript@next\`).`,
        },
      });
      continue;
    }

    const verdict = evaluateTypeScriptVersionSpecifier(specifier);
    if (isBlockingTypeScriptVersionSpecifierVerdict(verdict)) {
      blockingVerdicts.push({ dependencyName, specifier, verdict });
    }
  }

  if (blockingVerdicts.length === 0) {
    // All specifiers are conformant, sanctioned-compat-alias, or unresolvable (fail-open)
    return ALLOW_DECISION;
  }

  // Build deny reason with actionable guidance
  const denyReasonLines = [
    `[${TYPESCRIPT_VERSION_GUARD_HOOK_NAME}] TypeScript version policy violation in ${fileName}`,
    "",
    "TypeScript 7.x (Go-native tsc) is REQUIRED. It is 8–12x faster for full builds, ~13x faster for time-to-first-error.",
    "",
    "Offending dependencies:",
    ...blockingVerdicts.map(({ dependencyName, specifier, verdict }) => {
      const rationale = verdict.kind === "legacy"
        ? `${verdict.rationale}`
        : `${verdict.rationale}`;
      return `  "${dependencyName}": "${specifier}" — ${rationale}`;
    }),
    "",
    "FIX: For most packages, use:",
    '  "typescript": "latest"',
    "",
    "For compiler-EMBEDDING tools (Volar/Vue/Svelte/Astro, Angular templates, typescript-eslint, ts-morph):",
    '  "devDependencies": {',
    '    "@typescript/native": "npm:typescript@latest",',
    '    "typescript": "npm:@typescript/typescript6@^6.0.2"',
    "  }",
    "",
    "Then: commit the regenerated lockfile (bun install, npm ci, etc.).",
    "Escape hatch: Add ALLOW-LEGACY-TS comment if legacy is truly required.",
    "",
    `SSoT: ~/.claude/typescript-latest-CLAUDE.md (read it for complete migration recipe and TS 7 breakage list)`,
  ];

  const denyReason = denyReasonLines.join("\n");
  return denyDecision(denyReason);
}

// ============================================================================
// Standalone main (backward-compat for direct CLI invocation)
// ============================================================================

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("TYPESCRIPT-VERSION-GUARD");
  if (!input) return;

  const decision = await classifyTypeScriptVersionGuardForOrchestrator(input);

  switch (decision.kind) {
    case "deny":
      return deny(decision.reason ?? "(no reason given)");
    case "ask":
      // typescript-version-guard doesn't currently use ask; treat as deny for safety
      return deny(decision.reason ?? "(no reason given)");
    default:
      return allow();
  }
}

// Only run main() when this file is invoked directly. import.meta.main is
// true only for the entry-point script; when the orchestrator imports
// classifyTypeScriptVersionGuardForOrchestrator, this branch does NOT fire.
if (import.meta.main) {
  main().catch((e: unknown) => {
    const message = e instanceof Error ? e.message : String(e);
    trackHookError("pretooluse-typescript-version-guard", `Unhandled error: ${message}`);
    allow();
  });
}
