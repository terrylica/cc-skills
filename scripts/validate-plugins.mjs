#!/usr/bin/env node
/**
 * Plugin Registration Validator
 *
 * Validates that all plugin directories are registered in marketplace.json
 * with complete and valid entries, and tracks inter-plugin dependencies.
 *
 * Usage:
 *   node scripts/validate-plugins.mjs           # Validate only
 *   node scripts/validate-plugins.mjs --fix     # Show fix instructions
 *   node scripts/validate-plugins.mjs --strict  # Fail on warnings too
 *   node scripts/validate-plugins.mjs --deps    # Show dependency graph
 *
 * Validations:
 *   1. Plugin directories have marketplace.json entries (registration)
 *   2. Marketplace entries have required fields (name, description, version, source, category)
 *   3. Source paths in marketplace.json exist on disk
 *   4. Hooks paths (if specified) exist on disk
 *   5. No orphaned entries (registered but no directory)
 *   6. Inter-plugin dependencies are tracked and circular deps detected
 *   7. Referenced skills exist in target plugins
 *
 * Integration:
 *   - Pre-commit hook: Add to .husky/pre-commit or .git/hooks/pre-commit
 *   - CI validation: Add to GitHub Actions workflow
 *   - Manual: Run before `npm run release`
 *
 * ADR: /docs/adr/2025-12-05-centralized-version-management.md
 * ADR: /docs/adr/2025-12-14-alpha-forge-worktree-management.md (lesson learned)
 */

import { readFileSync, readdirSync, statSync, existsSync } from "fs";
import { resolve, join, dirname, relative } from "path";

const SHOW_FIX = process.argv.includes("--fix");
const STRICT_MODE = process.argv.includes("--strict");
const SHOW_DEPS = process.argv.includes("--deps");

const REQUIRED_FIELDS = ["name", "description", "version", "source", "category"];

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
 * ADR: /docs/adr/2025-12-14-alpha-forge-worktree-management.md (lesson learned)
 */
function validateMarketplaceEntries() {
  const data = getMarketplaceData();
  const plugins = data.plugins || [];
  const errors = [];
  const warnings = [];

  plugins.forEach((plugin, index) => {
    const prefix = `Plugin #${index + 1} (${plugin.name || "unnamed"})`;

    // Check required fields
    REQUIRED_FIELDS.forEach(field => {
      if (!plugin[field]) {
        errors.push(`${prefix}: Missing required field '${field}'`);
      }
    });

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
 */
function findMarkdownFiles(dir) {
  const files = [];
  if (!existsSync(dir)) return files;

  const entries = readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...findMarkdownFiles(fullPath));
    } else if (entry.name.endsWith(".md")) {
      files.push(fullPath);
    }
  }
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
function buildDependencyGraph() {
  const pluginsDir = resolve(process.cwd(), "plugins");
  const directories = getPluginDirectories();
  const graph = new Map(); // plugin -> Set of plugins it depends on
  const details = []; // detailed dependency info

  directories.forEach((pluginName) => {
    const pluginDir = join(pluginsDir, pluginName);
    const mdFiles = findMarkdownFiles(pluginDir);

    mdFiles.forEach((file) => {
      const deps = extractSkillDependencies(file);
      deps.forEach((dep) => {
        // Skip self-references
        if (dep.plugin === pluginName) return;

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
      });
    });
  });

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

  // Check for undeclared dependencies (detected but not in requires)
  for (const [plugin, detected] of detectedGraph.entries()) {
    const declared = declaredDeps.get(plugin) || [];
    for (const dep of detected) {
      if (!declared.includes(dep)) {
        warnings.push(
          `Plugin '${plugin}' uses Skill(${dep}:*) but doesn't declare it in 'requires'`
        );
      }
    }
  }

  // Check for over-declared dependencies (in requires but not detected)
  for (const [plugin, declared] of declaredDeps.entries()) {
    const detected = detectedGraph.get(plugin) || new Set();
    for (const dep of declared) {
      if (!detected.has(dep)) {
        warnings.push(
          `Plugin '${plugin}' declares '${dep}' in requires but no Skill() calls found`
        );
      }
    }
  }

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

// Main validation
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

// Dependency validation (detected from Skill() calls)
const { graph: depGraph, details: depDetails } = buildDependencyGraph();
const cycles = detectCircularDependencies(depGraph);
const { errors: depErrors, warnings: depWarnings } = validateSkillExistence(depDetails);

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
];
const allWarnings = [
  ...(orphaned.length > 0 ? [`${orphaned.length} orphaned entries`] : []),
  ...entryWarnings,
  ...depWarnings,
  ...declWarnings,
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
  console.error(`   Run: node scripts/validate-plugins.mjs --fix`);
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
