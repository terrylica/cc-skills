#!/usr/bin/env node
/**
 * Version Sync Script for semantic-release
 *
 * Updates version fields in all JSON files that contain version information.
 * Called by @semantic-release/exec during the prepare step.
 *
 * Usage: node scripts/sync-versions.mjs <version>
 * Example: node scripts/sync-versions.mjs 3.0.0
 *
 * Architecture: marketplace.json-only versioning (strict: false)
 * - Individual plugins do NOT have their own plugin.json files
 * - All version info is centralized in marketplace.json
 * - This follows the pattern used by claude-code-plugins-plus (254 plugins)
 *
 * AUTO-DISCOVERY: Plugin count is dynamically read from marketplace.json
 * - No hardcoded plugin counts - adapts to new plugins automatically
 * - Pre-commit hook validates plugin directory count matches marketplace.json
 *
 * ADR: /docs/adr/2025-12-05-centralized-version-management.md
 */

import { readFileSync, writeFileSync, readdirSync, statSync } from "fs";
import { resolve, join } from "path";

const VERSION = process.argv[2];

if (!VERSION) {
  console.error("Usage: node scripts/sync-versions.mjs <version>");
  console.error("Example: node scripts/sync-versions.mjs 3.0.0");
  process.exit(1);
}

// Validate semver format
if (!/^\d+\.\d+\.\d+(-[\w.]+)?$/.test(VERSION)) {
  console.error(`Invalid version format: ${VERSION}`);
  console.error("Expected: X.Y.Z or X.Y.Z-prerelease");
  process.exit(1);
}

// Files to sync (relative to repo root)
// marketplace.json-only architecture: no individual plugin.json files
const FILES = [
  "plugin.json",
  "package.json",
  ".claude-plugin/plugin.json",
  ".claude-plugin/marketplace.json",
];

/**
 * Auto-discover plugin count from marketplace.json
 * Returns: { pluginCount, pluginNames }
 */
function discoverPluginCount() {
  const marketplacePath = resolve(process.cwd(), ".claude-plugin/marketplace.json");
  try {
    const content = JSON.parse(readFileSync(marketplacePath, "utf8"));
    const plugins = content.plugins || [];
    return {
      pluginCount: plugins.length,
      pluginNames: plugins.map(p => p.name),
    };
  } catch (err) {
    console.error(`Error reading marketplace.json: ${err.message}`);
    process.exit(1);
  }
}

/**
 * Validate that plugins/ directory count matches marketplace.json
 * This catches the case where plugin files exist but weren't registered
 */
function validatePluginDirectories(expectedPlugins) {
  const pluginsDir = resolve(process.cwd(), "plugins");
  try {
    const dirs = readdirSync(pluginsDir).filter(name => {
      const path = join(pluginsDir, name);
      return statSync(path).isDirectory() && !name.startsWith(".");
    });

    const missing = dirs.filter(d => !expectedPlugins.includes(d));
    const extra = expectedPlugins.filter(p => !dirs.includes(p));

    if (missing.length > 0) {
      console.warn(`\n⚠️  Plugin directories not registered in marketplace.json:`);
      missing.forEach(m => console.warn(`   - plugins/${m}/`));
      console.warn(`   Run: Add these to .claude-plugin/marketplace.json\n`);
    }

    if (extra.length > 0) {
      console.warn(`\n⚠️  Plugins in marketplace.json without directories:`);
      extra.forEach(e => console.warn(`   - ${e}`));
    }

    return { dirs, missing, extra };
  } catch (err) {
    console.warn(`Could not validate plugins directory: ${err.message}`);
    return { dirs: [], missing: [], extra: [] };
  }
}

// Auto-discover plugin count
const { pluginCount, pluginNames } = discoverPluginCount();
console.log(`Discovered ${pluginCount} plugins in marketplace.json`);

// Validate plugin directories match
const { missing } = validatePluginDirectories(pluginNames);
if (missing.length > 0) {
  console.error(`\n❌ Unregistered plugins detected! Register them in marketplace.json first.`);
  process.exit(1);
}

// Expected version field counts per file (auto-discovered)
const EXPECTED_COUNTS = {
  "plugin.json": 1,
  "package.json": 1,
  ".claude-plugin/plugin.json": 1,
  ".claude-plugin/marketplace.json": 1 + pluginCount, // 1 root + N plugins
};

// Version regex pattern
const VERSION_PATTERN = /"version":\s*"[0-9]+\.[0-9]+\.[0-9]+(-[\w.]+)?"/g;

let totalReplacements = 0;
const results = [];

for (const file of FILES) {
  const filePath = resolve(process.cwd(), file);

  try {
    const content = readFileSync(filePath, "utf8");
    const matches = content.match(VERSION_PATTERN) || [];

    if (matches.length === 0) {
      console.warn(`Warning: No version fields found in ${file}`);
      results.push({ file, replacements: 0, status: "no-match" });
      continue;
    }

    const updated = content.replace(
      VERSION_PATTERN,
      `"version": "${VERSION}"`
    );

    writeFileSync(filePath, updated, "utf8");

    console.log(`Updated ${file}: ${matches.length} version field(s)`);
    results.push({ file, replacements: matches.length, status: "updated" });
    totalReplacements += matches.length;
  } catch (err) {
    if (err.code === "ENOENT") {
      console.error(`Error: File not found: ${file}`);
      results.push({ file, replacements: 0, status: "not-found" });
    } else {
      throw err;
    }
  }
}

// Summary
console.log("\n--- Version Sync Summary ---");
console.log(`Version: ${VERSION}`);
console.log(`Files processed: ${FILES.length}`);
console.log(`Total replacements: ${totalReplacements}`);

// Validate expected counts
let hasError = false;
for (const { file, replacements, status } of results) {
  const expected = EXPECTED_COUNTS[file];
  if (status === "updated" && replacements !== expected) {
    console.error(
      `Validation error: ${file} expected ${expected} replacements, got ${replacements}`
    );
    hasError = true;
  }
}

if (hasError) {
  console.error("\nVersion sync completed with validation errors!");
  process.exit(1);
}

// Verify total expected replacements: 1 + 1 + 1 + 15 = 18 (root + 14 plugins)
const expectedTotal = Object.values(EXPECTED_COUNTS).reduce((a, b) => a + b, 0);
if (totalReplacements !== expectedTotal) {
  console.error(`\nExpected ${expectedTotal} total replacements, got ${totalReplacements}`);
  process.exit(1);
}

console.log("\nVersion sync completed successfully!");
