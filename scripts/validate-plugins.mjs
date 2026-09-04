#!/usr/bin/env bun
// FILE-SIZE-OK — comprehensive validator for 24+ plugins, hooks, commands, dependencies
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
 *   9. All skills/{name}/SKILL.md must have name + description frontmatter
 *  10. No hook command invokes a proto-shimmed tool bare (proto's NDJSON banner
 *      lands on stdout ahead of the hook's JSON, silently voiding its decision)
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
import { homedir } from "os";
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

    // Warn if plugin still has deprecated "commands" field (commands/ layer eliminated in v11.54.0)
    if (plugin.commands) {
      warnings.push(`${prefix}: Has deprecated "commands" field in marketplace.json — remove it (commands/ layer eliminated, see v11.54.0 migration)`);
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
 * Known complementary plugin pairs that have intentional bidirectional Skill() references.
 * These are NOT true circular dependencies - they are collaborative workflows where
 * each plugin recommends using the other for related tasks. Neither REQUIRES
 * the other.
 */
const KNOWN_COMPLEMENTARY_PAIRS = new Set([
  "doc-tools:itp",   // Diagram generation ↔ diagram validation workflows
  "itp:doc-tools",   // Same pair, reverse direction
]);

/**
 * Check if a cycle is a known complementary pair (not a real circular dependency)
 */
function isComplementaryPair(cycle) {
  // A cycle like ["doc-tools", "itp", "doc-tools"] has 3 elements
  // The actual pair is the first two elements
  if (cycle.length !== 3) return false;
  const pair = `${cycle[0]}:${cycle[1]}`;
  return KNOWN_COMPLEMENTARY_PAIRS.has(pair);
}

/**
 * Detect circular dependencies using DFS
 * Returns array of cycles found, e.g., [["a", "b", "a"], ["x", "y", "z", "x"]]
 * Filters out known complementary pairs that are intentionally bidirectional.
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

  // Filter out known complementary pairs (not real circular dependencies)
  return cycles.filter((cycle) => !isComplementaryPair(cycle));
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
      "**/*.test.mjs",   // Exclude JavaScript test files
      "**/*.spec.mjs",   // Exclude JavaScript spec files
      "**/*.test.js",    // Exclude plain JS test files
      "**/*.spec.js",    // Exclude plain JS spec files
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
  if (lowerFilename.includes("sessionstart") || lowerFilename.includes("session-start") || lowerFilename.includes("session-bind")) {
    return "SessionStart";
  }
  if (lowerFilename.includes("empty-firing") || lowerFilename.includes("firing-detector")) {
    return "Stop";
  }

  // Content-based heuristics
  if (content.includes("PostToolUse") || content.includes("tool_response")) {
    return "PostToolUse";
  }
  if (content.includes("stop_hook_active") || content.includes('"Stop hook"') || content.includes("(Claude Code Stop hook)")) {
    return "Stop";
  }
  if (content.includes("permissionDecision") || content.includes("PreToolUse")) {
    return "PreToolUse";
  }
  if (content.includes("SessionStart") || content.includes('"hookEventName": "SessionStart"')) {
    return "SessionStart";
  }

  return "unknown";
}

/**
 * Validate hook output format for Claude Code consumption
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
          content.toLowerCase().includes("must be fixed") ||
          content.toLowerCase().includes("fix before") ||
          content.toLowerCase().includes("hard-blocking") ||
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
            `${relPath}: Hook outputs fields invisible to Claude Code`
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
/**
 * Every tool `proto` installs a PATH shim for. Invoking one of these BARE from a
 * hook command re-execs the proto CLI, which sniffs AI_AGENT/CLAUDECODE, decides
 * it is talking to an agent, and writes an NDJSON banner to STDOUT before
 * delegating — so the hook's own JSON lands on line 2 and Claude Code's single
 * JSON.parse throws "Hook output looks like a JSON object but is not valid JSON".
 * The hook is then treated as failed and its decision is DISCARDED, silently
 * disarming the guard while exit code stays 0.
 *
 * Measured 2026-08-30 over three days across 241 tool calls and 8 projects:
 * 2,008 DISCARDED hook decisions, plus ~3,600 further events that carried the
 * proto banner but still succeeded. (The first pass reported 1,716 polluted
 * events; that was an undercount, corrected upward.) See /docs/LESSONS.md
 * (2026-08-30 entry).
 */
const PROTO_SHIMMED_TOOLS = new Set(["bun", "bunx", "node", "go", "gofmt", "moon", "moonx", "zig"]);
const AGENT_ENV_STRIP_PREFIX = "env -u AI_AGENT -u CLAUDECODE ";

/**
 * Interpreters a hook command may name before its script. Mirrors the list in
 * tasks/lib/hook-command-parsing.sh — that bash file is the parsing SSoT; this
 * is its JS port (a .mjs validator cannot source bash). Keep the two in step.
 */
const HOOK_COMMAND_INTERPRETERS = new Set([
  // MUST remain a SUPERSET of PROTO_SHIMMED_TOOLS. parseHookCommand() returns
  // interpreter:null for a head it does not recognise, and the proto-shim check
  // keys off that interpreter — so any tool present in PROTO_SHIMMED_TOOLS but
  // absent here can never be flagged, silently. `go`/`gofmt`/`moon`/`moonx`/
  // `zig` were in exactly that state: a bare `moon …` hook command that the
  // previous implementation caught produced zero errors after the port, and the
  // same omission raised a false positive in the other direction (a correctly
  // prefixed `env -u … moon run :x` was reported as a missing script). The
  // spread below makes the containment structural rather than a thing two
  // hand-maintained lists have to agree about. Caught in review 2026-09-01.
  ...PROTO_SHIMMED_TOOLS,
  "deno", "npx", "bash", "sh", "zsh", "python", "python3", "uv", "uvx",
]);

// Fail loudly at load time if the invariant above is ever broken by an edit
// that adds to PROTO_SHIMMED_TOOLS without touching this set.
for (const shimmedTool of PROTO_SHIMMED_TOOLS) {
  if (!HOOK_COMMAND_INTERPRETERS.has(shimmedTool)) {
    throw new Error(
      `validate-plugins.mjs invariant broken: "${shimmedTool}" is in PROTO_SHIMMED_TOOLS but not ` +
        `HOOK_COMMAND_INTERPRETERS, so the proto-shim check can never fire for it.`,
    );
  }
}

/** `env` options that consume a SEPARATE following argument. */
const ENV_OPTIONS_TAKING_A_SEPARATE_ARGUMENT = new Set(["-u", "--unset", "-C", "--chdir", "-S", "--split-string"]);

/**
 * Where a hook path written as `$HOME/.claude/plugins/marketplaces/cc-skills/…`
 * lives inside THIS repo. Resolving through it keeps the existence check
 * deterministic instead of "whatever this machine happens to have installed".
 */
const MARKETPLACE_CLONE_PATH_SEGMENT = "/.claude/plugins/marketplaces/cc-skills/";

/** Strip surrounding/embedded quotes — a hook script path never contains one. */
function unquoteHookCommandToken(token) {
  return token.replace(/["']/g, "");
}

/** Drop a leading `env` invocation (incl. nested env, -u VAR, --unset=VAR, -i, VAR=value). */
function stripEnvInvocationPrefixTokens(tokens) {
  if (tokens.length === 0) return tokens;
  if (tokens[0].split("/").pop() !== "env") return tokens;

  let i = 1;
  while (i < tokens.length) {
    const token = tokens[i];
    if (ENV_OPTIONS_TAKING_A_SEPARATE_ARGUMENT.has(token)) { i += 2; continue; }
    if (token.startsWith("-")) { i += 1; continue; }
    if (token.includes("=")) { i += 1; continue; }
    break;
  }
  const rest = tokens.slice(i);
  // Recurse only when the remainder actually shrank — a degenerate `env` with
  // no program must not loop forever.
  return rest.length < tokens.length ? stripEnvInvocationPrefixTokens(rest) : rest;
}

/**
 * Split a hooks.json `command` into { interpreter, scriptToken }. Normalises
 * FIRST (quotes, env prefix, interpreter flags, a `bun run`/`uv run`
 * subcommand) so downstream checks are generic instead of pattern-matching one
 * spelling of one path form.
 */
function parseHookCommand(command) {
  const tokens = stripEnvInvocationPrefixTokens(
    command.split(/\s+/).filter(Boolean).map(unquoteHookCommandToken),
  );
  if (tokens.length === 0) return { interpreter: null, scriptToken: null };

  const head = tokens[0].split("/").pop();
  if (!HOOK_COMMAND_INTERPRETERS.has(head)) {
    // Shape 4: a bare shebang script, no explicit interpreter.
    return { interpreter: null, scriptToken: tokens[0] };
  }

  let i = 1;
  while (i < tokens.length && (tokens[i].startsWith("-") || tokens[i] === "run")) i += 1;
  return { interpreter: head, scriptToken: i < tokens.length ? tokens[i] : null };
}

/**
 * Expand a hook script token to a filesystem path.
 *
 * Returns { path, repoPath, deterministic } where `repoPath` is the in-repo
 * equivalent of a marketplace-clone path (or null), and `deterministic` says
 * whether a miss is a real repo defect (plugin-relative / in-repo) rather than
 * a machine-dependent absolute path this checkout cannot vouch for.
 */
function resolveHookScriptPath(scriptToken, pluginDir, rootDir) {
  if (!scriptToken) return null;

  const referencesPluginRoot = /\$\{?CLAUDE_PLUGIN_ROOT\}?/.test(scriptToken);
  let path = scriptToken
    .replace(/\$\{CLAUDE_PLUGIN_ROOT\}/g, pluginDir)
    .replace(/\$CLAUDE_PLUGIN_ROOT/g, pluginDir)
    .replace(/\$\{HOME\}/g, homedir())
    .replace(/\$HOME/g, homedir());

  if (path.startsWith("~/")) path = join(homedir(), path.slice(2));
  const wasRelative = !path.startsWith("/");
  if (wasRelative) path = join(rootDir, path);

  const segmentIndex = path.indexOf(MARKETPLACE_CLONE_PATH_SEGMENT);
  const repoPath =
    segmentIndex === -1
      ? null
      : join(rootDir, path.slice(segmentIndex + MARKETPLACE_CLONE_PATH_SEGMENT.length));

  return {
    path,
    repoPath,
    deterministic: referencesPluginRoot || wasRelative || repoPath !== null,
  };
}

/**
 * The interpreter named in a script's shebang, or null when it has none.
 *
 * Callers MUST establish existence separately (resolveHookScriptPath +
 * existsSync). Until 2026-09-02 this function folded "the file is not there"
 * into the same `null` it returns for "not a shimmed tool", so a hook command
 * naming a nonexistent script read as CLEAN — and nothing else in this
 * validator noticed the missing file either. A registered hook Claude Code
 * cannot execute is a permanently disarmed guard, which is the exact failure
 * mode this whole check exists to prevent.
 */
function shebangInterpreter(scriptPath) {
  if (!scriptPath || !existsSync(scriptPath)) return null;
  const firstLine = readFileSync(scriptPath, "utf8").split("\n", 1)[0].trim();
  if (!firstLine.startsWith("#!")) return null;

  const tokens = firstLine.slice(2).trim().split(/\s+/).filter(Boolean);
  let i = 0;
  if (tokens[i] && tokens[i].split("/").pop() === "env") {
    i += 1;
    while (i < tokens.length && (tokens[i].startsWith("-") || tokens[i].includes("="))) i += 1;
  }
  return tokens[i] ? tokens[i].split("/").pop() : null;
}

/**
 * Validation 10: hook COMMAND hygiene. Two failure modes, both of which leave a
 * guard registered but not guarding:
 *
 *   (a) the command invokes a proto-shimmed tool without stripping the env vars
 *       proto sniffs — proto prepends an NDJSON banner to stdout and Claude Code
 *       silently discards the hook's decision at exit 0;
 *   (b) the command names a script that IS NOT ON DISK — Claude Code cannot
 *       execute it at all, so the guard is permanently disarmed.
 *
 * (b) was undetectable until 2026-09-02: shebangInterpreter() returned the same
 * `null` for "file absent" as for "not shimmed", the caller read that as clean,
 * and no other validation in this file looked at hook script existence either.
 *
 * Matching is done on a NORMALISED command (quotes stripped, env prefix and
 * interpreter removed, ${CLAUDE_PLUGIN_ROOT}/$HOME/~ expanded) rather than on a
 * literal /^\$\{?CLAUDE_PLUGIN_ROOT\}?\// regex, which missed every quoted token
 * and every $HOME-rooted path in the marketplace.
 *
 * @param {string} rootDir Repository root to resolve against (injectable for tests).
 */
export async function validateHookCommandHygiene(rootDir = process.cwd()) {
  const errors = [];
  const warnings = [];

  const hooksFiles = await glob("plugins/*/hooks/hooks.json", {
    cwd: rootDir,
    absolute: true,
    onlyFiles: true,
  });

  for (const hooksPath of hooksFiles) {
    const relPath = relative(rootDir, hooksPath);
    const pluginDir = dirname(dirname(hooksPath));

    let doc;
    try {
      doc = JSON.parse(readFileSync(hooksPath, "utf8"));
    } catch (parseError) {
      // Surface it rather than skipping silently: an unreadable hooks.json means
      // this check did NOT cover that plugin, and "0 errors" would otherwise
      // read as "clean" for a file nobody inspected.
      warnings.push(`${relPath}: unparseable, hook-command hygiene NOT checked (${parseError.message})`);
      continue;
    }

    const container = doc.hooks ?? doc;
    for (const entries of Object.values(container)) {
      if (!Array.isArray(entries)) continue;
      for (const entry of entries) {
        for (const hook of entry.hooks ?? []) {
          const command = hook.command ?? "";
          if (!command) continue;

          const { interpreter, scriptToken } = parseHookCommand(command);
          const resolved = resolveHookScriptPath(scriptToken, pluginDir, rootDir);

          // ---- (b) the script must actually be on disk ----
          const existingScriptPath =
            resolved === null
              ? null
              : existsSync(resolved.path)
                ? resolved.path
                : resolved.repoPath && existsSync(resolved.repoPath)
                  ? resolved.repoPath
                  : null;

          if (resolved === null) {
            warnings.push(
              `${relPath}: hook command has no resolvable script path — nothing was verified for it. Command: ${command.slice(0, 160)}`,
            );
          } else if (existingScriptPath === null) {
            const detail =
              `${relPath}: registered hook script DOES NOT EXIST: ${resolved.path}` +
              (resolved.repoPath ? ` (in-repo equivalent ${relative(rootDir, resolved.repoPath)} is missing too)` : "") +
              `. Claude Code cannot execute it, so this guard is permanently disarmed while the event still exits 0. Command: ${command.slice(0, 160)}`;
            // A plugin-relative or in-repo path is this repo's own business — a
            // miss is a defect here and errors. A bare absolute path outside the
            // repo depends on the machine, so it can only warn.
            if (resolved.deterministic) errors.push(detail);
            else warnings.push(detail);
          }

          // ---- (a) proto-shim hygiene: RETIRED 2026-09-01, RESTORED 2026-09-03 ----
          //
          // History matters here, because this check has been argued in both
          // directions and the second argument is not the first one reversed.
          //
          // ORIGINALLY (2026-08-30) it required every command invoking a
          // proto-shimmed tool to carry `env -u AI_AGENT -u CLAUDECODE `,
          // because proto < 0.61.2 wrote an NDJSON banner to the shim's STDOUT
          // and Claude Code silently voided the hook's decision at exit 0.
          //
          // RETIRED once proto fixed that upstream (moonrepo/proto#1105, "Fixed
          // in v0.61.2"), verified at 0/100 polluted on the same 100-way
          // concurrency that gave 27-45/100 on 0.61.1. The reasoning was sound
          // as far as it went: a lint enforcing a workaround for a fixed bug
          // reads as a live hazard and invites cargo-culting.
          //
          // RESTORED because #1105 fixed only the SUCCESS path. proto still
          // routes ERRORS through its NDJSON reporter when it sniffs an agent
          // environment, so a failing shim writes its diagnostic to STDOUT and
          // leaves STDERR EMPTY (moonrepo/proto#1110, open). Claude Code reports
          // such a hook as, in full:
          //
          //     Failed with non-blocking status code: No stderr output
          //
          // On 2026-09-02 a pinned bun install directory was renamed while
          // ~/.proto/.prototools still demanded it. Every bun-backed hook began
          // failing; 2,105 failures landed in a 23-minute window across four
          // sessions. Of those, the 1,211 that NAMED their cause did so only
          // because the installed plugins still carried this prefix — proto
          // writes to stderr when the agent vars are absent. The 894 without it
          // said nothing at all. That 58/42 split is the entire value of this
          // lint, measured rather than argued.
          //
          // So the prefix is NOT a workaround for a fixed bug; it is the only
          // thing that keeps a failing hook diagnosable while #1110 is open.
          // The TEST that replaced this lint
          // (tasks/tests/test-proto-shim-does-not-write-an-ai-agent-ndjson-banner-*.sh)
          // stays — it asserts the #1105 property directly, which a lint cannot.
          // The two are complementary: the test proves the banner is gone, this
          // lint keeps the error path readable.
          //
          // Covers the SHEBANG case, which the pre-retirement version missed:
          // four hook commands name a bare `.mjs` path whose interpreter is
          // decided by `#!/usr/bin/env bun|node`. Those are just as shimmed as
          // an explicit `bun …` and were silently unprotected.
          //
          // Retire this for real when #1110 ships and .prototools pins a proto
          // that carries the fix.
          const effectiveInterpreter =
            interpreter ?? (existingScriptPath ? shebangInterpreter(existingScriptPath) : null);

          if (
            PROTO_SHIMMED_TOOLS.has(effectiveInterpreter) &&
            !command.startsWith(AGENT_ENV_STRIP_PREFIX)
          ) {
            errors.push(
              `${relPath}: hook command invokes proto-shimmed "${effectiveInterpreter}" without the ` +
                `\`${AGENT_ENV_STRIP_PREFIX}\` prefix` +
                (interpreter === null ? ` (via its ${basename(existingScriptPath)} shebang)` : "") +
                `. When the shim fails, proto writes the reason to STDOUT and leaves STDERR empty ` +
                `(moonrepo/proto#1110), so Claude Code reports only "Failed with non-blocking status ` +
                `code: No stderr output" and the cause is invisible. Command: ${command.slice(0, 160)}`,
            );
          }

          // The EXISTENCE check above is unrelated and still runs
          // unconditionally — a registered hook whose script is missing is a
          // permanently disarmed guard regardless of proto's version.
        }
      }
    }
  }

  return { errors, warnings };
}

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

    try {
      const content = readFileSync(scriptPath, "utf8");

      // EVERY single-quoted object literal in the generator, however it is introduced.
      //
      // This previously required the literal to follow `jq -n`:
      //     /jq\s+-n\s+(?:--arg\s+\w+\s+"[^"]*"\s*)*'(\{[^']+\})'/g
      // Three hook entries across two generators are plain bash assignments instead --
      //     local posttooluse_entry='{"matcher":"Bash|Write|Edit",…,"timeout":10000}'
      // -- so they were read by NO check at all: this pattern skipped them, and the shipped-artifact
      // loop below only globs `plugins/*/hooks/hooks.json`. Measured on 6f1c9e22: the validator
      // reported "All 41 plugins valid" over a tree whose installer wrote a 10000-SECOND (2h47m)
      // timeout onto a blocking PostToolUse hook. Issue #109, which the timeout fix did not finish.
      const objectLiterals = [...content.matchAll(/'(\{[^']*\})'/g)].map((literal) => ({
        expression: literal[1],
        line: content.slice(0, literal.index).split("\n").length,
      }));

      for (const { expression, line } of objectLiterals) {
        // Skip literals that are clearly not hook entries
        if (!expression.includes("type") && !expression.includes("matcher")) {
          continue;
        }

        let entry;
        try {
          // A bash-literal entry is ALREADY valid JSON -- a `$HOME` inside a quoted value is just
          // characters. Parse it as-is. The `$var -> "placeholder"` substitution below is right for
          // a bare jq variable but CORRUPTS a shell variable inside a JSON string, turning
          // {"command":"$HOME/x.sh"} into {"command":""placeholder"/x.sh"}, which then fails to
          // parse and would be reported as an unreadable expression rather than validated.
          entry = JSON.parse(expression);
        } catch {
          try {
            const testExpr = expression.replace(/\$\w+/g, '"placeholder"');
            entry = JSON.parse(
              execSync(`jq -n '${testExpr}'`, { encoding: "utf8", timeout: 5000 }).trim()
            );
          } catch (parseErr) {
            warnings.push(`${relPath}:${line}: Could not validate hook entry: ${parseErr.message}`);
            continue;
          }
        }

        if (entry.matcher !== undefined) {
          // hookMatcher (PreToolUse, PostToolUse)
          validateHookMatcher(entry, relPath, line, errors, warnings);
        } else if (entry.hooks !== undefined) {
          // hookEventArray entry (Stop, SubagentStop)
          validateHookEventEntry(entry, relPath, line, errors, warnings);
        }
      }

      // SHAPE-INDEPENDENT TIMEOUT SCAN. This, not the widened extractor, is what closes #109.
      //
      // Entry extraction reads two shapes: `jq -n '{…}'` and `local entry='{…}'`. There is a THIRD,
      // an object literal embedded in a multi-line jq PROGRAM with the value bound through --argjson:
      //
      //     jq --argjson timeout "$HOOK_TIMEOUT" '… .hooks.Stop += [{ … "timeout": $timeout }]'
      //
      // No `'{…}'` pattern can see that, and it concealed HOOK_TIMEOUT=30000 -- eight hours twenty
      // minutes on a BLOCKING Stop hook. That is the largest wrong timeout in the repository, larger
      // than the 18-hour value #124 was written to fix, and neither #124 nor a hand grep for
      // oversized literals found it. A checker that only sees the shapes someone thought to enumerate
      // will keep missing the next one.
      //
      // So do not reach the timeout THROUGH a parsed entry. Read every `"timeout":` binding straight
      // out of the text, resolve it across at most two hops (jq arg -> shell variable), and bounds
      // -check the number. Robust to a fourth shape nobody has written yet.
      const { min: timeoutMin, max: timeoutMax } = resolveTimeoutBounds();
      const timeoutBindings = [...content.matchAll(/"timeout"\s*:\s*(\$?[A-Za-z_]\w*|\d+)/g)].map(
        (binding) => ({
          token: binding[1],
          line: content.slice(0, binding.index).split("\n").length,
        }),
      );

      // A binding inside a literal the extractor DID parse is reported twice — once by the schema
      // path above and once here. That is deliberate: the two reports rest on different evidence
      // (a parsed entry vs. raw text), and suppressing one would mean trusting the extractor to
      // decide what the scan is allowed to see, which is the coupling that produced the blind spot.
      for (const { token, line } of timeoutBindings) {
        const seconds = resolveGeneratorTimeoutValue(token, content);

        if (seconds === null) {
          // An unresolvable value must never read as a passing value.
          errors.push(
            `${relPath}:${line}: writes "timeout": ${token}, which cannot be resolved to a number ` +
              `from this file, so its value goes unchecked. Bind it to a literal or to a plain ` +
              `NAME=<digits> assignment that this scan can follow.`
          );
        } else if (timeoutMax === undefined) {
          errors.push(
            `${relPath}:${line}: cannot locate timeout bounds in hooks.schema.json, so the ` +
              `generator timeout constraint is unenforceable. Fix resolveTimeoutBounds() rather ` +
              `than leaving the value unchecked.`
          );
        } else if (seconds < timeoutMin || seconds > timeoutMax) {
          const via = token.startsWith("$") ? ` (via ${token})` : "";
          errors.push(
            `${relPath}:${line}: timeout must be ${timeoutMin}-${timeoutMax} SECONDS, got ` +
              `${seconds}${via}. That is ${describeDurationInSeconds(seconds)}; a blocking hook ` +
              `holds the session for exactly that long.`
          );
        }
      }

      // ANTI-VACUITY. The scan above is `for (...) { check }`, which reports success over an empty
      // set -- the same shape that let these values ship in the first place. If the file writes a
      // `"timeout"` key at all but the scan bound nothing, the spelling has moved and this check
      // has silently stopped covering the file.
      if (content.includes('"timeout"') && timeoutBindings.length === 0) {
        errors.push(
          `${relPath}: contains a "timeout" key but the scan resolved no binding, so no timeout ` +
            `in this generator is checked. Widen the scan rather than leaving it blind.`
        );
      }
    } catch (err) {
      warnings.push(`${relPath}: Could not read script: ${err.message}`);
    }
  }

  // THE SHIPPED ARTIFACT, not only the generator that writes it.
  //
  // Everything above validates jq expressions inside `plugins/*/scripts/manage-hooks.sh`. Five of
  // those scripts exist; TEN `plugins/*/hooks/hooks.json` files actually ship, and none of them was
  // ever checked against hooks.schema.json. Measured: with the loop below absent, restoring the
  // Stop orchestrator's timeout to 65000 -- eighteen hours for a blocking hook -- passed validation
  // with "Errors: 0".
  //
  // A schema applied to a code-generation template rather than to the artifact is a schema that
  // documents an intention. This makes it enforce one.
  const shippedHookFiles = await glob("plugins/*/hooks/hooks.json", {
    cwd: process.cwd(),
    absolute: true,
    onlyFiles: true,
  });

  if (shippedHookFiles.length === 0) {
    // Anti-vacuity: the loop below is `for (...) { check }`, which reports success over an empty
    // set. A glob that stops matching would silently retire this check with no other symptom.
    errors.push(
      "No plugins/*/hooks/hooks.json matched — hook-artifact validation examined nothing. " +
        "Either the layout moved or the glob is wrong; both must fail loudly rather than pass."
    );
  }

  for (const hooksPath of shippedHookFiles) {
    const relPath = relative(process.cwd(), hooksPath);
    let doc;
    try {
      doc = JSON.parse(readFileSync(hooksPath, "utf8"));
    } catch (err) {
      errors.push(`${relPath}: not parseable as JSON: ${err.message}`);
      continue;
    }

    const events = doc.hooks ?? doc;
    if (typeof events !== "object" || events === null) continue;

    for (const [eventName, entries] of Object.entries(events)) {
      if (!Array.isArray(entries)) continue;
      for (const [i, entry] of entries.entries()) {
        const where = `${relPath} ${eventName}[${i}]`;
        if (entry.matcher !== undefined) {
          validateHookMatcher(entry, where, 0, errors, warnings);
        } else if (entry.hooks !== undefined) {
          validateHookEventEntry(entry, where, 0, errors, warnings);
        }
      }
    }
  }

  return { errors, warnings };
}

/**
 * The `timeout` bounds, read from hooks.schema.json rather than restated.
 *
 * ONE lookup, used by both the shipped-artifact check and the generator scan. The bound existed in
 * three places before #124 (a hardcoded 600000, a doc line saying "milliseconds", and the schema),
 * and they disagreed; that disagreement is what shipped 53 wrong values. `max` is deliberately
 * returned as `undefined` when the lookup path breaks, so callers must handle "unknown" explicitly
 * instead of receiving a permissive default.
 */
function resolveTimeoutBounds() {
  const bound =
    hooksSchema?.$defs?.hookDefinition?.properties?.timeout ??
    hooksSchema?.definitions?.hookDefinition?.properties?.timeout;
  return { min: bound?.minimum ?? 1, max: bound?.maximum };
}

/**
 * Resolve a generator's `"timeout":` token to a number, or null when it cannot be resolved.
 *
 * Handles the two indirections that actually occur: a jq argument bound from a shell variable
 * (`--argjson timeout "$HOOK_TIMEOUT"`), and that shell variable's own assignment
 * (`HOOK_TIMEOUT=30000`). Returning null rather than a default is the point — an unresolved
 * timeout is reported as unchecked, never as acceptable.
 */
function resolveGeneratorTimeoutValue(token, content) {
  if (/^\d+$/.test(token)) return Number(token);

  const jqArgName = token.replace(/^\$/, "");
  // Hop 1: jq --argjson <name> "$SHELL_VAR" / "${SHELL_VAR}"
  const jqBinding = content.match(
    new RegExp(String.raw`--argjson\s+${jqArgName}\s+"\$\{?(\w+)\}?"`),
  );
  const shellName = jqBinding ? jqBinding[1] : jqArgName;

  // Hop 2: NAME=<digits>, with or without local/readonly/declare
  const assignment = content.match(
    new RegExp(
      String.raw`(?:^|\n)\s*(?:local\s+|readonly\s+|declare\s+(?:-\w+\s+)?)?${shellName}=(\d+)\b`,
    ),
  );
  return assignment ? Number(assignment[1]) : null;
}

/** Render a seconds value the way a reader feels it, so "30000" reads as the outage it is. */
function describeDurationInSeconds(seconds) {
  if (seconds < 60) return `${seconds} second${seconds === 1 ? "" : "s"}`;
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.round((seconds % 3600) / 60);
  if (hours === 0) return `${minutes} minutes`;
  return `${hours}h${String(minutes).padStart(2, "0")}m`;
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

  // Validate timeout if present.
  //
  // THE BOUND IS READ FROM THE SCHEMA, NOT RESTATED HERE. This check previously hardcoded
  // `hook.timeout > 600000` — a second copy of a constraint whose source of truth is
  // hooks.schema.json — so tightening the schema changed nothing and the schema was, for this
  // field, documentation. Measured: with the schema at `"maximum": 600`, a hook carrying
  // `"timeout": 65000` (eighteen hours, on a BLOCKING Stop hook) still validated with
  // "Errors: 0".
  //
  // It was also a WARNING, and warnings do not fail the run, so even the hardcoded bound could
  // only ever have produced a line nobody reads.
  //
  // The unit is SECONDS. Upstream: "timeout ... Seconds before canceling. ... Defaults: 600 for
  // command, http, and mcp_tool" — https://docs.claude.com/en/docs/claude-code/hooks. The old
  // message said "ms", which is how 53 entries across 10 plugins came to be written as
  // milliseconds in the first place.
  if (hook.timeout !== undefined) {
    const { min, max } = resolveTimeoutBounds();

    if (max === undefined) {
      // Fail loudly rather than silently skipping: a schema whose shape moved must not read as
      // "no constraint". Absence of the bound is a defect in this validator, not permission.
      errors.push(
        `${location}: cannot locate timeout bounds in hooks.schema.json, so the timeout ` +
          `constraint is unenforceable. Fix the lookup path in validateHookDefinition rather ` +
          `than leaving the field unchecked.`
      );
    } else if (typeof hook.timeout !== "number" || hook.timeout < min || hook.timeout > max) {
      errors.push(
        `${location}: timeout must be ${min}-${max} SECONDS, got ${hook.timeout}. ` +
          `A value like 5000 is the millisecond spelling and means ${Math.round(5000 / 60)} ` +
          `minutes here; a blocking hook holds the session for that long.`
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
 * Validate skills frontmatter completeness (v11.54.0 — replaces parity check)
 *
 * Rule: Every skills/{skill}/SKILL.md must have 'name' and 'description'
 * in its YAML frontmatter. This is the canonical source for both context
 * and user-invocable slash commands (via sync-commands-to-settings.sh).
 *
 * Returns { errors: [...], warnings: [...] }
 */
async function validateAllSkillsFrontmatter() {
  const errors = [];
  const warnings = [];

  const skillPaths = await glob("plugins/*/skills/*/SKILL.md", {
    cwd: process.cwd(),
    absolute: true,
    onlyFiles: true,
  });

  for (const skillPath of skillPaths) {
    const relPath = relative(process.cwd(), skillPath);
    try {
      const content = readFileSync(skillPath, "utf8");
      const fmMatch = content.match(/^---\n([\s\S]*?)\n---/);
      if (!fmMatch) {
        errors.push(`${relPath}: SKILL.md missing YAML frontmatter`);
        continue;
      }
      const fm = fmMatch[1];
      if (!fm.includes("name:")) errors.push(`${relPath}: missing 'name' in frontmatter`);
      if (!fm.includes("description:")) errors.push(`${relPath}: missing 'description' in frontmatter`);
    } catch (err) {
      warnings.push(`Could not validate skill frontmatter: ${relPath} (${err.message})`);
    }
  }

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

/**
 * Validate ~/.claude/settings.json for shadow hooks.
 *
 * A "shadow hook" is a non-cc-skills hook whose script basename matches
 * a cc-skills hook. This causes double-firing (duplicate MiniMax calls,
 * duplicate log entries, duplicate block/allow decisions).
 *
 * Example: ~/.claude/automation/.../auto-continue-wrapper.sh shadows
 *          ~/.claude/plugins/marketplaces/cc-skills/.../auto-continue-wrapper.sh
 *
 * Returns { errors: [...], warnings: [...] }
 *
 * @param {string} settingsPath settings.json to inspect (injectable so this can
 *   be exercised against a fixture — a check that can only ever read the
 *   operator's live settings.json is a check nobody can prove still works).
 */
export function validateSettingsHookShadows(
  settingsPath = join(process.env.HOME, ".claude", "settings.json"),
) {
  const errors = [];
  const warnings = [];

  if (!existsSync(settingsPath)) {
    return { errors, warnings };
  }

  let settings;
  try {
    settings = JSON.parse(readFileSync(settingsPath, "utf8"));
  } catch {
    warnings.push("Could not parse ~/.claude/settings.json");
    return { errors, warnings };
  }

  const hookTypes = ["PreToolUse", "PostToolUse", "Stop"];

  for (const hookType of hookTypes) {
    const entries = settings.hooks?.[hookType] ?? [];

    // Extract command strings from each hook entry (handles nested .hooks[] structure)
    const getCommands = (entry) => {
      const cmds = [];
      if (entry.command) cmds.push(entry.command);
      if (Array.isArray(entry.hooks)) {
        for (const h of entry.hooks) {
          if (h.command) cmds.push(h.command);
        }
      }
      return cmds;
    };

    // Extract script basename from a command string.
    //
    // Routed through parseHookCommand() — the JS port of the parsing SSoT
    // tasks/lib/hook-command-parsing.sh, already defined above in this file.
    // The former inline body was "the first whitespace token containing a `/`",
    // which returns `env` for `/usr/bin/env -u AI_AGENT -u CLAUDECODE bun
    // …/hooks/foo.ts` and `/etc/x` for `bash foo.sh --config /etc/x`. Two
    // parsers in ONE file is how they drift; there is now one.
    const scriptBasename = (cmd) => {
      const { scriptToken } = parseHookCommand(cmd);
      if (!scriptToken) return null;
      return scriptToken.split("/").pop();
    };

    // Collect cc-skills basenames and non-cc-skills entries
    const ccBasenames = new Map(); // basename → full command
    const nonCcEntries = []; // { basename, command }

    for (const entry of entries) {
      for (const cmd of getCommands(entry)) {
        const bn = scriptBasename(cmd);
        // An unparseable command has no basename to shadow or be shadowed by.
        // Without this guard two such commands would both key on `null` and
        // report each other as a shadow — a fabricated error, worse than a
        // miss.
        if (!bn) continue;
        if (cmd.includes("cc-skills")) {
          ccBasenames.set(bn, cmd);
        } else {
          nonCcEntries.push({ basename: bn, command: cmd });
        }
      }
    }

    // Check for shadows
    for (const { basename: bn, command } of nonCcEntries) {
      if (ccBasenames.has(bn)) {
        errors.push(
          `Shadow hook in ${hookType}: '${command}' duplicates cc-skills hook '${ccBasenames.get(bn)}' (same basename '${bn}')`
        );
      }
    }
  }

  return { errors, warnings };
}

// Main validation - wrapped in async IIFE for tinyglobby async functions
(async () => {
// Importing this file (a regression test calling validateHookCommandHygiene()
// directly against a fixture tree) must NOT run the whole marketplace
// validation and process.exit() out of the test. `=== false` on purpose: any
// runtime that does not define import.meta.main still executes as before.
if (import.meta.main === false) return;

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

// Hook output format validation (Claude Code consumption) - async with tinyglobby
// ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md
const { errors: hookErrors, warnings: hookWarnings } = await validateHookOutputFormat();

// Hook JSON structure validation (manage-hooks.sh jq expressions) - async with tinyglobby
// ADR: Lesson from user "Chen" - "Invalid discriminator value" from malformed hook structure
const { errors: hookStructErrors, warnings: hookStructWarnings } = await validateHooksJsonStructure();

// Hook command hygiene — no hook may invoke a proto-shimmed tool bare, or proto's
// NDJSON banner lands on stdout ahead of the hook's JSON and the decision is dropped.
const { errors: hookHygieneErrors, warnings: hookHygieneWarnings } = await validateHookCommandHygiene();

// Skills frontmatter validation (v11.54.0 — all skills/*/SKILL.md must have name + description)
const { errors: skillsFrontmatterErrors, warnings: skillsFrontmatterWarnings } = await validateAllSkillsFrontmatter();

// Declared dependency validation (from 'requires' field in marketplace.json)
// Reference: https://github.com/anthropics/claude-code/issues/9444
const declaredDeps = getDeclaredDependencies();
const { errors: declErrors, warnings: declWarnings } = validateDeclaredDependencies(declaredDeps, depGraph);

// Settings.json shadow hook validation (prevents double-firing from duplicate hooks)
const { errors: shadowErrors, warnings: shadowWarnings } = validateSettingsHookShadows();

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

// Report skills frontmatter errors (v11.54.0 — name + description required in all SKILL.md)
if (skillsFrontmatterErrors.length > 0) {
  console.error(`\n❌ SKILLS FRONTMATTER ERRORS (${skillsFrontmatterErrors.length}):`);
  console.error(`   All skills/*/SKILL.md must have 'name' and 'description' in YAML frontmatter`);
  skillsFrontmatterErrors.forEach((e) => console.error(`   - ${e}`));
  hasErrors = true;
}

if (skillsFrontmatterWarnings.length > 0) {
  console.warn(`\n⚠️  Skills frontmatter warnings (${skillsFrontmatterWarnings.length}):`);
  skillsFrontmatterWarnings.forEach((w) => console.warn(`   - ${w}`));
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

// Report hook command hygiene issues (proto shim banner corrupts hook stdout)
if (hookHygieneErrors.length > 0) {
  console.error(`\n❌ HOOK COMMAND HYGIENE ERRORS (${hookHygieneErrors.length}):`);
  console.error(`   A bare proto-shimmed tool makes proto route its output through the NDJSON reporter:`);
  console.error(`   on FAILURE the reason goes to stdout and stderr is left empty (moonrepo/proto#1110),`);
  console.error(`   so a broken hook reports only "Failed with non-blocking status code: No stderr output".`);
  console.error(`   Measured 2026-09-02: of 2,105 such failures, only the 1,211 whose commands carried the`);
  console.error(`   prefix named their own cause; the other 894 said nothing at all.`);
  hookHygieneErrors.forEach((e) => console.error(`   - ${e}`));
  hasErrors = true;
}

if (hookHygieneWarnings.length > 0) {
  console.warn(`\n⚠️  Hook command hygiene warnings (${hookHygieneWarnings.length}):`);
  hookHygieneWarnings.forEach((w) => console.warn(`   - ${w}`));
  hasWarnings = true;
}

// Report shadow hook issues (double-firing from non-cc-skills duplicates in settings.json)
if (shadowErrors.length > 0) {
  console.error(`\n❌ SHADOW HOOK ERRORS (${shadowErrors.length}):`);
  console.error(`   Non-cc-skills hooks shadowing marketplace hooks cause double-firing.`);
  console.error(`   Remove the non-cc-skills duplicate from ~/.claude/settings.json.`);
  shadowErrors.forEach((e) => console.error(`   - ${e}`));
  hasErrors = true;
}

if (shadowWarnings.length > 0) {
  console.warn(`\n⚠️  Shadow hook warnings (${shadowWarnings.length}):`);
  shadowWarnings.forEach((w) => console.warn(`   - ${w}`));
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
  ...hookHygieneErrors,
  ...skillsFrontmatterErrors,
  ...shadowErrors,
];
const allWarnings = [
  ...(orphaned.length > 0 ? [`${orphaned.length} orphaned entries`] : []),
  ...entryWarnings,
  ...depWarnings,
  ...declWarnings,
  ...hookWarnings,
  ...hookStructWarnings,
  ...hookHygieneWarnings,
  ...skillsFrontmatterWarnings,
  ...shadowWarnings,
  ...(cycles.length > 0 ? [`${cycles.length} circular dependencies`] : []),
];

// Show installation instructions if --deps flag
if (SHOW_DEPS && declaredDeps.size > 0) {
  console.log(generateInstallInstructions(declaredDeps));
}

// Exit with appropriate code - LOUD and EXPLICIT for Claude Code
console.log("\n" + "═".repeat(60));
console.log("VALIDATION SUMMARY");
console.log("═".repeat(60));
console.log(`Errors:   ${allErrors.length}`);
console.log(`Warnings: ${allWarnings.length}`);
console.log(`Plugins:  ${directories.length} directories, ${registered.length} registered`);
// Count skills across all plugins (canonical source: skills/{name}/SKILL.md)
const skillCount = (getMarketplaceData().plugins || []).reduce((count, p) => {
  if (p.source) {
    const skillsDir = resolve(process.cwd(), p.source, "skills");
    if (existsSync(skillsDir)) {
      count += readdirSync(skillsDir).filter(d => {
        return existsSync(join(skillsDir, d, "SKILL.md"));
      }).length;
    }
  }
  return count;
}, 0);
if (skillCount > 0) console.log(`Skills: ${skillCount} skill(s) across registered plugins`);
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
