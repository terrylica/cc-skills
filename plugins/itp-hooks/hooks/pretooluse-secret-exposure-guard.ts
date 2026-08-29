#!/usr/bin/env bun
/**
 * PreToolUse hook: live-credential exposure guard.
 *
 * Blocks a Write/Edit/MultiEdit whose NEW content would put a live credential
 * on disk — before the bytes land, and therefore before they can be committed,
 * pushed and published.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  The structural gap this closes
 * ════════════════════════════════════════════════════════════════════════
 *
 * A 23-repo audit found a LIVE Telegram bot token that survived TWO deliberate
 * scrub campaigns (gitleaks has no Telegram rule; only trufflehog's
 * provider-side verification caught it), LIVE Pushover app tokens and a user
 * key (bare 30-char alphanumerics that NO scanner detects by shape), and every
 * one of them was sitting in an ADR / design spec / planning doc as a worked
 * example of a `doppler secrets set …` provisioning command.
 *
 * Scanners in a gate run after the fact and are blind to these shapes. This
 * hook runs at the keystroke and is calibrated for exactly them.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Why this one BLOCKS
 * ════════════════════════════════════════════════════════════════════════
 *
 * The three credential detectors are structurally distinctive (a BotFather
 * `<id>:AA…` token, a 30-char bare token beside a Pushover cue, a provisioning
 * command with a non-placeholder literal), and the cost of a miss is a rotated
 * credential at best and a compromised bot at worst. Its sibling — the fuzzy
 * third-party-PII class — deliberately does NOT block; it lives in
 * `posttooluse-pii-exposure-reminder.ts` as a reminder, because a noisy guard
 * gets disabled and a disabled guard is worse than no guard.
 *
 * Escape hatch: `SECRET-SCAN-OK: <reason>` (reason ≥10 characters) anywhere in
 * the new content. A reason is REQUIRED here, unlike most markers in this repo,
 * because "I am sure this is fake" is the sentence that preceded every one of
 * the audit's findings.
 *
 * Fail-open everywhere: any parse/logic error allows the write. This guard
 * must never be the reason real work cannot proceed.
 */

import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import {
  buildCredentialDenyReason,
  type CredentialFinding,
  detectCredentialExposure,
} from "./lib/secret-and-pii-exposure-detector.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";

const HOOK_NAME = "pretooluse-secret-exposure-guard";

/** Operator escape hatch. A ≥10-character justification is mandatory. */
const SECRET_SCAN_OK_MARKER = "SECRET-SCAN-OK";
const SECRET_SCAN_OK_MINIMUM_REASON_CHARACTERS = 10;

const FILE_EDIT_TOOL_NAMES: ReadonlySet<string> = new Set(["Write", "Edit", "MultiEdit"]);

/**
 * Binary payloads are skipped: a NUL byte in the first kilobyte means the
 * "content" is not text a human authored, and the entropy of compressed bytes
 * would only manufacture false positives.
 */
function looksLikeBinaryPayload(content: string): boolean {
  return content.slice(0, 1024).includes("\u0000");
}

/**
 * Every string a Write/Edit/MultiEdit would ADD to disk. Only new content is
 * scanned — this guard exists to stop a credential being introduced, not to
 * re-litigate one already on disk (that is the audit gate's job, and blocking
 * an unrelated edit to a file that already leaks would be unactionable).
 */
export function collectNewContentFragmentsFromToolInput(
  toolInput: Record<string, unknown>,
): string[] {
  const fragments: string[] = [];
  const push = (value: unknown): void => {
    if (typeof value === "string" && value.length > 0) fragments.push(value);
  };

  push(toolInput.content);
  push(toolInput.new_string);

  const edits = toolInput.edits;
  if (Array.isArray(edits)) {
    for (const edit of edits) {
      if (edit && typeof edit === "object") {
        push((edit as Record<string, unknown>).new_string);
      }
    }
  }

  return fragments;
}

/**
 * Pure classifier (exported for tests): given the new-content fragments, return
 * the deny reason, or `null` when the write is clean or explicitly excused.
 *
 * Fragments are scanned SEPARATELY so a context window cannot be manufactured
 * across two unrelated edits in one MultiEdit.
 */
export function evaluateNewContentForCredentialExposure(
  filePath: string,
  fragments: readonly string[],
): string | null {
  const findings: CredentialFinding[] = [];

  for (const fragment of fragments) {
    if (looksLikeBinaryPayload(fragment)) continue;
    if (
      hasFileWideEscapeHatchMarkerInContent(fragment, {
        markerNameTokenIncludingSuffix: SECRET_SCAN_OK_MARKER,
        requireMinimumReasonCharacterCountAfterColonOrZeroForOptional:
          SECRET_SCAN_OK_MINIMUM_REASON_CHARACTERS,
      })
    ) {
      continue;
    }
    findings.push(...detectCredentialExposure(fragment));
  }

  if (findings.length === 0) return null;
  return buildCredentialDenyReason(filePath, findings);
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("SECRET-EXPOSURE-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;
  if (!FILE_EDIT_TOOL_NAMES.has(tool_name)) {
    allow();
    return;
  }

  const filePath = (tool_input.file_path as string) || "(unknown file)";
  const fragments = collectNewContentFragmentsFromToolInput(tool_input);
  if (fragments.length === 0) {
    allow();
    return;
  }

  const reason = evaluateNewContentForCredentialExposure(filePath, fragments);
  if (reason) {
    deny(reason);
    return;
  }

  allow();
}

if (import.meta.main) {
  main().catch((err) => {
    trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
    allow();
  });
}
