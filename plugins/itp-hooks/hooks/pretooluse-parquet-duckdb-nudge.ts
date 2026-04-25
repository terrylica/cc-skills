#!/usr/bin/env bun
/**
 * PreToolUse hook: Parquet → DuckDB Nudge
 *
 * Problem: Parquet is a columnar binary format. Reaching for awk/sed (line-oriented),
 * `pyarrow.parquet.read_table` (Python boilerplate for one-off queries), or pandas
 * for ad-hoc analysis is slower to write and slower to run than DuckDB SQL.
 *
 * Behavior:
 *   - Soft nudge (warn + allow), never deny — preserves binary forensics workflows
 *     and any deliberate non-DuckDB use.
 *   - Detects Bash commands that combine a `.parquet` reference with a known
 *     non-DuckDB analysis tool.
 *   - Emits a stderr reminder with a concrete `duckdb -c` template Claude can adapt.
 *
 * Triggers ONLY when both conditions hold:
 *   1. Command references at least one `.parquet` path/glob.
 *   2. Command uses an analysis tool that's a poor fit for parquet:
 *      - `awk` / `sed` (line-oriented, won't parse columnar binary)
 *      - Inline Python with `read_parquet` / `pq.read_table` / `pyarrow.parquet`
 *      - `parquet-tools` (slower than duckdb for content queries)
 *   3. Command does NOT already invoke `duckdb`.
 *
 * Skips (allows silently):
 *   - `ls`, `du`, `wc -c`, `stat`, `mv`, `cp`, `rm` on parquet files
 *   - File-level forensics (`xxd`, `head -c`, `od`)
 *   - Any command containing `# DUCKDB-SKIP`
 *   - Any command already calling `duckdb`
 */

import { allow, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";

const PARQUET_REF = /\.parquet\b/i;

/** Patterns that indicate content analysis with non-DuckDB tools */
const ANTI_PATTERNS: { name: string; rx: RegExp }[] = [
  { name: "awk", rx: /(?:^|\|\s*|;\s*|&&\s*)awk\s/i },
  { name: "sed", rx: /(?:^|\|\s*|;\s*|&&\s*)sed\s/i },
  { name: "parquet-tools", rx: /\bparquet-tools\b/i },
  { name: "python read_parquet", rx: /\bread_parquet\s*\(/i },
  { name: "python pyarrow.parquet", rx: /\bpyarrow\.parquet\b/i },
  { name: "python pq.read_table", rx: /\bpq\.read_table\s*\(/i },
];

/** Already using duckdb — no nudge needed */
const DUCKDB_PRESENT = /\bduckdb\b/i;

/** Explicit opt-out */
const SKIP_COMMENT = /#\s*DUCKDB-SKIP/i;

/** File-level forensics — legitimate use of binary tools on parquet, don't nudge */
const FORENSICS_PATTERN = /\b(xxd|od|file|hexdump|stat)\b|\bhead\s+-c\b|\btail\s+-c\b/i;

function buildNudge(matchedTool: string, command: string): string {
  // Match path-like substrings only (word chars, /, ., =, *, ?, -).
  // This excludes `(`, `"`, etc. so Python expressions like
  // `pq.read_table("foo.parquet")` yield `foo.parquet`, not the wrapper.
  const allMatches = command.match(/[\w./=*?-]*\.parquet[\w./=*?-]*/gi) || [];
  // Prefer real file refs (with `/`, `*`, `=`, or `?`) over module names.
  const filey =
    allMatches.find((m) => /[/*=?]/.test(m)) ||
    allMatches.find((m) => m.toLowerCase() !== "pyarrow.parquet");
  const samplePath = filey || "data/year=*/week=*.parquet";

  return [
    "💡 Parquet → DuckDB nudge:",
    `   This command uses ${matchedTool} on a Parquet file. Parquet is columnar binary —`,
    "   DuckDB will be faster to write AND faster to run for content analysis.",
    "",
    "   Example:",
    `     duckdb -c "SELECT * FROM read_parquet('${samplePath}', hive_partitioning=1) LIMIT 10"`,
    "",
    "   Allowed to proceed (this is a preference, not a safety rule).",
    "   Escape hatch: append `# DUCKDB-SKIP` to the command to silence this nudge.",
  ].join("\n");
}

async function main() {
  const input = await parseStdinOrAllow("PARQUET-DUCKDB-NUDGE");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;

  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";

  // Skip if not a parquet-related command
  if (!PARQUET_REF.test(command)) {
    allow();
    return;
  }

  // Skip if already using duckdb
  if (DUCKDB_PRESENT.test(command)) {
    allow();
    return;
  }

  // Skip if explicit opt-out
  if (SKIP_COMMENT.test(command)) {
    allow();
    return;
  }

  // Skip if it's binary forensics (xxd, od, head -c, etc.)
  if (FORENSICS_PATTERN.test(command)) {
    allow();
    return;
  }

  // Find the first matching anti-pattern
  const matched = ANTI_PATTERNS.find(({ rx }) => rx.test(command));
  if (!matched) {
    allow();
    return;
  }

  // Soft nudge: warn but allow
  console.warn(buildNudge(matched.name, command));
  allow();
}

main().catch((err) => {
  trackHookError(
    "pretooluse-parquet-duckdb-nudge",
    err instanceof Error ? err.message : String(err),
  );
  allow();
});
