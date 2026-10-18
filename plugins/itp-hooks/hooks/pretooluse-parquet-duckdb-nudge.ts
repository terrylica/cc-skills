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
 *   - Emits a reminder with a concrete `duckdb -c` template Claude can adapt, ONCE per session.
 *
 * Triggers ONLY when both conditions hold:
 *   1. Command references at least one `.parquet` path/glob.
 *   2. Command uses an analysis tool that's a poor fit for parquet:
 *      - `awk` / `sed` given a `.parquet` file as an operand (line-oriented, won't parse columnar binary)
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

import { allow, output, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName } from "./lib/posttooluse-subhook-async-helpers-iter95.ts";
import { walkShellInvocations } from "./lib/shell-command-invocation-walker.ts";

// Tight match: `.parquet` must be followed by a path-terminator (whitespace,
// quote, end of string, common punctuation). Avoids false positives on
// natural-language tokens like `pyarrow.parquet.read_schema` where `.parquet`
// is followed by another `.` (it's a Python module path, not a file path).
const PARQUET_REF = /\.parquet(?=$|[\s'"`,;)\]}>])/i;

/**
 * Patterns that indicate content analysis with non-DuckDB tools.
 *
 * awk and sed are NOT here any more: they are matched as invocations, and only when one of their
 * own operands is a Parquet file (see `lineToolOnParquet`). The regexes they replaced fired on any
 * command that mentioned `.parquet` anywhere and ran sed or awk anywhere, e.g. `sed -n 1,80p
 * scripts/load.py` in a command that also listed a Parquet directory (2026-10-17).
 */
const ANTI_PATTERNS: { name: string; rx: RegExp }[] = [
  { name: "parquet-tools", rx: /\bparquet-tools\b/i },
  { name: "python read_parquet", rx: /\bread_parquet\s*\(/i },
  { name: "python pyarrow.parquet", rx: /\bpyarrow\.parquet\b/i },
  { name: "python pq.read_table", rx: /\bpq\.read_table\s*\(/i },
];

/** Already using duckdb — no nudge needed */
const DUCKDB_PRESENT = /\bduckdb\b/i;

/** Explicit opt-out */
const SKIP_COMMENT = /#\s*DUCKDB-SKIP/i;

/** File-level forensics — legitimate use of binary tools on parquet, don't nudge.
 *  Scoped to actual command invocations: keyword at start of a shell statement
 *  (or after `|`/`;`/`&&`) followed by whitespace and an argument.
 *  Avoids false positives from `file.parquet` matching `\bfile\b`. */
const FORENSICS_PATTERN =
  /(?:^|\|\s*|;\s*|&&\s*)(xxd|od|file|hexdump|stat)\s+\S|\bhead\s+-c\b|\btail\s+-c\b/i;

const LINE_TOOLS: ReadonlySet<string> = new Set(["awk", "gawk", "mawk", "sed", "gsed"]);

/** awk/sed INVOCATION with a Parquet file among its own operands, or null. Exported for tests. */
export function lineToolOnParquet(command: string): string | null {
  let found: string | null = null;
  walkShellInvocations(command, /\b(?:g|m)?awk\b|\bg?sed\b/, (invocation) => {
    if (found !== null || !LINE_TOOLS.has(invocation.program)) return;
    if (invocation.args.some((w) => PARQUET_REF.test(w.value))) found = invocation.program;
  });
  return found;
}

/** The anti-pattern this command uses on Parquet, or null. Exported for tests. */
export function findParquetAntiPattern(command: string): { name: string } | null {
  const lineTool = lineToolOnParquet(command);
  if (lineTool !== null) return { name: lineTool };
  return ANTI_PATTERNS.find(({ rx }) => rx.test(command)) ?? null;
}

/** True the first time in a session; without a session id there is nothing to key on. */
function claimOncePerSessionNudge(sessionId: unknown): boolean {
  if (typeof sessionId !== "string" || sessionId === "") return true;
  return tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName("parquet-duckdb-nudge", sessionId);
}

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

export async function main() {
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
  const matched = findParquetAntiPattern(command);
  if (!matched) {
    allow();
    return;
  }

  // ONCE PER SESSION (2026-10-17). It is a preference, not a safety rule, and repeating the same
  // template on every read_parquet in a session where the agent has already seen it was noise.
  if (!claimOncePerSessionNudge(input.session_id)) {
    allow();
    return;
  }

  // Soft nudge: emit additionalContext (surfaces to Claude as system-reminder)
  // and allow execution. console.warn does NOT propagate to the model when
  // permission is "allow" — only additionalContext does. Same pattern as
  // pretooluse-large-file-read-guard.ts.
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: buildNudge(matched.name, command),
    },
  });
}

// Standalone entry point. The Bash orchestrator (#111) imports `main` and runs it in-process.
if (import.meta.main) void main().catch((err) => {
  trackHookError(
    "pretooluse-parquet-duckdb-nudge",
    err instanceof Error ? err.message : String(err),
  );
  allow();
});
