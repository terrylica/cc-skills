#!/usr/bin/env node
/**
 * Version Sync Script for semantic-release
 *
 * Updates version fields in all plugin JSON files.
 * Called by @semantic-release/exec during the prepare step.
 *
 * Usage: node scripts/sync-versions.mjs <version>
 * Example: node scripts/sync-versions.mjs 2.6.0
 *
 * ADR: /docs/adr/2025-12-05-centralized-version-management.md
 */

import { readFileSync, writeFileSync, readdirSync, existsSync } from "fs";
import { resolve, join } from "path";

const VERSION = process.argv[2];

if (!VERSION) {
  console.error("Usage: node scripts/sync-versions.mjs <version>");
  console.error("Example: node scripts/sync-versions.mjs 2.6.0");
  process.exit(1);
}

// Validate semver format
if (!/^\d+\.\d+\.\d+(-[\w.]+)?$/.test(VERSION)) {
  console.error(`Invalid version format: ${VERSION}`);
  console.error("Expected: X.Y.Z or X.Y.Z-prerelease");
  process.exit(1);
}

// Core files to sync (relative to repo root)
const CORE_FILES = [
  "plugin.json",
  "package.json",
  ".claude-plugin/plugin.json",
  ".claude-plugin/marketplace.json",
];

// Dynamically discover individual plugin.json files
function discoverPluginFiles() {
  const pluginsDir = resolve(process.cwd(), "plugins");
  const pluginFiles = [];

  if (!existsSync(pluginsDir)) {
    return pluginFiles;
  }

  const plugins = readdirSync(pluginsDir, { withFileTypes: true });
  for (const plugin of plugins) {
    if (plugin.isDirectory()) {
      const pluginJsonPath = join(
        "plugins",
        plugin.name,
        ".claude-plugin",
        "plugin.json"
      );
      const fullPath = resolve(process.cwd(), pluginJsonPath);
      if (existsSync(fullPath)) {
        pluginFiles.push(pluginJsonPath);
      }
    }
  }

  return pluginFiles;
}

// Version regex pattern
const VERSION_PATTERN = /"version":\s*"[0-9]+\.[0-9]+\.[0-9]+(-[\w.]+)?"/g;

// Discover all files to sync
const pluginFiles = discoverPluginFiles();
const ALL_FILES = [...CORE_FILES, ...pluginFiles];

console.log(`Discovered ${pluginFiles.length} individual plugin file(s)`);

let totalReplacements = 0;
const results = [];

for (const file of ALL_FILES) {
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
console.log(`Core files: ${CORE_FILES.length}`);
console.log(`Plugin files: ${pluginFiles.length}`);
console.log(`Total files processed: ${ALL_FILES.length}`);
console.log(`Total replacements: ${totalReplacements}`);

// Validate core files have expected counts
const expectedCore = {
  "plugin.json": 1,
  "package.json": 1,
  ".claude-plugin/plugin.json": 1,
  ".claude-plugin/marketplace.json": 10 + 1, // N plugins + 1 root version
};

let hasError = false;
for (const { file, replacements, status } of results) {
  const expectedCount = expectedCore[file];
  // Only validate core files with known expected counts
  if (expectedCount !== undefined && status === "updated" && replacements !== expectedCount) {
    console.error(
      `Validation error: ${file} expected ${expectedCount} replacements, got ${replacements}`
    );
    hasError = true;
  }
  // Individual plugin files should have exactly 1 version field
  if (file.startsWith("plugins/") && status === "updated" && replacements !== 1) {
    console.error(
      `Validation error: ${file} expected 1 replacement, got ${replacements}`
    );
    hasError = true;
  }
}

if (hasError) {
  console.error("\nVersion sync completed with validation errors!");
  process.exit(1);
}

// Verify minimum expected replacements
// Core: 1 + 1 + 1 + 11 = 14
// Plus 1 per individual plugin file
const expectedMinimum = 14 + pluginFiles.length;
if (totalReplacements < expectedMinimum) {
  console.error(`\nExpected at least ${expectedMinimum} total replacements, got ${totalReplacements}`);
  process.exit(1);
}

console.log("\nVersion sync completed successfully!");
