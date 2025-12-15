#!/usr/bin/env node
/**
 * Plugin Registration Validator
 *
 * Validates that all plugin directories are registered in marketplace.json
 * with complete and valid entries.
 *
 * Usage:
 *   node scripts/validate-plugins.mjs           # Validate only
 *   node scripts/validate-plugins.mjs --fix     # Show fix instructions
 *   node scripts/validate-plugins.mjs --strict  # Fail on warnings too
 *
 * Validations:
 *   1. Plugin directories have marketplace.json entries (registration)
 *   2. Marketplace entries have required fields (name, description, version, source, category)
 *   3. Source paths in marketplace.json exist on disk
 *   4. Hooks paths (if specified) exist on disk
 *   5. No orphaned entries (registered but no directory)
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
import { resolve, join, dirname } from "path";

const SHOW_FIX = process.argv.includes("--fix");
const STRICT_MODE = process.argv.includes("--strict");

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

// Exit with appropriate code
if (hasErrors) {
  console.error(`\n❌ Validation failed! Fix errors before committing.`);
  console.error(`   Run: node scripts/validate-plugins.mjs --fix`);
  process.exit(1);
} else if (hasWarnings && STRICT_MODE) {
  console.error(`\n❌ Validation failed (strict mode)! Fix warnings before committing.`);
  process.exit(1);
} else if (hasWarnings) {
  console.log(`\n⚠️  Validation passed with warnings.`);
} else {
  console.log(`\n✅ All plugins validated successfully!`);
}
