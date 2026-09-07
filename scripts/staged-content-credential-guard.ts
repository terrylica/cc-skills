#!/usr/bin/env bun
/**
 * Pre-commit CREDENTIAL guard for staged file CONTENT — the last unwatched
 * route into a commit.
 *
 * # The gap this closes
 *
 * Three surfaces already look for credentials in this repository, and between
 * them they leave one hole large enough to drive every real incident through:
 *
 *   1. `pretooluse-secret-exposure-guard.ts` blocks a CREDENTIAL in the payload
 *      of an agent's Write / Edit / MultiEdit. It sees a tool call, not a file:
 *      bytes that arrive by any other route are invisible to it.
 *   2. `commit-message-exposure-guard.ts` blocks a credential in the COMMIT
 *      MESSAGE. That is the semantic-release republication surface, and nothing
 *      to do with file content.
 *   3. `pii-staged-content-guard.ts` reads exactly the right bytes — the staged
 *      blobs — but matches them only against a proper-noun PII denylist. It has
 *      never looked for a credential SHAPE.
 *
 * So a secret that entered the tree through a human editor, `git apply`, `sed`,
 * a merge, a `curl … > file`, a copied file from another repo, or a commit made
 * from another client is staged and committed with ZERO credential inspection.
 * Every one of those routes is ordinary. The audit that motivated the shared
 * detector found live tokens sitting in ADRs and design specs — documents that
 * are written and pasted into far more often than they are agent-edited.
 *
 * This guard runs the SAME shared detector
 * (`plugins/itp-hooks/hooks/lib/secret-and-pii-exposure-detector.ts`) over the
 * bytes git is about to record, at the one checkpoint every route must pass.
 *
 * # Staged blob, not working tree
 *
 * Content comes from `git show :<path>`, never from the file on disk. The two
 * differ whenever a file is partially staged (`git add -p`), and it is the
 * STAGED bytes that become the commit. Reading the working tree would let a
 * `git add -p` of a secret through while blocking on a line the operator had
 * already removed — wrong in both directions at once.
 *
 * The whole staged blob is scanned, not just the added lines. A file being
 * touched for an unrelated reason that still carries a credential from an
 * earlier commit is a finding worth surfacing on a public repo, and diff-hunk
 * parsing would additionally lose the ±80-character context windows that keep
 * the Pushover and provisioning detectors quiet.
 *
 * # Why this BLOCKS, when the sibling PII guard's fuzzy half only reminds
 *
 * Credential classes are structurally distinctive and catastrophic once
 * published; the shared detector is calibrated for low false positives on
 * exactly these three shapes, which is why the PreToolUse guard is allowed to
 * deny on them. Identifier/PII classes are fuzzier and are deliberately NOT
 * scanned here — that half of the surface belongs to `pii-staged-content-guard`
 * and its denylist. This guard has one job and one severity.
 *
 * # Reporting policy — redacted values only
 *
 * A finding prints `path:line`, the class label, and the detector's already
 * REDACTED excerpt. Never the matched value. The reasoning is the sibling
 * guard's, and it is not decorative: hook output lands in terminal scrollback,
 * CI logs, asciinema recordings, and the screenshot someone pastes into an
 * issue asking why their commit is blocked. A guard that echoes the secret has
 * moved the leak from a commit (rewritable) into a log (not). Re-publishing
 * what you are redacting is the precise error the commit-message guard exists
 * to stop; committing it in a block message would be that error one level up.
 *
 * # Escape hatch — per file, in the content, reason mandatory
 *
 *   SECRET-SCAN-OK: <reason of at least 10 characters>
 *
 * anywhere in the staged blob, matching the marker, the reason gate and the
 * FILE_WIDE window the PreToolUse credential guard already registers. The
 * marker travels with the content, so a bypass names exactly ONE file and
 * survives in review rather than evaporating with the shell that set it.
 *
 * There is deliberately NO commit-wide environment bypass. The sibling PII
 * guard needs one because its denylist can fire on a common surname in a file
 * nobody wants to annotate; a credential finding is specific enough that a
 * per-file marker is always placeable, and a commit-wide switch would excuse
 * files nobody looked at. `--no-verify` remains the blunt instrument.
 *
 * ## Why a reason in angle brackets does not count
 *
 * This guard is stricter than the commit-message guard's `hasValidEscapeHatch`
 * in one respect: a reason that is nothing but placeholder syntax is read as
 * DOCUMENTATION of the marker, not a use of it.
 *
 * That divergence is forced by the surface. A commit message almost never
 * documents the escape hatch; source files do it constantly — this repo has a
 * registry entry, a docs page, and two guards that all spell the marker beside
 * `<reason>`. Without this rule, every file that explains the marker would
 * silently exempt itself from the scan, including the file you are reading.
 *
 * # Failure policy
 *
 * Fail OPEN on any internal error, loudly. A crashing guard must never make the
 * repository uncommittable, because an operator facing that deletes the hook
 * rather than fixing it — and then the gate is gone for good. Loudly, so it is
 * never silently inactive: a quiet no-op is worse than no guard, since it looks
 * like protection.
 */

import { execFileSync } from "node:child_process";
import {
  type CredentialFinding,
  CREDENTIAL_LABELS,
  detectCredentialExposure,
} from "../plugins/itp-hooks/hooks/lib/secret-and-pii-exposure-detector.ts";

/** Marker and reason gate, kept identical to the two guards that precede this one. */
const ESCAPE_HATCH_MARKER = "SECRET-SCAN-OK";
const MINIMUM_ESCAPE_REASON_CHARACTER_COUNT = 10;

/** A credential was found in staged content. The commit is rejected. */
const EXIT_CODE_CREDENTIAL_DETECTED = 1;

/**
 * Mis-invocation. Deliberately distinct from a finding, for the reason the
 * sibling guard spells out at length: a guard that never ran must not be
 * indistinguishable from a guard that ran and found nothing. 64 is `EX_USAGE`.
 */
const EXIT_CODE_USAGE_ERROR = 64;

const USAGE_LINE = "usage: staged-content-credential-guard [--check] [--help]";

/**
 * NUL in the first kilobyte means binary. This is the PreToolUse credential
 * guard's own `looksLikeBinaryPayload` window, chosen over the PII guard's
 * 8 KiB so the two CREDENTIAL surfaces classify a payload identically — a
 * secret that the write-time guard would refuse to scan must not become a
 * commit-time block, or the two guards disagree about the same bytes.
 *
 * Binary blobs are skipped outright: they have no meaningful line numbers, and
 * decoding compressed bytes as UTF-8 manufactures high-entropy runs that exist
 * only to trip a detector.
 */
const BINARY_SNIFF_WINDOW_BYTES = 1024;

/**
 * Blobs above this size are reported and skipped rather than scanned.
 *
 * A pre-commit hook that hangs on a vendored bundle is a hook that gets
 * removed. The classes this guard detects are hand-pasted into prose and
 * config, not emitted into multi-megabyte generated artifacts, so the recall
 * lost here is close to nil — and the skip is announced, never silent.
 */
const MAXIMUM_SCANNED_BLOB_BYTES = 5 * 1024 * 1024;

/** A credential finding, tagged with the staged file it came from. */
export interface StagedCredentialFinding {
  readonly filePath: string;
  readonly finding: CredentialFinding;
}

/**
 * Three-state escape-hatch classification.
 *
 * `rejected` is reported rather than folded into `absent` — the sibling PII
 * guard's `TOO_SHORT` reasoning. Silently treating a malformed marker as "no
 * marker" leaves the operator believing they bypassed the guard when they did
 * not, and the next thing they reach for is `--no-verify`.
 */
export type EscapeHatchState = "valid" | "rejected" | "absent";

/**
 * A reason that OPENS with placeholder syntax is a specimen of the marker, not
 * a use of it: `SECRET-SCAN-OK: <reason> to suppress` is a sentence explaining
 * the feature. Optional leading quoting is consumed because documentation
 * habitually writes the whole thing inside backticks, and `&lt;` is accepted
 * because a rendered CHANGELOG carries the HTML-escaped form of the same text.
 */
const PLACEHOLDER_LEADING_REASON_PATTERN = /^["'`]*(?:<|&lt;)[^>]*>/;

/**
 * Strip placeholder syntax and trailing comment closers, leaving the text that
 * an operator actually wrote as justification.
 *
 * `<reason of at least 10 characters>` collapses to nothing, which is the whole
 * point: documenting the marker must not exempt the documenting file.
 */
function substantiveEscapeReason(rawReason: string): string {
  return rawReason
    .replace(/<[^>]*>/g, "")
    .replace(/(?:-->|\*\/|`)+\s*$/, "")
    .trim();
}

/**
 * A justification qualifies when it is not a specimen and still carries the
 * required number of characters once placeholder syntax is removed.
 *
 * No rule can perfectly separate "documents the marker" from "uses the marker"
 * — prose is prose. These two catch every form this repository actually
 * contains, including the header of the file you are reading; anything subtler
 * is accepted, and the cost of that is one file scanned less, never a value
 * published more.
 */
function isQualifyingEscapeReason(rawReason: string): boolean {
  if (PLACEHOLDER_LEADING_REASON_PATTERN.test(rawReason.trim())) return false;
  return substantiveEscapeReason(rawReason).length >= MINIMUM_ESCAPE_REASON_CHARACTER_COUNT;
}

/**
 * Classify every occurrence of the marker in a blob. Any single valid one
 * excuses the file; a present-but-malformed one is surfaced to the operator.
 */
export function classifyEscapeHatch(content: string): EscapeHatchState {
  // The backtick lookbehind skips a QUOTED MENTION of the marker name —
  // `SECRET-SCAN-OK:` inside prose is documentation, and without this the
  // sibling commit-message guard's own source exempts itself from being
  // scanned. Only the backtick is excluded, deliberately: double and single
  // quotes are how a marker would legitimately be placed in a JSON or YAML
  // file, which has no comment syntax to carry it.
  const pattern = new RegExp(`(?<!\`)${ESCAPE_HATCH_MARKER}:[ \\t]*(.*)`, "g");
  let sawMarker = false;
  for (const match of content.matchAll(pattern)) {
    sawMarker = true;
    if (isQualifyingEscapeReason(match[1] ?? "")) {
      return "valid";
    }
  }
  return sawMarker ? "rejected" : "absent";
}

/** See `BINARY_SNIFF_WINDOW_BYTES`. */
export function isProbablyBinary(blob: Buffer): boolean {
  return blob.subarray(0, BINARY_SNIFF_WINDOW_BYTES).includes(0);
}

/** Run a git command, returning stdout as a Buffer. */
function runGit(args: readonly string[], repositoryDirectory?: string): Buffer {
  const fullArgs =
    repositoryDirectory === undefined ? [...args] : ["-C", repositoryDirectory, ...args];
  return execFileSync("git", fullArgs, { maxBuffer: 512 * 1024 * 1024 });
}

/**
 * Staged paths for added/copied/modified/renamed entries. Deletions are
 * excluded: a deleted file contributes no content to the new commit.
 *
 * `-z` so paths containing spaces, quotes or newlines survive intact — git's
 * default output would quote and escape them, and a guard that mangles a path
 * scans the wrong blob or none at all.
 */
export function listStagedPaths(repositoryDirectory?: string): string[] {
  const stdout = runGit(
    ["diff", "--cached", "--diff-filter=ACMR", "-z", "--name-only"],
    repositoryDirectory,
  ).toString("utf8");
  return stdout.split("\0").filter((path) => path !== "");
}

/** Read the staged blob for a path. `null` when it cannot be read. */
export function readStagedBlob(filePath: string, repositoryDirectory?: string): Buffer | null {
  try {
    return runGit(["show", `:${filePath}`], repositoryDirectory);
  } catch {
    return null;
  }
}

/**
 * Pure classifier, exported for tests: one file's staged bytes in, findings
 * out. No I/O, no process exit. Returns `[]` when the file carries a valid
 * escape marker.
 */
export function scanStagedBlobContent(
  filePath: string,
  content: string,
): StagedCredentialFinding[] {
  if (classifyEscapeHatch(content) === "valid") return [];
  return detectCredentialExposure(content).map((finding) => ({ filePath, finding }));
}

export interface StagedScanResult {
  readonly findings: readonly StagedCredentialFinding[];
  /** Files whose staged blob carried a valid escape marker. */
  readonly excusedFilePaths: readonly string[];
  /** Files skipped as binary or oversized, with the reason. */
  readonly skippedFilePaths: readonly string[];
  /** Files with a marker whose reason did not qualify. */
  readonly rejectedMarkerFilePaths: readonly string[];
}

/** Enumerate the staged set and scan every text blob in it. */
export function scanStagedChanges(repositoryDirectory?: string): StagedScanResult {
  const findings: StagedCredentialFinding[] = [];
  const excusedFilePaths: string[] = [];
  const skippedFilePaths: string[] = [];
  const rejectedMarkerFilePaths: string[] = [];

  for (const filePath of listStagedPaths(repositoryDirectory)) {
    const blob = readStagedBlob(filePath, repositoryDirectory);
    if (blob === null) continue;
    if (isProbablyBinary(blob)) continue;
    if (blob.byteLength > MAXIMUM_SCANNED_BLOB_BYTES) {
      skippedFilePaths.push(filePath);
      continue;
    }

    const content = blob.toString("utf8");
    const escapeHatchState = classifyEscapeHatch(content);
    if (escapeHatchState === "valid") {
      excusedFilePaths.push(filePath);
      continue;
    }
    if (escapeHatchState === "rejected") {
      rejectedMarkerFilePaths.push(filePath);
    }

    for (const finding of detectCredentialExposure(content)) {
      findings.push({ filePath, finding });
    }
  }

  return { findings, excusedFilePaths, skippedFilePaths, rejectedMarkerFilePaths };
}

/**
 * Render the blocking message.
 *
 * The detector's own `buildCredentialDenyReason()` is deliberately NOT reused,
 * for the reason the commit-message guard documents: its prose says "this
 * write" and "the file", which describes a PreToolUse payload, not an index
 * entry. The DETECTION is shared — that is the point of the shared detector —
 * but remediation advice that names the wrong surface is advice an operator
 * learns to skip. `CREDENTIAL_LABELS` is imported so the vocabulary at least
 * stays in one place.
 */
export function buildStagedCredentialBlock(
  findings: readonly StagedCredentialFinding[],
  rejectedMarkerFilePaths: readonly string[] = [],
): string {
  const shown = findings.slice(0, 5).map(({ filePath, finding }) => {
    return `  • ${filePath}:${finding.line} — ${CREDENTIAL_LABELS[finding.kind]} — ${finding.excerpt}`;
  });
  const distinctFileCount = new Set(findings.map((f) => f.filePath)).size;

  return [
    "",
    "[secret-guard] BLOCKED — staged content carries a live-shaped credential.",
    "",
    ...shown,
    findings.length > 5 ? `  • …and ${findings.length - 5} more` : "",
    "",
    `  ${findings.length} finding(s) across ${distinctFileCount} file(s). Values are shown REDACTED:`,
    "  hook output reaches logs, screenshots and transcripts far more often than",
    "  commits get rewritten.",
    "",
    "  This is the staged-CONTENT surface. The PreToolUse guard only sees an agent's",
    "  Write/Edit, so a secret that arrived via an editor, `git apply`, sed, a merge",
    "  or a copied file reaches the commit unexamined — that is the hole this closes.",
    "",
    "  Fix: replace the value with a placeholder, or name the secret instead of",
    "  quoting it. If the value was ever real, ROTATE IT — removing it from the file",
    "  is not enough; it is already in your shell history and in a git object.",
    "",
    `  Escape hatch, per file: put "${ESCAPE_HATCH_MARKER}: <reason>" (reason >=${MINIMUM_ESCAPE_REASON_CHARACTER_COUNT} chars)`,
    "  in the file itself when the value is genuinely synthetic — a fixture for this",
    "  guard's own tests, say. There is no commit-wide bypass on purpose.",
    rejectedMarkerFilePaths.length > 0
      ? [
          "",
          `  The marker IS present but was NOT honored in: ${rejectedMarkerFilePaths.join(", ")}`,
          `  A reason under ${MINIMUM_ESCAPE_REASON_CHARACTER_COUNT} characters, or one that is only placeholder syntax such as`,
          "  an angle-bracketed <reason>, reads as documentation of the marker rather than",
          "  a use of it, and does not suppress.",
        ].join("\n")
      : "",
    "",
  ]
    .filter((line, index, all) => !(line === "" && all[index - 1] === ""))
    .join("\n");
}

type ParsedArguments =
  | { readonly kind: "help" }
  | { readonly kind: "check" }
  | { readonly kind: "usage-error"; readonly detail: string };

/**
 * Strict argv parsing. An unrecognised flag is an error, never a fall-through
 * to the default scan — an exit 0 from a mis-invocation is an untraceable
 * bypass that reads exactly like a clean tree.
 */
export function parseArguments(args: readonly string[]): ParsedArguments {
  let mode: "help" | "check" = "check";
  for (const argument of args) {
    if (argument === "--help" || argument === "-h") {
      mode = "help";
    } else if (argument === "--check") {
      mode = "check";
    } else {
      return { kind: "usage-error", detail: `unknown argument: ${argument}` };
    }
  }
  return mode === "help" ? { kind: "help" } : { kind: "check" };
}

function printHelp(): void {
  process.stdout.write(
    `staged-content-credential-guard — block a commit whose staged files carry a credential

USAGE
  bun scripts/staged-content-credential-guard.ts [--check] [--help]

  --check   Scan staged blobs and exit non-zero on a credential. Default.
  --help    This text.

WHY
  Credentials are intercepted at PreToolUse (agent Write/Edit only) and in the
  commit message. Staged file CONTENT was scanned only against a proper-noun PII
  denylist, so a secret arriving by an editor, git apply, sed, a merge or a
  copied file was committed with no credential inspection at all. Invoked from
  the pre-commit git hook, beside the PII guard.

DETECTORS
  Shared with the PreToolUse guard: BotFather Telegram tokens, bare 30-char
  Pushover-style tokens beside a naming cue, and secret-manager provisioning
  commands carrying a real literal value.

ESCAPE HATCH
  Put "${ESCAPE_HATCH_MARKER}: <reason>" (reason >=${MINIMUM_ESCAPE_REASON_CHARACTER_COUNT} chars) in the FILE.
  Per file, not per commit; a reason that is only placeholder syntax does not
  suppress, or every file documenting the marker would exempt itself.

REPORTING
  Path, line, class and a redacted excerpt only — never the matched value.

EXIT
  0   clean, or every finding excused
  ${EXIT_CODE_CREDENTIAL_DETECTED}   credential found in staged content
  ${EXIT_CODE_USAGE_ERROR}  usage error (deliberately distinct from a finding)
`,
  );
}

function main(): number {
  const parsed = parseArguments(process.argv.slice(2));

  if (parsed.kind === "help") {
    printHelp();
    return 0;
  }
  if (parsed.kind === "usage-error") {
    process.stderr.write(
      `staged-content-credential-guard: ${parsed.detail}\n` +
        "\n" +
        "  Refusing to run. An unrecognised argument is an operator error, and\n" +
        "  exiting 0 here would look identical to a clean scan that never ran.\n" +
        "\n" +
        `  ${USAGE_LINE}\n`,
    );
    return EXIT_CODE_USAGE_ERROR;
  }

  const result = scanStagedChanges();

  for (const filePath of result.skippedFilePaths) {
    process.stderr.write(
      `[secret-guard] NOT SCANNED — ${filePath} exceeds ${MAXIMUM_SCANNED_BLOB_BYTES} bytes.\n`,
    );
  }

  if (result.findings.length === 0) {
    return 0;
  }

  process.stderr.write(
    `${buildStagedCredentialBlock(result.findings, result.rejectedMarkerFilePaths)}\n`,
  );
  return EXIT_CODE_CREDENTIAL_DETECTED;
}

if (import.meta.main) {
  try {
    process.exit(main());
  } catch (error) {
    // Fail OPEN, loudly. See the failure-policy note in the file header: a
    // guard bug must not be able to wedge every commit in the repository, and
    // a silent no-op would be worse than no guard because it looks like one.
    //
    // "Loudly" needs help to actually be loud. execFileSync inherits git's
    // stderr, so a crash inside a git call emits git's whole usage text —
    // roughly 200 lines — and then repeats it in the error message. A single
    // trailing line lands dead last and scrolls off the top of the terminal,
    // which is the opposite of loud. Adversarial review caught this. So the
    // notice is fenced, and the underlying error is truncated rather than
    // allowed to bury its own headline.
    const detail = error instanceof Error ? error.message : String(error);
    const firstLine = detail.split("\n")[0]?.slice(0, 200) ?? "unknown error";
    const banner = "═".repeat(72);
    process.stderr.write(
      `\n${banner}\n` +
        `[secret-guard] NOT ACTIVE — guard crashed, commit allowed UNCHECKED.\n` +
        `  cause: ${firstLine}\n` +
        `  Staged content was NOT scanned for credentials. Re-run after fixing,\n` +
        `  or inspect the diff by hand before pushing.\n` +
        `${banner}\n\n`,
    );
    process.exit(0);
  }
}
