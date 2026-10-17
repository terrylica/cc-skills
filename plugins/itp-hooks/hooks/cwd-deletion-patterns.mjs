#!/usr/bin/env bun
/**
 * CWD Deletion Pattern Definitions
 *
 * Patterns for detecting commands that would delete or overwrite the
 * current working directory. When CWD is deleted, the shell becomes
 * unrecoverable — every subsequent command fails with exit code 1
 * because the OS cannot resolve the process's working directory.
 *
 * Two lessons encoded:
 * 1. NEVER delete CWD without cd-ing elsewhere first
 * 2. For git re-clone operations, prefer git remote set-url + fetch + reset
 *
 * ADR: /docs/adr/2026-02-09-cwd-deletion-guard.md
 */

import { homedir } from "node:os";
import { resolve } from "node:path";
import { walkShellInvocations } from "./lib/shell-command-invocation-walker.ts";

/**
 * Iter-109: migrated to the iter-107 canonical shared escape-hatch-marker
 * detection helper. Behavior-preserving: marker token `CWD-DELETE-OK`
 * detected file-wide (here "file-wide" means "anywhere in the bash
 * command string") with CASE_INSENSITIVE matching (preserves pre-iter-109
 * `/i` flag).
 *
 * Iter-111: dropped the @deprecated `export const ESCAPE_HATCH = /.../i;`
 * regex literal — verified zero external consumers via marketplace-wide
 * grep. The canonical detection path is now the helper call below; no
 * grandfathered raw-regex API surface remains.
 */
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/escape-hatch-marker-detection-iter107.ts";
const CWD_DELETION_GUARD_ESCAPE_HATCH_CONFIGURATION = {
  markerNameTokenIncludingSuffix: "CWD-DELETE-OK",
  caseSensitivityMode: "CASE_INSENSITIVE",
};

/**
 * Normalize a path for comparison.
 * - Expands ~ to $HOME
 * - Resolves to absolute path
 * - Removes trailing slashes
 */
function normalizePath(p) {
  const home = process.env.HOME || "/Users/unknown";
  let normalized = p.trim();

  // Strip surrounding quotes
  normalized = normalized.replace(/^["']|["']$/g, "");

  // Expand ~
  if (normalized.startsWith("~/")) {
    normalized = home + normalized.slice(1);
  } else if (normalized === "~") {
    normalized = home;
  }

  // Expand $HOME
  normalized = normalized.replace(/\$HOME\b/g, home);
  normalized = normalized.replace(/\$\{HOME\}/g, home);

  // Resolve to absolute (handles . and ..)
  normalized = resolve(normalized);

  // Remove trailing slash
  normalized = normalized.replace(/\/+$/, "");

  return normalized;
}

/**
 * Check if a resolved target path would delete the protected directory.
 *
 * Returns true if:
 * - target === protected (exact match)
 * - target is a parent of protected (deleting parent kills child)
 */
function wouldDeleteCwd(targetPath, cwd) {
  const normalizedTarget = normalizePath(targetPath);
  const normalizedCwd = normalizePath(cwd);

  // Exact match
  if (normalizedTarget === normalizedCwd) return true;

  // Parent directory deletion (target is ancestor of CWD)
  if (normalizedCwd.startsWith(normalizedTarget + "/")) return true;

  return false;
}

const GLOB_CHARS = /[*?[]/;

/**
 * Resolve one rm/rmdir/mv operand against the directory the command runs in.
 *
 * Knowable from the text alone: `.`, `..`, relative and absolute paths, `~`, `$HOME`, `${HOME}`,
 * `$PWD`, `${PWD}`, `$(pwd)` and `` `pwd` `` (the last four are the directory the command is in at
 * that point, which follows any `cd` before it). Any other expansion (`$DIR`, `$(cmd)`) is
 * unknowable, returns null, and is not reported: the guard must not invent a target.
 *
 * Returns `{ path, glob }`: for an operand with a glob character, `path` is the directory part
 * before the first glob segment and `glob` is true, because `../*` can match the cwd itself while
 * `*` (children of the cwd) cannot.
 */
function resolveOperand(operand, dir, home) {
  let v = operand;
  v = v.replace(/^~(?=\/|$)/, home);
  v = v.replace(/\$\{HOME\}|\$HOME\b/g, home);
  v = v.replace(/\$\{PWD\}|\$PWD\b|\$\(pwd\)|`pwd`/g, dir);
  if (/[$`]/.test(v) || v === "") return null;
  const absolute = resolve(dir, v);
  if (!GLOB_CHARS.test(v)) return { path: absolute, glob: false };
  const segments = resolve(dir, v).split("/");
  const firstGlob = segments.findIndex((s) => GLOB_CHARS.test(s));
  return { path: segments.slice(0, firstGlob).join("/") || "/", glob: true };
}

/**
 * The text of a lexed word, with command substitutions restored.
 *
 * The lexer replaces a substitution in a word's decoded `value` with a placeholder (`$(…)`, `` `…` ``)
 * and keeps the source in `raw`. `$(pwd)` has to stay recognisable, so a word holding a placeholder
 * is read from `raw` with its double quotes removed (inside double quotes a substitution still runs).
 */
function operandText(word) {
  if (!word.value.includes("$(…)") && !word.value.includes("`…`")) return word.value;
  return word.raw.replace(/"/g, "");
}

/** rm needs -r/-R/--recursive to remove a directory at all. */
function rmIsRecursive(args) {
  for (const a of args) {
    if (a === "--") break;
    if (a === "--recursive") return true;
    if (/^-[A-Za-z]+$/.test(a) && /[rR]/.test(a)) return true;
  }
  return false;
}

/** Non-option operands (everything after `--` counts as an operand). */
function operandsOf(args) {
  const out = [];
  let endOfOptions = false;
  for (const a of args) {
    if (!endOfOptions && a === "--") {
      endOfOptions = true;
      continue;
    }
    if (!endOfOptions && a.startsWith("-") && a !== "-") continue;
    out.push(a);
  }
  return out;
}

/**
 * Detect if a bash command would delete the CWD.
 *
 * WHAT COUNTS (2026-10-17). Only an `rm -r` / `rmdir` / `mv` (as a source) INVOCATION whose operand
 * resolves to the protected directory or one of its parents. The previous version matched text:
 * any `rm` with an `-f` flag anywhere, plus `$PWD` or `$(pwd)` anywhere, was a hit, so
 * `pueue add -w "$PWD" -- cmd && rm -f reports/x.json` was denied as deleting the cwd. Invocations
 * are found with the shared walker (lib/shell-command-invocation-walker.ts): quoted text, comments
 * and heredocs written to files are not commands; `bash -c '…'` and `xargs` are looked through.
 *
 * Protected: the session cwd, always, and the directory the command has `cd`'d into by that point.
 * Claude Code resumes in the session cwd after a command, so deleting it from elsewhere still
 * strands the session. Relative operands resolve against the directory after any `cd`.
 *
 * @param {string} command - The bash command to check
 * @param {string} cwd - The current working directory
 * @returns {{ detected: boolean, target?: string, isGitOperation: boolean }}
 */
export function detectCwdDeletion(command, cwd) {
  if (!command || !cwd) {
    return { detected: false, isGitOperation: false };
  }

  // Check escape hatch (iter-109: delegated to canonical shared helper).
  if (hasFileWideEscapeHatchMarkerInContent(command, CWD_DELETION_GUARD_ESCAPE_HATCH_CONFIGURATION)) {
    return { detected: false, isGitOperation: false };
  }

  const home = process.env.HOME || homedir();
  const sessionCwd = normalizePath(cwd);
  let dir = sessionCwd;
  let hit = null;

  walkShellInvocations(command, /\b(?:rm|rmdir|mv|cd|pushd)\b/, (invocation) => {
    if (hit !== null) return;
    if (invocation.context === "ssh remote command") return; // another machine's filesystem
    const args = invocation.args.map(operandText);

    if ((invocation.program === "cd" || invocation.program === "pushd") && invocation.context === "command") {
      const target = args.find((a) => !a.startsWith("-"));
      const next = target === undefined ? { path: home, glob: false } : resolveOperand(target, dir, home);
      // An unknowable `cd` leaves relative operands unknowable too; keep only the session cwd.
      dir = next === null || next.glob ? sessionCwd : next.path;
      return;
    }

    let operands;
    if (invocation.program === "rm") {
      if (!rmIsRecursive(args)) return;
      operands = operandsOf(args);
    } else if (invocation.program === "rmdir") {
      operands = operandsOf(args);
    } else if (invocation.program === "mv") {
      operands = operandsOf(args).slice(0, -1); // sources only; the last operand is the destination
    } else {
      return;
    }

    for (const operand of operands) {
      const resolved = resolveOperand(operand, dir, home);
      if (resolved === null) continue;
      for (const protectedDir of new Set([sessionCwd, dir])) {
        const deletes = resolved.glob
          ? protectedDir.startsWith(`${resolved.path.replace(/\/$/, "")}/`)
          : wouldDeleteCwd(resolved.path, protectedDir);
        if (deletes) {
          hit = operand;
          return;
        }
      }
    }
  });

  if (hit === null) return { detected: false, isGitOperation: false };

  // Determine if this is a git-related operation (rm before clone)
  const isGit = /\bgit\s+(clone|init)\b/.test(command) || /\bgh\s+repo\s+clone\b/.test(command);
  return { detected: true, target: hit, isGitOperation: isGit };
}

/**
 * Format denial message with actionable guidance.
 *
 * @param {string} target - The path that would be deleted
 * @param {string} cwd - The current working directory
 * @param {boolean} isGitOperation - Whether this is a git clone/re-clone operation
 * @returns {string}
 */
export function formatDenial(target, cwd, isGitOperation) {
  const lines = [
    "[CWD DELETION GUARD] Blocked: This command would delete the current working directory.\n",
    `  CWD:    ${cwd}`,
    `  Target: ${target}\n`,
    "Deleting the CWD makes the shell unrecoverable — every subsequent",
    "command fails with exit code 1 (including cd). The entire session breaks.\n",
  ];

  if (isGitOperation) {
    lines.push("RECOMMENDED (git re-clone): Use git remote set-url instead of rm + clone:\n");
    lines.push("  git remote set-url origin <new-url>");
    lines.push("  git fetch origin");
    lines.push("  git reset --hard origin/main\n");
    lines.push("This preserves CWD, avoids re-downloading, and keeps local branches.");
  } else {
    lines.push("RECOMMENDED: delete it from a session whose working directory is elsewhere.");
    lines.push("A `cd` inside the same command does not help: the session resumes in its");
    lines.push("working directory after the command, and that directory would be gone.");
  }

  lines.push("\nEscape hatch: Add '# CWD-DELETE-OK' comment if intentional.");

  return lines.join("\n");
}
