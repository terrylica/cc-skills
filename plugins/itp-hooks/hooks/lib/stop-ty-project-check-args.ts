/**
 * Argument vector for the Stop-hook project-wide `ty check`.
 *
 * Deliberately passes NO `--python-version`. ty's own resolution already implements
 * the fleet policy "Python 3.14 default — repo pin wins": a `ty.toml` /
 * `[tool.ty.environment] python-version`, then `project.requires-python`, then the
 * active environment, and only then ty's default (3.14). A command-line flag takes
 * precedence over all of that, so forcing one would override the repository's pin
 * (issue #157). Re-implementing the detection here would be a second, weaker copy
 * of logic ty already owns.
 */
export const TY_PROJECT_CHECK_ARGS: readonly string[] = [
  "ty",
  "check",
  ".",
  "--output-format",
  "concise",
  "--exit-zero",
];
