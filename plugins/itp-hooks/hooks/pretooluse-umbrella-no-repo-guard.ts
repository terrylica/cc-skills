#!/usr/bin/env bun
/**
 * PreToolUse hook: Umbrella-folder "never a repository" guard
 *
 * An UMBRELLA folder represents an owner/namespace and CONTAINS repositories.
 * It is not one itself. Operator ruling 2026-09-05:
 *
 *   "~/459ecs should never become a repository because it is representing user,
 *    but never a repository."
 *
 * WHY A GUARD, WHEN A FILESYSTEM SENTINEL ALREADY EXISTS. Each umbrella folder
 * carries an immutable `.git` FILE (macOS `chflags uchg`) that makes `git init`
 * fail with `fatal: invalid gitfile format`. That is a harder stop than this
 * hook — but it is silent about WHY, and a cryptic error is exactly the thing a
 * helpful agent "fixes". This guard exists to refuse the command with a reason,
 * so the protection survives contact with the next session. Measured cause: an
 * agent proposed turning ~/459ecs into a repository twice in one session.
 *
 * WHAT IT BLOCKS, when the resolved target is an umbrella folder itself:
 *   - `git init` (including `--separate-git-dir`, `--bare`)
 *   - `gh repo create` run from inside one
 *   - `git clone <url> <umbrella-path>` — cloning ONTO the folder
 *
 * WHAT IT DELIBERATELY DOES NOT BLOCK:
 *   - anything targeting a SUBDIRECTORY (`~/459ecs/newthing`) — nested repos are
 *     the entire point of an umbrella folder
 *   - `git init` anywhere else on the machine
 *
 * KNOWN GAP, stated rather than hidden: `GIT_DIR=/elsewhere git init` is not
 * matched by the filesystem sentinel because it never touches the folder's .git
 * path. It is matched here, which is the only layer that sees it.
 *
 * SSoT for the folder list: ~/.claude/path-owner-registry.toml, `[[umbrella]]`.
 * FAIL-OPEN: unreadable or unparseable registry -> allow. A guard that locks the
 * operator out of their own machine is worse than the thing it guards against.
 *
 * Escape hatch: ALLOW_UMBRELLA_REPO=1 anywhere in the command.
 */

import { homedir } from "node:os";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";

const HOOK_NAME = "umbrella-no-repo-guard";
const REGISTRY = `${homedir()}/.claude/path-owner-registry.toml`;
const ESCAPE = /ALLOW_UMBRELLA_REPO=1/;

/**
 * Read the `[[umbrella]]` paths without a TOML dependency.
 *
 * Deliberately literal: it matches `path = "..."` lines that appear AFTER an
 * `[[umbrella]]` header and before the next `[[...]]` header. A full TOML parser
 * would be more correct, but this hook must run on every Bash call, and the
 * shape it reads is one this repo controls.
 */
function umbrellaPaths(): string[] {
  let text: string;
  try {
    text = readFileSync(REGISTRY, "utf8");
  } catch {
    return []; // fail-open
  }
  const out: string[] = [];
  let inUmbrella = false;
  for (const line of text.split("\n")) {
    const header = line.match(/^\s*\[\[(\w+)\]\]/);
    if (header) {
      inUmbrella = header[1] === "umbrella";
      continue;
    }
    if (!inUmbrella) continue;
    const m = line.match(/^\s*path\s*=\s*"([^"]+)"/);
    if (m) out.push(m[1].replace(/^~/, homedir()));
  }
  return out;
}

/** Split a shell command on separators so `cd /tmp && git init` is seen as two segments. */
function segments(command: string): string[] {
  return command.split(/&&|\|\||;|\n/).map((s) => s.trim()).filter(Boolean);
}

/**
 * Only `VAR=value` assignments may precede the command word.
 *
 * This used to be `(?:\S*\s+)*?`, which matched ANY leading words — so
 * `echo git init` was treated as a repo creation and denied. Caught by the
 * must-not-fire half of the test suite; a guard tested only in the firing
 * direction would have shipped it.
 */
const ENV_PREFIX = String.raw`^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*`;

/** Expand a leading `~` — `resolve()` does not, so `git init ~/459ecs` slipped through. */
function expandTilde(p: string): string {
  if (p === "~") return homedir();
  if (p.startsWith("~/")) return `${homedir()}/${p.slice(2)}`;
  return p;
}

/** Does this segment try to create a repository, and at which target path? */
function repoCreationTarget(seg: string, cwd: string): string | null {
  // `git init [flags] [dir]`
  const init = seg.match(new RegExp(`${ENV_PREFIX}git\\s+init\\b(.*)$`));
  if (init) {
    const positional = (init[1] ?? "")
      .trim()
      .split(/\s+/)
      .filter((t) => t && !t.startsWith("-") && !t.includes("="));
    return resolve(cwd, expandTilde(positional[0] ?? "."));
  }
  // `gh repo create` — creates a remote and, without a name, uses cwd
  if (new RegExp(`${ENV_PREFIX}gh\\s+repo\\s+create\\b`).test(seg)) return resolve(cwd, ".");
  // `git clone <url> <dir>` — cloning ONTO an umbrella folder makes it a repo
  const clone = seg.match(new RegExp(`${ENV_PREFIX}git\\s+clone\\b(.*)$`));
  if (clone) {
    const toks = (clone[1] ?? "")
      .trim()
      .split(/\s+/)
      .filter((t) => t && !t.startsWith("-"));
    if (toks.length >= 2) return resolve(cwd, expandTilde(toks[toks.length - 1]));
  }
  return null;
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow(HOOK_NAME);
  if (!input) return;
  if (input.tool_name !== "Bash") return allow();

  const command = String((input.tool_input as { command?: string })?.command ?? "");
  if (!command || ESCAPE.test(command)) return allow();

  const paths = umbrellaPaths();
  if (paths.length === 0) return allow(); // fail-open

  const cwd = String((input as { cwd?: string }).cwd ?? process.cwd());

  for (const seg of segments(command)) {
    const target = repoCreationTarget(seg, cwd);
    if (!target) continue;
    // Exact match only. A SUBDIRECTORY is fine — that is what umbrellas are for.
    const hit = paths.find((p) => resolve(p) === target);
    if (!hit) continue;
    return deny(
      `Refusing to create a git repository at ${hit} — that is an UMBRELLA folder.\n\n` +
        `An umbrella folder represents an owner/namespace and CONTAINS repositories; it is ` +
        `never one itself. Operator ruling 2026-09-05.\n\n` +
        `The folder also carries an immutable .git sentinel, so this would have failed anyway ` +
        `with "fatal: invalid gitfile format" — this hook exists to tell you WHY rather than ` +
        `leave you debugging that message.\n\n` +
        `If you meant a repository INSIDE it, name the subdirectory: git init ${hit}/<name>\n` +
        `Rationale: ~/.claude/decisions-security-CLAUDE.md · SSoT: ${REGISTRY} [[umbrella]]\n` +
        `Override (means it): ALLOW_UMBRELLA_REPO=1`
    );
  }
  return allow();
}

main().catch((error) => {
  trackHookError(HOOK_NAME, error);
  allow(); // fail-open
});
