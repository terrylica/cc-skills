#!/usr/bin/env bun
/**
 * PostToolUse hook: Python-preference nudge (orchestrator-inlined subhook).
 *
 * ── Why this hook exists (operator directive 2026-06-25) ──────────────────
 *
 * The user's language-selection doctrine (`~/.claude/principles-CLAUDE.md`
 * §"Language selection default") prefers Bun/TypeScript over Python (and Go
 * over Rust) for greenfield code, reserving Python for genuine SOTA-native
 * lanes (ML / data-science / quant: numpy, polars, torch, MetaTrader5) or an
 * existing Python convention. Nothing surfaced that preference at the moment
 * an agent writes a `.py` file, so greenfield Python crept in silently.
 *
 * This subhook fires on EVERY Write/Edit of a `.py` file and emits a
 * non-blocking, Claude-visible reminder UNLESS that specific file has been
 * EXPLICITLY allowed — with a justification — in a `python-allowlist.toml`
 * discovered by walking up from the file toward the project root.
 *
 * ── Allow mechanism (the ONLY way to silence the nudge for a file) ────────
 *
 * Centralized, machine-readable TOML (lychee / gitleaks / CODEOWNERS
 * lineage; matches the CLI-first machine-readable-SSoT doctrine). NO inline
 * pragma — the TOML is the single allow channel. A file is allowed iff some
 * ancestor `python-allowlist.toml` contains an `[[allow]]` entry whose
 * `path` (resolved relative to THAT allowlist's directory) matches the file
 * AND whose `reason` is a non-empty trimmed string. Reason-gated, PR-reviewed
 * (no content-hash pinning) — editing an already-listed file stays silent.
 *
 *   # python-allowlist.toml
 *   [[allow]]
 *   path   = "services/etl/legacy_load.py"   # relative to this file's dir
 *   reason = "pandas-native ETL; migration tracked"
 *   issue  = "eon/mono#1234"                  # optional
 *
 * NO blanket suppression: being inside a Python project (even legacy) does
 * NOT exempt its files — every `.py` must be allowed individually.
 *
 * The ONE implicit exemption is ephemeral throwaway scratch under a temp dir
 * (`/tmp`, `$TMPDIR`, …) via the shared iter-124 helper — those files are
 * discarded, so nudging on them is pure noise. This never applies to project
 * files.
 *
 * Fail-open everywhere: any unexpected error → `noop`. A malformed individual
 * allowlist file contributes ZERO entries (it does NOT grant blanket silence)
 * — that is stricter than a generic fail-open and is deliberate.
 *
 * Schema: ../schemas/python-allowlist.schema.json (JSON Schema 2020-12).
 * Spoke: ./docs/python-preference-nudge.md
 * ADR:   /docs/adr/2026-06-25-python-preference-nudge-per-file-toml-allowlist.md
 */

import { existsSync, readFileSync } from "node:fs";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import { homedir } from "node:os";
import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
  isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import { truncateHookOutputToStayBelowClaudeFileSpilloverThreshold } from "./lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts";
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";

// --- Constants ---

const PYTHON_ALLOWLIST_FILENAME = "python-allowlist.toml";

/**
 * Path substrings that mark a `.py` file as NOT first-party project source
 * (vendored deps, virtualenvs, caches, git internals). Edits there never
 * warrant a language-preference nudge.
 */
const NON_FIRST_PARTY_PATH_SEGMENTS: readonly string[] = [
  "/.venv/",
  "/venv/",
  "/node_modules/",
  "/site-packages/",
  "/__pycache__/",
  "/.git/",
  "/.tox/",
  "/.mypy_cache/",
];

// ══════════════════════════════════════════════════════════════════════════
//  Allowlist resolution (pure, testable — does NOT apply the temp-scratch skip)
// ══════════════════════════════════════════════════════════════════════════

/**
 * Collect every `python-allowlist.toml` from the edited file's directory up
 * toward the project root. The walk stops at (and INCLUDES) the first
 * directory containing a `.git` entry (the repo root), at the user's home
 * directory, or at the filesystem root — whichever comes first. Returns the
 * absolute allowlist paths nearest-first.
 */
export function findApplicablePythonAllowlistFiles(startDirectory: string): string[] {
  const allowlistFiles: string[] = [];
  const home = homedir();
  let dir = resolve(startDirectory);

  // Bounded walk: filesystem depth is finite; the parent === dir check
  // terminates at the root. The .git / home guards keep us inside one repo.
  for (;;) {
    const candidate = join(dir, PYTHON_ALLOWLIST_FILENAME);
    if (existsSync(candidate)) allowlistFiles.push(candidate);

    // Include the repo-root allowlist (added above) then stop at the boundary.
    if (existsSync(join(dir, ".git"))) break;
    if (dir === home) break;

    const parent = dirname(dir);
    if (parent === dir) break; // filesystem root
    dir = parent;
  }

  return allowlistFiles;
}

/** Parse one allowlist file into normalized entries; never throws. */
function readAllowlistEntries(
  allowlistFilePath: string,
): Array<{ path: string; reason: string }> {
  try {
    const raw = readFileSync(allowlistFilePath, "utf8");
    const parsed = Bun.TOML.parse(raw) as { allow?: unknown };
    const allow = parsed?.allow;
    if (!Array.isArray(allow)) return [];
    const entries: Array<{ path: string; reason: string }> = [];
    for (const item of allow) {
      if (!item || typeof item !== "object") continue;
      const entryPath = (item as Record<string, unknown>).path;
      const entryReason = (item as Record<string, unknown>).reason;
      if (typeof entryPath !== "string") continue;
      if (typeof entryReason !== "string") continue;
      // Reason-gated: a blank/whitespace-only reason does NOT count as allowed.
      if (entryReason.trim().length === 0) continue;
      entries.push({ path: entryPath, reason: entryReason });
    }
    return entries;
  } catch {
    // Malformed/unreadable allowlist contributes ZERO entries — it must not
    // grant blanket silence. Stricter than a generic fail-open, by design.
    return [];
  }
}

/**
 * Whether `filePath` is explicitly allowed by some ancestor
 * `python-allowlist.toml` with a non-empty reason. Pure filesystem read; does
 * NOT consider the temp-scratch exemption (the classifier handles that first).
 */
export function isPythonFileExplicitlyAllowed(filePath: string): boolean {
  const absoluteFile = resolve(filePath);
  const allowlistFiles = findApplicablePythonAllowlistFiles(dirname(absoluteFile));
  for (const allowlistFile of allowlistFiles) {
    const allowlistDir = dirname(allowlistFile);
    for (const entry of readAllowlistEntries(allowlistFile)) {
      // Entry path resolves relative to the allowlist file's own directory.
      if (resolve(allowlistDir, entry.path) === absoluteFile) return true;
    }
  }
  return false;
}

// ══════════════════════════════════════════════════════════════════════════
//  Nudge evaluation (pure, testable — gates minus the temp-scratch skip)
// ══════════════════════════════════════════════════════════════════════════

export interface PythonPreferenceNudgeEvaluation {
  shouldNudge: boolean;
  /** Display path for the reminder (project-relative when resolvable). */
  relativePath: string;
}

const NO_NUDGE: PythonPreferenceNudgeEvaluation = { shouldNudge: false, relativePath: "" };

/** Project-relative display path when under CLAUDE_PROJECT_DIR, else basename. */
function toDisplayRelativePath(filePath: string): string {
  const projectDir = process.env.CLAUDE_PROJECT_DIR; // SSoT-OK: Claude-runtime-injected project root is the SSoT for display-relative paths
  if (projectDir) {
    try {
      const rel = relative(projectDir, filePath);
      if (rel && !rel.startsWith("..") && !isAbsolute(rel)) return rel;
    } catch {
      // fall through to basename
    }
  }
  return basename(filePath);
}

/**
 * Decide whether a Write/Edit of `filePath` should nudge — independent of the
 * temp-scratch exemption so the allow/deny logic is unit-testable with
 * fixtures placed under a temp directory.
 */
export function evaluatePythonPreferenceNudgeIgnoringTempScratch(
  toolName: string | undefined,
  filePath: string | undefined,
): PythonPreferenceNudgeEvaluation {
  if (!isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook(toolName)) return NO_NUDGE;
  if (!filePath) return NO_NUDGE;
  if (!filePath.endsWith(".py")) return NO_NUDGE;
  if (NON_FIRST_PARTY_PATH_SEGMENTS.some((seg) => filePath.includes(seg))) return NO_NUDGE;
  if (isPythonFileExplicitlyAllowed(filePath)) return NO_NUDGE;
  return { shouldNudge: true, relativePath: toDisplayRelativePath(filePath) };
}

/** The Claude-visible reminder text. */
export function buildPythonPreferenceReminderMessage(relativePath: string): string {
  return [
    `[PY-PREFER] ${relativePath} is a Python file with no explicit allow entry.`,
    ``,
    `Default preference: Bun/TypeScript for greenfield (Go/Rust per SOTA) —`,
    `see ~/.claude/principles-CLAUDE.md §"Language selection default".`,
    `Python IS correct for SOTA-native lanes (ML/data/quant: numpy, polars,`,
    `torch, MetaTrader5) or an existing Python project — but each .py must be`,
    `EXPLICITLY allowed, one file at a time.`,
    ``,
    `To keep this file, add an entry to the nearest python-allowlist.toml:`,
    ``,
    `  [[allow]]`,
    `  path   = "${relativePath}"   # relative to the allowlist file's directory`,
    `  reason = "<why Python is the right choice here>"`,
    ``,
    `Otherwise prefer reimplementing in Bun/TypeScript (or Go/Rust for`,
    `perf-critical / systems work).`,
  ].join("\n");
}

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

export async function classifyPythonPreferenceNudgeForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    const filePath = input.tool_input?.file_path;
    // The ONE implicit exemption: ephemeral throwaway scratch under a temp dir.
    if (isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const evaluation = evaluatePythonPreferenceNudgeIgnoringTempScratch(input.tool_name, filePath);
    if (!evaluation.shouldNudge) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    return buildPostToolUseAdditionalContextDecision(
      truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(
        buildPythonPreferenceReminderMessage(evaluation.relativePath),
      ),
    );
  } catch {
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Standalone CLI entry point
// ══════════════════════════════════════════════════════════════════════════

async function runStandaloneCliMain(): Promise<void> {
  const inputText = await Bun.stdin.text();

  let input: PostToolUseInput;
  try {
    input = JSON.parse(inputText) as PostToolUseInput;
  } catch {
    process.exit(0);
  }

  const decision = await classifyPythonPreferenceNudgeForPostToolUseOrchestrator(input);
  if (decision.kind === "additional_context") {
    console.log(JSON.stringify({ decision: "block", reason: decision.message }));
  }
  process.exit(0);
}

if (import.meta.main) {
  runStandaloneCliMain().catch(() => {
    process.exit(0);
  });
}
