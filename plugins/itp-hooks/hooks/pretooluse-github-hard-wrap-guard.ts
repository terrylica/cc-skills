#!/usr/bin/env bun
/**
 * PreToolUse hook: GitHub hard-wrap guard.
 *
 * Blocks GitHub-bound prose text (`gh` commands that publish to GFM-rendering
 * surfaces) when hard-wrapped at a fixed column width. GFM renders every `\n`
 * as an HTML `<br>`, so prose wrapped at ~100 columns becomes columns of short
 * mid-sentence lines instead of paragraphs that reflow to the reader's window.
 *
 * Interception points (see survey in the directive):
 *   - `gh release create|edit` → measure inline --notes / --notes-file text
 *   - `gh issue create` → measure inline --body / -b text
 *   - `gh issue edit` → measure inline --body text
 *   - `gh issue comment` → measure inline --body / -b text
 *   - `gh pr create` → measure inline --body / -b text
 *   - `gh pr edit` → measure inline --body text
 *   - `gh pr comment` → measure inline --body / -b text
 *   - `gh api` writing to a releases/issues/pulls endpoint → measure the
 *     `body=`/`notes=` field, or the `.body` of an `--input` JSON envelope
 *
 * GFM hard-break surfaces:
 *   ✓ release notes, issue body, PR body, issue comments, PR comments
 *   ✗ gist descriptions, repo descriptions (both plain-text, not GFM)
 *   ✗ git objects — commit messages and annotated tag messages
 *
 * Do not extend this guard to `git commit` or `git tag`. A git object is not a
 * GFM surface, and hard wrapping at 72 columns is the correct git convention.
 * The reflow belongs at the PUBLISH boundary, which is exactly what this guard
 * covers: a release built from hard-wrapped commit bodies must be reflowed on
 * its way into `--notes`/`--notes-file`, not by rewriting the commits.
 *
 * Output: PreToolUse `deny` with a reminder listing the offending lines and the
 * single fix. Escape hatch: `GH-HARD-WRAP-OK` anywhere in the command.
 *
 * Fail-open everywhere: any parse/read/logic error → allow (never blocks real
 * work). A missing/unreadable notes-file or body-file is skipped, not blocked.
 *
 * Doctrine SSoT: ~/~/.claude/release-notes-doctrine-CLAUDE.md (release-notes section)
 * Operator directive: hard-wrapped prose must never be published to GitHub
 */

import { existsSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";
import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import { detectHardWraps, type WrapIssue } from "./lib/hard-wrap-detector.ts";
import { extractFlagValues, extractHeredocs, type Heredoc } from "./lib/shell-arg-extractor.ts";

const HOOK_NAME = "github-hard-wrap-guard";

/**
 * File-wide escape hatch: GH-HARD-WRAP-OK anywhere in the command.
 * No reason required (bare marker OK) — the guard's purpose is simple enough.
 */
const HARD_WRAP_OK = {
  markerNameTokenIncludingSuffix: "GH-HARD-WRAP-OK",
  windowSemanticsMode: "FILE_WIDE" as const,
  caseSensitivityMode: "CASE_SENSITIVE" as const,
} as const;

/** Expand a leading `~` and resolve a file path relative to the tool cwd. */
function resolveFilePath(rawPath: string, cwd: string | undefined): string {
  let p = rawPath;
  if (p === "~") p = homedir();
  else if (p.startsWith("~/")) p = `${homedir()}/${p.slice(2)}`;
  if (isAbsolute(p)) return p;
  const base = cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  return resolve(base, p);
}

/**
 * Match the verb as an ADJACENT token sequence (`gh release create`), never as
 * independent substrings anywhere in the command.
 *
 * Testing `/\bgh\s/` and `/\brelease\s+(create|edit)/` separately makes any
 * command that merely MENTIONS the pattern a match — writing documentation
 * about this guard, grepping for it, or committing a message that quotes it.
 * The sibling release-notes-extensiveness-guard has that flaw and blocked a
 * `cat >> notes.md` heredoc whose prose quoted the command it watches for.
 */
const adjacent = (noun: string, verbs: string) =>
  new RegExp(String.raw`\bgh\s+${noun}\s+(?:${verbs})\b`, "i");

const GH_RELEASE = adjacent("release", "create|edit");
const GH_ISSUE = adjacent("issue", "create|edit|comment");
/**
 * `review` is here because `gh pr review` takes `-b/--body` and `-F/--body-file`
 * and publishes to a full GFM surface. It was missing until 2026-08-24, when an
 * adversarial sweep denied the identical body under `pr create` and allowed it
 * under `pr review`.
 */
const GH_PR = adjacent("pr", "create|edit|comment|review");

/** True when the command is a `gh release` create or edit. */
function isGhReleaseCommand(command: string): boolean {
  return GH_RELEASE.test(command);
}

/** True when the command is a `gh issue` command (create/edit/comment). */
function isGhIssueCommand(command: string): boolean {
  return GH_ISSUE.test(command);
}

/** True when the command is a `gh pr` command (create/edit/comment). */
function isGhPrCommand(command: string): boolean {
  return GH_PR.test(command);
}

/**
 * `gh api` writing to a release / issue / pull endpoint.
 *
 * This is the bypass that makes the rest of the guard optional if left open:
 * `gh api repos/o/r/releases -X POST -f body='<wrapped>'` publishes exactly the
 * same body to exactly the same GFM surface, and matches none of the porcelain
 * patterns above. Measured before the fix: `allow` for a body that
 * `gh release create` denied.
 */
const GH_API = /\bgh\s+api\b/i;
const GH_API_WRITE_TARGET = /\/(releases|issues|pulls)\b/i;
const GH_API_MUTATING_METHOD = /(?:-X|--method)\s+(?:POST|PATCH|PUT)\b/i;

function isGhApiWrite(command: string): boolean {
  if (!GH_API.test(command) || !GH_API_WRITE_TARGET.test(command)) return false;
  // An explicit mutating method, OR any field flag — `gh api` implies POST as
  // soon as a field is supplied, so `-f body=…` with no `-X` still writes.
  //
  // `--input` belongs in this list for the same reason and was missing: `gh api
  // repos/o/r/issues --input payload.json` silently becomes a POST, and the
  // guard treated it as a read. Verified 2026-08-24 — identical payload allowed
  // without `-X POST` and denied with it.
  return (
    GH_API_MUTATING_METHOD.test(command) ||
    /\s(?:-f|-F|--field|--raw-field)[=\s]/.test(command) ||
    /\s--input[=\s]/.test(command)
  );
}

/**
 * Read a file's text ONLY when it is a regular file.
 *
 * `Bun.file(p).text()` on a FIFO blocks until a writer appears, which for
 * `--notes-file <(cat x)` or `--notes-file /dev/stdin` means the hook hangs
 * until Claude Code's 5s timeout kills it. A guard that can hang is a guard
 * that gets removed. Anything not a regular file is skipped — fail-open.
 */
/**
 * `gh api` body fields, e.g. `-f body="…"` / `--field notes='…'`.
 *
 * The shared shell-arg extractor cannot do this: it splits on whitespace and
 * only honours a quote that OPENS the value, whereas here the value is
 * `body="…"` — the quote arrives after the `key=` prefix, so the extractor
 * returned `body="This` and the whole bypass stayed open.
 */
function extractGhApiBodyFields(command: string): { field: string; text: string }[] {
  // Three quoting shapes, all of which `gh` accepts identically:
  //   -f body="…"     quote AFTER the key   (the original case)
  //   -f "body=…"     quote BEFORE the key  (missed until 2026-08-24)
  //   -f body=…       bare
  // The quote-before-key form was a silent bypass: the pattern demanded a
  // literal `body=` immediately after the flag separator, so a leading quote
  // made the whole field invisible.
  const pattern =
    /(?:^|\s)(?:-f|-F|--field|--raw-field)[=\s]+(?:"(body|notes?)=([\s\S]*?)"|'(body|notes?)=([\s\S]*?)'|(body|notes?)=(?:"([\s\S]*?)"|'([\s\S]*?)'|(\S+)))/gi;
  const found: { field: string; text: string }[] = [];
  let m: RegExpExecArray | null = pattern.exec(command);
  while (m !== null) {
    const field = m[1] ?? m[3] ?? m[5] ?? "body";
    const text = m[2] ?? m[4] ?? m[6] ?? m[7] ?? m[8] ?? "";
    found.push({ field, text });
    m = pattern.exec(command);
  }
  return found;
}

/**
 * `gh api -F body=@path` reads the field value FROM A FILE (`@-` means stdin).
 * Without this the extractor captured the literal string `@/tmp/body.md`,
 * measured zero wraps in a 15-character path, and allowed the publish.
 */
const FIELD_FILE_VALUE = /^@(.*)$/;

/** The `body` string from a `gh api --input` JSON envelope, or null. */
function extractJsonBodyField(raw: string): string | null {
  try {
    const parsed: unknown = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      const body = (parsed as Record<string, unknown>).body;
      if (typeof body === "string") return body;
    }
  } catch {
    // Not JSON we understand → skip, never block.
  }
  return null;
}

async function readRegularFileText(resolvedPath: string): Promise<string | null> {
  try {
    if (!existsSync(resolvedPath)) return null;
    if (!statSync(resolvedPath).isFile()) return null;
    return await Bun.file(resolvedPath).text();
  } catch {
    return null; // unreadable → skip, never block
  }
}

interface TextSource {
  label: string;
  text: string;
  issues: WrapIssue[];
}

/**
 * ════════════════════════════════════════════════════════════════════════
 *  The same-command write, and why reading the path is not enough
 * ════════════════════════════════════════════════════════════════════════
 *
 * A PreToolUse hook is handed a command STRING. It is not handed the
 * filesystem that command is about to create. The dominant way an agent
 * publishes prose is to write the body and publish it in ONE Bash call:
 *
 *     cat > /tmp/body.md <<'EOF'
 *     …prose…
 *     EOF
 *     gh issue comment 8 --body-file /tmp/body.md
 *
 * At hook time `/tmp/body.md` does not exist, `readRegularFileText` returns
 * null, and this guard allowed it. Measured on 2026-08-24: an 88-line
 * hard-wrapped comment was published to a live repository through exactly this
 * path, and the guard reported `allow`.
 *
 * Two repairs, in order of preference:
 *
 *   1. If the command carries a heredoc redirected INTO the path being
 *      published, measure that heredoc body. This is exact — the text is right
 *      there in the command string.
 *   2. If the path is missing AND the command demonstrably writes to it by some
 *      means this parser cannot read (printf, tee, a script), refuse rather
 *      than fail open, and say how to make the text visible: write the file in
 *      a SEPARATE Bash call. Fail-open is correct for a hook that cannot tell
 *      whether there is a problem; it is not correct for a hook that can see
 *      the problem being hidden from it.
 */

/** Resolve a redirect target the same way a `--body-file` path is resolved. */
function sameResolvedPath(a: string, b: string, cwd: string | undefined): boolean {
  return resolveFilePath(a, cwd) === resolveFilePath(b, cwd);
}

/**
 * The heredoc whose body will become the file at `rawPath`, if the command
 * contains one.
 */
function heredocWritingTo(
  heredocs: readonly Heredoc[],
  rawPath: string,
  cwd: string | undefined,
): Heredoc | undefined {
  return heredocs.find(
    (h) => h.redirectTarget !== null && sameResolvedPath(h.redirectTarget, rawPath, cwd),
  );
}

/**
 * Positive evidence that the command writes to `rawPath` itself — a redirect,
 * a `tee`, or an `-o`/`--output` naming it. Used only to decide whether a
 * MISSING file is being hidden from the guard or is simply a stale argument.
 */
function commandWritesTo(command: string, rawPath: string): boolean {
  const escaped = rawPath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const patterns = [
    new RegExp(String.raw`>>?\s*["']?${escaped}["']?`),
    new RegExp(String.raw`\btee\s+(?:-a\s+)?["']?${escaped}["']?`),
    new RegExp(String.raw`(?:-o|--output)[=\s]+["']?${escaped}["']?`),
  ];
  return patterns.some((p) => p.test(command));
}

/**
 * A body file the guard could not read, that the command itself creates.
 * Collected so the reminder can name the exact path and flag.
 */
interface UnreadableWrittenFile {
  readonly flag: string;
  readonly rawPath: string;
}

interface ResolvedBodyText {
  /** The text, when it could be obtained. */
  readonly text: string | null;
  /** How it was obtained, for the reminder's label. */
  readonly origin: "disk" | "heredoc";
  /** The file is missing AND this command writes it by an unreadable means. */
  readonly hiddenFromGuard: boolean;
}

/**
 * Obtain the text a `--body-file` / `--notes-file` / `--input` flag points at,
 * from the filesystem when it already exists and from the command's own
 * heredoc when the command is about to create it.
 */
async function resolveBodyText(
  rawPath: string,
  command: string,
  heredocs: readonly Heredoc[],
  cwd: string | undefined,
): Promise<ResolvedBodyText> {
  const onDisk = await readRegularFileText(resolveFilePath(rawPath, cwd));
  if (onDisk !== null) return { text: onDisk, origin: "disk", hiddenFromGuard: false };

  const heredoc = heredocWritingTo(heredocs, rawPath, cwd);
  if (heredoc) return { text: heredoc.body, origin: "heredoc", hiddenFromGuard: false };

  return { text: null, origin: "disk", hiddenFromGuard: commandWritesTo(command, rawPath) };
}

/**
 * A path expressed as a shell variable — `--body-file "$BF"`. The extractor
 * deliberately does not expand variables, so the raw value is the literal
 * `$BF`. Resolve it from a `BF=…` assignment earlier in the SAME command,
 * which is the only assignment the guard can see.
 */
function resolveShellVariablePath(rawPath: string, command: string): string | null {
  const name = /^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$/.exec(rawPath)?.[1];
  if (name === undefined) return null;
  const assignment = new RegExp(String.raw`(?:^|[\s;&(])${name}=("([^"]*)"|'([^']*)'|([^\s;&|]+))`).exec(
    command,
  );
  if (!assignment) return null;
  return assignment[2] ?? assignment[3] ?? assignment[4] ?? null;
}

/**
 * An inline body whose ENTIRE value is a command substitution reading a file:
 * `--body "$(cat notes.md)"`, `--body "$(< notes.md)"`, `` --body "`cat f`" ``.
 *
 * The shell-arg extractor copies substitutions in verbatim rather than
 * expanding them, so the guard was measuring the 18-character string
 * `$(cat /tmp/body.md)` and finding no wraps in it. Returns the path the
 * substitution reads, so the caller can measure the real body.
 *
 * Deliberately anchored: a body that merely CONTAINS a `$(…)` is prose and is
 * measured as prose. Only a value that is nothing but the substitution is a
 * file reference.
 */
function fileReadSubstitutionPath(value: string): string | null {
  const v = value.trim();
  const m =
    /^\$\(\s*(?:cat|<)\s+(?:"([^"]+)"|'([^']+)'|(\S+?))\s*\)$/.exec(v) ??
    /^`\s*cat\s+(?:"([^"]+)"|'([^']+)'|(\S+?))\s*`$/.exec(v);
  if (!m) return null;
  return m[1] ?? m[2] ?? m[3] ?? null;
}

/** True when the value is ENTIRELY an unexpanded substitution or variable. */
function isWhollyUnexpanded(value: string): boolean {
  const v = value.trim();
  return /^\$\(.*\)$/.test(v) || /^`.*`$/.test(v) || /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$/.test(v);
}

/** Build a user-facing reminder message for hard-wrapped text. */
function buildHardWrapReminder(sources: TextSource[]): string {
  const sourcesWithIssues = sources.filter((s) => s.issues.length > 0);
  if (sourcesWithIssues.length === 0) return "";

  const totalIssues = sourcesWithIssues.reduce((sum, s) => sum + s.issues.length, 0);

  const lines: string[] = [
    "[GH-HARD-WRAP-GUARD] This text contains hard-wrapped prose, which will render as columns of short lines on GitHub.",
    "",
    "Why: GitHub Flavored Markdown renders every newline as `<br>`. A paragraph wrapped at ~100",
    "columns becomes columns of short mid-sentence lines instead of reflowing to the reader's window.",
    "",
    "Affected text (showing first 2 sources, first 2 wraps per source):",
  ];

  for (const src of sourcesWithIssues.slice(0, 2)) {
    lines.push(``, `  ${src.label}:`);
    for (const w of src.issues.slice(0, 2)) {
      lines.push(`    L${w.line}: ${w.width} cols → continues: "${w.nextPreview}"`);
    }
    if (src.issues.length > 2) {
      lines.push(`    …and ${src.issues.length - 2} more wrapped line(s).`);
    }
  }

  if (sourcesWithIssues.length > 2) {
    lines.push(``, `  …and ${sourcesWithIssues.length - 2} more source(s) with wraps.`);
  }

  lines.push(
    "",
    "Fix: author each PARAGRAPH as ONE unbroken line. Let GitHub reflow it to the reader's window.",
    "Keep only intentional breaks (list items, headings, code blocks, blank lines).",
    "",
    "Or repair an existing file mechanically (joins lines only; refuses to run if content would change):",
    '  bun "$(cc-plugin-root itp-hooks)/scripts/gfm-unwrap.ts" <file>',
    '  bun "$(cc-plugin-root itp-hooks)/scripts/gfm-unwrap.ts" --check <file>   # just report',
    "",
    "Override (rare — e.g. an intentional code sample): add GH-HARD-WRAP-OK anywhere in the command.",
  );

  return lines.join("\n");
}

/**
 * The reminder for a body the guard could not see because this same command
 * creates it.
 *
 * This is deliberately a DENY and not a silent allow. Fail-open is right when a
 * guard cannot tell whether there is a problem; it is wrong when the guard can
 * see that the evidence is being created after it has looked. The remedy asked
 * for is trivial and always available: two Bash calls instead of one.
 */
function buildUnreadableReminder(unreadable: readonly UnreadableWrittenFile[]): string {
  return [
    "[GH-HARD-WRAP-GUARD] This command writes the body file and publishes it in ONE step, so the",
    "text cannot be checked for hard wrapping before it reaches GitHub.",
    "",
    ...unreadable.map((u) => `  ${u.flag} "${u.rawPath}" — does not exist yet; this command creates it.`),
    "",
    "Why it matters: GitHub Flavored Markdown renders every newline inside a paragraph as `<br>`.",
    "Prose wrapped at ~100 columns is frozen at that width and cannot reflow to the reader's window.",
    "",
    "Fix: split it into TWO Bash calls — write the file first, then publish it. The guard reads the",
    "file on the second call and can then vouch for it.",
    "",
    "  call 1:  cat > /tmp/body.md <<'EOF'  …  EOF",
    "  call 2:  gh issue comment N --body-file /tmp/body.md",
    "",
    "A heredoc redirected straight into the published path IS readable and needs no split — this",
    "message means the write used a form the guard cannot parse (printf, tee, a script).",
    "",
    "Override: add GH-HARD-WRAP-OK anywhere in the command.",
  ].join("\n");
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow(HOOK_NAME);
  if (!input) return;

  const { tool_name, tool_input = {} } = input;
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";
  if (!command.trim()) {
    allow();
    return;
  }

  // Operator escape hatch.
  if (hasFileWideEscapeHatchMarkerInContent(command, HARD_WRAP_OK)) {
    allow();
    return;
  }

  // Fast path: if none of the target patterns match, no guard needed.
  if (
    !isGhReleaseCommand(command) &&
    !isGhIssueCommand(command) &&
    !isGhPrCommand(command) &&
    !isGhApiWrite(command)
  ) {
    allow();
    return;
  }

  const sources: TextSource[] = [];
  const unreadable: UnreadableWrittenFile[] = [];
  const cwd = input.cwd;
  const heredocs = extractHeredocs(command);

  /** The heredoc feeding a command's stdin — no redirect target of its own. */
  const stdinHeredoc = () => heredocs.find((h) => h.redirectTarget === null)?.body ?? null;

  /** Measure one file-valued flag, from disk or from the command's heredoc. */
  const measureFileFlag = async (flag: string, rawValue: string): Promise<void> => {
    // `-` is stdin, which on these command shapes is a heredoc in the command.
    if (rawValue === "-" || rawValue === "/dev/stdin") {
      const piped = stdinHeredoc();
      if (piped === null) return;
      const issues = detectHardWraps(piped);
      if (issues.length > 0)
        sources.push({ label: `${flag} - (heredoc on stdin)`, text: piped, issues });
      return;
    }

    // `--body-file "$BF"` — resolve from an assignment in the same command.
    const rawPath = resolveShellVariablePath(rawValue, command) ?? rawValue;

    const resolved = await resolveBodyText(rawPath, command, heredocs, cwd);
    if (resolved.text === null) {
      if (resolved.hiddenFromGuard) unreadable.push({ flag, rawPath });
      return;
    }
    const issues = detectHardWraps(resolved.text);
    if (issues.length === 0) return;
    const via = resolved.origin === "heredoc" ? " (via the heredoc in this command)" : "";
    sources.push({ label: `${flag} "${rawPath}"${via}`, text: resolved.text, issues });
  };

  /**
   * Measure one `gh api` body/notes field, following `@path` to the file whose
   * contents `gh` will send.
   */
  const measureApiField = async (field: string, text: string): Promise<void> => {
    const filePath = FIELD_FILE_VALUE.exec(text)?.[1];
    if (filePath !== undefined) {
      await measureFileFlag(`gh api -F ${field}=@`, filePath === "-" ? "-" : filePath);
      return;
    }
    const issues = detectHardWraps(text);
    if (issues.length > 0) sources.push({ label: `gh api -f ${field}=`, text, issues });
  };

  /**
   * Measure an INLINE flag value, following it through a whole-value command
   * substitution (`--body "$(cat notes.md)"`) to the file it reads.
   */
  const measureInlineFlag = async (flag: string, value: string): Promise<void> => {
    const substitutionPath = fileReadSubstitutionPath(value);
    if (substitutionPath !== null) {
      await measureFileFlag(`${flag} $(cat …)`, substitutionPath);
      return;
    }
    if (isWhollyUnexpanded(value)) return; // a variable the guard cannot see
    const issues = detectHardWraps(value);
    if (issues.length > 0) sources.push({ label: `${flag} (inline)`, text: value, issues });
  };

  // ---- gh release create|edit: --notes / --notes-file ----
  if (isGhReleaseCommand(command)) {
    for (const notes of extractFlagValues(command, ["--notes", "-n"])) {
      await measureInlineFlag("--notes", notes);
    }

    for (const rawPath of extractFlagValues(command, ["--notes-file", "-F"])) {
      await measureFileFlag("--notes-file", rawPath);
    }
  }

  // ---- gh issue/pr create|edit|comment|review: --body / -b / --body-file ----
  if (isGhIssueCommand(command) || isGhPrCommand(command)) {
    for (const body of extractFlagValues(command, ["--body", "-b"])) {
      await measureInlineFlag("--body", body);
    }

    // `-F` is the documented short form of `--body-file` for issue and pr
    // (`gh issue create --help`: "-F, --body-file file"). Omitting it was a
    // silent bypass: the same file denied under --body-file and allowed under
    // -F. It cannot collide here — `-F` means --notes-file only for `gh
    // release` and --field only for `gh api`, both handled in other branches.
    for (const rawPath of extractFlagValues(command, ["--body-file", "-F"])) {
      await measureFileFlag("--body-file", rawPath);
    }
  }

  // ---- gh api: -f/--field/-F/--raw-field body=… ----
  if (isGhApiWrite(command)) {
    for (const f of extractGhApiBodyFields(command)) await measureApiField(f.field, f.text);

    const inputPaths = extractFlagValues(command, ["--input"]);
    for (const rawPath of inputPaths) {
      // `--input -` reads stdin, which on this command shape is a heredoc fed
      // straight to gh. That heredoc carries no redirect target, so match it by
      // its position rather than by path.
      const raw =
        rawPath === "-"
          ? stdinHeredoc()
          : (await resolveBodyText(resolveShellVariablePath(rawPath, command) ?? rawPath, command, heredocs, cwd))
              .text;
      if (raw === null) continue;
      // The payload is a JSON envelope; measure its body field, not the JSON.
      const body = extractJsonBodyField(raw);
      if (body === null) continue;
      const issues = detectHardWraps(body);
      if (issues.length > 0)
        sources.push({ label: `gh api --input "${rawPath}" (.body)`, text: body, issues });
    }
  }

  // A measured wrap outranks an unmeasurable body: report the concrete defect.
  if (sources.length > 0) {
    deny(buildHardWrapReminder(sources));
    return;
  }

  if (unreadable.length > 0) {
    deny(buildUnreadableReminder(unreadable));
    return;
  }

  allow();
}

main().catch((err) => {
  trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
  allow();
});
