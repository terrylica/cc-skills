/**
 * Argument vectors for both ty checks: the Stop-hook project-wide check and the
 * PostToolUse per-file check. This file is the single source of truth for ty argv.
 *
 * Neither passes `--python-version`. ty's own resolution already implements the
 * fleet policy "Python 3.14 default — repo pin wins": a `ty.toml` /
 * `[tool.ty.environment] python-version`, then `project.requires-python`, then the
 * active environment, and only then ty's default (3.14). A command-line flag takes
 * precedence over all of that, so forcing one would override the repository's pin
 * (issue #157). Re-implementing the detection here would be a second, weaker copy
 * of logic ty already owns. Both checks inherit the session's working directory, so
 * ty discovers the same project configuration for each.
 */

/** Flags common to both checks. Deliberately contains no Python-version flag. */
const TY_SHARED_OUTPUT_ARGS: readonly string[] = ["--output-format", "concise"];

/** Stop hook: whole project; `--exit-zero` so diagnostics never fail the hook. */
export const TY_PROJECT_CHECK_ARGS: readonly string[] = [
  "ty",
  "check",
  ".",
  ...TY_SHARED_OUTPUT_ARGS,
  "--exit-zero",
];

/**
 * PostToolUse hook: one edited file. No `--exit-zero`: the per-file classifier reads
 * ty's exit code (0 clean, 1 diagnostics, 2 configuration error, 101 internal bug).
 */
export function tyPerFileCheckArgs(filePath: string): string[] {
  return ["ty", "check", filePath, ...TY_SHARED_OUTPUT_ARGS];
}
