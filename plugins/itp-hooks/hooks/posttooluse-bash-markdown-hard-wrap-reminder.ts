#!/usr/bin/env bun
/**
 * PostToolUse hook (Bash): markdown hard-wrap reminder for Markdown written by a SHELL COMMAND.
 *
 * The edit-time reminder (`posttooluse-markdown-hard-wrap-reminder.ts`) is registered on
 * `Write|Edit`, so Markdown produced any other way was invisible to it: `cat > f.md <<EOF`,
 * `python3 - <<EOF` rewriting files, a generator script, `sed -i`. Measured 2026-10-01: a session
 * rewrote dozens of `.md` files that way, all hard-wrapped, and the reminder never fired once. This
 * hook closes that gap as a reminder; `pretooluse-markdown-commit-hard-wrap-guard.ts` enforces the same
 * rule at commit time, which no authoring path can avoid.
 *
 * A PostToolUse hook cannot see what a command wrote, only what is on disk afterwards, so it looks in
 * two places:
 *
 *   1. `.md` paths the command names (resolved against the cwd and any `cd` target), and
 *   2. Markdown that `git status` reports modified or untracked in the repository the command ran in,
 *
 * keeping only files modified in the last {@link RECENT_WINDOW_MS}, and compares each against its
 * `HEAD` version (net-new wraps only, the shared detector). A file with no `HEAD` version is new, so
 * every wrap in it counts, as for a Write.
 *
 * Dedupe: a dirty file stays dirty across many Bash calls, so each (file, content hash) is judged once
 * per session; the edit-time reminder records what it judged in the same cache, so a file an Edit
 * already reported is not reported again by the next Bash call.
 *
 * Fail-open everywhere and bounded: git calls carry a timeout, at most {@link MAX_CANDIDATES} files are
 * read per call, non-regular files and files over 2 MB are skipped unread.
 */

import { statSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, relative, resolve } from "node:path";
import { trackHookError } from "./lib/hook-error-tracker.ts";
import {
  contentHash,
  type FileWrapReport,
  formatFileWrapReports,
  GFM_UNWRAP_COMMAND,
  gitTopLevel,
  isMarkdownFilePath,
  loadSeenMarkdownContent,
  MD_HARD_WRAP_OK_MARKER,
  netNewMarkdownHardWraps,
  readGitBlobs,
  readRegularTextFile,
  recordSeenMarkdownContent,
  runGit,
} from "./lib/markdown-net-new-hard-wraps.ts";
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temp-dir-edit-path-detection-iter124.ts";
import { walkShellInvocations } from "./lib/shell-command-invocation-walker.ts";

const HOOK_NAME = "bash-markdown-hard-wrap-reminder";
/** A file last modified longer ago than this was not written by the command that just ran. */
export const RECENT_WINDOW_MS = 15 * 60 * 1000;
const MAX_CANDIDATES = 200;

function expandHome(p: string): string {
  if (p === "~") return homedir();
  return p.startsWith("~/") ? `${homedir()}${p.slice(1)}` : p;
}

/** The directories the command ran in: the cwd plus every `cd` / `git -C` target. */
export function commandDirectories(command: string, cwd: string): string[] {
  const dirs = new Set<string>([cwd]);
  let dir = cwd;
  walkShellInvocations(command, /\b(cd|pushd|git)\b/, (inv) => {
    const args = inv.args.map((w) => w.value);
    if (inv.program === "cd" || inv.program === "pushd") {
      const t = args.find((a) => !a.startsWith("-"));
      dir = t ? (isAbsolute(expandHome(t)) ? expandHome(t) : resolve(dir, expandHome(t))) : homedir();
      dirs.add(dir);
    } else if (inv.program === "git") {
      const c = args.indexOf("-C");
      if (c !== -1 && args[c + 1]) dirs.add(resolve(dir, expandHome(args[c + 1])));
    }
  });
  return [...dirs];
}

/** `.md` / `.markdown` path-like tokens anywhere in the command text, quoted or not. */
export function markdownPathsMentioned(command: string): string[] {
  const re = /(?:^|[\s'"=<>(|;&`])((?:~\/|\.{1,2}\/|\/)?[\w@%+,.~/-]*\.(?:md|markdown))(?=$|[\s'"<>|;&)`])/gi;
  const out = new Set<string>();
  for (const m of command.matchAll(re)) out.add(m[1]);
  return [...out];
}

/** Markdown `git status` reports modified, added, renamed or untracked, as absolute paths. */
function dirtyMarkdownInRepo(root: string): string[] {
  const out = runGit(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]);
  if (!out) return [];
  const fields = out.split("\0");
  const paths: string[] = [];
  for (let i = 0; i < fields.length; i++) {
    const f = fields[i];
    if (f.length < 4) continue;
    const xy = f.slice(0, 2);
    const p = f.slice(3);
    if (xy[0] === "R" || xy[0] === "C") i++; // the next field is the rename source
    if (xy.includes("D")) continue;
    if (isMarkdownFilePath(p)) paths.push(resolve(root, p));
  }
  return paths;
}

function isRecentRegularFile(path: string, now: number): boolean {
  try {
    const st = statSync(path);
    return st.isFile() && now - st.mtimeMs <= RECENT_WINDOW_MS;
  } catch {
    return false;
  }
}

/** Candidate files this command may have written, most specific first, de-duplicated and bounded. */
export function candidateMarkdownFiles(command: string, cwd: string, now = Date.now()): string[] {
  const dirs = commandDirectories(command, cwd);
  const found = new Set<string>();
  for (const token of markdownPathsMentioned(command)) {
    const t = expandHome(token);
    for (const d of isAbsolute(t) ? [""] : dirs) found.add(d ? resolve(d, t) : t);
  }
  const roots = new Set<string>();
  for (const d of dirs) {
    const r = gitTopLevel(d);
    if (r) roots.add(r);
  }
  for (const r of roots) for (const p of dirtyMarkdownInRepo(r)) found.add(p);

  return [...found]
    .filter((p) => !p.includes("/.git/") && !p.includes("/node_modules/"))
    .filter((p) => !isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(p))
    .filter((p) => isRecentRegularFile(p, now))
    .slice(0, MAX_CANDIDATES);
}

/**
 * The net-new wraps in each candidate, skipping content this session has already judged. Returns the
 * reports and the (path → hash) entries to record as judged.
 */
export function evaluateCandidates(
  files: readonly string[],
  seen: Readonly<Record<string, string>>,
): { reports: FileWrapReport[]; judged: Record<string, string> } {
  const reports: FileWrapReport[] = [];
  const judged: Record<string, string> = {};
  const byRoot = new Map<string | null, Array<{ path: string; text: string }>>();
  for (const path of files) {
    const text = readRegularTextFile(path);
    if (text === null) continue;
    const h = contentHash(text);
    if (seen[path] === h) continue;
    judged[path] = h;
    const root = gitTopLevel(resolve(path, ".."));
    const list = byRoot.get(root) ?? [];
    list.push({ path, text });
    byRoot.set(root, list);
  }
  for (const [root, list] of byRoot) {
    const specs = root ? list.map((f) => `HEAD:${relative(root, f.path)}`) : [];
    const blobs = root ? readGitBlobs(root, specs) : new Map<string, string | null>();
    for (const f of list) {
      const before = root ? (blobs.get(`HEAD:${relative(root, f.path)}`) ?? null) : null;
      const wraps = netNewMarkdownHardWraps(before, f.text);
      if (wraps.length > 0) reports.push({ path: f.path, wraps });
    }
  }
  return { reports, judged };
}

export function buildBashMarkdownHardWrapReminder(reports: readonly FileWrapReport[]): string {
  return [
    "[MD-HARD-WRAP] Markdown written by that command has hard-wrapped prose (new since HEAD):",
    "",
    ...formatFileWrapReports(reports),
    "",
    "Author each paragraph and list item as ONE unbroken line; keep only structural breaks. This applies",
    "to Markdown written by heredocs, scripts and generators exactly as to Write/Edit. The commit guard",
    "will refuse these wraps at `git commit`, so reflow now:",
    `  ${GFM_UNWRAP_COMMAND} <file>`,
    "",
    `Deliberate wrapping: <!-- ${MD_HARD_WRAP_OK_MARKER}: why --> in the file, as an HTML comment in live markdown.`,
  ].join("\n");
}

interface BashPostToolUseInput {
  tool_name?: string;
  tool_input?: { command?: string };
  cwd?: string;
  session_id?: string;
}

async function main(): Promise<void> {
  const input = JSON.parse(await Bun.stdin.text()) as BashPostToolUseInput;
  if (input.tool_name !== "Bash") return;
  const command = input.tool_input?.command ?? "";
  if (!command.trim()) return;
  const sessionId = input.session_id ?? "";
  const files = candidateMarkdownFiles(command, input.cwd || process.cwd());
  if (files.length === 0) return;
  const { reports, judged } = evaluateCandidates(files, sessionId ? loadSeenMarkdownContent(sessionId) : {});
  if (sessionId) recordSeenMarkdownContent(sessionId, judged);
  if (reports.length === 0) return;
  console.log(JSON.stringify({ decision: "block", reason: buildBashMarkdownHardWrapReminder(reports) }));
}

if (import.meta.main) {
  main()
    .catch((err: unknown) => trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err)))
    .finally(() => process.exit(0));
}
