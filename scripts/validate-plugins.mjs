#!/usr/bin/env bun
/**
 * Plugin Registration Validator
 *
 * Validates that all plugin directories are registered in marketplace.json
 * with complete and valid entries, and tracks inter-plugin dependencies.
 *
 * Usage:
 *   bun scripts/validate-plugins.mjs           # Validate only (5x faster)
 *   bun scripts/validate-plugins.mjs --fix     # Show fix instructions
 *   bun scripts/validate-plugins.mjs --strict  # Fail on warnings too
 *   bun scripts/validate-plugins.mjs --deps    # Show dependency graph
 *
 * Validations:
 *   1. Plugin directories have marketplace.json entries (registration)
 *   2. Marketplace entries have required fields (JSON Schema validation)
 *   3. Source paths in marketplace.json exist on disk
 *   4. Hooks paths (if specified) exist on disk
 *   5. No orphaned entries (registered but no directory)
 *   6. Inter-plugin dependencies are tracked and circular deps detected
 *   7. Referenced skills exist in target plugins
 *   8. Hook JSON structure from manage-hooks.sh (prevents "Invalid discriminator value")
 *
 * Integration:
 *   - Pre-commit hook: Add to .husky/pre-commit or .git/hooks/pre-commit
 *   - CI validation: Add to GitHub Actions workflow
 *   - Manual: Run before `npm run release`
 *
 * OSS Libraries (v8.7.0):
 *   - tinyglobby: File globbing (supersedes globby, 72% smaller)
 *   - ajv: JSON Schema validation (industry standard)
 *
 * ADR: /docs/adr/2025-12-05-centralized-version-management.md
 * ADR: /docs/adr/2025-12-14-alpha-forge-worktree-management.md (lesson learned)
 */

import { readFileSync, readdirSync, statSync, existsSync } from "fs";
import { resolve, join, dirname, relative, basename } from "path";
import { execSync } from "child_process";
import { glob } from "tinyglobby";
import Ajv from "ajv";

const SHOW_FIX = process.argv.includes("--fix");
const STRICT_MODE = process.argv.includes("--strict");
const SHOW_DEPS = process.argv.includes("--deps");

// Legacy constant for backward compatibility
const REQUIRED_FIELDS = ["name", "description", "version", "source", "category"];

// Load JSON Schema for marketplace.json validation
// ADR: Uses AJV (industry standard) for schema validation
const schemaPath = resolve(dirname(import.meta.url.replace("file://", "")), "marketplace.schema.json");
let marketplaceSchema;
let validateSchema;
try {
  marketplaceSchema = JSON.parse(readFileSync(schemaPath, "utf8"));
  // Remove $schema key - AJV doesn't need it for validation
  delete marketplaceSchema.$schema;
  const ajv = new Ajv({ allErrors: true, strict: false });
  validateSchema = ajv.compile(marketplaceSchema);
} catch (err) {
  console.warn(`⚠️  Could not load marketplace.schema.json: ${err.message}`);
  console.warn(`   Falling back to basic field validation.`);
  validateSchema = null;
}

// Load JSON Schema for hooks.json validation
// ADR: Prevents "Invalid discriminator value" regressions from malformed hook structures
const hooksSchemaPath = resolve(dirname(import.meta.url.replace("file://", "")), "hooks.schema.json");
let hooksSchema;
let validateHooksSchema;
try {
  hooksSchema = JSON.parse(readFileSync(hooksSchemaPath, "utf8"));
  delete hooksSchema.$schema;
  const ajv = new Ajv({ allErrors: true, strict: false });
  validateHooksSchema = ajv.compile(hooksSchema);
} catch (err) {
  console.warn(`⚠️  Could not load hooks.schema.json: ${err.message}`);
  console.warn(`   Hook structure validation disabled.`);
  validateHooksSchema = null;
}

/**
 * Read marketplace.json and return full plugin entries
 */
function getMarketplaceData() {
  const marketplacePath = resolve(process.cwd(), ".claude-plugin/marketplace.json");
  try {
    return JSON.parse(readFileSync(marketplacePath, "utf8"));
  } catch (err) {
    console.error(`❌ Error reading marketplace.json: ${err.message}`);
    process.exit(1);
  }
}

/**
 * Read marketplace.json and extract plugin names (legacy compatibility)
 */
function getRegisteredPlugins() {
  const data = getMarketplaceData();
  return (data.plugins || []).map(p => p.name);
}

/**
 * Get all plugin directories
 */
function getPluginDirectories() {
  const pluginsDir = resolve(process.cwd(), "plugins");
  try {
    return readdirSync(pluginsDir).filter(name => {
      const path = join(pluginsDir, name);
      return statSync(path).isDirectory() && !name.startsWith(".");
    });
  } catch (err) {
    console.error(`❌ Error reading plugins directory: ${err.message}`);
    process.exit(1);
  }
}

/**
 * Validate marketplace.json entries have required fields and valid paths
 * Uses AJV for JSON Schema validation + custom path existence checks
 * ADR: /docs/adr/2025-12-14-alpha-forge-worktree-management.md (lesson learned)
 */
function validateMarketplaceEntries() {
  const data = getMarketplaceData();
  const plugins = data.plugins || [];
  const errors = [];
  const warnings = [];

  // Step 1: AJV Schema validation (if schema loaded successfully)
  if (validateSchema) {
    const valid = validateSchema(data);
    if (!valid && validateSchema.errors) {
      validateSchema.errors.forEach((err) => {
        const path = err.instancePath || err.dataPath || "";
        const message = err.message || "validation error";
        errors.push(`Schema: ${path} ${message}`);
      });
    }
  } else {
    // Fallback: manual required field checks if schema unavailable
    plugins.forEach((plugin, index) => {
      const prefix = `Plugin #${index + 1} (${plugin.name || "unnamed"})`;
      REQUIRED_FIELDS.forEach(field => {
        if (!plugin[field]) {
          errors.push(`${prefix}: Missing required field '${field}'`);
        }
      });
    });
  }

  // Step 2: Path existence checks (cannot be in JSON Schema)
  plugins.forEach((plugin, index) => {
    const prefix = `Plugin #${index + 1} (${plugin.name || "unnamed"})`;

    // Validate source path exists
    if (plugin.source) {
      const sourcePath = resolve(process.cwd(), plugin.source);
      if (!existsSync(sourcePath)) {
        errors.push(`${prefix}: Source path does not exist: ${plugin.source}`);
      }
    }

    // Validate hooks path exists (if specified)
    if (plugin.hooks) {
      const hooksPath = resolve(process.cwd(), plugin.hooks);
      if (!existsSync(hooksPath)) {
        errors.push(`${prefix}: Hooks file does not exist: ${plugin.hooks}`);
      }
    }

    // Warn about missing optional but recommended fields
    if (!plugin.author) {
      warnings.push(`${prefix}: Missing recommended field 'author'`);
    }
    if (!plugin.keywords || plugin.keywords.length === 0) {
      warnings.push(`${prefix}: Missing recommended field 'keywords'`);
    }
  });

  return { errors, warnings };
}

/**
 * Recursively find all markdown files in a directory
 * Uses tinyglobby for efficient file globbing (72% smaller than globby)
 */
async function findMarkdownFiles(dir) {
  if (!existsSync(dir)) return [];

  // Use tinyglobby for efficient file discovery
  const pattern = join(dir, "**/*.md").replace(/\\/g, "/");
  const files = await glob(pattern, {
    absolute: true,
    onlyFiles: true,
  });
  return files;
}

/**
 * Extract Skill() invocations from a markdown file
 * Matches patterns like: Skill(plugin:skill), Skill(plugin-name:skill-name)
 * Returns array of { plugin, skill, file, line }
 */
function extractSkillDependencies(filePath) {
  const dependencies = [];
  try {
    const content = readFileSync(filePath, "utf8");
    const lines = content.split("\n");

    // Pattern: Skill(plugin:skill) or Skill(plugin-name:skill-name)
    const skillPattern = /Skill\(([a-z0-9-]+):([a-z0-9-]+)\)/gi;

    lines.forEach((line, index) => {
      let match;
      while ((match = skillPattern.exec(line)) !== null) {
        dependencies.push({
          plugin: match[1],
          skill: match[2],
          file: filePath,
          line: index + 1,
        });
      }
    });
  } catch (err) {
    // Explicit warning for unreadable files (no silent failures)
    console.warn(`⚠️  Could not read file: ${filePath} (${err.code || err.message})`);
  }
  return dependencies;
}

/**
 * Build dependency graph for all plugins
 * Returns { graph: Map<plugin, Set<dependsOn>>, details: [...] }
 */
async function buildDependencyGraph() {
  const pluginsDir = resolve(process.cwd(), "plugins");
  const directories = getPluginDirectories();
  const graph = new Map(); // plugin -> Set of plugins it depends on
  const details = []; // detailed dependency info

  // Process all plugins (await for async findMarkdownFiles)
  for (const pluginName of directories) {
    const pluginDir = join(pluginsDir, pluginName);
    const mdFiles = await findMarkdownFiles(pluginDir);

    for (const file of mdFiles) {
      const deps = extractSkillDependencies(file);
      for (const dep of deps) {
        // Skip self-references
        if (dep.plugin === pluginName) continue;

        // Add to graph
        if (!graph.has(pluginName)) {
          graph.set(pluginName, new Set());
        }
        graph.get(pluginName).add(dep.plugin);

        // Store detailed info
        details.push({
          from: pluginName,
          to: dep.plugin,
          skill: dep.skill,
          file: relative(process.cwd(), dep.file),
          line: dep.line,
        });
      }
    }
  }

  return { graph, details };
}

/**
 * Detect circular dependencies using DFS
 * Returns array of cycles found, e.g., [["a", "b", "a"], ["x", "y", "z", "x"]]
 */
function detectCircularDependencies(graph) {
  const cycles = [];
  const visited = new Set();
  const recursionStack = new Set();

  function dfs(node, path) {
    if (recursionStack.has(node)) {
      // Found cycle - extract it from path
      const cycleStart = path.indexOf(node);
      const cycle = [...path.slice(cycleStart), node];
      cycles.push(cycle);
      return;
    }
    if (visited.has(node)) return;

    visited.add(node);
    recursionStack.add(node);
    path.push(node);

    const deps = graph.get(node) || new Set();
    for (const dep of deps) {
      dfs(dep, [...path]);
    }

    recursionStack.delete(node);
  }

  for (const node of graph.keys()) {
    if (!visited.has(node)) {
      dfs(node, []);
    }
  }

  return cycles;
}

/**
 * Find all hook files in plugin directories (shell, Python, TypeScript, JavaScript)
 * Returns array of { path, plugin, filename, language }
 * Uses tinyglobby for efficient file discovery
 *
 * Language support:
 *   - .sh → shell (bash)
 *   - .py → python
 *   - .ts → typescript (Bun)
 *   - .mjs → javascript (Bun)
 */
async function findHookScripts() {
  const pluginsDir = resolve(process.cwd(), "plugins");

  // Use tinyglobby to find all hook scripts at once
  // Added .ts and .mjs support for TypeScript/Bun hooks (ADR: 2026-01-10-uv-reminder-hook)
  const hookPaths = await glob("plugins/*/hooks/*.{sh,py,ts,mjs}", {
    cwd: process.cwd(),
    absolute: true,
    onlyFiles: true,
    ignore: [
      "**/__*.py",       // Exclude Python dunder files (__init__.py, etc.)
      "**/*.test.ts",    // Exclude TypeScript test files
      "**/*.spec.ts",    // Exclude TypeScript spec files
    ],
  });

  // Map paths to structured objects preserving language field
  const hookFiles = hookPaths.map((fullPath) => {
    const relPath = relative(pluginsDir, fullPath);
    const parts = relPath.split(/[/\\]/);
    const pluginName = parts[0];
    const filename = basename(fullPath);

    // Determine language from file extension
    let language;
    if (filename.endsWith(".sh")) {
      language = "shell";
    } else if (filename.endsWith(".py")) {
      language = "python";
    } else if (filename.endsWith(".ts")) {
      language = "typescript";
    } else if (filename.endsWith(".mjs")) {
      language = "javascript";
    } else {
      language = "unknown";
    }

    return {
      path: fullPath,
      plugin: pluginName,
      filename: filename,
      language: language,
    };
  });

  return hookFiles;
}

/**
 * Detect hook type from filename, content, and hooks.json
 * Returns: "PostToolUse" | "Stop" | "PreToolUse" | "SubagentStop" | "unknown"
 *
 * ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md
 * Reference: plugins/itp-hooks/skills/hooks-development/references/lifecycle-reference.md
 */
function detectHookType(filename, content, hooksJsonPath) {
  const lowerFilename = filename.toLowerCase();

  // Try to read hooks.json for definitive type
  if (existsSync(hooksJsonPath)) {
    try {
      const hooksJson = JSON.parse(readFileSync(hooksJsonPath, "utf8"));
      const hooks = hooksJson.hooks || hooksJson;

      // Search all hook types for this script
      for (const [hookType, matchers] of Object.entries(hooks)) {
        if (!Array.isArray(matchers)) continue;
        for (const matcher of matchers) {
          const hookList = matcher.hooks || [];
          for (const hook of hookList) {
            if (hook.command && hook.command.includes(filename)) {
              return hookType;
            }
          }
        }
      }
    } catch (err) {
      // Fall through to heuristics
    }
  }

  // Heuristics based on filename
  if (lowerFilename.includes("stop") && !lowerFilename.includes("subagent")) {
    return "Stop";
  }
  if (lowerFilename.includes("subagent")) {
    return "SubagentStop";
  }
  if (lowerFilename.includes("posttooluse") || lowerFilename.includes("post-tool")) {
    return "PostToolUse";
  }
  if (lowerFilename.includes("pretooluse") || lowerFilename.includes("pre-tool")) {
    return "PreToolUse";
  }

  // Content-based heuristics
  if (content.includes("PostToolUse") || content.includes("tool_response")) {
    return "PostToolUse";
  }
  if (content.includes("stop_hook_active")) {
    return "Stop";
  }
  if (content.includes("permissionDecision") || content.includes("PreToolUse")) {
    return "PreToolUse";
  }

  return "unknown";
}

/**
 * Validate hook output format for Claude Code CLI consumption
 *
 * Different hook types have DIFFERENT semantics:
 *
 * PostToolUse:
 *   - "decision": "block" = VISIBILITY only (non-blocking)
 *   - "reason" = what Claude sees
 *   - MUST use decision:block for Claude to see output
 *
 * Stop/SubagentStop:
 *   - "decision": "block" = ACTUALLY BLOCKS stopping (forces continuation)
 *   - For informational: use {systemMessage: "..."} (hookSpecificOutput NOT supported)
 *   - Empty {} = allow stop normally
 *
 * PreToolUse:
 *   - "decision": "block" = DEPRECATED (use permissionDecision)
 *   - Use permissionDecision: "deny" + permissionDecisionReason
 *
 * ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md
 * Reference: lifecycle-reference.md "JSON Field Visibility by Hook Type"
 *
 * Returns { errors: [...], warnings: [...] }
 */
async function validateHookOutputFormat() {
  const hookFiles = await findHookScripts();
  const errors = [];
  const warnings = [];

  // Fields that Claude Code actually reads from PostToolUse JSON
  const CLAUDE_VISIBLE_FIELDS = new Set(["decision", "reason"]);

  // Fields that are valid but not shown to Claude (informational)
  const OPTIONAL_FIELDS = new Set([
    "hookSpecificOutput",
    "suppressOutput",
    "systemMessage",
    "continue",
    "stopReason",
  ]);

  hookFiles.forEach(({ path, plugin, filename, language }) => {
    try {
      const content = readFileSync(path, "utf8");
      const lines = content.split("\n");
      const relPath = relative(process.cwd(), path);
      const hooksJsonPath = join(dirname(path), "hooks.json");

      // Detect hook type
      const hookType = detectHookType(filename, content, hooksJsonPath);

      // Skip non-hook Python files (utilities, adapters, etc.)
      if (language === "python" && hookType === "unknown") {
        // Check if it's actually a hook entry point (has main() or is referenced in hooks.json)
        const isHookEntryPoint =
          content.includes('if __name__ == "__main__"') ||
          content.includes("def main()");
        if (!isHookEntryPoint) {
          return; // Skip utility modules
        }
      }

      // Track issues for this file
      const fileIssues = [];

      // Helper: check if pattern exists in non-comment lines
      const hasPatternInCode = (pattern) => {
        return lines.some((line) => {
          const trimmed = line.trim();
          // Skip comment lines
          if (trimmed.startsWith("#") || trimmed.startsWith("//")) return false;
          return pattern.test(line);
        });
      };

      // === STOP HOOK VALIDATION ===
      // Check for decision:block used for informational purposes (should use additionalContext)
      if (hookType === "Stop" || hookType === "SubagentStop") {
        const hasDecisionBlock = hasPatternInCode(/["']?decision["']?\s*[:=]\s*["']block["']/);

        const hasAdditionalContext = content.includes("additionalContext");
        const hasStopHookActiveCheck = content.includes("stop_hook_active");

        // If using decision:block but NOT checking stop_hook_active, warn about infinite loop
        if (hasDecisionBlock && !hasStopHookActiveCheck) {
          warnings.push(
            `${relPath}: Stop hook uses "decision: block" but doesn't check stop_hook_active - risk of infinite loop`
          );
        }

        // If file seems informational (mentions "info", "summary", "validation results")
        // but uses decision:block, warn that it will actually block stopping
        // EXCEPTION: Files that clearly intend to block (loop control, continuation, etc.)
        const seemsInformational =
          content.toLowerCase().includes("validation result") ||
          content.toLowerCase().includes("session ended") ||
          content.toLowerCase().includes("link validation");

        const intentionallyBlocking =
          content.toLowerCase().includes("continue_session") ||
          content.toLowerCase().includes("loop") ||
          content.toLowerCase().includes("autonomous") ||
          content.toLowerCase().includes("force continuation") ||
          filename.toLowerCase().includes("loop");

        if (hasDecisionBlock && seemsInformational && !hasAdditionalContext && !intentionallyBlocking) {
          warnings.push(
            `${relPath}: Stop hook appears informational but uses "decision: block" which ACTUALLY BLOCKS stopping`
          );
          warnings.push(
            `   → For informational output, use: {systemMessage: "..."} (Stop hooks don't support hookSpecificOutput)`
          );
        }

        // Check for incorrect continue:false usage
        if (content.includes('"continue": false') || content.includes("continue: false")) {
          // This is valid for hard stop, but warn if it seems like "allow stop" intent
          const beforeContinue = content.substring(0, content.indexOf("continue"));
          if (beforeContinue.includes("allow") || beforeContinue.includes("normal")) {
            warnings.push(
              `${relPath}: "continue: false" means HARD STOP, not "allow normal stop". Use {} for allow stop.`
            );
          }
        }
      }

      // === PRETOOLUSE HOOK VALIDATION ===
      if (hookType === "PreToolUse") {
        const hasDecisionBlock =
          content.includes('"decision": "block"') ||
          content.includes("decision: \"block\"") ||
          content.includes('decision: "block"');

        const hasDecisionAllow =
          content.includes('"decision": "allow"') ||
          content.includes("decision: \"allow\"") ||
          content.includes('decision: "allow"');

        const hasPermissionDecision = content.includes("permissionDecision");

        if (hasDecisionBlock && !hasPermissionDecision) {
          warnings.push(
            `${relPath}: PreToolUse hook uses deprecated "decision: block". Use permissionDecision: "deny" instead.`
          );
          warnings.push(
            `   → Use: {hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: "..."}}`
          );
        }

        if (hasDecisionAllow && !hasPermissionDecision) {
          warnings.push(
            `${relPath}: PreToolUse hook uses deprecated "decision: allow". Use permissionDecision: "allow" instead.`
          );
          warnings.push(
            `   → Use: {hookSpecificOutput: {permissionDecision: "allow"}} or just exit 0 with no output`
          );
        }
      }

      // === POSTTOOLUSE HOOK VALIDATION ===
      if (hookType === "PostToolUse") {
        const hasDecisionBlock =
          content.includes('"decision": "block"') ||
          content.includes("decision: \"block\"") ||
          content.includes('decision: "block"') ||
          content.includes("{decision: \"block\"");

        // Check for jq output without decision:block
        if (!hasDecisionBlock && content.includes("jq")) {
          // Check if it's actually emitting JSON (not just parsing input)
          const hasJqOutput = content.match(/jq\s+(-n\s+)?.*'\{/);
          if (hasJqOutput) {
            warnings.push(
              `${relPath}: PostToolUse hook may be missing "decision: block" - output won't be visible to Claude`
            );
          }
        }

        // Check for extra fields that won't be visible
        lines.forEach((line, index) => {
          const lineNum = index + 1;

          // Pattern 1: jq -n with field definitions
          const jqObjectMatch = line.match(/jq\s+(-n\s+)?.*'\{([^}]+)\}'/);
          if (jqObjectMatch) {
            const objectContent = jqObjectMatch[2];
            const fieldPattern = /["']?(\w+)["']?\s*:/g;
            let fieldMatch;
            const foundFields = new Set();

            while ((fieldMatch = fieldPattern.exec(objectContent)) !== null) {
              foundFields.add(fieldMatch[1]);
            }

            const invisibleFields = [...foundFields].filter(
              (f) => !CLAUDE_VISIBLE_FIELDS.has(f) && !OPTIONAL_FIELDS.has(f)
            );

            if (invisibleFields.length > 0) {
              fileIssues.push({
                line: lineNum,
                fields: invisibleFields,
                lineContent: line.trim().substring(0, 80),
              });
            }
          }

          // Pattern 2: echo with JSON
          const echoJsonMatch = line.match(/echo\s+['"]?\{([^}]+)\}['"]?/);
          if (echoJsonMatch) {
            const jsonContent = echoJsonMatch[1];
            const fieldPattern = /"(\w+)"\s*:/g;
            let fieldMatch;
            const foundFields = new Set();

            while ((fieldMatch = fieldPattern.exec(jsonContent)) !== null) {
              foundFields.add(fieldMatch[1]);
            }

            const invisibleFields = [...foundFields].filter(
              (f) => !CLAUDE_VISIBLE_FIELDS.has(f) && !OPTIONAL_FIELDS.has(f)
            );

            if (invisibleFields.length > 0) {
              fileIssues.push({
                line: lineNum,
                fields: invisibleFields,
                lineContent: line.trim().substring(0, 80),
              });
            }
          }
        });

        // Report invisible field issues
        if (fileIssues.length > 0) {
          warnings.push(
            `${relPath}: Hook outputs fields invisible to Claude Code CLI`
          );
          fileIssues.forEach((issue) => {
            warnings.push(
              `   Line ${issue.line}: Fields [${issue.fields.join(", ")}] will be LOGGED but NOT VISIBLE to Claude`
            );
            warnings.push(
              `   → Move content into "reason" field for Claude to see it`
            );
          });
        }
      }

      // === UNKNOWN HOOK TYPE ===
      if (hookType === "unknown" && content.includes("jq")) {
        warnings.push(
          `${relPath}: Could not determine hook type - verify output format manually`
        );
      }

      // === COMMON HOOK PITFALLS ===
      // ADR: Lessons learned from v8.2.1 fixes

      // Pitfall 1: Checking command output without filtering success messages
      // e.g., ruff outputs "All checks passed!" which is non-empty but not an error
      // Exception: --output-format=json outputs [] on success, not a message
      if (
        content.includes("ruff check") &&
        !content.includes("--output-format=json") &&
        content.match(/\[\[\s*-n\s+"\$[A-Z_]*OUTPUT"/) &&
        !content.includes('grep -v "All checks passed"')
      ) {
        warnings.push(
          `${relPath}: Ruff output check may trigger false positives - ruff outputs "All checks passed!" on success`
        );
        warnings.push(
          `   → Filter with: | grep -v "All checks passed" | before storing output`
        );
      }

      // Pitfall 2: Path comparison without handling relative paths
      // e.g., using eval echo without CLAUDE_PROJECT_DIR for relative paths
      if (
        content.includes("eval echo") &&
        content.match(/\[\[.*==.*"\$HOME/) &&
        !content.includes("CLAUDE_PROJECT_DIR")
      ) {
        warnings.push(
          `${relPath}: Path comparison may fail for relative paths - eval echo doesn't convert relative to absolute`
        );
        warnings.push(
          `   → Use CLAUDE_PROJECT_DIR to resolve relative paths before comparison`
        );
      }

      // Pitfall 3: PostToolUse hooks emitting reminders for code files without content verification
      // ADR: Lesson from v8.5.1 fix - ADR traceability reminder fired even when ADR existed
      // Pattern: Sets REMINDER for file extensions but doesn't verify condition with file content
      if (
        hookType === "PostToolUse" &&
        content.match(/\.(py|ts|js|mjs|rs|go)\$/) &&  // Checks for code file extensions
        content.match(/REMINDER\s*=\s*["'][^"']+TRACEABILITY|REMINDER\s*=\s*["'][^"']+Consider/) &&  // Sets reminder
        !content.match(/head\s+-?\d+|grep\s+-[qE]|cat\s+["']?\$FILE/) // Doesn't check file content
      ) {
        warnings.push(
          `${relPath}: PostToolUse hook may emit false positive reminders - sets reminder for code files without checking file content`
        );
        warnings.push(
          `   → Before emitting traceability reminders, check if condition already satisfied: head -50 "$FILE" | grep -qE 'pattern'`
        );
      }

    } catch (err) {
      warnings.push(`Could not validate hook: ${path} (${err.message})`);
    }
  });

  return { errors, warnings };
}

/**
 * Validate hooks.json structure generated by manage-hooks.sh scripts
 * Extracts jq expressions, runs them, and validates output against schema
 *
 * This catches regressions like:
 * - PreToolUse entry with extra {"hooks": [...]} wrapper (v8.7.7 bug)
 * - Invalid type values (must be 'command' | 'prompt' | 'agent')
 * - Missing required fields
 *
 * ADR: Lesson learned from user "Chen" installation failure
 *
 * Returns { errors: [...], warnings: [...] }
 */
async function validateHooksJsonStructure() {
  const errors = [];
  const warnings = [];

  if (!validateHooksSchema) {
    warnings.push("hooks.schema.json not loaded - skipping hook structure validation");
    return { errors, warnings };
  }

  // Find all manage-hooks.sh scripts
  const hookScripts = await glob("plugins/*/scripts/manage-hooks.sh", {
    cwd: process.cwd(),
    absolute: true,
    onlyFiles: true,
  });

  for (const scriptPath of hookScripts) {
    const relPath = relative(process.cwd(), scriptPath);
    const pluginName = relPath.split("/")[1];

    try {
      const content = readFileSync(scriptPath, "utf8");

      // Extract jq expressions that generate hook entries
      // Pattern: jq -n --arg ... '{...}' or jq -n '{...}'
      const jqExpressions = [];
      const jqPattern = /jq\s+-n\s+(?:--arg\s+\w+\s+"[^"]*"\s*)*'(\{[^']+\})'/g;
      let match;

      while ((match = jqPattern.exec(content)) !== null) {
        const lineNum = content.substring(0, match.index).split("\n").length;
        jqExpressions.push({
          expression: match[1],
          fullMatch: match[0],
          line: lineNum,
        });
      }

      // Validate each extracted jq expression
      for (const { expression, fullMatch, line } of jqExpressions) {
        // Skip expressions that are clearly not hook entries
        if (!expression.includes("type") && !expression.includes("matcher")) {
          continue;
        }

        // Run jq to get actual JSON output
        try {
          // Replace $cmd variable references with placeholder for validation
          const testExpr = expression.replace(/\$\w+/g, '"placeholder"');
          const jqCmd = `jq -n '${testExpr}'`;

          const output = execSync(jqCmd, {
            encoding: "utf8",
            timeout: 5000,
          }).trim();

          const jsonOutput = JSON.parse(output);

          // Determine what schema to validate against based on content
          if (jsonOutput.matcher !== undefined) {
            // This is a hookMatcher (PreToolUse, PostToolUse)
            validateHookMatcher(jsonOutput, relPath, line, errors, warnings);
          } else if (jsonOutput.hooks !== undefined) {
            // This is a hookEventArray entry (Stop, SubagentStop)
            validateHookEventEntry(jsonOutput, relPath, line, errors, warnings);
          }
        } catch (jqErr) {
          warnings.push(
            `${relPath}:${line}: Could not validate jq expression: ${jqErr.message}`
          );
        }
      }
    } catch (err) {
      warnings.push(`${relPath}: Could not read script: ${err.message}`);
    }
  }

  return { errors, warnings };
}

/**
 * Validate a hookMatcher entry (used for PreToolUse, PostToolUse)
 * Structure: { matcher?: string, hooks: hookDefinition[] }
 */
function validateHookMatcher(entry, file, line, errors, warnings) {
  // Must have hooks array
  if (!entry.hooks || !Array.isArray(entry.hooks)) {
    errors.push(
      `${file}:${line}: hookMatcher missing required 'hooks' array`
    );
    return;
  }

  // Hooks must not be nested in extra wrapper
  // Bug detection: {"hooks": [{"matcher": "...", "hooks": [...]}]} is WRONG
  // Correct: {"matcher": "...", "hooks": [{type, command}]}
  if (entry.hooks.length > 0) {
    const firstHook = entry.hooks[0];
    if (firstHook.matcher !== undefined) {
      errors.push(
        `${file}:${line}: INVALID NESTING - hook entry has nested 'matcher' inside 'hooks' array. ` +
        `This causes "Invalid discriminator value" error. ` +
        `Remove outer {"hooks": [...]} wrapper.`
      );
      return;
    }
  }

  // Validate each hook definition
  for (let i = 0; i < entry.hooks.length; i++) {
    const hook = entry.hooks[i];
    validateHookDefinition(hook, `${file}:${line}[${i}]`, errors, warnings);
  }
}

/**
 * Validate a hookEventEntry (used for Stop, SubagentStop events without matcher)
 * Structure: { hooks: hookDefinition[] }
 */
function validateHookEventEntry(entry, file, line, errors, warnings) {
  // Must have hooks array
  if (!Array.isArray(entry.hooks)) {
    errors.push(
      `${file}:${line}: hookEventEntry 'hooks' must be an array`
    );
    return;
  }

  // Validate each hook definition
  for (let i = 0; i < entry.hooks.length; i++) {
    const hook = entry.hooks[i];
    validateHookDefinition(hook, `${file}:${line}[${i}]`, errors, warnings);
  }
}

/**
 * Validate individual hook definition
 * Structure: { type: "command"|"prompt"|"agent", command?: string, prompt?: string, timeout?: number }
 */
function validateHookDefinition(hook, location, errors, warnings) {
  const validTypes = ["command", "prompt", "agent"];

  // Must have type field
  if (!hook.type) {
    errors.push(
      `${location}: hookDefinition missing required 'type' field`
    );
    return;
  }

  // Type must be valid enum value
  if (!validTypes.includes(hook.type)) {
    errors.push(
      `${location}: Invalid type '${hook.type}'. Expected: ${validTypes.join(" | ")}. ` +
      `This causes "Invalid discriminator value" error.`
    );
    return;
  }

  // Type-specific validation
  if (hook.type === "command" && !hook.command) {
    errors.push(
      `${location}: type "command" requires 'command' field`
    );
  }

  if (hook.type === "prompt" && !hook.prompt) {
    errors.push(
      `${location}: type "prompt" requires 'prompt' field`
    );
  }

  // Validate timeout if present
  if (hook.timeout !== undefined) {
    if (typeof hook.timeout !== "number" || hook.timeout < 1 || hook.timeout > 600000) {
      warnings.push(
        `${location}: timeout should be 1-600000ms, got ${hook.timeout}`
      );
    }
  }
}

/**
 * Validate that referenced skills actually exist in target plugins
 * Returns { errors: [...], warnings: [...] }
 */
function validateSkillExistence(details) {
  const pluginsDir = resolve(process.cwd(), "plugins");
  const errors = [];
  const warnings = [];
  const checked = new Set(); // Avoid duplicate checks

  details.forEach((dep) => {
    const key = `${dep.to}:${dep.skill}`;
    if (checked.has(key)) return;
    checked.add(key);

    const targetPluginDir = join(pluginsDir, dep.to);

    // Check if target plugin exists
    if (!existsSync(targetPluginDir)) {
      errors.push(
        `Missing plugin '${dep.to}' referenced by ${dep.from} (${dep.file}:${dep.line})`
      );
      return;
    }

    // Check if skill exists in commands/ or skills/
    const commandPath = join(targetPluginDir, "commands", `${dep.skill}.md`);
    const skillDir = join(targetPluginDir, "skills", dep.skill);
    const skillPath = join(skillDir, "SKILL.md");

    const commandExists = existsSync(commandPath);
    const skillExists = existsSync(skillDir) && existsSync(skillPath);

    if (!commandExists && !skillExists) {
      warnings.push(
        `Skill '${dep.skill}' not found in plugin '${dep.to}' - referenced by ${dep.from} (${dep.file}:${dep.line})`
      );
    }
  });

  return { errors, warnings };
}

/**
 * Extract declared dependencies from marketplace.json 'requires' field
 * Returns Map<plugin, string[]> of declared dependencies
 */
function getDeclaredDependencies() {
  const data = getMarketplaceData();
  const plugins = data.plugins || [];
  const deps = new Map();

  plugins.forEach((plugin) => {
    if (plugin.requires && Array.isArray(plugin.requires)) {
      deps.set(plugin.name, plugin.requires);
    }
  });

  return deps;
}

/**
 * Validate declared dependencies match detected dependencies
 * Returns { errors: [...], warnings: [...] }
 */
function validateDeclaredDependencies(declaredDeps, detectedGraph) {
  const errors = [];
  const warnings = [];
  const registeredPlugins = getRegisteredPlugins();

  // Check declared dependencies exist
  for (const [plugin, requires] of declaredDeps.entries()) {
    for (const req of requires) {
      if (!registeredPlugins.includes(req)) {
        errors.push(
          `Plugin '${plugin}' requires '${req}' which is not registered in marketplace`
        );
      }
    }
  }

  // Note: 'requires' field is not yet supported by Claude Code (see issue #9444)
  // These checks are disabled until the feature is implemented
  // Dependencies are detected automatically via Skill() call analysis

  return { errors, warnings };
}

/**
 * Generate installation instructions with dependencies
 */
function generateInstallInstructions(declaredDeps) {
  const lines = [];

  // Find plugins with dependencies
  const pluginsWithDeps = [...declaredDeps.entries()].filter(
    ([_, deps]) => deps.length > 0
  );

  if (pluginsWithDeps.length === 0) {
    return "";
  }

  lines.push("\n📋 Installation Instructions (with dependencies):");
  lines.push("─".repeat(50));

  for (const [plugin, requires] of pluginsWithDeps) {
    const allDeps = resolveTransitiveDeps(plugin, declaredDeps, new Set());
    // Remove the plugin itself from deps and dedupe
    allDeps.delete(plugin);
    const installOrder = [...allDeps, plugin];

    // Skip if only self (circular with no other deps)
    if (installOrder.length === 1 && installOrder[0] === plugin) {
      lines.push(`\n   ${plugin}: (circular dependency - install with peer)`);
      const peers = requires.filter(r => declaredDeps.has(r) && declaredDeps.get(r).includes(plugin));
      if (peers.length > 0) {
        lines.push(`   # Install together: ${plugin}, ${peers.join(", ")}`);
      }
      continue;
    }

    lines.push(`\n   ${plugin}:`);
    lines.push(`   # Install in order (dependencies first):`);
    installOrder.forEach((p, i) => {
      const marker = i === installOrder.length - 1 ? "→" : " ";
      lines.push(`   ${marker} /plugin install cc-skills@${p}`);
    });
  }

  return lines.join("\n");
}

/**
 * Resolve transitive dependencies (recursive)
 */
function resolveTransitiveDeps(plugin, declaredDeps, visited) {
  if (visited.has(plugin)) return new Set(); // Avoid circular
  visited.add(plugin);

  const direct = declaredDeps.get(plugin) || [];
  const all = new Set();

  for (const dep of direct) {
    // Add transitive deps first
    const transitive = resolveTransitiveDeps(dep, declaredDeps, visited);
    for (const t of transitive) {
      all.add(t);
    }
    all.add(dep);
  }

  return all;
}

/**
 * Format dependency graph for display
 */
function formatDependencyGraph(graph, details) {
  const lines = [];
  const registeredPlugins = getRegisteredPlugins();

  lines.push("\n📊 Inter-Plugin Dependency Graph:");
  lines.push("─".repeat(50));

  if (graph.size === 0) {
    lines.push("   No inter-plugin dependencies found.");
    return lines.join("\n");
  }

  // Group by source plugin
  for (const [plugin, deps] of graph.entries()) {
    const depsArray = [...deps];
    const isRegistered = (p) => registeredPlugins.includes(p);

    lines.push(`\n   ${plugin} depends on:`);
    depsArray.forEach((dep) => {
      const status = isRegistered(dep) ? "✓" : "✗";
      const depDetails = details.filter(
        (d) => d.from === plugin && d.to === dep
      );
      const skills = [...new Set(depDetails.map((d) => d.skill))].join(", ");
      lines.push(`      ${status} ${dep} (skills: ${skills})`);
    });
  }

  // Summary
  const allDeps = new Set();
  for (const deps of graph.values()) {
    for (const dep of deps) {
      allDeps.add(dep);
    }
  }

  lines.push("\n" + "─".repeat(50));
  lines.push(
    `   ${graph.size} plugins have dependencies on ${allDeps.size} other plugins`
  );

  return lines.join("\n");
}

// Main validation - wrapped in async IIFE for tinyglobby async functions
(async () => {
const registered = getRegisteredPlugins();
const directories = getPluginDirectories();

const unregistered = directories.filter(d => !registered.includes(d));
const orphaned = registered.filter(r => !directories.includes(r));
const { errors: entryErrors, warnings: entryWarnings } = validateMarketplaceEntries();

console.log(`📦 Registered plugins: ${registered.length}`);
console.log(`📁 Plugin directories: ${directories.length}`);

let hasErrors = false;
let hasWarnings = false;

// Check for unregistered directories (CRITICAL - this catches the alpha-forge-worktree bug)
if (unregistered.length > 0) {
  console.error(`\n❌ Unregistered plugin directories (${unregistered.length}):`);
  unregistered.forEach(p => console.error(`   - plugins/${p}/`));
  hasErrors = true;

  if (SHOW_FIX) {
    console.log(`\n📝 To fix, add entries to .claude-plugin/marketplace.json:`);
    unregistered.forEach(p => {
      console.log(`
    {
      "name": "${p}",
      "description": "TODO: Add description",
      "version": "1.0.0",
      "source": "./plugins/${p}/",
      "category": "TODO",
      "author": { "name": "Terry Li", "url": "https://github.com/terrylica" },
      "keywords": [],
      "strict": false
    }`);
    });
  }
}

// Check for entry validation errors (missing fields, invalid paths)
if (entryErrors.length > 0) {
  console.error(`\n❌ Marketplace entry errors (${entryErrors.length}):`);
  entryErrors.forEach(e => console.error(`   - ${e}`));
  hasErrors = true;
}

// Check for orphaned entries
if (orphaned.length > 0) {
  console.warn(`\n⚠️  Orphaned entries in marketplace.json (no directory):`);
  orphaned.forEach(p => console.warn(`   - ${p}`));
  hasWarnings = true;
}

// Check for entry warnings (missing recommended fields)
if (entryWarnings.length > 0) {
  console.warn(`\n⚠️  Marketplace entry warnings (${entryWarnings.length}):`);
  entryWarnings.forEach(w => console.warn(`   - ${w}`));
  hasWarnings = true;
}

// Dependency validation (detected from Skill() calls) - async with tinyglobby
const { graph: depGraph, details: depDetails } = await buildDependencyGraph();
const cycles = detectCircularDependencies(depGraph);
const { errors: depErrors, warnings: depWarnings } = validateSkillExistence(depDetails);

// Hook output format validation (Claude Code CLI consumption) - async with tinyglobby
// ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md
const { errors: hookErrors, warnings: hookWarnings } = await validateHookOutputFormat();

// Hook JSON structure validation (manage-hooks.sh jq expressions) - async with tinyglobby
// ADR: Lesson from user "Chen" - "Invalid discriminator value" from malformed hook structure
const { errors: hookStructErrors, warnings: hookStructWarnings } = await validateHooksJsonStructure();

// Declared dependency validation (from 'requires' field in marketplace.json)
// Reference: https://github.com/anthropics/claude-code/issues/9444
const declaredDeps = getDeclaredDependencies();
const { errors: declErrors, warnings: declWarnings } = validateDeclaredDependencies(declaredDeps, depGraph);

// Report circular dependencies
if (cycles.length > 0) {
  console.warn(`\n🔄 Circular dependencies detected (${cycles.length}):`);
  cycles.forEach((cycle) => {
    console.warn(`   - ${cycle.join(" → ")}`);
  });
  hasWarnings = true;
}

// Report missing plugins/skills (from Skill() detection)
if (depErrors.length > 0) {
  console.error(`\n❌ MISSING PLUGIN DEPENDENCIES (${depErrors.length}):`);
  depErrors.forEach((e) => console.error(`   - ${e}`));
  hasErrors = true;
}

if (depWarnings.length > 0) {
  console.warn(`\n⚠️  Missing skill references (${depWarnings.length}):`);
  depWarnings.forEach((w) => console.warn(`   - ${w}`));
  hasWarnings = true;
}

// Report declared dependency issues (from 'requires' field validation)
if (declErrors.length > 0) {
  console.error(`\n❌ MARKETPLACE.JSON 'requires' FIELD ERRORS (${declErrors.length}):`);
  declErrors.forEach((e) => console.error(`   - ${e}`));
  hasErrors = true;
}

if (declWarnings.length > 0) {
  console.warn(`\n⚠️  Declared dependency mismatches (${declWarnings.length}):`);
  declWarnings.forEach((w) => console.warn(`   - ${w}`));
  hasWarnings = true;
}

// Report hook output format issues
// ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md
if (hookErrors.length > 0) {
  console.error(`\n❌ HOOK OUTPUT FORMAT ERRORS (${hookErrors.length}):`);
  hookErrors.forEach((e) => console.error(`   - ${e}`));
  hasErrors = true;
}

if (hookWarnings.length > 0) {
  console.warn(`\n⚠️  Hook output format issues (${hookWarnings.length}):`);
  console.warn(`   Claude Code only reads "decision" and "reason" fields from PostToolUse JSON.`);
  console.warn(`   Other fields are logged but NOT visible to Claude.`);
  hookWarnings.forEach((w) => console.warn(`   - ${w}`));
  hasWarnings = true;
}

// Report hook structure issues (manage-hooks.sh jq validation)
// ADR: Lesson from user "Chen" - "Invalid discriminator value" from malformed hook structure
if (hookStructErrors.length > 0) {
  console.error(`\n❌ HOOK JSON STRUCTURE ERRORS (${hookStructErrors.length}):`);
  console.error(`   These will cause "Invalid discriminator value" errors when installing hooks.`);
  hookStructErrors.forEach((e) => console.error(`   - ${e}`));
  hasErrors = true;
}

if (hookStructWarnings.length > 0) {
  console.warn(`\n⚠️  Hook structure warnings (${hookStructWarnings.length}):`);
  hookStructWarnings.forEach((w) => console.warn(`   - ${w}`));
  hasWarnings = true;
}

// Show declared dependencies summary
if (declaredDeps.size > 0) {
  console.log(`\n📦 Declared Dependencies (marketplace.json 'requires'):`);
  for (const [plugin, requires] of declaredDeps.entries()) {
    console.log(`   ${plugin} → [${requires.join(", ")}]`);
  }
}

// Show dependency graph if requested
if (SHOW_DEPS) {
  console.log(formatDependencyGraph(depGraph, depDetails));
}

// Collect all issues for explicit summary
const allErrors = [
  ...(unregistered.length > 0 ? [`${unregistered.length} unregistered plugins`] : []),
  ...entryErrors,
  ...depErrors,
  ...declErrors,
  ...hookErrors,
  ...hookStructErrors,
];
const allWarnings = [
  ...(orphaned.length > 0 ? [`${orphaned.length} orphaned entries`] : []),
  ...entryWarnings,
  ...depWarnings,
  ...declWarnings,
  ...hookWarnings,
  ...hookStructWarnings,
  ...(cycles.length > 0 ? [`${cycles.length} circular dependencies`] : []),
];

// Show installation instructions if --deps flag
if (SHOW_DEPS && declaredDeps.size > 0) {
  console.log(generateInstallInstructions(declaredDeps));
}

// Exit with appropriate code - LOUD and EXPLICIT for Claude Code CLI
console.log("\n" + "═".repeat(60));
console.log("VALIDATION SUMMARY");
console.log("═".repeat(60));
console.log(`Errors:   ${allErrors.length}`);
console.log(`Warnings: ${allWarnings.length}`);
console.log(`Plugins:  ${directories.length} directories, ${registered.length} registered`);
console.log(`Dependencies: ${depGraph.size} plugins depend on ${[...new Set([...depGraph.values()].flatMap(s => [...s]))].length} others`);
console.log("═".repeat(60));

if (hasErrors) {
  console.error(`\n❌ VALIDATION FAILED - ${allErrors.length} error(s) must be fixed`);
  console.error(`   Run: bun scripts/validate-plugins.mjs --fix`);
  process.exit(1);
} else if (hasWarnings && STRICT_MODE) {
  console.error(`\n❌ VALIDATION FAILED (strict mode) - ${allWarnings.length} warning(s) must be fixed`);
  process.exit(1);
} else if (hasWarnings) {
  console.log(`\n⚠️  VALIDATION PASSED WITH ${allWarnings.length} WARNING(S)`);
  if (!SHOW_DEPS && depGraph.size > 0) {
    console.log(`   Run with --deps to see inter-plugin dependency graph.`);
  }
  process.exit(0);
} else {
  console.log(`\n✅ VALIDATION PASSED - All ${directories.length} plugins valid`);
  if (!SHOW_DEPS && depGraph.size > 0) {
    console.log(`   Run with --deps to see inter-plugin dependency graph.`);
  }
  process.exit(0);
}
})();
