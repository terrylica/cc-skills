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

import { readFileSync, writeFileSync } from "fs";
import { resolve } from "path";

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

// Files to sync (relative to repo root)
const FILES = [
  "plugin.json",
  "package.json",
  ".claude-plugin/plugin.json",
  ".claude-plugin/marketplace.json",
];

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
// Note: marketplace.json count = 1 (root) + N (plugins array entries)
const expected = {
  "plugin.json": 1,
  "package.json": 1,
  ".claude-plugin/plugin.json": 1,
  ".claude-plugin/marketplace.json": 11,
};

let hasError = false;
for (const { file, replacements, status } of results) {
  const expectedCount = expected[file];
  if (status === "updated" && replacements !== expectedCount) {
    console.error(
      `Validation error: ${file} expected ${expectedCount} replacements, got ${replacements}`
    );
    hasError = true;
  }
}

if (hasError) {
  console.error("\nVersion sync completed with validation errors!");
  process.exit(1);
}

if (totalReplacements !== 14) {
  console.error(`\nExpected 14 total replacements, got ${totalReplacements}`);
  process.exit(1);
}

console.log("\nVersion sync completed successfully!");
