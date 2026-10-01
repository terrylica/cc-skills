/**
 * Net-new markdown hard-wrap detection — the ONE definition shared by every hook that asks "did this
 * change add a hard-wrapped paragraph to a `.md` file?".
 *
 * Three surfaces ask it, and until 2026-10-01 only the first one existed:
 *
 *   1. `posttooluse-markdown-hard-wrap-reminder.ts` — Write/Edit/MultiEdit of a `.md`.
 *   2. `posttooluse-bash-markdown-hard-wrap-reminder.ts` — a Bash command that wrote a `.md`
 *      (heredoc, `python3 - <<EOF`, a generator script, `sed -i`). Measured gap: a session reflowed
 *      and rewrote dozens of Markdown files through Bash and Python and the reminder never fired,
 *      because its matcher is `Write|Edit|MultiEdit` and a Bash command is not a file edit.
 *   3. `pretooluse-markdown-commit-hard-wrap-guard.ts` — `git commit`, the boundary every authoring
 *      path converges on, whatever tool wrote the file.
 *
 * Splitting the detector three ways would let the surfaces disagree about what a wrap is, so they all
 * import from here: the joiner filter, the shape signature, the multiset diff and the escape marker.
 *
 * "Net-new" is the whole design. Measured over this repo's 1,114 tracked `.md` files, 17% are already
 * hard-wrapped; a check that fired on any wrap would fire on legacy debt the change did not create, and
 * a guard that cries wolf gets disabled. So every surface compares BEFORE against AFTER and reports
 * only the wraps the change added.
 */

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { computeJoinedWithNextLineMask } from "./gfm-unwrap.ts";
import { detectHardWraps, type WrapIssue } from "./hard-wrap-detector.ts";
import { hasMarkdownCommentInvokedEscapeHatchMarkerInMarkdownContent } from "./shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";

export type { WrapIssue } from "./hard-wrap-detector.ts";

export const MD_HARD_WRAP_OK_MARKER = "MD-HARD-WRAP-OK";

/** The repair command every surface names — one tool, resolvable from any repository. */
export const GFM_UNWRAP_COMMAND = `bun "$(cc-plugin-root itp-hooks)/scripts/gfm-unwrap.ts"`;

/** `.md` / `.markdown`, case-insensitive. */
export function isMarkdownFilePath(filePath: string): boolean {
  return /\.(?:md|markdown)$/i.test(filePath);
}

/**
 * True when the file opts out with the escape marker inside an HTML comment in live markdown. A token
 * in prose, backticks or a fence documents the hatch without switching anything off (issue #106).
 */
export function isMarkdownHardWrapCheckSuppressed(markdown: string): boolean {
  return hasMarkdownCommentInvokedEscapeHatchMarkerInMarkdownContent(markdown, {
    markerNameTokenIncludingSuffix: MD_HARD_WRAP_OK_MARKER,
  });
}

/**
 * The wraps in `text` that the JOINER would actually repair. The detector reads hand-aligned indented
 * blocks as wrapped prose; the joiner refuses to touch them, so reporting them would be a false
 * positive by construction (issue #106 finding 3). Fails toward REPORTING: a broken joiner must never
 * silence the detector.
 */
export function detectJoinerRepairableHardWraps(text: string): WrapIssue[] {
  const wraps = detectHardWraps(text);
  if (wraps.length === 0) return wraps;
  try {
    const joinedWithNext = computeJoinedWithNextLineMask(text);
    return wraps.filter((w) => joinedWithNext[w.line - 1] === true);
  } catch {
    return wraps;
  }
}

/**
 * A wrap's SHAPE, not its line number: an edit above it shifts every later line, so a line-number join
 * would report the whole tail of the file as new. Width + continuation text survives that shift.
 */
const wrapSignature = (w: WrapIssue): string => `${w.width}\0${w.nextPreview}`;

/** Multiset difference: the `after` wraps that were not already in `before`. */
export function wrapsAddedBetween(before: WrapIssue[], after: WrapIssue[]): WrapIssue[] {
  const remaining = new Map<string, number>();
  for (const w of before) {
    const k = wrapSignature(w);
    remaining.set(k, (remaining.get(k) ?? 0) + 1);
  }
  const added: WrapIssue[] = [];
  for (const w of after) {
    const k = wrapSignature(w);
    const n = remaining.get(k) ?? 0;
    if (n > 0) remaining.set(k, n - 1);
    else added.push(w);
  }
  return added;
}

/**
 * The wraps `after` added relative to `before`, whole-file on both sides so the fence scanner sees the
 * real state. `before === null` means there is no previous version (a new file): every wrap counts.
 * A file carrying the escape comment reports nothing.
 */
export function netNewMarkdownHardWraps(before: string | null, after: string): WrapIssue[] {
  if (isMarkdownHardWrapCheckSuppressed(after)) return [];
  const added = detectJoinerRepairableHardWraps(after);
  if (added.length === 0 || before === null) return added;
  return wrapsAddedBetween(detectJoinerRepairableHardWraps(before), added);
}

/** One file's verdict, for the multi-file surfaces (Bash watch, commit guard). */
export interface FileWrapReport {
  readonly path: string;
  readonly wraps: WrapIssue[];
}

/** The per-file lines of a multi-file report: at most `maxFiles` files, three wraps each. */
export function formatFileWrapReports(reports: readonly FileWrapReport[], maxFiles = 8): string[] {
  const lines: string[] = [];
  for (const r of reports.slice(0, maxFiles)) {
    lines.push(`  ${r.path} — ${r.wraps.length} new wrap(s)`);
    for (const w of r.wraps.slice(0, 3)) {
      lines.push(`    L${w.line}: ${w.width} cols → continues: "${w.nextPreview}"`);
    }
    if (r.wraps.length > 3) lines.push(`    …and ${r.wraps.length - 3} more.`);
  }
  if (reports.length > maxFiles) lines.push(`  …and ${reports.length - maxFiles} more file(s).`);
  return lines;
}

// ── git access — bounded, never throws ──────────────────────────────────────

const GIT_TIMEOUT_MS = 3_000;
const GIT_MAX_BUFFER = 64 * 1024 * 1024;
/** Above this a "markdown" file is generated data, not prose anyone authored. */
export const MAX_MARKDOWN_BYTES = 2 * 1024 * 1024;

function runGitBytes(cwd: string, args: string[], stdin?: string): Buffer | null {
  try {
    const p = Bun.spawnSync(["git", ...args], {
      cwd,
      stdin: stdin === undefined ? "ignore" : Buffer.from(stdin),
      stdout: "pipe",
      stderr: "ignore",
      timeout: GIT_TIMEOUT_MS,
      maxBuffer: GIT_MAX_BUFFER,
      env: { ...process.env, GIT_OPTIONAL_LOCKS: "0" },
    });
    if (p.exitCode !== 0) return null;
    return Buffer.from(p.stdout);
  } catch {
    return null;
  }
}

/** Run git; stdout on exit 0, null on anything else (not a repo, timeout, missing binary). */
export function runGit(cwd: string, args: string[]): string | null {
  const out = runGitBytes(cwd, args);
  return out ? out.toString("utf8") : null;
}

/** The repository root containing `dir`, or null. */
export function gitTopLevel(dir: string): string | null {
  const out = runGit(dir, ["rev-parse", "--show-toplevel"]);
  return out ? out.trim() || null : null;
}

/** Parse one `git cat-file --batch` header line: `<sha> <type> <size>`, or null for `missing`. */
function parseBatchHeader(header: string): { type: string; size: number } | null {
  const parts = header.split(" ");
  if (parts.length !== 3 || !/^[0-9a-f]+$/.test(parts[0]) || !/^\d+$/.test(parts[2])) return null;
  return { type: parts[1], size: Number(parts[2]) };
}

/**
 * Read several blobs in ONE `git cat-file --batch` process. Each spec is `<rev>:<path>` (`:<path>` is
 * the index). A missing object, or one larger than {@link MAX_MARKDOWN_BYTES}, maps to null.
 */
export function readGitBlobs(repoRoot: string, specs: readonly string[]): Map<string, string | null> {
  const result = new Map<string, string | null>();
  for (const s of specs) result.set(s, null);
  // cat-file reads one spec per line, so a path containing a newline cannot be asked for.
  const askable = specs.filter((s) => !s.includes("\n"));
  if (askable.length === 0) return result;
  const out = runGitBytes(repoRoot, ["cat-file", "--batch"], `${askable.join("\n")}\n`);
  if (!out) return result;
  let pos = 0;
  for (const spec of askable) {
    const nl = out.indexOf(0x0a, pos);
    if (nl === -1) break;
    const header = parseBatchHeader(out.subarray(pos, nl).toString());
    pos = nl + 1;
    if (!header) continue; // "<spec> missing" / "ambiguous": no body follows
    if (header.type === "blob" && header.size <= MAX_MARKDOWN_BYTES) {
      result.set(spec, out.subarray(pos, pos + header.size).toString("utf8"));
    }
    pos += header.size + 1; // body + its trailing newline
  }
  return result;
}

/** A regular file's text, or null (missing, FIFO, directory, too large, unreadable). */
export function readRegularTextFile(path: string): string | null {
  try {
    if (!existsSync(path)) return null;
    const st = statSync(path);
    if (!st.isFile() || st.size > MAX_MARKDOWN_BYTES) return null;
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

// ── per-session "already reported" cache ───────────────────────────────────

/**
 * Remembers which (file, content) pairs a session has already been told about, so a dirty file is not
 * re-reported after every later Bash call. Keyed by content hash: change the file again and it is
 * checked again. Best-effort — a cache that cannot be read or written means a possible repeat, never a
 * missed report.
 */
export function contentHash(text: string): string {
  return createHash("sha256").update(text).digest("hex").slice(0, 16);
}

function cachePath(sessionId: string): string {
  const safe = sessionId.replace(/[^A-Za-z0-9_-]/g, "") || "no-session";
  return join(tmpdir(), "itp-hooks-md-hard-wrap", `${safe}.json`);
}

export function loadSeenMarkdownContent(sessionId: string): Record<string, string> {
  try {
    const parsed: unknown = JSON.parse(readFileSync(cachePath(sessionId), "utf8"));
    return parsed && typeof parsed === "object" ? (parsed as Record<string, string>) : {};
  } catch {
    return {};
  }
}

export function recordSeenMarkdownContent(sessionId: string, entries: Record<string, string>): void {
  if (Object.keys(entries).length === 0) return;
  try {
    const p = cachePath(sessionId);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, JSON.stringify({ ...loadSeenMarkdownContent(sessionId), ...entries }));
  } catch {
    // best-effort, see above
  }
}
