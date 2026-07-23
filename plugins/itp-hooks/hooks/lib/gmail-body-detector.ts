/**
 * Gmail draft body detector (SSoT) — pure, dependency-free.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Why this file exists (incident 2026-07-22)
 * ════════════════════════════════════════════════════════════════════════
 *
 * The `gmail` CLI (plugins/gmail-commander/scripts/gmail-cli) renders a draft
 * body by turning EVERY authored newline into an HTML `<br>` (see `toHtmlBody`
 * in gmail-drafts.ts) and does NOT render markdown (it HTML-escapes the text).
 * Two authoring mistakes therefore reach the recipient verbatim:
 *
 *   1. HARD-WRAP — a paragraph wrapped at a fixed column (e.g. a markdown file
 *      wrapped at ~100 chars) gets a literal `<br>` at every wrap point, so the
 *      reader sees a column of short, mid-sentence lines instead of a paragraph
 *      that reflows to their window (the "chopped" look).
 *   2. LITERAL MARKDOWN — `**bold**`, `` `code` ``, `[text](url)`, `#` headings
 *      and `|pipe|` tables render as their raw source characters.
 *
 * The gmail-access skill's doctrine (SKILL.md Evolution Log 2026-07-10 / -07-22):
 * author each paragraph as a single unbroken line and send plain prose, not
 * markdown. This module detects violations so the PreToolUse guard can block a
 * `gmail draft` before the bad draft is created.
 *
 * Pure (string in, findings out — no I/O). Fence scanning is delegated to the
 * shared markdown-fence-scanner; shell-command arg extraction to the shared
 * shell-arg-extractor. The file read for `--body-file` happens in the hook.
 */

import { computeFencedCodeLineMask } from "./markdown-fence-scanner.ts";
import { extractFlagValues } from "./shell-arg-extractor.ts";

// ════════════════════════════════════════════════════════════════════════
//  Hard-wrap detection
// ════════════════════════════════════════════════════════════════════════

export interface WrapIssue {
  /** 1-based line number of the line that breaks mid-sentence (line A). */
  readonly line: number;
  /** Trimmed visible width of line A (how wide the wrap point is). */
  readonly width: number;
  /** Short preview of the continuation line B (for the reminder). */
  readonly nextPreview: string;
}

export interface DetectOptions {
  /**
   * Minimum trimmed width for line A to be considered a suspicious wrap point.
   * Below this, a line that "ends open" is treated as a deliberately short line
   * (salutation, sign-off) rather than a machine wrap. Default 50.
   */
  readonly minWrapWidth?: number;
}

const DEFAULT_MIN_WRAP_WIDTH = 50;

/** A markdown table row: trimmed line starts with a pipe. */
function isTableRow(rawLine: string): boolean {
  return /^\s*\|/.test(rawLine);
}

/** An ATX heading (`# …` … `###### …`). */
function isHeading(rawLine: string): boolean {
  return /^ {0,3}#{1,6}\s/.test(rawLine);
}

/** A thematic break (`---`, `***`, `___`, optionally spaced). */
function isThematicBreak(rawLine: string): boolean {
  const t = rawLine.trim();
  return /^(?:-\s*){3,}$/.test(t) || /^(?:\*\s*){3,}$/.test(t) || /^(?:_\s*){3,}$/.test(t);
}

/**
 * True when `line`, after stripping leading whitespace, begins a NEW structural
 * block element — so a break before it is intentional, not a prose wrap.
 */
function beginsNewStructuralElement(line: string): boolean {
  const t = line.replace(/^\s+/, "");
  if (t === "") return false;
  if (/^[-*+]\s/.test(t)) return true; // unordered list item
  if (/^\d+[.)]\s/.test(t)) return true; // ordered list item
  if (/^#{1,6}\s/.test(t)) return true; // heading
  if (t.startsWith(">")) return true; // blockquote
  if (t.startsWith("|")) return true; // table row
  return false;
}

/** Line A "ends open" when its last non-space char is not a clause terminator. */
function endsOpen(trimmedEnd: string): boolean {
  if (trimmedEnd === "") return false;
  const last = trimmedEnd[trimmedEnd.length - 1];
  return !".!?:;".includes(last);
}

/** A short, single-line preview (whitespace-collapsed, capped). */
function preview(line: string, max = 60): string {
  const collapsed = line.replace(/\s+/g, " ").trim();
  return collapsed.length > max ? collapsed.slice(0, max - 1) + "…" : collapsed;
}

/**
 * Scan an email body and return every hard-wrap (mid-sentence line break in a
 * prose paragraph), ordered by line number. Pure; never throws on normal input.
 */
export function detectHardWraps(body: string, opts: DetectOptions = {}): WrapIssue[] {
  const minWrapWidth = opts.minWrapWidth ?? DEFAULT_MIN_WRAP_WIDTH;
  const lines = body.replace(/\r\n/g, "\n").split("\n");
  const inFence = computeFencedCodeLineMask(lines);
  const issues: WrapIssue[] = [];

  for (let i = 0; i < lines.length - 1; i++) {
    const a = lines[i];
    const b = lines[i + 1];
    if (inFence[i] || inFence[i + 1]) continue;
    const aTrimEnd = a.replace(/\s+$/, "");
    if (aTrimEnd === "" || b.trim() === "") continue; // blank ends the block

    if (isTableRow(a) || isHeading(a) || isThematicBreak(a)) continue;
    if (!endsOpen(aTrimEnd)) continue;
    if (aTrimEnd.trim().length < minWrapWidth) continue;
    if (beginsNewStructuralElement(b)) continue;

    issues.push({ line: i + 1, width: aTrimEnd.trim().length, nextPreview: preview(b) });
  }
  return issues;
}

// ════════════════════════════════════════════════════════════════════════
//  Literal-markdown detection (high-signal, low-false-positive set)
// ════════════════════════════════════════════════════════════════════════

export type MarkdownConstruct = "bold" | "code" | "link" | "heading" | "table";

export interface MarkdownIssue {
  /** 1-based line number where the raw-markdown construct appears. */
  readonly line: number;
  readonly kind: MarkdownConstruct;
  /** Short sample of the offending construct (for the reminder). */
  readonly sample: string;
}

/** `**bold**` and `__bold__` (paired double); `__` skips bare identifiers (e.g. `__init__`). */
const BOLD_STAR_RX = /\*\*(?=\S)(?:(?!\*\*).)+?\*\*/g;
const BOLD_UNDERSCORE_RX = /(?<![\w])__(?=\S)((?:(?!__).)+?)__(?![\w])/g;
/** `` `inline code` `` — paired single backticks with non-empty content. */
const INLINE_CODE_RX = /`(?=\S)(?:[^`\n]+?)`/g;
/** `[text](url)` markdown link — the `](` pivot is highly markdown-specific. */
const MD_LINK_RX = /\[[^\]\n]+\]\([^)\n]+\)/g;

/** True when the inner text of an `__…__` run is a bare identifier (skip dunders). */
function isBareIdentifier(inner: string): boolean {
  return /^\w+$/.test(inner);
}

function sampleOf(s: string, max = 40): string {
  return s.length > max ? s.slice(0, max - 1) + "…" : s;
}

/**
 * Detect raw markdown that the gmail CLI renders literally. High-signal set:
 * `**bold**`/`__bold__`, `` `code` ``, `[text](url)` links, `#` headings, and
 * `|pipe|` table rows. Single-char `*italic*`/`_italic_` are intentionally NOT
 * flagged (too many false positives from prose, math, filenames, emails, URLs).
 * Fenced code blocks are skipped (their contents are examples, not intended
 * markdown to render).
 */
export function detectLiteralMarkdown(body: string): MarkdownIssue[] {
  const lines = body.replace(/\r\n/g, "\n").split("\n");
  const inFence = computeFencedCodeLineMask(lines);
  const issues: MarkdownIssue[] = [];

  for (let i = 0; i < lines.length; i++) {
    if (inFence[i]) continue;
    const line = lines[i];
    const ln = i + 1;

    if (isHeading(line) && !isThematicBreak(line)) {
      issues.push({ line: ln, kind: "heading", sample: sampleOf(line.trim()) });
    }
    if (isTableRow(line) && (line.match(/\|/g)?.length ?? 0) >= 2) {
      issues.push({ line: ln, kind: "table", sample: sampleOf(line.trim()) });
    }
    for (const m of line.matchAll(BOLD_STAR_RX)) {
      issues.push({ line: ln, kind: "bold", sample: sampleOf(m[0]) });
    }
    for (const m of line.matchAll(BOLD_UNDERSCORE_RX)) {
      if (!isBareIdentifier(m[1])) issues.push({ line: ln, kind: "bold", sample: sampleOf(m[0]) });
    }
    for (const m of line.matchAll(INLINE_CODE_RX)) {
      issues.push({ line: ln, kind: "code", sample: sampleOf(m[0]) });
    }
    for (const m of line.matchAll(MD_LINK_RX)) {
      issues.push({ line: ln, kind: "link", sample: sampleOf(m[0]) });
    }
  }
  return issues;
}

// ════════════════════════════════════════════════════════════════════════
//  Combined body issues
// ════════════════════════════════════════════════════════════════════════

export interface BodyIssues {
  readonly wraps: WrapIssue[];
  readonly markdown: MarkdownIssue[];
}

/** Run both detectors over one body. */
export function detectBodyIssues(body: string, opts: DetectOptions = {}): BodyIssues {
  return { wraps: detectHardWraps(body, opts), markdown: detectLiteralMarkdown(body) };
}

/** True when a body has any hard-wrap or literal-markdown issue. */
export function hasBodyIssues(issues: BodyIssues): boolean {
  return issues.wraps.length > 0 || issues.markdown.length > 0;
}

// ════════════════════════════════════════════════════════════════════════
//  Gmail-draft command parsing
// ════════════════════════════════════════════════════════════════════════

export interface ExtractedBodies {
  /** Inline `--body` argument values. */
  readonly inline: string[];
  /** `--body-file` path arguments (not yet resolved/read). */
  readonly bodyFilePaths: string[];
}

/**
 * A gmail-draft invocation: references the gmail CLI (`gmail`, `$GMAIL_CLI`, or
 * a `.../gmail` path) AND a `draft` / `draft-update` subcommand.
 */
export function isGmailDraftCommand(command: string): boolean {
  const mentionsCli = /(?:^|[\s"'/=$])(?:gmail|GMAIL_CLI)\b/.test(command);
  const mentionsDraft = /\bdraft(?:-update)?\b/.test(command);
  return mentionsCli && mentionsDraft;
}

/**
 * Extract inline `--body` values and `--body-file` paths from a gmail-draft
 * command via the shared shell-arg-extractor. Returns empty arrays when the
 * command is not a gmail-draft command. `--body` never captures `--body-file`
 * (word-boundary joiner in the shared extractor).
 */
export function parseGmailDraftBodies(command: string): ExtractedBodies {
  if (!isGmailDraftCommand(command)) return { inline: [], bodyFilePaths: [] };
  return {
    inline: extractFlagValues(command, ["--body"]),
    bodyFilePaths: extractFlagValues(command, ["--body-file"]),
  };
}

// ════════════════════════════════════════════════════════════════════════
//  Reminder builder (shared by hook + tests)
// ════════════════════════════════════════════════════════════════════════

export interface BodySource {
  /** Human label for where the body came from (`--body` or a file path). */
  readonly label: string;
  readonly issues: BodyIssues;
}

/**
 * Build the Claude-visible `deny` reason for one or more problematic bodies.
 * Lists hard-wraps and/or literal-markdown per source, then the single fix.
 */
export function buildBodyReminder(sources: readonly BodySource[]): string {
  const withIssues = sources.filter((s) => hasBodyIssues(s.issues));
  const anyWrap = withIssues.some((s) => s.issues.wraps.length > 0);
  const anyMd = withIssues.some((s) => s.issues.markdown.length > 0);

  const lines: string[] = ["[GMAIL-BODY-GUARD] This gmail draft body will render badly in the recipient's inbox."];
  if (anyWrap) {
    lines.push(
      "",
      "• HARD-WRAP: the CLI turns every newline into a <br>, so a paragraph wrapped at a fixed column",
      "  becomes a column of short, mid-sentence lines instead of reflowing to the reader's window.",
    );
  }
  if (anyMd) {
    lines.push(
      "",
      "• RAW MARKDOWN: the CLI HTML-escapes the body and does NOT render markdown, so **bold**,",
      "  `code`, [text](url), # headings and |tables| show as their literal source characters.",
    );
  }

  for (const src of withIssues) {
    lines.push("", `  ${src.label}:`);
    for (const w of src.issues.wraps.slice(0, 5)) {
      lines.push(`    L${w.line}: hard-wrap (${w.width} cols) → continues: "${w.nextPreview}"`);
    }
    if (src.issues.wraps.length > 5) lines.push(`    …and ${src.issues.wraps.length - 5} more wrapped line(s).`);
    for (const m of src.issues.markdown.slice(0, 5)) {
      lines.push(`    L${m.line}: raw ${m.kind} → ${m.sample}`);
    }
    if (src.issues.markdown.length > 5) {
      lines.push(`    …and ${src.issues.markdown.length - 5} more markdown construct(s).`);
    }
  }

  lines.push(
    "",
    "Fix: author each PARAGRAPH as ONE unbroken line (long lines reflow; keep only intended breaks",
    'such as list items and the "Best,"/name sign-off on their own line), and write PLAIN prose — no',
    "markdown. This applies to --body and --body-file content alike.",
    "",
    "Doctrine: gmail-commander/skills/gmail-access/SKILL.md, Evolution Log 2026-07-22.",
    "Override (rare — e.g. an intentional ASCII table body): add GMAIL-BODY-OK anywhere in the command.",
  );
  return lines.join("\n");
}
