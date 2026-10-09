#!/usr/bin/env bun
/**
 * gmail-send-guard — PreToolUse(Bash|Write|Edit|MultiEdit|Read|Grep).
 *
 * GMAIL-SEND-OK: this file defines the detector; its patterns and comments are not Gmail calls.
 *
 * WHY (incident 2026-10-08): an agent wrote a Bun script that read a cached OAuth token file from
 * ~/.claude/tools/gmail-tokens/ and POSTed a raw message to the Gmail send endpoint with no From
 * header. Gmail filled the sender in from each account's DEFAULT send-as identity, which was the
 * wrong identity on both accounts it used. Nothing stopped it: gmail-draft-guard only watches the
 * drafts API, and a Bash hook cannot see a fetch() that lives inside a script file.
 *
 * So this guard watches every surface the incident crossed:
 *
 *   1. SEND — a direct call to the Gmail send endpoints (REST messages/send or drafts/send, or the
 *      client-library messages.send / drafts.send) together with a Gmail context marker:
 *        Bash   the command text itself (including heredoc bodies and inline `bun -e`), and the
 *               contents of any script file the command executes;
 *        Write  the content of a code file (prose files are out of scope: docs may describe the API);
 *        Edit   the file as it would be after the edit, when the edit is what introduces the call.
 *      Nothing in this plugin sends mail. Drafts go through scripts/gmail-draft.ts and a human sends
 *      them from Gmail, choosing the From line they can see.
 *
 *   2. TOKEN READ — reading the cached OAuth tokens, which are bearer credentials for whole mailboxes:
 *        Read / Grep  any path inside gmail-tokens/;
 *        Bash         a content-reading program (cat, jq, python, bun -e, cp, ...) aimed at that
 *                     directory, directly or via `cd` / a `for` loop over it; and executing a script,
 *                     outside this plugin's own scripts/, whose source references it.
 *      Metadata operations stay allowed (ls, stat, test -f, mv, rm, chmod), because the documented
 *      recovery steps use them. The sanctioned readers are this plugin's own CLIs, which never need
 *      the path on their command line: scripts/gmail-cli, scripts/gmail-draft.ts, and
 *      scripts/gmail-accounts.ts (which mailbox each token owns, its send-as aliases, its expiry).
 *
 * Escape: the marker shown at the top of this header comment, followed by a colon and a reason of at
 * least 10 characters, placed in the Bash command, the written content, or the executed script.
 * There is no escape for the Read and Grep tools: if a token file must be inspected, a human does it.
 *
 * Not a containment boundary. It catches the shapes agents actually write; obfuscated code (split
 * strings, base64) passes. Fails open on unparseable input, because a wedged session costs more than
 * one missed detection, and the sending account's own send-as settings remain the real backstop.
 */

import { existsSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";

// ── Detection patterns ────────────────────────────────────────────────────────

/** The send endpoints: REST paths and client-library method calls (JS `messages.send(`, Python `messages().send(`). */
export const SEND_CALL_RE =
  /\b(?:messages|drafts)(?:\/send\b|\s*\.\s*send\s*\(|\s*\(\s*\)\s*\.\s*send\s*\()/i;

/** Evidence the send call is aimed at Gmail rather than some other API with a `messages.send`. */
export const GMAIL_CONTEXT_RE =
  /gmail\.googleapis\.com|googleapis|gmail\s*\.\s*users|gmail_v1|build\(\s*["']gmail["']|google\.gmail\s*\(|users\/me\/(?:messages|drafts)/i;

export const TOKEN_DIR_RE = /gmail-tokens/;

const ESCAPE_MARKER = ["GMAIL", "SEND", "OK"].join("-");
/**
 * Marker, colon, then a reason of at least 10 characters on the same line. Documentation placeholders
 * do not count, so copying an example out of a doc never pastes a working escape: a reason that starts
 * with `<` (`<reason, 10+ chars>`) or is the marker reference's generic example sentence is rejected.
 */
const ESCAPE_CANDIDATE_RE = new RegExp(
  `${ESCAPE_MARKER}:[ \\t]*([^\\n]*)`,
  "g",
);
const PLACEHOLDER_REASON_RE = /^<|explain the deliberate exception here/i;
export const ESCAPE_RE = {
  test(text: string): boolean {
    for (const m of text.matchAll(ESCAPE_CANDIDATE_RE)) {
      const reason = (m[1] ?? "").trim();
      if (reason.length >= 10 && !PLACEHOLDER_REASON_RE.test(reason))
        return true;
    }
    return false;
  },
};

/** Files where the endpoint is prose, not code. */
const PROSE_EXT_RE = /\.(?:md|mdx|markdown|txt|rst|adoc|org)$/i;

/** Programs that only touch a file's metadata (or move/delete it) — the documented recovery steps. */
const METADATA_PROGRAMS = new Set([
  "ls",
  "stat",
  "test",
  "[",
  "[[",
  "mv",
  "rm",
  "trash",
  "chmod",
  "touch",
  "mkdir",
  "basename",
  "dirname",
  "realpath",
  "readlink",
  "file",
  "du",
  "wc",
  "cd",
  "pushd",
  "popd",
  "echo",
  "printf",
  "for",
  "case",
  "esac",
  "while",
  "if",
  "true",
  "false",
  "find",
]);

/** Programs that read a file's bytes. Used when a token path arrives by `cd` or a loop variable. */
const CONTENT_READERS = new Set([
  "cat",
  "bat",
  "less",
  "more",
  "head",
  "tail",
  "jq",
  "yq",
  "python",
  "python3",
  "node",
  "bun",
  "bunx",
  "deno",
  "tsx",
  "ruby",
  "perl",
  "awk",
  "gawk",
  "sed",
  "grep",
  "egrep",
  "rg",
  "ag",
  "xxd",
  "od",
  "hexdump",
  "strings",
  "base64",
  "cp",
  "scp",
  "rsync",
  "curl",
  "wget",
  "open",
  "source",
  ".",
  "tar",
  "zip",
  "pbcopy",
  "security",
  "openssl",
  "nl",
  "tac",
  "sort",
  "uniq",
  "cut",
  "tr",
  "xargs",
  "vim",
  "vi",
  "nano",
  "code",
]);

const INTERPRETERS = new Set([
  "bun",
  "bunx",
  "node",
  "deno",
  "tsx",
  "ts-node",
  "python",
  "python3",
  "ruby",
  "perl",
  "bash",
  "sh",
  "zsh",
]);
const SCRIPT_EXT_RE = /\.(?:ts|tsx|mts|cts|js|mjs|cjs|py|sh|bash|zsh|rb|pl)$/i;
/** This plugin's own scripts are the sanctioned token readers, wherever the checkout lives. */
const SANCTIONED_SCRIPT_RE = /plugins\/gmail-commander\/scripts\//;

// ── Shell helpers ─────────────────────────────────────────────────────────────

/** Split a command into simple-command segments. Crude by design: heredoc bodies become segments too. */
export function shellSegments(cmd: string): string[] {
  return cmd
    .split(/\n|;|&&|\|\||\||\$\(|`|\)/)
    .map((s) => s.trim())
    .filter(Boolean);
}

const WRAPPERS = new Set([
  "sudo",
  "env",
  "command",
  "exec",
  "nohup",
  "time",
  "do",
  "then",
  "else",
  "{",
  "(",
  "!",
]);

/** The program a segment runs: skips VAR=value assignments, wrappers, and `timeout <n>`. */
export function leadingProgram(segment: string): string {
  const words = segment.split(/\s+/).filter(Boolean);
  let i = 0;
  while (i < words.length) {
    const w = words[i];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(w) || WRAPPERS.has(w)) {
      i++;
      continue;
    }
    if (w === "timeout") {
      i += 2;
      while (i < words.length && words[i].startsWith("-")) i++;
      continue;
    }
    break;
  }
  const prog = (words[i] ?? "").replace(/^["']|["']$/g, "");
  return prog.split("/").pop() ?? prog;
}

function expandHome(p: string): string {
  return p
    .replace(/^~(?=\/|$)/, homedir())
    .replace(/^\$HOME(?=\/|$)/, homedir())
    .replace(/^\$\{HOME\}(?=\/|$)/, homedir());
}

/** Script files a command would execute: interpreter arguments and ./direct execution. */
export function executedScripts(cmd: string, cwd: string): string[] {
  const out: string[] = [];
  for (const seg of shellSegments(cmd)) {
    const prog = leadingProgram(seg);
    const words = seg.split(/\s+/).map((w) => w.replace(/^["']|["']$/g, ""));
    // An interpreter anywhere in the segment counts: `uv run python x.py`, `npx tsx x.ts`, `pueue add -- bun x.ts`.
    const runsScript =
      INTERPRETERS.has(prog) ||
      words.some(
        (w) => INTERPRETERS.has(w.split("/").pop() ?? w) || w.startsWith("./"),
      );
    if (!runsScript) continue;
    // `bun test` / `bun build` and friends operate ON a file without running it.
    if (
      /\b(?:bun|bunx)\s+(?:test|build|install|add|pm|x)\b|\bdeno\s+(?:check|lint|fmt|test)\b/.test(
        seg,
      )
    )
      continue;
    for (const w of words) {
      if (!SCRIPT_EXT_RE.test(w)) continue;
      const abs = isAbsolute(expandHome(w)) ? expandHome(w) : resolve(cwd, w);
      out.push(abs);
    }
  }
  return out;
}

function readSmallFile(path: string): string | undefined {
  try {
    if (!existsSync(path)) return undefined;
    const st = statSync(path);
    if (!st.isFile() || st.size > 2_000_000) return undefined;
    return readFileSync(path, "utf8");
  } catch {
    return undefined;
  }
}

// ── Classifiers (pure; exported for tests) ────────────────────────────────────

export function textSendsGmail(text: string): boolean {
  return SEND_CALL_RE.test(text) && GMAIL_CONTEXT_RE.test(text);
}

const SEARCH_PROGRAMS = new Set([
  "grep",
  "egrep",
  "fgrep",
  "rg",
  "ag",
  "git",
  "gh",
]);

/** True when the command only searches or inspects history (and writes nothing), so a match is a mention. */
function isSearchOnly(cmd: string): boolean {
  if (/<<|(?:^|[^<>&\d])>{1,2}(?!&)|\btee\b/.test(cmd)) return false;
  return shellSegments(cmd).every((seg) => {
    const p = leadingProgram(seg);
    if (p === "git")
      return /\bgit\s+(?:-C\s+\S+\s+)?(?:grep|log|show|diff|blame)\b/.test(seg);
    if (p === "gh") return /\bgh\s+search\b/.test(seg);
    return (
      SEARCH_PROGRAMS.has(p) ||
      METADATA_PROGRAMS.has(p) ||
      p === "head" ||
      p === "wc"
    );
  });
}

export type Verdict = { deny: false } | { deny: true; reason: string };
const ALLOW: Verdict = { deny: false };

const SEND_ADVICE = [
  "Nothing in this toolchain sends Gmail directly. Stage a draft with the canonical builder, which sets an explicit From header, and let a human send it from Gmail:",
  "  bun ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts --account <tokenbase> --from 'Name <addr>' --body <file.md> ...",
  "Why: a raw send without a From line goes out under the account's DEFAULT send-as identity, which is often not the identity you meant (incident 2026-10-08).",
  "To check which alias is the default: bun ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-accounts.ts",
  `Deliberate exception: add "${ESCAPE_MARKER}: <reason, 10+ chars>" to the command, or as a comment in the script.`,
].join("\n");

const TOKEN_ADVICE = [
  "The files in ~/.claude/tools/gmail-tokens/ are bearer credentials for whole mailboxes. Read them only through this plugin's CLIs:",
  "  which mailbox / send-as aliases / expiry:  bun ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-accounts.ts",
  "  mail reads and drafts:                     the gmail CLI (scripts/gmail-cli/gmail) and scripts/gmail-draft.ts",
  "Metadata operations (ls, stat, test -f, mv, rm) are allowed.",
].join("\n");

/**
 * A git commit/tag or a gh issue/pr/release command carries PROSE (a message or body) that may
 * legitimately discuss the API or the token directory — including this guard's own commits.
 */
function carriesProse(cmd: string): boolean {
  return shellSegments(cmd).some((seg) => {
    const p = leadingProgram(seg);
    if (p === "git")
      return /\bgit\s+(?:-C\s+\S+\s+)?(?:commit|tag|notes)\b/.test(seg);
    if (p === "gh") return /\bgh\s+(?:issue|pr|release)\b/.test(seg);
    return false;
  });
}

/** In a prose-carrying command, only a concrete token-file argument counts, e.g. `gh gist create <token file>`. */
const TOKEN_FILE_ARG_RE =
  /(?:^|\s)["']?(?:~|\$HOME|\$\{HOME\}|\/)[^\s"']*gmail-tokens\/[^\s"'<>]*\.json\b/;

export function classifyBash(cmd: string, cwd: string): Verdict {
  if (ESCAPE_RE.test(cmd)) return ALLOW;
  const prose = carriesProse(cmd);

  if (prose) {
    if (TOKEN_FILE_ARG_RE.test(cmd) && !/^\s*(?:git|cd)\b/.test(cmd)) {
      return {
        deny: true,
        reason: `BLOCKED (gmail-send-guard): this command passes a Gmail token file as an argument.\n\n${TOKEN_ADVICE}`,
      };
    }
  } else if (textSendsGmail(cmd) && !isSearchOnly(cmd)) {
    return {
      deny: true,
      reason: `BLOCKED (gmail-send-guard): this command calls the Gmail send API directly.\n\n${SEND_ADVICE}`,
    };
  }

  if (!prose && TOKEN_DIR_RE.test(cmd)) {
    const segs = shellSegments(cmd);
    const capturesDir = segs.some(
      (s) =>
        TOKEN_DIR_RE.test(s) &&
        ["cd", "pushd", "for"].includes(leadingProgram(s)),
    );
    for (const seg of segs) {
      const prog = leadingProgram(seg);
      if (TOKEN_DIR_RE.test(seg)) {
        if (prog === "find" && /\s-(?:exec|execdir|ok|delete)\b/.test(seg)) {
          return {
            deny: true,
            reason: `BLOCKED (gmail-send-guard): \`find -exec\` over the Gmail token directory.\n\n${TOKEN_ADVICE}`,
          };
        }
        if (!METADATA_PROGRAMS.has(prog)) {
          return {
            deny: true,
            reason: `BLOCKED (gmail-send-guard): \`${prog}\` would read the cached Gmail OAuth tokens.\n\n${TOKEN_ADVICE}`,
          };
        }
      } else if (capturesDir && CONTENT_READERS.has(prog)) {
        return {
          deny: true,
          reason: `BLOCKED (gmail-send-guard): \`${prog}\` runs on files from the Gmail token directory (reached via cd or a loop).\n\n${TOKEN_ADVICE}`,
        };
      }
    }
  }

  for (const script of executedScripts(cmd, cwd)) {
    const src = readSmallFile(script);
    if (src === undefined || ESCAPE_RE.test(src)) continue;
    if (textSendsGmail(src)) {
      return {
        deny: true,
        reason: `BLOCKED (gmail-send-guard): ${script} calls the Gmail send API directly (found by reading the script; the command line names no endpoint).\n\n${SEND_ADVICE}`,
      };
    }
    if (TOKEN_DIR_RE.test(src) && !SANCTIONED_SCRIPT_RE.test(script)) {
      return {
        deny: true,
        reason: `BLOCKED (gmail-send-guard): ${script} reads the cached Gmail OAuth tokens and is not one of this plugin's own scripts.\n\n${TOKEN_ADVICE}`,
      };
    }
  }
  return ALLOW;
}

/** Write / Edit / MultiEdit. `before` is the file's current content (undefined when new or unreadable). */
export function classifyFileWrite(
  path: string,
  after: string,
  before: string | undefined,
): Verdict {
  if (PROSE_EXT_RE.test(path)) return ALLOW;
  if (ESCAPE_RE.test(after)) return ALLOW;
  if (!textSendsGmail(after)) return ALLOW;
  // An edit elsewhere in a file that already carried the call is not what introduced it.
  if (before !== undefined && textSendsGmail(before)) return ALLOW;
  return {
    deny: true,
    reason: `BLOCKED (gmail-send-guard): ${path} would call the Gmail send API directly. A Bash hook cannot see a send inside a script, so it is stopped when the script is written.\n\n${SEND_ADVICE}`,
  };
}

export function classifyRead(path: string): Verdict {
  if (!TOKEN_DIR_RE.test(path)) return ALLOW;
  return {
    deny: true,
    reason: `BLOCKED (gmail-send-guard): ${path} is in the Gmail token directory.\n\n${TOKEN_ADVICE}`,
  };
}

// ── Hook entry ────────────────────────────────────────────────────────────────

interface Edit {
  old_string?: string;
  new_string?: string;
  replace_all?: boolean;
}
interface HookInput {
  tool_name?: string;
  cwd?: string;
  tool_input?: {
    command?: string;
    file_path?: string;
    path?: string;
    content?: string;
    old_string?: string;
    new_string?: string;
    replace_all?: boolean;
    edits?: Edit[];
  };
}

function applyEdits(before: string | undefined, edits: Edit[]): string {
  let text = before ?? "";
  for (const e of edits) {
    const oldS = e.old_string ?? "";
    const newS = e.new_string ?? "";
    if (before === undefined || oldS === "" || !text.includes(oldS)) {
      text += `\n${newS}`; // cannot place it; judge the new text alongside the file
    } else {
      text = e.replace_all
        ? text.split(oldS).join(newS)
        : text.replace(oldS, () => newS);
    }
  }
  return text;
}

export function classify(input: HookInput): Verdict {
  const tool = input.tool_name ?? "";
  const ti = input.tool_input ?? {};
  const cwd = input.cwd ?? process.cwd();
  switch (tool) {
    case "Bash":
      return typeof ti.command === "string"
        ? classifyBash(ti.command, cwd)
        : ALLOW;
    case "Read":
      return classifyRead(ti.file_path ?? "");
    case "Grep":
      return classifyRead(ti.path ?? "");
    case "Write":
      return classifyFileWrite(
        ti.file_path ?? "",
        ti.content ?? "",
        readSmallFile(ti.file_path ?? ""),
      );
    case "Edit":
    case "MultiEdit": {
      const path = ti.file_path ?? "";
      const before = readSmallFile(path);
      const edits =
        tool === "Edit"
          ? [
              {
                old_string: ti.old_string,
                new_string: ti.new_string,
                replace_all: ti.replace_all,
              },
            ]
          : (ti.edits ?? []);
      return classifyFileWrite(path, applyEdits(before, edits), before);
    }
    default:
      return ALLOW;
  }
}

if (import.meta.main) {
  let verdict: Verdict = ALLOW;
  try {
    const raw = await Bun.stdin.text();
    verdict = classify(JSON.parse(raw) as HookInput);
  } catch {
    verdict = ALLOW; // fail open
  }
  if (verdict.deny) {
    console.log(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: verdict.reason,
        },
      }),
    );
  }
  process.exit(0);
}
