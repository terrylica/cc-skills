#!/usr/bin/env bun
/**
 * Process Storm Pattern Definitions
 *
 * Patterns for detecting dangerous subprocess spawning that can cause:
 * - Fork bombs (exponential process growth)
 * - Credential helper recursion (gh auth storms)
 * - Shell initialization storms (mise in .zshenv)
 * - Unbounded process spawning (subprocess in loops)
 *
 * Critical for macOS where cgroups don't exist for runtime containment.
 *
 * ADR: /docs/adr/2026-01-13-process-storm-prevention.md
 */

/**
 * Pattern categories with severity levels.
 * CRITICAL = block unconditionally
 * HIGH = block with escape hatch available
 */
export const PATTERNS = {
  // CRITICAL: Classic fork bomb patterns - always block
  fork_bomb: {
    severity: "critical",
    description: "Fork bomb patterns that spawn unlimited processes",
    patterns: [
      // :(){ :|:& };: and variants
      /:\s*\(\s*\)\s*\{\s*:[^}]*\|[^}]*:[^}]*&[^}]*\}/,
      // .() { .|.& }; .
      /\.\s*\(\s*\)\s*\{\s*\.[^}]*\|[^}]*\.[^}]*&[^}]*\}/,
      // Generic: function calling itself with pipe and background
      // Uses word boundaries (\b) to prevent partial function name matches
      // (fixes false positive where 's' from 'check_status' matched 'grep s')
      /\b(\w+)\s*\(\s*\)\s*\{[^}]*\b\1\b[^}]*\|[^}]*\b\1\b[^}]*&[^}]*\}/,
      // while true; do ... & done (unbounded background spawn)
      /while\s+(true|:|\[\s*1\s*\])\s*;\s*do[^d]*[^o]*[^n]*[^e]*&[^d]*done/i,
      // Infinite for loop with background spawn
      /for\s*\(\s*;\s*;\s*\)[^{]*\{[^}]*&[^}]*\}/,
    ],
  },

  // CRITICAL: gh CLI credential helper recursion patterns # PROCESS-STORM-OK
  // Only block subshell patterns that trigger credential helper loops.
  // Direct gh commands (gh api, gh issue, gh pr) are safe from Claude Code
  // Bash tool — recursion only happens inside hooks/credential helpers.
  gh_recursion: {
    severity: "critical",
    description: "gh CLI subshell patterns that cause credential helper recursion",
    patterns: [
      // GH_TOKEN=$(gh auth ...) subshell pattern (credential helper recursion)
      /GH_TOKEN\s*=\s*\$\(\s*gh\s+auth/i,
      // GITHUB_TOKEN=$(gh auth ...) subshell pattern
      /GITHUB_TOKEN\s*=\s*\$\(\s*gh\s+auth/i,
      // $(gh auth token) in any subshell context
      /\$\(\s*gh\s+auth\s+(token|status)/i,
    ],
  },

  // CRITICAL: Git credential helper recursion
  credential_storm: {
    severity: "critical",
    description: "Git credential patterns that cause recursion",
    patterns: [
      // git credential fill in loops
      /while[^;]*;\s*do[^d]*git\s+credential\s+fill/i,
      // credential.helper with gh auth (not git-credential)
      /credential\.helper.*gh\s+auth(?!.*git-credential)/i,
      // GIT_ASKPASS pointing to gh
      /GIT_ASKPASS.*gh\s+auth/i,
    ],
  },

  // HIGH: mise activation in wrong contexts
  mise_fork: {
    severity: "high",
    description: "mise activation patterns that cause fork storms in .zshenv",
    patterns: [
      // eval "$(mise activate ...)" - spawns subprocesses
      /eval\s+["']\$\(mise\s+activate/i,
      // source <(mise activate) - spawns subprocesses
      /source\s+<\(mise\s+activate/i,
      // mise activate --shims (conflicts with PATH shims)
      /mise\s+activate\s+[^|&;]*--shims/i,
    ],
  },

  // HIGH: Python subprocess patterns without guards
  python_storm: {
    severity: "high",
    description: "Python subprocess patterns prone to storms",
    patterns: [
      // subprocess with shell=True
      /subprocess\.(run|call|Popen|check_output)\s*\([^)]*shell\s*=\s*True/i,
      // os.system() calls
      /os\.system\s*\(/,
      // os.popen() calls
      /os\.popen\s*\(/,
      // subprocess in while True loop
      /while\s+True\s*:[^#\n]*(subprocess\.(Popen|run|call)|os\.(system|popen))/i,
    ],
  },

  // HIGH: Node.js child_process patterns in loops
  node_storm: {
    severity: "high",
    description: "Node.js child_process patterns in loops",
    patterns: [
      // child_process.exec in while/for loop
      /while\s*\([^)]*\)[^{]*\{[^}]*(child_process\.)?exec\s*\(/i,
      /for\s*\([^)]*\)[^{]*\{[^}]*(child_process\.)?exec\s*\(/i,
      // spawn in setInterval with low delay
      /setInterval\s*\([^,]*(exec|spawn|fork)[^,]*,\s*[0-9]{1,3}\s*\)/i,
      // Recursive function with spawn
      /function\s+(\w+)[^{]*\{[^}]*(spawn|exec|fork)[^}]*\1\s*\(\s*\)/i,
    ],
  },
};

/**
 * Escape hatch comment pattern.
 * Adding this comment to a line or file allows the pattern to pass.
 */
export const ESCAPE_HATCH = /#\s*PROCESS-STORM-OK/i;

/**
 * Default configuration for process storm guard.
 */
export const DEFAULT_CONFIG = {
  enabled: true,
  categories: {
    fork_bomb: true,
    gh_recursion: true,
    credential_storm: true,
    mise_fork: true,
    python_storm: true,
    node_storm: true,
  },
  escape_hatch_comment: "# PROCESS-STORM-OK",
};

/**
 * Finding type for detected process storm patterns.
 * @typedef {Object} StormFinding
 * @property {string} category - Pattern category name
 * @property {string} severity - "critical" or "high"
 * @property {string} match - Matched text (truncated)
 * @property {string} description - Category description
 */

/**
 * Detect process storm patterns in content.
 *
 * @param {string} content - Content to scan (command or file content)
 * @param {Object} enabledCategories - Object with category names as keys, boolean values
 * @returns {StormFinding[]} Array of findings
 */
export function detectPatterns(content, enabledCategories = DEFAULT_CONFIG.categories) {
  const findings = [];

  // Check escape hatch first
  if (ESCAPE_HATCH.test(content)) {
    return [];
  }

  for (const [category, config] of Object.entries(PATTERNS)) {
    // Skip disabled categories
    if (!enabledCategories[category]) continue;

    for (const pattern of config.patterns) {
      const match = content.match(pattern);
      if (match) {
        findings.push({
          category,
          severity: config.severity,
          match: match[0].substring(0, 50), // Truncate for readability
          description: config.description,
        });
        break; // One finding per category is enough
      }
    }
  }

  return findings;
}

/**
 * Format findings for display in permission dialog.
 *
 * @param {StormFinding[]} findings - Array of findings
 * @returns {string} Formatted string for display
 */
export function formatFindings(findings) {
  const critical = findings.filter((f) => f.severity === "critical");
  const high = findings.filter((f) => f.severity === "high");

  const lines = ["[PROCESS STORM GUARD] Blocked: Detected patterns that may cause process storms.\n"];

  if (critical.length > 0) {
    lines.push("CRITICAL (blocked unconditionally):");
    for (const f of critical) {
      lines.push(`  - ${f.category}: '${f.match}'`);
      lines.push(`    ${f.description}`);
    }
    lines.push("");
  }

  if (high.length > 0) {
    lines.push("HIGH (blocked, escape hatch available):");
    for (const f of high) {
      lines.push(`  - ${f.category}: '${f.match}'`);
    }
    lines.push("");
  }

  lines.push("Escape hatch: Add '# PROCESS-STORM-OK' comment if intentional.");
  lines.push("Reference: CLAUDE.md Process Storm Prevention section");

  return lines.join("\n");
}
