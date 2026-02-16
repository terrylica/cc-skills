#!/usr/bin/env bun
/**
 * Fake Data Pattern Definitions
 *
 * 69 patterns across 7 categories for detecting fake/synthetic data
 * in Python files. Used by pretooluse-fake-data-guard.mjs.
 *
 * ADR: /docs/adr/2025-12-27-fake-data-guard-universal.md
 */

/**
 * Pattern categories with regex patterns for fake data detection.
 * Each category can be individually enabled/disabled via config.
 */
export const PATTERNS = {
  // 15 patterns: NumPy random generation
  numpy_random: [
    /\bnp\.random\.randn\b/,
    /\bnp\.random\.rand\b/,
    /\bnp\.random\.normal\b/,
    /\bnp\.random\.uniform\b/,
    /\bnp\.random\.randint\b/,
    /\bnp\.random\.choice\b/,
    /\bnp\.random\.poisson\b/,
    /\bnp\.random\.exponential\b/,
    /\bnp\.random\.beta\b/,
    /\bnp\.random\.gamma\b/,
    /\bnp\.random\.shuffle\b/,
    /\bnp\.random\.permutation\b/,
    /\bRandomState\b/,
    /\bdefault_rng\b/,
    /\bGenerator\s*\(/,
  ],

  // 10 patterns: Python stdlib random
  python_random: [
    /\brandom\.random\s*\(/,
    /\brandom\.randint\s*\(/,
    /\brandom\.choice\s*\(/,
    /\brandom\.choices\s*\(/,
    /\brandom\.sample\s*\(/,
    /\brandom\.shuffle\s*\(/,
    /\brandom\.uniform\s*\(/,
    /\brandom\.gauss\s*\(/,
    /\brandom\.normalvariate\s*\(/,
    /\brandom\.triangular\s*\(/,
  ],

  // 4 patterns: Faker library
  faker_library: [
    /\bFaker\s*\(/,
    /\bfaker\.\w+/,
    /\bfake\.\w+/,
    /from\s+faker\s+import\b/,
  ],

  // 7 patterns: Factory patterns
  factory_patterns: [
    /\bFactory\.create\b/,
    /\bfactory_boy\b/,
    /\bFactoryBoy\b/,
    /(?<!default)_factory\b/,
    /\.make_\w+/,
    /\bbuild_batch\b/,
    /\bcreate_batch\b/,
  ],

  // 21 patterns: Synthetic/mock/dummy keywords
  synthetic_keywords: [
    /\bsynthetic_data\b/i,
    /\bsynthetic\s+data\b/i,
    /\bmock_data\b/i,
    /\bmock\s+data\b/i,
    /\bdummy_data\b/i,
    /\bdummy\s+data\b/i,
    /\bfake_data\b/i,
    /\bfake\s+data\b/i,
    /\bplaceholder_data\b/i,
    /\bplaceholder\s+data\b/i,
    /\bsample_data\b/i,
    /\bsample\s+data\b/i,
    /\btest_data\b/i,
    /\btest\s+data\b/i,
    /\bfixture_data\b/i,
    /\bfixture\s+data\b/i,
    /\bgenerate_random\b/i,
    /\bgenerate_fake\b/i,
    /\bcreate_mock\b/i,
    /\bcreate_fake\b/i,
    /\bcreate_dummy\b/i,
  ],

  // 7 patterns: sklearn data generation
  data_generation: [
    /\bmake_classification\b/,
    /\bmake_regression\b/,
    /\bmake_blobs\b/,
    /\bmake_moons\b/,
    /\bmake_circles\b/,
    /\bdatasets\.make_\w+/,
    /\bsklearn\.datasets\.make\b/,
  ],

  // 5 patterns: Test data libraries
  test_data_libs: [
    /\bhypothesis\b/,
    /\bmimesis\b/,
    /\bpolyfactory\b/,
    /\bfactory-boy\b/,
    /\bpytest-factoryboy\b/,
  ],
};

/**
 * Default configuration for fake data guard.
 */
export const DEFAULT_CONFIG = {
  enabled: true,
  mode: "deny", // "deny" | "ask" — deny gives Claude Code actionable guidance to self-correct
  patterns: {
    numpy_random: true,
    python_random: true,
    faker_library: true,
    factory_patterns: true,
    synthetic_keywords: true,
    data_generation: true,
    test_data_libs: true,
  },
  whitelist_comments: ["# noqa: fake-data", "# allow-random"],
  exclude_paths: ["tests/", "*_test.py", "conftest.py"],
};

/**
 * Finding type for detected fake data patterns.
 * @typedef {Object} FakeDataFinding
 * @property {string} category - Pattern category name
 * @property {number} line - Line number (1-indexed)
 * @property {string} match - Matched text
 * @property {string} context - Full line content (trimmed)
 */

/**
 * Detect fake data patterns in content.
 *
 * @param {string} content - File content to scan
 * @param {Object} enabledPatterns - Object with category names as keys, boolean values
 * @param {string[]} whitelistComments - Comments that whitelist a line
 * @returns {FakeDataFinding[]} Array of findings
 */
export function detectFakeData(content, enabledPatterns, whitelistComments = []) {
  const findings = [];
  const lines = content.split("\n");

  for (const [category, patterns] of Object.entries(PATTERNS)) {
    // Skip disabled categories
    if (!enabledPatterns[category]) continue;

    for (let lineNum = 0; lineNum < lines.length; lineNum++) {
      const line = lines[lineNum];

      // Skip whitelisted lines
      if (isWhitelisted(line, whitelistComments)) continue;

      // Skip comments (Python)
      const trimmedLine = line.trim();
      if (trimmedLine.startsWith("#")) continue;

      // Check each pattern in category
      for (const pattern of patterns) {
        const match = line.match(pattern);
        if (match) {
          findings.push({
            category,
            line: lineNum + 1,
            match: match[0],
            context: trimmedLine,
          });
          break; // One finding per line per category is enough
        }
      }
    }
  }

  return findings;
}

/**
 * Check if a line is whitelisted via inline comment.
 *
 * @param {string} line - Line to check
 * @param {string[]} whitelistComments - Array of whitelist comment strings
 * @returns {boolean} True if line is whitelisted
 */
export function isWhitelisted(line, whitelistComments) {
  return whitelistComments.some((comment) => line.includes(comment));
}

/**
 * Check if a path should be excluded from scanning.
 *
 * @param {string} filePath - File path to check
 * @param {string[]} excludePaths - Array of path patterns to exclude
 * @returns {boolean} True if path should be excluded
 */
export function isExcludedPath(filePath, excludePaths) {
  for (const pattern of excludePaths) {
    // Simple glob matching
    if (pattern.endsWith("/")) {
      // Directory prefix match
      if (filePath.includes(pattern) || filePath.startsWith(pattern)) {
        return true;
      }
    } else if (pattern.startsWith("*")) {
      // Suffix match
      const suffix = pattern.slice(1);
      if (filePath.endsWith(suffix)) {
        return true;
      }
    } else {
      // Exact match
      if (filePath === pattern || filePath.endsWith(`/${pattern}`)) {
        return true;
      }
    }
  }
  return false;
}

/**
 * Format findings for display in permission dialog.
 *
 * @param {FakeDataFinding[]} findings - Array of findings
 * @returns {string} Formatted string for display
 */
export function formatFindings(findings) {
  // Group by category
  const grouped = {};
  for (const finding of findings) {
    if (!grouped[finding.category]) {
      grouped[finding.category] = [];
    }
    grouped[finding.category].push(finding);
  }

  // Format output
  const lines = [];
  for (const [category, categoryFindings] of Object.entries(grouped)) {
    lines.push(`  ${category}:`);
    for (const f of categoryFindings.slice(0, 3)) {
      // Limit to 3 per category
      lines.push(`    - Line ${f.line}: '${f.match}'`);
    }
    if (categoryFindings.length > 3) {
      lines.push(`    ... and ${categoryFindings.length - 3} more`);
    }
  }

  return lines.join("\n");
}
