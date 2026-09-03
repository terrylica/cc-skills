#!/usr/bin/env bun
/**
 * Pre-commit PII guard — blocks staged content that contains a forbidden
 * third-party identifier.
 *
 * # Why this exists
 *
 * Client PII reached this PUBLIC repository three times. The instructive
 * detail is not that someone wrote a name down — it is WHERE the name was
 * written each time:
 *
 *   1. a research synthesis using a real client's name as a worked example;
 *   2. a reference document ABOUT redaction, which republished every
 *      identifier it documented redacting;
 *   3. a test fixture that WAS a redaction-mapping table.
 *
 * Two of the three arrived inside content whose own subject was redaction.
 * An author writing that content believes they are documenting, not
 * disclosing, so no amount of "remember not to write names" prevents it.
 * Only a mechanical check on the bytes about to be committed does.
 *
 * Remediation cost a `git filter-repo` rewrite of 3,890 commits and 1,021
 * tags, a force-push, and a GitHub Support request that is still open —
 * because GitHub retains unreachable objects and forks are independent
 * repositories beyond anyone's reach. Prevention is orders of magnitude
 * cheaper than the rewrite, which is why this guard fails the commit rather
 * than warning about it.
 *
 * Do NOT read the rewrite above as this repo's general incident response. It
 * is the IRREVOCABLE-disclosure path. For a leaked CREDENTIAL the opposite
 * applies — rotate, never rewrite — because rotation makes the published bytes
 * inert while a rewrite breaks every consumer for no security gain. The two
 * doctrines sat in this repo contradicting each other with nothing reconciling
 * them until docs/adr/2026-09-03-revocability-determines-the-disclosure-response.md,
 * which is the entry point for deciding which path an incident takes.
 *
 * # Scope
 *
 * Staged content only, at commit time. Full-history scanning is a separate,
 * already-completed job and is deliberately NOT attempted here.
 *
 * Content is read from the STAGED BLOB (`git show :path`), not from the
 * working tree, because the two differ whenever a file is partially staged —
 * and it is the staged bytes that are about to become a commit.
 *
 * File PATHS are scanned as well as file contents. Incident 1's identifier
 * appeared as a surname inside a filename, which a contents-only scan misses.
 *
 * # Reporting policy — why this never prints the matched text
 *
 * This guard reports `file`, `line number`, and a stable `term #N`, and never
 * the matched term or the surrounding line.
 *
 * The reasoning: a pre-commit hook's stdout is one of the most-copied
 * surfaces in the whole workflow. It lands in terminal scrollback, in CI job
 * logs, in `script`/asciinema recordings, in the screenshot someone pastes
 * into an issue asking "why is my commit blocked?", and in this repo's own
 * agent transcripts. A guard that echoes the identifier back has simply moved
 * the leak from the commit into the log — and unlike the commit, nobody
 * rewrites their scrollback. Incident 2 is exactly this failure mode one
 * level up: a document about redaction that reprinted what it redacted. A
 * guard that printed the term would be committing the same error in the same
 * repository, which would be difficult to defend.
 *
 * The term ID is a 1-based index over the non-comment, non-blank lines of the
 * denylist, so the operator resolves it locally with `--explain N` against a
 * file that already sits on their disk. That keeps the identifier in exactly
 * one place instead of two, at the cost of one extra command — a trade worth
 * making, because the operator running `--explain` has chosen to see it,
 * whereas everyone downstream of a log has not.
 *
 * # Matching
 *
 * Case-insensitive, Unicode-aware substring matching. All three properties
 * are load-bearing:
 *
 *   - SUBSTRING, because the real leaks were substrings: an email local-part
 *     inside a longer address, a surname inside a filename. Word-boundary
 *     matching would have missed both.
 *   - CASE-INSENSITIVE via `toLocaleLowerCase()`, which is Unicode-aware,
 *     rather than a byte-wise fold.
 *   - NFC-NORMALIZED on both sides, so a CJK or accented name composed
 *     differently by two editors still matches. A CJK name identifies a
 *     person exactly as well as a Latin one, and an `[a-z]`-shaped pattern
 *     would silently ignore it.
 *
 * # Denylist location
 *
 * `~/.local/state/claude-pii-denylist.txt` (override with `$PII_DENYLIST`).
 *
 * The list of forbidden identifiers is itself PII, so it lives outside ANY
 * git repository — not merely outside this one. `~/.claude` was rejected as a
 * home despite being private and gitignored: it is a real repo with a real
 * remote, and a `.gitignore` entry is one `git add -f`, one ignore-file edit,
 * or one "why is this untracked?" tidy-up away from being wrong. A file whose
 * only reader is a tool gets no human glance to catch that. `~/.local/state`
 * is under no version control at all, which is a property of the location
 * rather than a rule someone has to keep obeying.
 */

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

/** Minimum characters of justification required after `PII_GUARD_OK=`. */
const MINIMUM_ESCAPE_REASON_CHARACTER_COUNT = 12;

/**
 * Environment variable carrying the escape-hatch reason.
 *
 * # Do not rename this to `PII-GUARD-OK`
 *
 * The underscores are a deliberate convention choice, not an oversight, and
 * "fixing" them to match the marketplace's `UPPER-KEBAB-OK` marker family
 * would break the guard's audit standing.
 *
 * This marketplace runs two distinct escape conventions:
 *
 *   1. **Marker tokens** (`SHELL-SAFETY-OK`, `ALLOW-LEGACY-TS`, `FILE-SIZE-OK`)
 *      are written into FILE CONTENT and read by Claude Code lifecycle hooks
 *      through the iter-107 detection helper. Every one of them must be
 *      declared in the iter-111 canonical registry.
 *   2. **Environment variables** (`ALLOW_BARE_BRANCH=1`,
 *      `ALLOW_OWNER_MISMATCH=1`) are the convention for GIT-level escapes —
 *      guards that fire during a git operation, where there is no file being
 *      edited to carry a marker and no hook helper in the process.
 *
 * This guard is squarely in category 2: it runs inside `.git/hooks/pre-commit`
 * and cannot call the iter-107 helper, so registering a marker token would
 * assert a mechanism that does not exist here. Worse, the literal string
 * `PII-GUARD-OK` in this file would be picked up by the iter-111 typo audit —
 * which greps producer files for `[A-Z][A-Z0-9-]+-(OK|SKIP|WRAP)` — and
 * reported as an unregistered marker, for a registry this guard cannot
 * legitimately join. The underscore spelling sidesteps that regex precisely
 * because it is a different convention, which is the honest signal to send.
 */
const ESCAPE_HATCH_ENVIRONMENT_VARIABLE_NAME = "PII_GUARD_OK";

/**
 * Exit code used when staged content matches a denylisted term. This is a
 * FINDING: the guard ran, and it has something to say about the world.
 */
const EXIT_CODE_PII_DETECTED = 1;

/**
 * Exit code used for a usage error — unknown flag, missing or malformed
 * argument. Deliberately distinct from EXIT_CODE_PII_DETECTED.
 *
 * A finding and a mis-invocation are different events and must not share a
 * code. Conflating them makes an operator error look like the opposite of a
 * clean scan, when in truth the scan never happened at all. 64 is the
 * conventional `EX_USAGE` from sysexits.h.
 */
const EXIT_CODE_USAGE_ERROR = 64;

/** One-line usage summary, printed on any argument error. */
const USAGE_LINE =
  "usage: pii-staged-content-guard [--check] [--explain <N>] [--help]";

interface DenylistTerm {
  /** 1-based index over non-comment, non-blank denylist lines. Stable ID. */
  readonly termId: number;
  /** The raw term, exactly as written in the denylist. */
  readonly rawTerm: string;
  /** NFC-normalized, lowercased form used for matching. */
  readonly foldedTerm: string;
}

interface PiiMatch {
  readonly filePath: string;
  /** 1-based line number, or `null` when the match is in the path itself. */
  readonly lineNumber: number | null;
  readonly termId: number;
}

/**
 * Fold a string for comparison: NFC-normalize, then lowercase with Unicode
 * semantics. Applied identically to needle and haystack so the two agree.
 */
function foldForComparison(value: string): string {
  return value.normalize("NFC").toLocaleLowerCase();
}

function resolveDenylistPath(): string {
  const override = process.env.PII_DENYLIST;
  if (override !== undefined && override !== "") {
    return override;
  }
  // ~/.local/state, NOT ~/.claude — see the denylist-location note in the
  // file header. The point is a path under no version control at all.
  return join(homedir(), ".local", "state", "claude-pii-denylist.txt");
}

/**
 * Parse the denylist. Returns `null` when the file does not exist, which the
 * caller distinguishes from "exists but is empty".
 */
function loadDenylistTerms(denylistPath: string): DenylistTerm[] | null {
  let rawContent: string;
  try {
    rawContent = readFileSync(denylistPath, "utf8");
  } catch {
    return null;
  }

  const terms: DenylistTerm[] = [];
  for (const line of rawContent.split("\n")) {
    const trimmed = line.trim();
    if (trimmed === "" || trimmed.startsWith("#")) {
      continue;
    }
    terms.push({
      termId: terms.length + 1,
      rawTerm: trimmed,
      foldedTerm: foldForComparison(trimmed),
    });
  }
  return terms;
}

/** Run a git command, returning stdout as a Buffer. */
function runGit(args: string[]): Buffer {
  return execFileSync("git", args, { maxBuffer: 512 * 1024 * 1024 });
}

/**
 * List staged paths for added/copied/modified/renamed entries. Deletions are
 * excluded — a deleted file contributes no content to the new commit.
 *
 * `-z` is used so that paths containing spaces, quotes, or newlines survive
 * intact; git's default output would quote and escape them.
 */
function listStagedPaths(): string[] {
  const stdout = runGit([
    "diff",
    "--cached",
    "--name-only",
    "--diff-filter=ACMR",
    "-z",
  ]).toString("utf8");

  return stdout.split("\0").filter((path) => path !== "");
}

/** Read the staged blob for a path. Returns `null` if it cannot be read. */
function readStagedBlob(filePath: string): Buffer | null {
  try {
    return runGit(["show", `:${filePath}`]);
  } catch {
    return null;
  }
}

/**
 * Treat a blob as binary if it contains a NUL byte in its leading window —
 * the same heuristic git itself uses. Binary blobs are skipped: they have no
 * meaningful line numbers, and decoding them as UTF-8 would produce garbage
 * that could match a term by coincidence.
 */
function isProbablyBinary(blob: Buffer): boolean {
  const inspectionWindow = blob.subarray(0, 8000);
  return inspectionWindow.includes(0);
}

/** Scan one already-folded haystack line, appending any matches. */
function collectMatchesInLine(
  foldedLine: string,
  terms: readonly DenylistTerm[],
  filePath: string,
  lineNumber: number | null,
  sink: PiiMatch[],
): void {
  for (const term of terms) {
    if (foldedLine.includes(term.foldedTerm)) {
      sink.push({ filePath, lineNumber, termId: term.termId });
    }
  }
}

function scanStagedChanges(terms: readonly DenylistTerm[]): PiiMatch[] {
  const matches: PiiMatch[] = [];

  for (const filePath of listStagedPaths()) {
    // The path itself is scanned first: incident 1's identifier travelled as
    // a surname inside a filename, where no contents scan would see it.
    collectMatchesInLine(
      foldForComparison(filePath),
      terms,
      filePath,
      null,
      matches,
    );

    const blob = readStagedBlob(filePath);
    if (blob === null || isProbablyBinary(blob)) {
      continue;
    }

    const lines = blob.toString("utf8").split("\n");
    for (const [index, line] of lines.entries()) {
      collectMatchesInLine(
        foldForComparison(line),
        terms,
        filePath,
        index + 1,
        matches,
      );
    }
  }

  return matches;
}

/**
 * Read the escape-hatch reason, if the operator supplied a valid one.
 *
 * Returns the reason when it is present and long enough, `"TOO_SHORT"` when
 * present but under the minimum, and `null` when absent. A too-short reason
 * is reported rather than ignored — silently treating it as "no escape" would
 * leave the operator believing they had bypassed the guard when they had not.
 */
function readEscapeHatchReason(): string | "TOO_SHORT" | null {
  const raw = process.env[ESCAPE_HATCH_ENVIRONMENT_VARIABLE_NAME];
  if (raw === undefined || raw.trim() === "") {
    return null;
  }
  const reason = raw.trim();
  if (reason.length < MINIMUM_ESCAPE_REASON_CHARACTER_COUNT) {
    return "TOO_SHORT";
  }
  return reason;
}

function printHelp(): void {
  process.stdout.write(
    `pii-staged-content-guard — block staged content containing forbidden identifiers

USAGE
  bun scripts/pii-staged-content-guard.ts [--check] [--explain N] [--help]

  --check       Scan staged content and exit non-zero on a match. Default.
  --explain N   Print denylist term #N. Prints PII to your terminal, so it is
                a deliberate, explicit action — never done automatically.
  --help        This text.

DENYLIST
  ${resolveDenylistPath()}
  Override with $PII_DENYLIST. One term per line; '#' comments and blank
  lines ignored. Kept outside ANY git repo on purpose: the list of forbidden
  identifiers is itself PII.

ESCAPE HATCH
  ${ESCAPE_HATCH_ENVIRONMENT_VARIABLE_NAME}="<reason, >=${MINIMUM_ESCAPE_REASON_CHARACTER_COUNT} chars>" git commit ...

  A reason is required. False positives on a common surname are inevitable,
  and a guard with no way out gets deleted instead of fixed — but the bypass
  is recorded in the hook output so it is a decision, not a reflex.

REPORTING
  Reports file, line number and term ID only. It never prints the matched
  term or the line it appeared on, because hook output is copied into logs,
  screenshots and transcripts far more often than commits are rewritten.
`,
  );
}

function commandExplain(termIdArgument: string | undefined): number {
  if (termIdArgument === undefined) {
    process.stderr.write(
      "pii-staged-content-guard: --explain requires a term ID, e.g. --explain 3\n" +
        `${USAGE_LINE}\n`,
    );
    return EXIT_CODE_USAGE_ERROR;
  }

  // Strict digits-only. `Number.parseInt` would accept "3abc" as 3 and
  // silently explain a term the operator did not ask for — the same
  // accept-something-close failure this whole guard is arguing against.
  if (!/^\d+$/.test(termIdArgument)) {
    process.stderr.write(
      `pii-staged-content-guard: not a valid term ID: ${termIdArgument}\n` +
        "  Term IDs are positive whole numbers, counted from 1.\n" +
        `${USAGE_LINE}\n`,
    );
    return EXIT_CODE_USAGE_ERROR;
  }

  const termId = Number.parseInt(termIdArgument, 10);
  if (termId < 1) {
    process.stderr.write(
      `pii-staged-content-guard: term IDs start at 1, got ${termIdArgument}\n` +
        `${USAGE_LINE}\n`,
    );
    return EXIT_CODE_USAGE_ERROR;
  }

  const denylistPath = resolveDenylistPath();
  const terms = loadDenylistTerms(denylistPath);
  if (terms === null) {
    process.stderr.write(`No denylist at ${denylistPath}\n`);
    return EXIT_CODE_USAGE_ERROR;
  }

  const match = terms.find((term) => term.termId === termId);
  if (match === undefined) {
    process.stderr.write(
      `pii-staged-content-guard: no term #${termId}; the denylist holds ${terms.length} term(s).\n`,
    );
    return EXIT_CODE_USAGE_ERROR;
  }

  process.stdout.write(`${match.rawTerm}\n`);
  return 0;
}

function commandCheck(): number {
  const denylistPath = resolveDenylistPath();
  const terms = loadDenylistTerms(denylistPath);

  // Fail-open on a missing or empty denylist, but loudly. The denylist is
  // machine-local by design, so "absent" is the normal state on any other
  // clone; failing closed there would make the repository uncommittable for
  // everyone without the file and guarantee the hook is removed rather than
  // configured. The warning is unconditional so the guard is never silently
  // inactive — a quiet no-op would be worse than no guard at all, because it
  // would look like protection.
  if (terms === null) {
    process.stderr.write(
      `[pii-guard] NOT ACTIVE — no denylist found.\n` +
        `[pii-guard]   expected at: ${denylistPath}\n` +
        "[pii-guard]   (deliberately outside any git repo; override with $PII_DENYLIST)\n" +
        "[pii-guard] Staged content was NOT scanned for client identifiers.\n",
    );
    return 0;
  }
  if (terms.length === 0) {
    process.stderr.write(
      `[pii-guard] NOT ACTIVE — denylist holds no terms.\n` +
        `[pii-guard]   read from: ${denylistPath}\n` +
        "[pii-guard] Staged content was NOT scanned for client identifiers.\n",
    );
    return 0;
  }

  const matches = scanStagedChanges(terms);
  if (matches.length === 0) {
    return 0;
  }

  const escapeReason = readEscapeHatchReason();
  if (typeof escapeReason === "string" && escapeReason !== "TOO_SHORT") {
    process.stderr.write(
      `[pii-guard] BYPASSED (${matches.length} match(es)) — reason: ${escapeReason}\n`,
    );
    return 0;
  }

  process.stderr.write(
    `\n[pii-guard] BLOCKED — staged content matches the PII denylist.\n\n`,
  );
  for (const match of matches) {
    const location =
      match.lineNumber === null
        ? `${match.filePath}  (in the file PATH)`
        : `${match.filePath}:${match.lineNumber}`;
    process.stderr.write(`  ${location}  → term #${match.termId}\n`);
  }

  process.stderr.write(
    `\n  ${matches.length} match(es). The matched text is deliberately not shown:\n` +
      "  hook output ends up in logs, screenshots and transcripts.\n\n" +
      `  Identify a term:  bun scripts/pii-staged-content-guard.ts --explain <N>\n` +
      `  Denylist:         ${denylistPath}\n\n`,
  );

  if (escapeReason === "TOO_SHORT") {
    process.stderr.write(
      `  ${ESCAPE_HATCH_ENVIRONMENT_VARIABLE_NAME} was set but its reason is under ` +
        `${MINIMUM_ESCAPE_REASON_CHARACTER_COUNT} characters, so it was NOT honored.\n\n`,
    );
  } else {
    process.stderr.write(
      "  If this is a false positive (a common surname, say), bypass with a reason:\n" +
        `    ${ESCAPE_HATCH_ENVIRONMENT_VARIABLE_NAME}="why this is safe" git commit ...\n\n`,
    );
  }

  return EXIT_CODE_PII_DETECTED;
}

type ParsedArguments =
  | { readonly kind: "help" }
  | { readonly kind: "check" }
  | { readonly kind: "explain"; readonly termIdArgument: string | undefined }
  | { readonly kind: "unknown"; readonly offendingArgument: string };

/**
 * Parse argv strictly. Anything unrecognised is an error, never a silent
 * fall-through to the default action.
 *
 * # Why this is strict rather than forgiving
 *
 * An earlier version ignored unknown flags and ran the default check, so
 * `--path /nonexistent` scanned the real staged set, found nothing, and
 * exited 0 with no output. That reads exactly like "the guard ran and the
 * tree is clean", which is the most dangerous sentence this tool can imply
 * when it is not true.
 *
 * It is also the failure shape this repository keeps getting hurt by: a
 * query that is subtly wrong, returns empty, and has its emptiness read as a
 * fact about the world — `.id` instead of `draftId` returning null for every
 * row, or a scan for CSS `color:` reporting zero on a message carrying 25
 * legacy `<font color>` tags.
 *
 * Here it is worse than a reporting error, because this exit code is a GATE.
 * A mis-invocation that exits 0 is an untraceable bypass that needs no reason
 * string — precisely what the reason-gated escape hatch exists to prevent.
 * The escape hatch is honest about being a bypass; a silent zero is not.
 */
function parseArguments(args: readonly string[]): ParsedArguments {
  // `--check` is the explicit spelling of the default, accepted so the git
  // hook reads unambiguously. Last mode flag wins, as is conventional.
  let mode: "help" | "check" | "explain" = "check";
  let explainTermIdArgument: string | undefined;

  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--help" || argument === "-h") {
      mode = "help";
    } else if (argument === "--check") {
      mode = "check";
    } else if (argument === "--explain") {
      mode = "explain";
      explainTermIdArgument = args[index + 1];
      index += 1;
    } else {
      return { kind: "unknown", offendingArgument: argument as string };
    }
  }

  if (mode === "help") {
    return { kind: "help" };
  }
  if (mode === "explain") {
    return { kind: "explain", termIdArgument: explainTermIdArgument };
  }
  return { kind: "check" };
}

function reportUnknownArgument(offendingArgument: string): number {
  process.stderr.write(
    `pii-staged-content-guard: unknown argument: ${offendingArgument}\n` +
      "\n" +
      "  Refusing to run. An unrecognised argument is an operator error, and\n" +
      "  exiting 0 here would look identical to a clean scan that never ran.\n" +
      "\n" +
      `  ${USAGE_LINE}\n` +
      "  See --help for the full description.\n",
  );
  return EXIT_CODE_USAGE_ERROR;
}

function main(): number {
  const parsed = parseArguments(process.argv.slice(2));

  switch (parsed.kind) {
    case "unknown":
      return reportUnknownArgument(parsed.offendingArgument);
    case "help":
      printHelp();
      return 0;
    case "explain":
      return commandExplain(parsed.termIdArgument);
    case "check":
      return commandCheck();
  }
}

process.exit(main());
