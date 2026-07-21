#!/usr/bin/env bun
/**
 * PreToolUse hook: Release-Notes Extensiveness Guard
 *
 * Hard-blocks release/tag-publishing commands whose notes are not extensive and
 * human-readable. Every release — any repo, any bump — must carry BOTH a
 * narrative paragraph (the "why") AND a point-form summary. Terse commit-dump
 * releases (opendeviationbar-py v13.79.0 style) are blocked.
 *
 * Interception points (see release-notes-extensiveness-patterns.ts):
 *   - gh release create|edit  → measure inline --notes / --notes-file text
 *   - git tag -a/-s/-m/-F <semver>  → measure the annotated-tag message
 *   - semantic-release / mise run release[:*]  → inspect releasable commit bodies
 *
 * Escape hatch: add `RELEASE-NOTES-OK: <≥10-char reason>` to the command for a
 * genuinely un-narratable release (pure dependency/chore bump).
 *
 * Fail-open: any parse/logic/IO error allows the command (never blocks work).
 *
 * Doctrine SSoT: ~/.claude/release-notes-doctrine-CLAUDE.md
 * ADR: /docs/adr/2026-07-21-release-notes-extensiveness-guard.md
 * Spoke: plugins/itp-hooks/docs/release-notes-extensiveness-guard.md
 */

import { readFileSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import {
  classifyReleaseCommand,
  measureNotesExtensiveness,
  inspectReleasableCommitBodies,
  buildNotesDenyMessage,
  buildNotesAbsentDenyMessage,
  buildCommitDenyMessage,
} from "./release-notes-extensiveness-patterns.ts";

const HOOK_NAME = "release-notes-extensiveness-guard";

/** Reason-gated escape hatch (≥10 chars of justification after the colon). */
const RELEASE_NOTES_OK = {
  markerNameTokenIncludingSuffix: "RELEASE-NOTES-OK",
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
} as const;

/** Fast-path: if none present, no release/tag tool is involved. */
const FAST_PATH_KEYWORDS = ["gh", "git", "release"];

function isException(command: string): boolean {
  if (hasFileWideEscapeHatchMarkerInContent(command, RELEASE_NOTES_OK)) return true;
  const lower = command.toLowerCase();
  if (/^\s*(echo|printf)\s/i.test(lower)) return true;
  if (/^\s*#/.test(command)) return true;
  if (/^\s*(grep|egrep|fgrep|rg|ag|ack)\b/i.test(lower)) return true;
  return false;
}

/** Read a literal notes-file path; returns null if unreadable (→ fail-open). */
function readNotesFile(path: string, cwd?: string): string | null {
  try {
    const abs = isAbsolute(path) ? path : resolve(cwd ?? process.cwd(), path);
    return readFileSync(abs, "utf8");
  } catch {
    return null;
  }
}

async function main() {
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

  const lower = command.toLowerCase();
  if (!FAST_PATH_KEYWORDS.some((kw) => lower.includes(kw))) {
    allow();
    return;
  }
  if (isException(command)) {
    allow();
    return;
  }

  const verdict = classifyReleaseCommand(command);
  if (!verdict.isRelease) {
    allow();
    return;
  }

  const segment = verdict.segment ?? command;

  // ---- semantic-release: inspect commit bodies (the notes source) --------
  if (verdict.kind === "semantic-release") {
    const inspection = inspectReleasableCommitBodies(input.cwd ?? process.cwd());
    if (inspection.ok) {
      allow();
      return;
    }
    deny(buildCommitDenyMessage(segment, inspection));
    return;
  }

  // ---- gh release / git tag: measure the inline notes text ---------------
  // Cannot prove thinness of a variable / command-substitution → fail-open.
  if (verdict.notesUnmeasurable) {
    allow();
    return;
  }
  if (verdict.notesAbsent) {
    deny(buildNotesAbsentDenyMessage(segment));
    return;
  }

  let notes = verdict.notesText;
  if (notes === undefined && verdict.notesFile) {
    const fileText = readNotesFile(verdict.notesFile, input.cwd);
    if (fileText === null) {
      allow(); // unreadable file → cannot measure → fail-open
      return;
    }
    notes = fileText;
  }
  if (notes === undefined) {
    allow();
    return;
  }

  const measurement = measureNotesExtensiveness(notes);
  if (measurement.ok) {
    allow();
    return;
  }
  deny(buildNotesDenyMessage(segment, measurement));
}

main().catch((err) => {
  trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
  allow();
});
