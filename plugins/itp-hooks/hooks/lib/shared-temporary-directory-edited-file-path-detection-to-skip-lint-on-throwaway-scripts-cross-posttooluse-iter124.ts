/**
 * Shared temporary-directory edited-file-path detection — skip lint/type-check
 * on throwaway scripts (iter-124).
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Why this file exists (operator directive 2026-06-17)
 * ════════════════════════════════════════════════════════════════════════
 *
 * The PostToolUse edit-time linters (ty, tsgo, oxlint, biome, ssot-principles,
 * vale) fire on EVERY Write/Edit of an eligible file — including throwaway
 * scratch scripts an agent drops into a temp directory (`/tmp/foo.py`,
 * `$TMPDIR/scratch.ts`, a `mktemp` workspace). Carefully type-checking and
 * linting a file that exists only to be run once and discarded is wasted
 * wall-clock + wasted Claude context (the diagnostics get injected as
 * additional_context and the agent feels obliged to "fix" a file nobody keeps).
 *
 * This helper is the SINGLE SOURCE OF TRUTH for "is this edited file path
 * inside a temporary scratch directory where linting is wasteful". Every
 * file-path-based PostToolUse lint subhook calls it immediately after its
 * cheap extension filter and returns a noop when it matches.
 *
 * ── What counts as temporary (macOS + Linux) ────────────────────────────
 *
 *   • $TMPDIR                — per-user temp on macOS, e.g.
 *                              /var/folders/xx/.../T/ (realpath: /private/...)
 *   • /tmp, /private/tmp     — classic Unix temp (on macOS /tmp → /private/tmp)
 *   • /var/folders/          — macOS system/user temp root
 *   • /private/var/folders/  — realpath-resolved variant of the above
 *
 * Matching is by path PREFIX on a `/`-delimited boundary so that a legitimate
 * project directory whose name merely starts with "tmp" (e.g. `/repo/tmpl/`)
 * is NOT misclassified.
 *
 * Pure + dependency-free + fail-safe: any unexpected input returns `false`
 * (lint as normal) so a bug here can never silently disable linting for real
 * project files.
 */

/**
 * Static temp-directory prefixes that exist on every macOS / Linux box,
 * independent of the per-process $TMPDIR. Each entry is a directory whose
 * descendants are temporary.
 */
const STATIC_TEMPORARY_DIRECTORY_PREFIXES: readonly string[] = [
  "/tmp",
  "/private/tmp",
  "/var/folders",
  "/private/var/folders",
  "/dev/shm", // Linux tmpfs scratch
];

/** Strip a single trailing slash so prefix comparisons use a clean boundary. */
function stripTrailingSlash(path: string): string {
  return path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path;
}

/**
 * True when `candidate` is `prefix` itself or a path strictly beneath it,
 * matching only on a `/` boundary (so `/var/folders` does NOT match
 * `/var/foldersX/...`).
 */
function pathIsAtOrBeneathDirectoryPrefix(candidate: string, prefix: string): boolean {
  const normalizedPrefix = stripTrailingSlash(prefix);
  if (!normalizedPrefix) return false;
  return candidate === normalizedPrefix || candidate.startsWith(`${normalizedPrefix}/`);
}

/**
 * Return every temp-directory prefix to test against: the static set plus the
 * live `$TMPDIR` (and its `/private`-prefixed realpath twin on macOS, where
 * `$TMPDIR` is reported as `/var/folders/...` but symlink-resolves to
 * `/private/var/folders/...`).
 */
function collectTemporaryDirectoryPrefixesIncludingLiveTmpdir(): string[] {
  const prefixes = [...STATIC_TEMPORARY_DIRECTORY_PREFIXES];
  const envTmpdir = process.env.TMPDIR; // SSoT-OK: reading the live per-process temp dir is the purpose
  if (envTmpdir && envTmpdir.trim() !== "") {
    const normalized = stripTrailingSlash(envTmpdir.trim());
    prefixes.push(normalized);
    if (normalized.startsWith("/var/folders")) {
      prefixes.push(`/private${normalized}`);
    } else if (normalized.startsWith("/private/var/folders")) {
      prefixes.push(normalized.slice("/private".length));
    }
  }
  return prefixes;
}

/**
 * Whether the edited file lives inside a temporary scratch directory where
 * linting/type-checking a throwaway script is a waste of time.
 *
 * Only matches ABSOLUTE paths (temp dirs are always absolute); a relative
 * path returns `false` and lints as normal. Fail-safe: returns `false` for
 * any falsy / non-string input.
 */
export function isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(
  filePath: string | undefined | null,
): boolean {
  if (!filePath || typeof filePath !== "string") return false;
  if (!filePath.startsWith("/")) return false;
  const candidate = stripTrailingSlash(filePath);
  return collectTemporaryDirectoryPrefixesIncludingLiveTmpdir().some((prefix) =>
    pathIsAtOrBeneathDirectoryPrefix(candidate, prefix),
  );
}
