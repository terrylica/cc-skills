#!/usr/bin/env bun
/**
 * PreToolUse hook: markdown hard-wrap commit guard.
 *
 * Denies a `git commit` that would ADD hard-wrapped prose to a `.md` / `.markdown` file — a paragraph
 * broken mid-sentence at a fixed column instead of authored as one line the renderer reflows.
 *
 * Why at commit time: the edit-time reminder (`posttooluse-markdown-hard-wrap-reminder.ts`) only sees
 * Write/Edit/MultiEdit. Markdown written any other way — a heredoc, `python3 - <<EOF`, a generator
 * script, `sed -i`, another program entirely — never reached it. Measured 2026-10-01: a session rewrote
 * dozens of `.md` files through Bash and Python, all hard-wrapped, with the reminder enabled and
 * silent throughout. A commit is the one boundary every authoring path crosses, whatever wrote the
 * file, so the rule is enforced here and reminded about everywhere else.
 *
 * What is compared: the version being committed against `HEAD`, whole file on both sides, net-new
 * wraps only (lib/markdown-net-new-hard-wraps.ts — the same detector the reminders use). Legacy wraps
 * the commit did not add are never reported, so a repository full of old wrapped prose can still be
 * committed to; touching a wrapped paragraph changes its shape and IS reported, which is the moment to
 * reflow it.
 *
 *   - `git commit`            → the index (`:path`) against `HEAD:path`
 *   - `git commit -a` / `-am` → tracked working-tree files against `HEAD`
 *   - `git commit <paths>`    → those paths' working-tree content against `HEAD`
 *
 * `cd <dir> && git commit` and `git -C <dir> commit` are followed, so the repository checked is the
 * one the commit lands in. The commit MESSAGE is out of scope: a git object is not a GFM surface, and
 * 72-column message bodies are the git convention (see pretooluse-github-hard-wrap-guard.ts).
 *
 * Repair: `bun "$(cc-plugin-root itp-hooks)/scripts/gfm-unwrap.ts" <file>`, which refuses to write if
 * any content would change. Escape hatches: the marker inside an HTML comment in the file (per file,
 * the same one the reminder honours), or the marker anywhere in the command (whole commit).
 *
 * Fail-open everywhere: not a repository, git timing out, an unreadable blob, a parse error → allow.
 */

import { isAbsolute, resolve } from "node:path";
import { homedir } from "node:os";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import {
  type FileWrapReport,
  formatFileWrapReports,
  GFM_UNWRAP_COMMAND,
  gitTopLevel,
  isMarkdownFilePath,
  MD_HARD_WRAP_OK_MARKER,
  netNewMarkdownHardWraps,
  readGitBlobs,
  readRegularTextFile,
  runGit,
} from "./lib/markdown-net-new-hard-wraps.ts";
import { walkShellInvocations } from "./lib/shell-command-invocation-walker.ts";
import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";

const HOOK_NAME = "markdown-commit-hard-wrap-guard";
/** A commit touching more Markdown than this is a bulk operation; check this many and say so. */
const MAX_FILES_CHECKED = 400;

/** What a `git commit` will record, as far as the Markdown check needs to know. */
export interface GitCommitInvocation {
  /** Directory git runs in, after `cd` and `-C`. */
  readonly dir: string;
  /** `-a` / `--all`: tracked working-tree changes are committed too. */
  readonly all: boolean;
  /** `git commit <paths>`: exactly these paths' working-tree content is committed. */
  readonly pathspecs: string[];
}

/** git global options that consume the following word. */
const GIT_GLOBAL_OPTS_WITH_VALUE = new Set(["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"]);
/** `git commit` options that consume the following word (the `--x=y` form is self-contained). */
const COMMIT_OPTS_WITH_VALUE = new Set([
  "-m", "--message", "-F", "--file", "-C", "--reuse-message", "-c", "--reedit-message",
  "--author", "--date", "-t", "--template", "--fixup", "--squash", "--trailer", "--cleanup",
  "--pathspec-from-file",
]);
/** Short `git commit` flags whose value is the rest of the cluster (`-am msg`, `-mfoo`). */
const COMMIT_SHORT_FLAGS_WITH_VALUE = new Set(["m", "F", "C", "c", "t", "S", "u"]);

function expandHome(p: string): string {
  if (p === "~") return homedir();
  return p.startsWith("~/") ? `${homedir()}${p.slice(1)}` : p;
}

function resolveDir(base: string, target: string): string {
  const t = expandHome(target);
  return isAbsolute(t) ? t : resolve(base, t);
}

/** Read `git commit`'s own arguments: `-a`, and any pathspecs. */
function parseCommitArgs(args: string[]): { all: boolean; pathspecs: string[] } {
  let all = false;
  const pathspecs: string[] = [];
  let k = 0;
  while (k < args.length) {
    const a = args[k];
    k++;
    if (a === "--") {
      pathspecs.push(...args.slice(k));
      break;
    }
    if (a === "--all") {
      all = true;
    } else if (a.startsWith("--")) {
      if (!a.includes("=") && COMMIT_OPTS_WITH_VALUE.has(a)) k++;
    } else if (a.startsWith("-") && a.length > 1) {
      for (let i = 1; i < a.length; i++) {
        const letter = a[i];
        if (letter === "a") all = true;
        if (COMMIT_SHORT_FLAGS_WITH_VALUE.has(letter)) {
          // `-m msg` takes the next word; `-mmsg` and `-Skey` carry it attached. -S and -u only
          // ever take an attached value, so they never consume the next word.
          if (i === a.length - 1 && letter !== "S" && letter !== "u") k++;
          break;
        }
      }
    } else {
      pathspecs.push(a);
    }
  }
  return { all, pathspecs };
}

/**
 * Every `git commit` in `command`, with the directory it runs in. `cd` is tracked across the top-level
 * command list (`cd repo && git commit`); a `cd` inside `sh -c` applies to the commands after it in that
 * script too, which is an approximation the walker's flat visit order makes, and a harmless one: it can
 * only make the guard check a different repository, never skip a commit it saw.
 */
export function findGitCommitInvocations(command: string, cwd: string): GitCommitInvocation[] {
  const found: GitCommitInvocation[] = [];
  let dir = cwd;
  walkShellInvocations(command, /\b(git|cd|pushd)\b/, (inv) => {
    const args = inv.args.map((w) => w.value);
    if (inv.program === "cd" || inv.program === "pushd") {
      const target = args.find((a) => !a.startsWith("-"));
      dir = target ? resolveDir(dir, target) : homedir();
      return;
    }
    if (inv.program !== "git") return;
    let gitDir = dir;
    let k = 0;
    while (k < args.length && args[k].startsWith("-")) {
      const opt = args[k];
      k++;
      if (opt === "-C" && k < args.length) gitDir = resolveDir(gitDir, args[k]);
      if (GIT_GLOBAL_OPTS_WITH_VALUE.has(opt)) k++;
    }
    if (args[k] !== "commit") return;
    found.push({ dir: gitDir, ...parseCommitArgs(args.slice(k + 1)) });
  });
  return found;
}

/** One Markdown file the commit records: its previous path in HEAD (null if new) and its new path. */
interface ChangedMarkdown {
  readonly beforePath: string | null;
  readonly path: string;
}

/** Parse `git diff --name-status -z -M`, keeping Markdown that was added, copied, modified or renamed. */
export function parseNameStatusZ(out: string): ChangedMarkdown[] {
  const fields = out.split("\0");
  const changes: ChangedMarkdown[] = [];
  let i = 0;
  while (i < fields.length) {
    const status = fields[i];
    i++;
    if (!status) continue;
    const kind = status[0];
    if (kind === "R" || kind === "C") {
      const from = fields[i];
      const to = fields[i + 1];
      i += 2;
      if (to && isMarkdownFilePath(to)) changes.push({ beforePath: kind === "R" ? from : null, path: to });
      continue;
    }
    const p = fields[i];
    i++;
    if (!p || !isMarkdownFilePath(p)) continue;
    if (kind === "A") changes.push({ beforePath: null, path: p });
    else if (kind === "M" || kind === "T") changes.push({ beforePath: p, path: p });
  }
  return changes;
}

/** The net-new wraps one `git commit` would record, per Markdown file. */
export function evaluateGitCommit(inv: GitCommitInvocation): { reports: FileWrapReport[]; truncated: boolean } {
  const root = gitTopLevel(inv.dir);
  if (!root) return { reports: [], truncated: false };
  const hasHead = runGit(root, ["rev-parse", "--verify", "--quiet", "HEAD"]) !== null;
  const fromWorkingTree = hasHead && (inv.all || inv.pathspecs.length > 0);

  const diffArgs = fromWorkingTree
    ? ["diff", "HEAD", "--name-status", "-z", "-M"]
    : ["diff", "--cached", "--name-status", "-z", "-M"];
  // Pathspecs are relative to where git runs, so resolve them against inv.dir, not the root.
  if (inv.pathspecs.length > 0) {
    diffArgs.push("--", ...inv.pathspecs.map((p) => resolveDir(inv.dir, p)));
  }
  const out = runGit(root, diffArgs);
  if (out === null) return { reports: [], truncated: false };

  const all = parseNameStatusZ(out);
  const changes = all.slice(0, MAX_FILES_CHECKED);
  const specs: string[] = [];
  for (const c of changes) {
    if (c.beforePath && hasHead) specs.push(`HEAD:${c.beforePath}`);
    if (!fromWorkingTree) specs.push(`:${c.path}`);
  }
  const blobs = readGitBlobs(root, specs);

  const reports: FileWrapReport[] = [];
  for (const c of changes) {
    const after = fromWorkingTree ? readRegularTextFile(resolve(root, c.path)) : (blobs.get(`:${c.path}`) ?? null);
    if (after === null) continue; // deleted from the tree, unreadable, or too large: nothing to judge
    const before = c.beforePath && hasHead ? (blobs.get(`HEAD:${c.beforePath}`) ?? null) : null;
    const wraps = netNewMarkdownHardWraps(before, after);
    if (wraps.length > 0) reports.push({ path: c.path, wraps });
  }
  return { reports, truncated: all.length > changes.length };
}

export function buildCommitHardWrapDenial(reports: readonly FileWrapReport[], truncated: boolean): string {
  const total = reports.reduce((n, r) => n + r.wraps.length, 0);
  const lines = [
    `[MD-HARD-WRAP] This commit adds ${total} hard-wrapped line(s) to ${reports.length} Markdown file(s):`,
    "",
    ...formatFileWrapReports(reports),
  ];
  if (truncated) lines.push(`  (only the first ${MAX_FILES_CHECKED} changed Markdown files were checked)`);
  lines.push(
    "",
    "Markdown prose is authored one unbroken line per paragraph and per list item; only structural",
    "breaks remain (headings, list items, table rows, fences, blank lines). A wrapped paragraph turns",
    "into literal line breaks the moment it is quoted into an issue, PR, comment or release, and every",
    "reword re-diffs the whole paragraph. Only wraps this commit ADDS are counted; old ones are not.",
    "",
    "Fix, then re-stage and commit again:",
    `  ${GFM_UNWRAP_COMMAND} <file>`,
    "It joins wrapped prose, list items and blockquotes, leaves code and aligned blocks alone, and",
    "refuses to write if any content would change.",
    "",
    `Deliberate wrapping: put <!-- ${MD_HARD_WRAP_OK_MARKER}: why --> in that file (it must be an HTML`,
    `comment in live markdown), or put ${MD_HARD_WRAP_OK_MARKER} in the command to pass the whole commit.`,
  );
  return lines.join("\n");
}

export async function main(): Promise<void> {
  const input = await parseStdinOrAllow(HOOK_NAME);
  if (input?.tool_name !== "Bash") {
    allow();
    return;
  }
  const command = (input.tool_input?.command as string) || "";
  // Cheap prefilter before any lexing or git: the word "commit" must appear at all.
  if (!/\bcommit\b/.test(command) || !/\bgit\b/.test(command)) {
    allow();
    return;
  }
  if (hasFileWideEscapeHatchMarkerInContent(command, { markerNameTokenIncludingSuffix: MD_HARD_WRAP_OK_MARKER })) {
    allow();
    return;
  }

  const reports: FileWrapReport[] = [];
  let truncated = false;
  for (const inv of findGitCommitInvocations(command, input.cwd || process.cwd())) {
    const r = evaluateGitCommit(inv);
    reports.push(...r.reports);
    truncated ||= r.truncated;
  }
  if (reports.length > 0) {
    deny(buildCommitHardWrapDenial(reports, truncated));
    return;
  }
  allow();
}

if (import.meta.main) {
  main().catch((err: unknown) => {
    trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
    allow();
  });
}
