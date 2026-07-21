#!/usr/bin/env bun
/**
 * Pure detection logic for the release-notes extensiveness guard.
 *
 * Policy (operator directive 2026-07-21): every semantic-release release — in
 * ANY repo, for ANY version bump — must ship extensive, humanly-readable
 * explanations in BOTH paragraph (narrative "why") AND point form (a bullet
 * summary). Terse commit-dump releases like opendeviationbar-py v13.79.0 (a bare
 * `Bug Fixes` / `Features` one-liner list) are the failure mode this guard
 * blocks.
 *
 * The guard hard-blocks at the release/tag interception points, picking the
 * strongest MEASURABLE criterion at each:
 *
 *   1. `gh release create` / `gh release edit` — measure the inline notes text
 *      (`--notes` / `-n` / `--notes-file` / `-F`). Must contain both a narrative
 *      paragraph AND a point-form list.
 *   2. `git tag -a/-s/-m/-F <semver>` — measure the annotated-tag message. Same
 *      bar.
 *   3. semantic-release (`semantic-release`, `npx/bunx semantic-release`, and
 *      `mise run release[:*]` wrappers) — notes are DERIVED from commit bodies,
 *      so inspect the Conventional-Commit bodies of releasable commits since the
 *      last tag. This enforces the "rich commit bodies" source exactly when they
 *      are about to become immutable release notes.
 *
 * This module is PURE (the only IO is an injectable git runner used by
 * `inspectReleasableCommitBodies`, which defaults to a real `git` spawn but is
 * overridable in tests). The stdin/stdout wrapper lives in
 * pretooluse-release-notes-extensiveness-guard.ts.
 *
 * Doctrine SSoT: ~/.claude/release-notes-doctrine-CLAUDE.md
 * ADR: /docs/adr/2026-07-21-release-notes-extensiveness-guard.md
 * Spoke: plugins/itp-hooks/docs/release-notes-extensiveness-guard.md
 */

// ────────────────────────────────────────────────────────────────────────
//  Tunable thresholds (named exports so operators can adjust after real use)
// ────────────────────────────────────────────────────────────────────────

/** A narrative paragraph must reach this many characters of prose. */
export const NARRATIVE_MIN_CHARS = 240;
/** …and contain at least this many sentence terminators (`.`/`!`/`?`). */
export const NARRATIVE_MIN_SENTENCES = 3;
/** A release body must carry at least this many point-form bullet items. */
export const POINT_FORM_MIN_BULLETS = 4;

/** Commit-body path: aggregate body chars across releasable commits. */
export const COMMIT_AGGREGATE_MIN_CHARS = 400;
/** …and at least one releasable commit must have a body paragraph this long. */
export const COMMIT_RICH_PARAGRAPH_MIN_CHARS = 160;
/** A releasable commit whose body is shorter than this is reported as "thin". */
export const COMMIT_THIN_BODY_CHARS = 160;

/** Doctrine link surfaced in every deny message. */
export const DOCTRINE_DOC = "~/.claude/release-notes-doctrine-CLAUDE.md";

// ────────────────────────────────────────────────────────────────────────
//  Command classification
// ────────────────────────────────────────────────────────────────────────

export type ReleaseKind = "gh-release-notes" | "git-tag-message" | "semantic-release";

export interface ReleaseCommandClassification {
  /** True when a release/tag-publishing command was detected. */
  isRelease: boolean;
  kind?: ReleaseKind;
  /** The offending segment, trimmed (for the deny message). */
  segment?: string;
  /** Concrete inline notes/message text, if it could be extracted verbatim. */
  notesText?: string;
  /** Literal path from `--notes-file`/`-F` — the wrapper reads + measures it. */
  notesFile?: string;
  /**
   * True when the command DID pass notes, but via an unresolvable expression
   * (`$(...)`, backticks, `$VAR`) — we cannot prove thinness → wrapper allows.
   */
  notesUnmeasurable?: boolean;
  /** True when a gh release command carried NO notes body at all → block. */
  notesAbsent?: boolean;
}

/** Values we cannot statically resolve (command substitution / variables). */
function isUnmeasurableValue(raw: string): boolean {
  return /\$\(|`|\$\{?[A-Za-z_]/.test(raw);
}

/**
 * Extract a flag value from a raw segment, honoring `=`, whitespace, and single
 * or double quotes. Naive on nested/escaped quotes (fail-open by design).
 * Returns `{ present: true }` with no `value` for a bare/flag-only match.
 */
function extractFlagValue(
  segment: string,
  flags: string[],
): { present: boolean; value?: string } {
  for (const flag of flags) {
    const f = flag.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const valued = new RegExp(`(?:^|\\s)${f}(?:=|\\s+)(?:"([^"]*)"|'([^']*)'|(\\S+))`, "s");
    const m = segment.match(valued);
    if (m) return { present: true, value: m[1] ?? m[2] ?? m[3] ?? "" };
    const bare = new RegExp(`(?:^|\\s)${f}(?=\\s|$)`);
    if (bare.test(segment)) return { present: true };
  }
  return { present: false };
}

/** Collect ALL `-m <msg>` occurrences (git tag concatenates them by blank line). */
function extractAllMessageFlags(segment: string): string[] {
  const re = /(?:^|\s)(?:-m|--message)(?:=|\s+)(?:"([^"]*)"|'([^']*)'|(\S+))/gs;
  return Array.from(segment.matchAll(re), (m) => m[1] ?? m[2] ?? m[3] ?? "");
}

/** First line of the command, trimmed — used for the deny-message preview. */
function firstLine(command: string): string {
  const nl = command.indexOf("\n");
  return (nl === -1 ? command : command.slice(0, nl)).trim();
}

/** Is this command a semantic-release invocation (direct or via a wrapper)? */
function isSemanticReleaseCommand(command: string): boolean {
  const lower = command.toLowerCase();
  if (/\bsemantic-release\b/.test(lower)) return true;
  // mise release wrappers: `mise run release`, `mise run release:full`, `mise release`
  if (/\bmise\s+(?:run\s+)?release(?::[\w-]+)?\b/.test(lower)) return true;
  // direct task-file execution
  if (/\.mise\/tasks\/release\b/.test(lower)) return true;
  return false;
}

/** A semver token anywhere in a string (unanchored — command may be compound). */
const SEMVER_ANYWHERE = /\bv?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\b/;

function classifyGhRelease(command: string): ReleaseCommandClassification {
  const segment = firstLine(command);
  // Notes may legitimately come from the tag message → measured on the tag path.
  if (extractFlagValue(command, ["--notes-from-tag"]).present) {
    return { isRelease: false };
  }
  const file = extractFlagValue(command, ["--notes-file", "-F"]);
  if (file.present && file.value) {
    if (isUnmeasurableValue(file.value)) {
      return { isRelease: true, kind: "gh-release-notes", segment, notesUnmeasurable: true };
    }
    return { isRelease: true, kind: "gh-release-notes", segment, notesFile: file.value };
  }
  const notes = extractFlagValue(command, ["--notes", "-n"]);
  if (notes.present) {
    if (notes.value === undefined || isUnmeasurableValue(notes.value)) {
      return { isRelease: true, kind: "gh-release-notes", segment, notesUnmeasurable: true };
    }
    return { isRelease: true, kind: "gh-release-notes", segment, notesText: notes.value };
  }
  // No --notes / --notes-file / --notes-from-tag → no body at all.
  // `--generate-notes` alone counts as absent (GitHub auto-list, no narrative).
  return { isRelease: true, kind: "gh-release-notes", segment, notesAbsent: true };
}

function classifyGitTag(command: string, afterTag: string): ReleaseCommandClassification {
  const segment = firstLine(command);
  const annotated =
    /(?:^|\s)(?:-a|-s|--annotate|--sign)(?=\s|$)/.test(afterTag) ||
    /(?:^|\s)(?:-m|--message|-F|--file)(?:=|\s)/.test(afterTag);
  if (!annotated) return { isRelease: false }; // lightweight/list/delete tag → not a release note
  if (!SEMVER_ANYWHERE.test(afterTag)) return { isRelease: false }; // non-semver tag → not a release

  const file = extractFlagValue(afterTag, ["-F", "--file"]);
  if (file.present && file.value) {
    if (isUnmeasurableValue(file.value)) {
      return { isRelease: true, kind: "git-tag-message", segment, notesUnmeasurable: true };
    }
    return { isRelease: true, kind: "git-tag-message", segment, notesFile: file.value };
  }
  const messages = extractAllMessageFlags(afterTag);
  if (messages.length > 0) {
    if (messages.some(isUnmeasurableValue)) {
      return { isRelease: true, kind: "git-tag-message", segment, notesUnmeasurable: true };
    }
    return { isRelease: true, kind: "git-tag-message", segment, notesText: messages.join("\n\n") };
  }
  // Annotated (-a/-s) but message via editor — cannot measure → allow.
  return { isRelease: false };
}

/**
 * Classify a full (possibly compound / multi-line) command. Detection runs over
 * the WHOLE command (not per-newline segments) so multi-line `--notes "…"` and
 * `-m "…"` bodies are not fragmented.
 */
export function classifyReleaseCommand(command: string): ReleaseCommandClassification {
  if (isSemanticReleaseCommand(command)) {
    return { isRelease: true, kind: "semantic-release", segment: firstLine(command) };
  }
  if (/\bgh\s+release\s+(?:create|edit)\b/.test(command)) {
    return classifyGhRelease(command);
  }
  const tagMatch = command.match(/\bgit\s+tag\b([\s\S]*)$/);
  if (tagMatch) {
    return classifyGitTag(command, tagMatch[1]);
  }
  return { isRelease: false };
}

// ────────────────────────────────────────────────────────────────────────
//  Notes-text extensiveness measurement
// ────────────────────────────────────────────────────────────────────────

export interface ExtensivenessMeasurement {
  ok: boolean;
  hasNarrative: boolean;
  hasPointForm: boolean;
  bulletCount: number;
  narrativeChars: number;
  reasons: string[];
}

const BULLET_LINE = /^\s*(?:[-*+]|\d+[.)])\s+\S/;
const HEADING_LINE = /^\s*#{1,6}\s/;
const LINK_REF_ONLY = /^\s*\[[^\]]+\]:\s/;

/**
 * Measure whether a release-notes body carries BOTH a narrative paragraph and a
 * point-form list. A "narrative paragraph" is a contiguous run of non-bullet,
 * non-heading prose reaching NARRATIVE_MIN_CHARS with ≥NARRATIVE_MIN_SENTENCES
 * sentence terminators.
 */
export function measureNotesExtensiveness(text: string): ExtensivenessMeasurement {
  const reasons: string[] = [];
  const lines = (text ?? "").replace(/\r\n?/g, "\n").split("\n");

  let bulletCount = 0;
  let bestNarrativeChars = 0;
  let bestNarrativeSentences = 0;
  let paraChars = 0;
  let paraSentences = 0;

  const flushParagraph = () => {
    if (paraChars > bestNarrativeChars) {
      bestNarrativeChars = paraChars;
      bestNarrativeSentences = paraSentences;
    }
    paraChars = 0;
    paraSentences = 0;
  };

  for (const line of lines) {
    const trimmed = line.trim();
    if (BULLET_LINE.test(line)) {
      bulletCount++;
      flushParagraph();
      continue;
    }
    if (trimmed === "" || HEADING_LINE.test(line) || LINK_REF_ONLY.test(line)) {
      flushParagraph();
      continue;
    }
    // Prose line: accumulate into the current paragraph.
    paraChars += trimmed.length + 1;
    paraSentences += (trimmed.match(/[.!?](?:\s|$)/g) ?? []).length;
  }
  flushParagraph();

  const hasNarrative =
    bestNarrativeChars >= NARRATIVE_MIN_CHARS && bestNarrativeSentences >= NARRATIVE_MIN_SENTENCES;
  const hasPointForm = bulletCount >= POINT_FORM_MIN_BULLETS;

  if (!hasNarrative) {
    reasons.push(
      `no narrative paragraph (needs ≥${NARRATIVE_MIN_CHARS} chars & ≥${NARRATIVE_MIN_SENTENCES} sentences of prose; longest run = ${bestNarrativeChars} chars / ${bestNarrativeSentences} sentences)`,
    );
  }
  if (!hasPointForm) {
    reasons.push(
      `no point-form list (needs ≥${POINT_FORM_MIN_BULLETS} bullet items; found ${bulletCount})`,
    );
  }

  return {
    ok: hasNarrative && hasPointForm,
    hasNarrative,
    hasPointForm,
    bulletCount,
    narrativeChars: bestNarrativeChars,
    reasons,
  };
}

// ────────────────────────────────────────────────────────────────────────
//  Commit-body inspection (semantic-release path)
// ────────────────────────────────────────────────────────────────────────

export interface CommitRecord {
  hash: string;
  subject: string;
  body: string;
}

export interface CommitBodyInspection {
  ok: boolean;
  releasableCount: number;
  totalBodyChars: number;
  richestBodyChars: number;
  thinCommits: { hash: string; subject: string }[];
  reasons: string[];
}

const RELEASABLE_TYPE = /^(?:feat|fix|perf)(?:\([^)]*\))?!?:/i;
const BREAKING_FOOTER = /(^|\n)BREAKING[ -]CHANGE:/;

/** Parse `git log --format=%H%x1f%s%x1f%b%x1e` output into records. */
export function parseGitLogRecords(raw: string): CommitRecord[] {
  return raw
    .split("\x1e")
    .map((r) => r.trim())
    .filter((r) => r.length > 0)
    .map((r) => {
      const [hash = "", subject = "", body = ""] = r.split("\x1f");
      return { hash: hash.trim(), subject: subject.trim(), body: body.trim() };
    });
}

/** Pure analysis of commit records against the richness bar. */
export function analyzeCommitBodies(records: CommitRecord[]): CommitBodyInspection {
  const reasons: string[] = [];
  const releasable = records.filter(
    (c) => RELEASABLE_TYPE.test(c.subject) || BREAKING_FOOTER.test(`\n${c.body}`),
  );

  // Nothing releasable → semantic-release would no-op; nothing to enforce.
  if (releasable.length === 0) {
    return {
      ok: true,
      releasableCount: 0,
      totalBodyChars: 0,
      richestBodyChars: 0,
      thinCommits: [],
      reasons: [],
    };
  }

  let total = 0;
  let richest = 0;
  const thin: { hash: string; subject: string }[] = [];
  for (const c of releasable) {
    const len = c.body.trim().length;
    total += len;
    richest = Math.max(richest, len);
    if (len < COMMIT_THIN_BODY_CHARS) {
      thin.push({ hash: c.hash.slice(0, 8), subject: c.subject });
    }
  }

  const ok = total >= COMMIT_AGGREGATE_MIN_CHARS && richest >= COMMIT_RICH_PARAGRAPH_MIN_CHARS;
  if (total < COMMIT_AGGREGATE_MIN_CHARS) {
    reasons.push(
      `releasable commit bodies total ${total} chars (need ≥${COMMIT_AGGREGATE_MIN_CHARS})`,
    );
  }
  if (richest < COMMIT_RICH_PARAGRAPH_MIN_CHARS) {
    reasons.push(
      `no releasable commit has a substantive body paragraph (longest = ${richest} chars, need ≥${COMMIT_RICH_PARAGRAPH_MIN_CHARS})`,
    );
  }

  return {
    ok,
    releasableCount: releasable.length,
    totalBodyChars: total,
    richestBodyChars: richest,
    thinCommits: thin,
    reasons,
  };
}

export type GitRunner = (args: string[]) => { ok: boolean; stdout: string };

/** Default git runner: spawn `git` in `cwd`. Fail-open (`ok:false`) on any error. */
function defaultGitRunner(cwd: string): GitRunner {
  return (args) => {
    try {
      const proc = Bun.spawnSync(["git", ...args], { cwd, stderr: "ignore" });
      return { ok: proc.exitCode === 0, stdout: proc.stdout.toString() };
    } catch {
      return { ok: false, stdout: "" };
    }
  };
}

/**
 * Inspect releasable commit bodies since the last tag. IO wrapper around the
 * pure analyzer. Injectable `run` for tests; defaults to a real git spawn.
 * Fail-open: any git failure → `ok:true` (never block on tooling error).
 */
export function inspectReleasableCommitBodies(cwd: string, run?: GitRunner): CommitBodyInspection {
  const git = run ?? defaultGitRunner(cwd);
  const lastTag = git(["describe", "--tags", "--abbrev=0"]);
  const range = lastTag.ok && lastTag.stdout.trim() ? `${lastTag.stdout.trim()}..HEAD` : "HEAD";
  const log = git(["log", range, "--no-merges", "--format=%H%x1f%s%x1f%b%x1e"]);
  if (!log.ok) {
    return {
      ok: true,
      releasableCount: 0,
      totalBodyChars: 0,
      richestBodyChars: 0,
      thinCommits: [],
      reasons: [],
    };
  }
  return analyzeCommitBodies(parseGitLogRecords(log.stdout));
}

// ────────────────────────────────────────────────────────────────────────
//  Deny-message builders
// ────────────────────────────────────────────────────────────────────────

const HEADER = "[RELEASE-NOTES-GUARD] Release blocked — notes must be extensive and human-readable.";

const FORMAT_BLOCK = `REQUIRED (every release, any bump):
  • A NARRATIVE PARAGRAPH — plain-English "why": the problem, the change, the impact.
  • A POINT-FORM LIST — ≥${POINT_FORM_MIN_BULLETS} bullets summarizing what changed (link each PR/issue).
  • Keep-a-Changelog categories where they fit (Added / Changed / Deprecated /
    Removed / Fixed / Security) + issue/PR links (Common Changelog audit trail).

Doctrine (mandatory format + workflow): ${DOCTRINE_DOC}

Escape hatch (genuinely nothing to narrate — pure dep/chore bump):
  • add  RELEASE-NOTES-OK: <≥10-char reason>  to the command`;

export function buildNotesDenyMessage(
  segment: string,
  measurement: ExtensivenessMeasurement,
): string {
  const preview = segment.length > 120 ? segment.slice(0, 117) + "..." : segment;
  return `${HEADER}

BLOCKED: ${preview}
FAILED: ${measurement.reasons.join("; ")}

${FORMAT_BLOCK}`;
}

export function buildNotesAbsentDenyMessage(segment: string): string {
  const preview = segment.length > 120 ? segment.slice(0, 117) + "..." : segment;
  return `${HEADER}

BLOCKED: ${preview}
FAILED: no release notes supplied (no --notes / --notes-file, or --generate-notes only)

Provide extensive notes via  --notes-file <path>  pointing at a body that has:
${FORMAT_BLOCK}`;
}

export function buildCommitDenyMessage(
  segment: string,
  inspection: CommitBodyInspection,
): string {
  const preview = segment.length > 120 ? segment.slice(0, 117) + "..." : segment;
  const thin =
    inspection.thinCommits.length > 0
      ? `\nThin commits (enrich their bodies via amend/rebase, or curate the GitHub Release body after):\n` +
        inspection.thinCommits
          .slice(0, 10)
          .map((c) => `  • ${c.hash}  ${c.subject}`)
          .join("\n")
      : "";
  return `${HEADER}

BLOCKED: ${preview}
semantic-release derives notes from commit BODIES — and yours are thin.
FAILED: ${inspection.reasons.join("; ")}${thin}

Fix by writing extensive multi-paragraph Conventional-Commit bodies (the notes
source), then optionally augment the published GitHub Release body.
${FORMAT_BLOCK}`;
}
