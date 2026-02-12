#!/usr/bin/env bun
/**
 * PreToolUse hook: File Size Bloat Guard
 *
 * Prevents single-file bloat by checking line count before Write/Edit.
 * Uses "ask" mode by default so the user can override when intentional.
 *
 * Detection:
 * - Write: counts lines in proposed content
 * - Edit: reads existing file, applies edit, counts resulting lines
 *
 * Thresholds (per-extension, configurable via .claude/file-size-guard.json):
 *   Default: warn >500 lines, block >1000 lines
 *   .rs:    warn >500, block >1000 (Rust — PyO3 bindings tend to bloat)
 *   .py:    warn >500, block >1000
 *   .ts:    warn >500, block >1000
 *   .md:    warn >800, block >1500 (docs are naturally longer)
 *
 * Escape hatches:
 *   - "# FILE-SIZE-OK" comment anywhere in file
 *   - Plan mode (auto-skipped)
 *   - Glob patterns in config excludes
 *
 * ADR: (pending — will be created if hook proves valuable)
 */

import { readFileSync, existsSync } from "fs";
import { join } from "path";
import {
  parseStdinOrAllow,
  allow,
  ask,
  isPlanMode,
  createHookLogger,
} from "./pretooluse-helpers.ts";

// ============================================================================
// Configuration
// ============================================================================

interface ExtensionThresholds {
  warn: number;
  block: number;
}

interface GuardConfig {
  /** Default thresholds for any file extension */
  defaults: ExtensionThresholds;
  /** Per-extension overrides (key is extension with dot, e.g. ".rs") */
  extensions: Record<string, ExtensionThresholds>;
  /** Glob patterns to exclude from checking (e.g. "*.generated.ts") */
  excludes: string[];
  /** Escape hatch comment — if found in file, skip check */
  escapeComment: string;
}

const DEFAULT_CONFIG: GuardConfig = {
  defaults: { warn: 500, block: 1000 },
  extensions: {
    ".rs": { warn: 500, block: 1000 },
    ".py": { warn: 500, block: 1000 },
    ".ts": { warn: 500, block: 1000 },
    ".tsx": { warn: 500, block: 1000 },
    ".js": { warn: 500, block: 1000 },
    ".jsx": { warn: 500, block: 1000 },
    ".go": { warn: 500, block: 1000 },
    ".md": { warn: 800, block: 1500 },
    ".toml": { warn: 200, block: 500 },
    ".json": { warn: 1000, block: 3000 },
  },
  excludes: [
    "*.generated.*",
    "*.min.js",
    "*.min.css",
    "package-lock.json",
    "Cargo.lock",
    "uv.lock",
    "*.lock",
  ],
  escapeComment: "FILE-SIZE-OK",
};

// ============================================================================
// Config Loading
// ============================================================================

function loadConfig(): GuardConfig {
  const config = { ...DEFAULT_CONFIG };

  // Check project .claude/ dir first, then global ~/.claude/
  const candidates = [
    join(process.cwd(), ".claude", "file-size-guard.json"),
    join(process.env.HOME || "", ".claude", "file-size-guard.json"),
  ];

  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      try {
        const override = JSON.parse(readFileSync(candidate, "utf8"));
        if (override.defaults) {
          config.defaults = { ...config.defaults, ...override.defaults };
        }
        if (override.extensions) {
          config.extensions = { ...config.extensions, ...override.extensions };
        }
        if (override.excludes) {
          config.excludes = [...config.excludes, ...override.excludes];
        }
        if (override.escapeComment) {
          config.escapeComment = override.escapeComment;
        }
        break; // First found wins (project > global)
      } catch {
        // Invalid JSON — ignore and use defaults
      }
    }
  }

  return config;
}

// ============================================================================
// Detection
// ============================================================================

function getExtension(filePath: string): string {
  const parts = filePath.split("/").pop()?.split(".") || [];
  return parts.length > 1 ? `.${parts[parts.length - 1]}` : "";
}

function getThresholds(
  config: GuardConfig,
  filePath: string
): ExtensionThresholds {
  const ext = getExtension(filePath);
  return config.extensions[ext] || config.defaults;
}

function isExcluded(config: GuardConfig, filePath: string): boolean {
  const fileName = filePath.split("/").pop() || "";

  for (const pattern of config.excludes) {
    // Simple glob matching: *.ext and exact matches
    if (pattern.startsWith("*.")) {
      const suffix = pattern.slice(1); // ".ext" or ".generated.ts"
      if (fileName.endsWith(suffix)) return true;
    } else if (fileName === pattern) {
      return true;
    }
  }

  return false;
}

function hasEscapeComment(content: string, escapeComment: string): boolean {
  return content.includes(escapeComment);
}

/**
 * Apply an Edit tool's old_string → new_string to existing content.
 * Returns the resulting content after edit.
 */
function applyEdit(
  existing: string,
  oldString: string,
  newString: string
): string {
  const idx = existing.indexOf(oldString);
  if (idx === -1) return existing; // Can't find old_string — return as-is
  return existing.slice(0, idx) + newString + existing.slice(idx + oldString.length);
}

// ============================================================================
// Main
// ============================================================================

const logger = createHookLogger("FILE-SIZE-GUARD");

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("FILE-SIZE-GUARD");
  if (!input) return;

  const { tool_name, tool_input } = input;

  // Only check Write and Edit tools
  if (tool_name !== "Write" && tool_name !== "Edit") {
    return allow();
  }

  // Skip in plan mode
  const planContext = isPlanMode(input, {
    checkPermission: true,
    checkPath: true,
  });
  if (planContext.inPlanMode) {
    logger.debug("Skipping file size check in plan mode", {
      hook_event: "PreToolUse",
      tool_name,
      trace_id: input.tool_use_id,
    });
    return allow();
  }

  const filePath = tool_input.file_path;
  if (!filePath) return allow();

  const config = loadConfig();

  // Check exclusions
  if (isExcluded(config, filePath)) return allow();

  // Get the proposed content
  let proposedContent: string;

  if (tool_name === "Write") {
    proposedContent = (tool_input.content as string) || "";
  } else {
    // Edit: apply old_string → new_string to existing file
    const oldString = (tool_input.old_string as string) || "";
    const newString = (tool_input.new_string as string) || "";

    if (!existsSync(filePath)) {
      return allow(); // New file via Edit — unusual but allow
    }

    const existing = readFileSync(filePath, "utf8");
    proposedContent = applyEdit(existing, oldString, newString);
  }

  // Check escape hatch
  if (hasEscapeComment(proposedContent, config.escapeComment)) {
    return allow();
  }

  const lineCount = proposedContent.split("\n").length;
  const thresholds = getThresholds(config, filePath);

  // Under warn threshold — allow
  if (lineCount <= thresholds.warn) {
    return allow();
  }

  const ext = getExtension(filePath);
  const fileName = filePath.split("/").pop() || filePath;

  if (lineCount > thresholds.block) {
    // Above block threshold — ask with strong language
    const reason = [
      `[FILE-SIZE-GUARD] ${fileName} would be ${lineCount} lines (threshold: ${thresholds.block} for ${ext || "default"})`,
      "",
      `This file is very large. Large single files are harder to maintain,`,
      `review, and navigate. Consider splitting into multiple files.`,
      "",
      `**Suggestions:**`,
      ext === ".rs"
        ? `- Split into submodules: mod foo; (in separate .rs files)`
        : ext === ".py"
          ? `- Extract classes/functions into separate modules`
          : ext === ".ts" || ext === ".tsx"
            ? `- Extract components/utilities into separate files`
            : `- Split into smaller, focused files`,
      `- Add \`# ${config.escapeComment}\` comment to suppress this warning`,
      "",
      `Current: ${lineCount} lines | Warn: ${thresholds.warn} | Block: ${thresholds.block}`,
    ].join("\n");

    return ask(reason);
  }

  // Between warn and block — ask with softer language
  const reason = [
    `[FILE-SIZE-GUARD] ${fileName} is ${lineCount} lines (warn threshold: ${thresholds.warn} for ${ext || "default"})`,
    "",
    `This file is getting large. Consider whether it should be split.`,
    `Add \`# ${config.escapeComment}\` comment to suppress this warning.`,
    "",
    `Current: ${lineCount} lines | Warn: ${thresholds.warn} | Block: ${thresholds.block}`,
  ].join("\n");

  return ask(reason);
}

main().catch((err) => {
  console.error(`[file-size-guard] Error: ${err.message}`);
  allow(); // Fail-open
});
