#!/usr/bin/env bun
/**
 * Time-Weighted Sharpe Patterns for Range Bar Data
 *
 * Detects non-time-weighted Sharpe calculations that are problematic
 * when used with range bar data (variable bar durations).
 *
 * Reference: /docs/reference/range-bar-sharpe-calculation.md
 * ADR: /docs/adr/2026-01-21-time-weighted-sharpe-guard.md
 */

/**
 * Default configuration for the guard.
 */
export const DEFAULT_CONFIG = {
  enabled: true,
  mode: "deny", // "deny" = hard block, "ask" = permission dialog
  patterns: {
    simple_bar_sharpe: true,     // mean(pnl) / std(pnl) without time weighting
    missing_duration_pipeline: true,  // range bar pipeline without duration_us
    wrong_crypto_annualization: true, // sqrt(252) instead of sqrt(365) for crypto
  },
  whitelist_comments: [
    "# time-weighted-sharpe-ok",
    "# allow-simple-sharpe",
    "# noqa: sharpe",
  ],
  exclude_paths: [
    "tests/",
    "*_test.py",
    "test_*.py",
    "conftest.py",
    "/docs/",
    "/examples/01_",  // Tutorial examples only, NOT research
    "/examples/02_",
    "/examples/03_",
    "/__pycache__/",
  ],
  // Range bar context indicators
  range_bar_indicators: [
    "range_bar",
    "rangebar",
    "RangeBar",
    "threshold_decimal_bps",
    "duration_us",
    "bar_duration",
  ],
};

/**
 * Patterns that indicate simple bar Sharpe (NOT time-weighted).
 *
 * Each pattern has:
 * - regex: The detection regex
 * - description: Human-readable description
 * - severity: CRITICAL (always block) or HIGH (block in range bar context)
 * - fix_hint: How to fix the issue
 */
export const SIMPLE_BAR_SHARPE_PATTERNS = [
  {
    regex: /np\.mean\s*\([^)]*pnl[^)]*\)\s*\/\s*np\.std\s*\([^)]*pnl[^)]*\)/gi,
    description: "Simple bar Sharpe: np.mean(pnl) / np.std(pnl)",
    severity: "HIGH",
    fix_hint: "Use compute_time_weighted_sharpe(pnl, duration_us) instead",
  },
  {
    regex: /mean\s*\([^)]*\)\s*\/\s*std\s*\([^)]*\)\s*\*\s*np\.sqrt\s*\(\s*252\s*\)/gi,
    description: "Bar Sharpe with wrong annualization: mean/std * sqrt(252)",
    severity: "CRITICAL",
    fix_hint: "Use time-weighted Sharpe OR sqrt(365) for crypto",
  },
  {
    regex: /sharpe\s*=\s*[^#\n]*mean[^#\n]*\/[^#\n]*std/gi,
    description: "Assignment of simple mean/std Sharpe ratio",
    severity: "HIGH",
    fix_hint: "Use time-weighted Sharpe calculation",
  },
  {
    regex: /\.mean\(\)\s*\/\s*\.std\(\)/gi,
    description: "Pandas/NumPy simple mean/std ratio",
    severity: "HIGH",
    fix_hint: "Use time-weighted aggregation with duration weights",
  },
  {
    regex: /returns\.std\(\)[^#\n]*\*\s*np\.sqrt\s*\(\s*252\s*\)/gi,
    description: "Standard returns.std() with sqrt(252) annualization",
    severity: "HIGH",
    fix_hint: "Weight by bar duration for range bars",
  },
];

/**
 * Patterns that indicate missing duration in pipeline.
 */
export const MISSING_DURATION_PATTERNS = [
  {
    regex: /create_sequences\s*\([^)]*\)\s*(?!.*duration)/gi,
    description: "create_sequences() without duration preservation",
    severity: "HIGH",
    fix_hint: "Use create_sequences_with_duration() to preserve duration_us",
  },
  {
    regex: /X_train,\s*y_train\s*=\s*[^#\n]*(?!duration)/gi,
    description: "Train split without duration variable",
    severity: "HIGH",
    fix_hint: "Preserve duration_us: X, y, duration = create_sequences_with_duration(...)",
  },
];

/**
 * Patterns for wrong crypto annualization.
 */
export const WRONG_ANNUALIZATION_PATTERNS = [
  {
    regex: /np\.sqrt\s*\(\s*252\s*\)[^#\n]*(btc|eth|crypto|binance|usdt)/gi,
    description: "sqrt(252) with crypto assets (should be sqrt(365))",
    severity: "CRITICAL",
    fix_hint: "Crypto trades 24/7/365. Use sqrt(365) for annualization",
  },
  {
    regex: /(btc|eth|crypto|binance|usdt)[^#\n]*np\.sqrt\s*\(\s*252\s*\)/gi,
    description: "Crypto context with sqrt(252) annualization",
    severity: "CRITICAL",
    fix_hint: "Crypto trades 24/7/365. Use sqrt(365) for annualization",
  },
];

/**
 * Check if content has range bar context indicators.
 * @param {string} content - File content
 * @param {string[]} indicators - Range bar indicators
 * @returns {boolean} True if range bar context detected
 */
export function hasRangeBarContext(content, indicators = DEFAULT_CONFIG.range_bar_indicators) {
  const lowerContent = content.toLowerCase();
  return indicators.some((ind) => lowerContent.includes(ind.toLowerCase()));
}

/**
 * Check if a line has a whitelist comment.
 * @param {string} line - The line to check
 * @param {string[]} whitelistComments - Whitelist comment patterns
 * @returns {boolean} True if whitelisted
 */
export function isWhitelisted(line, whitelistComments) {
  const lowerLine = line.toLowerCase();
  return whitelistComments.some((comment) => lowerLine.includes(comment.toLowerCase()));
}

/**
 * Check if path should be excluded.
 * @param {string} filePath - File path
 * @param {string[]} excludePaths - Patterns to exclude
 * @returns {boolean} True if excluded
 */
export function isExcludedPath(filePath, excludePaths) {
  return excludePaths.some((pattern) => {
    if (pattern.startsWith("*")) {
      return filePath.endsWith(pattern.slice(1));
    }
    return filePath.includes(pattern);
  });
}

/**
 * Detect time-weighted Sharpe issues in content.
 *
 * @param {string} content - File content
 * @param {Object} enabledPatterns - Which pattern categories are enabled
 * @param {string[]} whitelistComments - Comments that whitelist a line
 * @returns {Array} Array of findings with line, pattern, severity, fix_hint
 */
export function detectSharpeIssues(content, enabledPatterns, whitelistComments) {
  const findings = [];
  const lines = content.split("\n");
  const hasRangeBars = hasRangeBarContext(content);

  lines.forEach((line, idx) => {
    // Skip whitelisted lines
    if (isWhitelisted(line, whitelistComments)) {
      return;
    }

    // Check simple bar Sharpe patterns
    if (enabledPatterns.simple_bar_sharpe) {
      for (const pattern of SIMPLE_BAR_SHARPE_PATTERNS) {
        pattern.regex.lastIndex = 0;
        if (pattern.regex.test(line)) {
          // CRITICAL patterns always trigger, HIGH only in range bar context
          if (pattern.severity === "CRITICAL" || hasRangeBars) {
            findings.push({
              line: idx + 1,
              content: line.trim().slice(0, 80),
              description: pattern.description,
              severity: pattern.severity,
              fix_hint: pattern.fix_hint,
            });
          }
        }
      }
    }

    // Check missing duration patterns (only in range bar context)
    if (enabledPatterns.missing_duration_pipeline && hasRangeBars) {
      for (const pattern of MISSING_DURATION_PATTERNS) {
        pattern.regex.lastIndex = 0;
        if (pattern.regex.test(line)) {
          findings.push({
            line: idx + 1,
            content: line.trim().slice(0, 80),
            description: pattern.description,
            severity: pattern.severity,
            fix_hint: pattern.fix_hint,
          });
        }
      }
    }

    // Check wrong annualization patterns
    if (enabledPatterns.wrong_crypto_annualization) {
      for (const pattern of WRONG_ANNUALIZATION_PATTERNS) {
        pattern.regex.lastIndex = 0;
        if (pattern.regex.test(line)) {
          findings.push({
            line: idx + 1,
            content: line.trim().slice(0, 80),
            description: pattern.description,
            severity: pattern.severity,
            fix_hint: pattern.fix_hint,
          });
        }
      }
    }
  });

  return findings;
}

/**
 * Format findings for user display.
 * @param {Array} findings - Array of findings
 * @returns {string} Formatted string
 */
export function formatFindings(findings) {
  if (findings.length === 0) return "";

  const critical = findings.filter((f) => f.severity === "CRITICAL");
  const high = findings.filter((f) => f.severity === "HIGH");

  let output = "";

  if (critical.length > 0) {
    output += "CRITICAL ISSUES:\n";
    for (const f of critical) {
      output += `  Line ${f.line}: ${f.description}\n`;
      output += `    Code: ${f.content}\n`;
      output += `    Fix: ${f.fix_hint}\n\n`;
    }
  }

  if (high.length > 0) {
    output += "HIGH SEVERITY (range bar context detected):\n";
    for (const f of high) {
      output += `  Line ${f.line}: ${f.description}\n`;
      output += `    Code: ${f.content}\n`;
      output += `    Fix: ${f.fix_hint}\n\n`;
    }
  }

  return output.trim();
}
