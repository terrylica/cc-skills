/**
 * Collect the prose bodies a `gh` command is about to publish to a GFM surface.
 *
 * WHY THIS IS A SHARED LIB AND NOT A COPY
 *
 * Answering "what text will this command put on GitHub?" is deceptively hard, and
 * `pretooluse-github-hard-wrap-guard` paid for the answer one bypass at a time. Every branch
 * below exists because a real command published real text past a guard that looked complete:
 *
 *   - `gh api -f body=…` — the porcelain patterns miss it entirely
 *   - `-f "body=…"` vs `-f body="…"` — the quote lands on either side of the `key=`
 *   - `-F body=@path` — the value is a FILE, not the literal string `@/tmp/body.md`
 *   - `gh api --input payload.json` — implies POST with no `-X`, and the prose is `.body`
 *   - `gh pr review -b` — full GFM surface, absent from the verb list until an adversarial sweep
 *   - `--body "$(cat notes.md)"` — the extractor copies substitutions verbatim, so the guard
 *     was measuring an 18-character string
 *   - `--body-file "$BF"` — a variable the extractor deliberately does not expand
 *   - write-and-publish in ONE Bash call — at hook time the file does not exist
 *
 * A second guard that re-implements this inherits all eight bypasses on day one. So the
 * collection is here, once, and each guard supplies only its own PREDICATE over the collected
 * text. Extracted 2026-09-02 when the PR-citation guard needed the same answer.
 *
 * This module deliberately does NOT judge the text. It returns what will be published and where
 * it came from; deciding whether that text is acceptable belongs to the caller.
 */

import { existsSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";
import { extractFlagValues, extractHeredocs, type Heredoc } from "./shell-arg-extractor.ts";

/** One body the command will publish, with a human-readable label naming its origin. */
export interface CollectedBody {
  /** e.g. `--body (inline)`, `--body-file "/tmp/b.md"`, `gh api -f body=` */
  readonly label: string;
  /** The prose itself. */
  readonly text: string;
}

/**
 * A body file the collector could not read because THIS command creates it.
 *
 * Reported separately so a caller can decide its own policy. The hard-wrap guard denies on it
 * (fail-open is right when a guard cannot tell whether there is a problem; it is wrong when the
 * guard can see the evidence being created after it looked). A softer guard may prefer to allow.
 */
export interface UnreadableWrittenFile {
  readonly flag: string;
  readonly rawPath: string;
}

export interface CollectedBodies {
  readonly bodies: readonly CollectedBody[];
  readonly unreadable: readonly UnreadableWrittenFile[];
  /** True when the command publishes to any GFM surface at all. */
  readonly isPublishingCommand: boolean;
}

/** Expand a leading `~` and resolve a file path relative to the tool cwd. */
export function resolveFilePath(rawPath: string, cwd: string | undefined): string {
  let p = rawPath;
  if (p === "~") p = homedir();
  else if (p.startsWith("~/")) p = `${homedir()}/${p.slice(2)}`;
  if (isAbsolute(p)) return p;
  const base = cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  return resolve(base, p);
}

/**
 * Match the verb as an ADJACENT token sequence (`gh release create`), never as independent
 * substrings anywhere in the command.
 *
 * Testing `/\bgh\s/` and `/\brelease\s+(create|edit)/` separately makes any command that merely
 * MENTIONS the pattern a match — writing documentation about a guard, grepping for it, or
 * committing a message that quotes it.
 */
const adjacent = (noun: string, verbs: string) =>
  new RegExp(String.raw`\bgh\s+${noun}\s+(?:${verbs})\b`, "i");

const GH_RELEASE = adjacent("release", "create|edit");
const GH_ISSUE = adjacent("issue", "create|edit|comment");
/** `gh pr review` takes `-b/--body` and `-F/--body-file` and publishes to a full GFM surface. */
const GH_PR = adjacent("pr", "create|edit|comment|review");

export const isGhReleaseCommand = (command: string): boolean => GH_RELEASE.test(command);
export const isGhIssueCommand = (command: string): boolean => GH_ISSUE.test(command);
export const isGhPrCommand = (command: string): boolean => GH_PR.test(command);

const GH_API = /\bgh\s+api\b/i;
const GH_API_WRITE_TARGET = /\/(releases|issues|pulls)\b/i;
const GH_API_MUTATING_METHOD = /(?:-X|--method)\s+(?:POST|PATCH|PUT)\b/i;

/**
 * `gh api` writing to a release / issue / pull endpoint — the bypass that makes every porcelain
 * pattern optional if left open.
 */
export function isGhApiWrite(command: string): boolean {
  if (!GH_API.test(command) || !GH_API_WRITE_TARGET.test(command)) return false;
  // An explicit mutating method, OR any field flag — `gh api` implies POST as soon as a field is
  // supplied. `--input` belongs here for the same reason: it silently becomes a POST.
  return (
    GH_API_MUTATING_METHOD.test(command) ||
    /\s(?:-f|-F|--field|--raw-field)[=\s]/.test(command) ||
    /\s--input[=\s]/.test(command)
  );
}

/** True when the command publishes prose to any GFM surface. */
export function isGitHubPublishingCommand(command: string): boolean {
  return (
    isGhReleaseCommand(command) ||
    isGhIssueCommand(command) ||
    isGhPrCommand(command) ||
    isGhApiWrite(command)
  );
}

/**
 * `gh api` body fields, e.g. `-f body="…"` / `--field notes='…'`.
 *
 * The shared shell-arg extractor cannot do this: it splits on whitespace and only honours a quote
 * that OPENS the value, whereas here the value is `body="…"` — the quote arrives after the `key=`
 * prefix.
 */
export function extractGhApiBodyFields(command: string): { field: string; text: string }[] {
  // Three quoting shapes, all of which `gh` accepts identically:
  //   -f body="…"     quote AFTER the key
  //   -f "body=…"     quote BEFORE the key  (a silent bypass until 2026-08-24)
  //   -f body=…       bare
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

/** `gh api -F body=@path` reads the field value FROM A FILE (`@-` means stdin). */
const FIELD_FILE_VALUE = /^@(.*)$/;

/** The `body` string from a `gh api --input` JSON envelope, or null. */
export function extractJsonBodyField(raw: string): string | null {
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

/**
 * Read a file's text ONLY when it is a regular file.
 *
 * `Bun.file(p).text()` on a FIFO blocks until a writer appears, which for `--notes-file <(cat x)`
 * or `--notes-file /dev/stdin` means the hook hangs until Claude Code's timeout kills it. A guard
 * that can hang is a guard that gets removed.
 */
async function readRegularFileText(resolvedPath: string): Promise<string | null> {
  try {
    if (!existsSync(resolvedPath)) return null;
    if (!statSync(resolvedPath).isFile()) return null;
    return await Bun.file(resolvedPath).text();
  } catch {
    return null; // unreadable → skip, never block
  }
}

function sameResolvedPath(a: string, b: string, cwd: string | undefined): boolean {
  return resolveFilePath(a, cwd) === resolveFilePath(b, cwd);
}

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
 * Positive evidence that the command writes to `rawPath` itself — a redirect, a `tee`, or an
 * `-o`/`--output` naming it. Used only to decide whether a MISSING file is being hidden from the
 * collector or is simply a stale argument.
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

interface ResolvedBodyText {
  readonly text: string | null;
  readonly origin: "disk" | "heredoc";
  readonly hiddenFromCollector: boolean;
}

/**
 * Obtain the text a `--body-file` / `--notes-file` / `--input` flag points at, from the
 * filesystem when it already exists and from the command's own heredoc when the command is about
 * to create it.
 */
async function resolveBodyText(
  rawPath: string,
  command: string,
  heredocs: readonly Heredoc[],
  cwd: string | undefined,
): Promise<ResolvedBodyText> {
  const onDisk = await readRegularFileText(resolveFilePath(rawPath, cwd));
  if (onDisk !== null) return { text: onDisk, origin: "disk", hiddenFromCollector: false };

  const heredoc = heredocWritingTo(heredocs, rawPath, cwd);
  if (heredoc) return { text: heredoc.body, origin: "heredoc", hiddenFromCollector: false };

  return { text: null, origin: "disk", hiddenFromCollector: commandWritesTo(command, rawPath) };
}

/**
 * A path expressed as a shell variable — `--body-file "$BF"`. The extractor deliberately does not
 * expand variables, so resolve it from a `BF=…` assignment earlier in the SAME command.
 */
function resolveShellVariablePath(rawPath: string, command: string): string | null {
  const name = /^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$/.exec(rawPath)?.[1];
  if (name === undefined) return null;
  const assignment = new RegExp(
    String.raw`(?:^|[\s;&(])${name}=("([^"]*)"|'([^']*)'|([^\s;&|]+))`,
  ).exec(command);
  if (!assignment) return null;
  return assignment[2] ?? assignment[3] ?? assignment[4] ?? null;
}

/**
 * An inline body whose ENTIRE value is a command substitution reading a file:
 * `--body "$(cat notes.md)"`, `--body "$(< notes.md)"`, `` --body "`cat f`" ``.
 *
 * Deliberately anchored: a body that merely CONTAINS a `$(…)` is prose and is treated as prose.
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

/**
 * Collect every prose body the command will publish to GitHub.
 *
 * Returns `isPublishingCommand: false` with empty lists when the command targets no GFM surface,
 * so a caller can fast-path out without repeating the verb matching.
 */
export async function collectGitHubPublishedBodies(
  command: string,
  cwd: string | undefined,
): Promise<CollectedBodies> {
  if (!isGitHubPublishingCommand(command)) {
    return { bodies: [], unreadable: [], isPublishingCommand: false };
  }

  const bodies: CollectedBody[] = [];
  const unreadable: UnreadableWrittenFile[] = [];
  const heredocs = extractHeredocs(command);

  /** The heredoc feeding a command's stdin — no redirect target of its own. */
  const stdinHeredoc = () => heredocs.find((h) => h.redirectTarget === null)?.body ?? null;

  const collectFileFlag = async (flag: string, rawValue: string): Promise<void> => {
    if (rawValue === "-" || rawValue === "/dev/stdin") {
      const piped = stdinHeredoc();
      if (piped === null) return;
      bodies.push({ label: `${flag} - (heredoc on stdin)`, text: piped });
      return;
    }

    const rawPath = resolveShellVariablePath(rawValue, command) ?? rawValue;
    const resolved = await resolveBodyText(rawPath, command, heredocs, cwd);
    if (resolved.text === null) {
      if (resolved.hiddenFromCollector) unreadable.push({ flag, rawPath });
      return;
    }
    const via = resolved.origin === "heredoc" ? " (via the heredoc in this command)" : "";
    bodies.push({ label: `${flag} "${rawPath}"${via}`, text: resolved.text });
  };

  const collectApiField = async (field: string, text: string): Promise<void> => {
    const filePath = FIELD_FILE_VALUE.exec(text)?.[1];
    if (filePath !== undefined) {
      await collectFileFlag(`gh api -F ${field}=@`, filePath === "-" ? "-" : filePath);
      return;
    }
    bodies.push({ label: `gh api -f ${field}=`, text });
  };

  const collectInlineFlag = async (flag: string, value: string): Promise<void> => {
    const substitutionPath = fileReadSubstitutionPath(value);
    if (substitutionPath !== null) {
      await collectFileFlag(`${flag} $(cat …)`, substitutionPath);
      return;
    }
    if (isWhollyUnexpanded(value)) return; // a variable the collector cannot see
    bodies.push({ label: `${flag} (inline)`, text: value });
  };

  if (isGhReleaseCommand(command)) {
    for (const notes of extractFlagValues(command, ["--notes", "-n"])) {
      await collectInlineFlag("--notes", notes);
    }
    for (const rawPath of extractFlagValues(command, ["--notes-file", "-F"])) {
      await collectFileFlag("--notes-file", rawPath);
    }
  }

  if (isGhIssueCommand(command) || isGhPrCommand(command)) {
    for (const body of extractFlagValues(command, ["--body", "-b"])) {
      await collectInlineFlag("--body", body);
    }
    // `-F` is the documented short form of `--body-file` for issue and pr. Omitting it was a
    // silent bypass. It cannot collide here — `-F` means --notes-file only for `gh release` and
    // --field only for `gh api`, both handled in other branches.
    for (const rawPath of extractFlagValues(command, ["--body-file", "-F"])) {
      await collectFileFlag("--body-file", rawPath);
    }
  }

  if (isGhApiWrite(command)) {
    for (const f of extractGhApiBodyFields(command)) await collectApiField(f.field, f.text);

    for (const rawPath of extractFlagValues(command, ["--input"])) {
      // `--input -` reads stdin, which on this command shape is a heredoc fed straight to gh.
      const raw =
        rawPath === "-"
          ? stdinHeredoc()
          : (
              await resolveBodyText(
                resolveShellVariablePath(rawPath, command) ?? rawPath,
                command,
                heredocs,
                cwd,
              )
            ).text;
      if (raw === null) continue;
      const body = extractJsonBodyField(raw);
      if (body === null) continue;
      bodies.push({ label: `gh api --input "${rawPath}" (.body)`, text: body });
    }
  }

  return { bodies, unreadable, isPublishingCommand: true };
}
