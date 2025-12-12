#!/usr/bin/env node
/**
 * Plugin Registration Validator
 *
 * Validates that all plugin directories are registered in marketplace.json.
 * Run before commit to catch missing plugin registrations early.
 *
 * Usage:
 *   node scripts/validate-plugins.mjs           # Validate only
 *   node scripts/validate-plugins.mjs --fix     # Show fix instructions
 *
 * Integration:
 *   - Pre-commit hook: Add to .husky/pre-commit or .git/hooks/pre-commit
 *   - CI validation: Add to GitHub Actions workflow
 *   - Manual: Run before `npm run release`
 *
 * This script ensures the sync-versions.mjs auto-discovery works correctly
 * by catching unregistered plugins before semantic-release runs.
 *
 * ADR: /docs/adr/2025-12-05-centralized-version-management.md
 */

import { readFileSync, readdirSync, statSync } from "fs";
import { resolve, join } from "path";

const SHOW_FIX = process.argv.includes("--fix");

/**
 * Read marketplace.json and extract plugin names
 */
function getRegisteredPlugins() {
  const marketplacePath = resolve(process.cwd(), ".claude-plugin/marketplace.json");
  try {
    const content = JSON.parse(readFileSync(marketplacePath, "utf8"));
    return (content.plugins || []).map(p => p.name);
  } catch (err) {
    console.error(`❌ Error reading marketplace.json: ${err.message}`);
    process.exit(1);
  }
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

// Main validation
const registered = getRegisteredPlugins();
const directories = getPluginDirectories();

const unregistered = directories.filter(d => !registered.includes(d));
const orphaned = registered.filter(r => !directories.includes(r));

console.log(`📦 Registered plugins: ${registered.length}`);
console.log(`📁 Plugin directories: ${directories.length}`);

let hasErrors = false;

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
      "version": "2.28.0",
      "source": "./plugins/${p}/",
      "category": "TODO",
      "author": { "name": "Terry Li", "url": "https://github.com/terrylica" },
      "keywords": [],
      "strict": false
    }`);
    });
  }
}

if (orphaned.length > 0) {
  console.warn(`\n⚠️  Orphaned entries in marketplace.json (no directory):`);
  orphaned.forEach(p => console.warn(`   - ${p}`));
}

if (hasErrors) {
  console.error(`\n❌ Validation failed! Register plugins before committing.`);
  console.error(`   Run: node scripts/validate-plugins.mjs --fix`);
  process.exit(1);
} else {
  console.log(`\n✅ All plugins validated successfully!`);
}
