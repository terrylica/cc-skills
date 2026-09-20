#!/usr/bin/env bun

/**
 * PreToolUse hook: TCC grant ordering + launchd Label addressing guard.
 *
 * Blocks two macOS uninstall mistakes that are IRREVERSIBLE or DESTRUCTIVE, and that both present
 * as success at the moment you make them.
 *
 * ── Violation 1: deleting an application before resetting its TCC grants ──────────────────────
 *
 * `tccutil reset <Service> <bundleid>` resolves the identifier through LaunchServices BEFORE it
 * touches the database. Once the bundle is gone the identifier no longer resolves, every reset
 * fails with -10814 kLSApplicationNotFoundErr, and the grant is stranded: macOS never garbage-
 * collects these rows, and System Settings does not render a row whose bundle will not resolve, so
 * there is no GUI path either. The grant then silently returns if the app is ever reinstalled with
 * the same signing identity, because the row's csreq pins the developer, not the install.
 *
 * Measured 2026-09-20: an uninstall script deleted the apps in stage 2 and attempted 98 TCC resets
 * in stage 9. All 98 failed. Recovering them required staging a fake .app in /Applications carrying
 * each orphaned identifier so LaunchServices would resolve it again — a workaround that exists only
 * because the ordering was wrong.
 *
 * The fix is free and takes one command, but ONLY BEFORE the delete. That asymmetry — trivial
 * beforehand, elaborate afterwards, and invisible either way — is what earns a block.
 *
 * ── Violation 2: addressing a launchd job by plist FILENAME ───────────────────────────────────
 *
 * launchctl addresses a job by the Label INSIDE the plist. A vendor plist named
 * `com.vendor.vendor_service.plist` can carry `Label com.vendor.service`. Then:
 *
 *     launchctl bootout system/com.vendor.vendor_service
 *
 * returns ESRCH, prints nothing alarming, and leaves a live KeepAlive job running — after which the
 * usual next step is deleting the binary out from under it. Measured 2026-09-20 on a real
 * TeamViewer uninstall: two of its plists carried a Label that differed from the filename.
 *
 * This guard cannot read the plist (it only sees a command string), so it blocks the shape that is
 * always wrong: a bootout/kickstart target derived from a `.plist` path or ending in a segment that
 * looks like a filename stem. Resolve the Label first.
 *
 * ── Deliberately NOT blocked ──────────────────────────────────────────────────────────────────
 *
 * Read-only inspection of any kind (`ls`, `plutil -p`, `launchctl list`, `launchctl print`), and
 * deleting anything that is not an application bundle. A positive destructive-verb signal is
 * required before any violation is reported.
 *
 * Knowledge SSoT (this file duplicates none of it):
 *   macos-permissions plugin — skills/tcc-grant-audit/SKILL.md, skills/persistence-audit/SKILL.md
 */

import {
  type EscapeHatchMarkerDetectionConfiguration,
  hasFileWideEscapeHatchMarkerInContent,
} from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import {
  allow,
  deny,
  parseStdinOrAllow,
  trackHookError,
} from "./pretooluse-helpers.ts";

/** Operator escape hatch. A >=10-character justification is mandatory. */
const TCC_ORDERING_ESCAPE_HATCH: Pick<
  EscapeHatchMarkerDetectionConfiguration,
  | "markerNameTokenIncludingSuffix"
  | "requireMinimumReasonCharacterCountAfterColonOrZeroForOptional"
> = {
  markerNameTokenIncludingSuffix: "TCC-ORDERING-OK",
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
};

export interface TccOrderingViolation {
  kind: "app-delete-before-tcc-reset" | "launchd-target-is-filename";
  detail: string;
}

/** Verbs that only READ. Any of these vetoes the whole check for that command. */
const INSPECTION_ONLY = /\b(ls|stat|file|plutil\s+-p|plutil\s+-lint|cat|grep|find\s+[^|]*-print|codesign\s+-d|launchctl\s+(list|print|print-disabled)|mdls|du)\b/;

/** Commands that remove an application bundle. */
const APP_DELETE =
  /(\brm\s+(-[a-zA-Z]*\s+)*[^|;&]*?\/[^\s|;&]+\.app\b)|(\bbrew\s+uninstall\b[^|;&]*--cask\b)|(\bbrew\s+uninstall\s+--cask\b)|(\btrash\s+[^|;&]*\.app\b)/;

/** A tccutil reset anywhere in the same command means the author already knows the rule. */
const TCC_RESET_PRESENT = /\btccutil\s+reset\b/;

/** launchctl subcommands that address a job by label. */
const LAUNCHCTL_TARGETED =
  /\blaunchctl\s+(bootout|kickstart|enable|disable|kill)\s+(\S+)/;

/**
 * A launchd target whose last path segment still looks like a plist FILENAME rather than a Label.
 * `system/com.vendor.vendor_service.plist` is unambiguous; so is a target built by interpolating a
 * basename. A bare `system/com.vendor.service` is indistinguishable from a correct Label and is
 * therefore allowed — this guard only catches the provable cases.
 */
function launchdTargetLooksLikeFilename(target: string): boolean {
  if (/\.plist(\b|$)/.test(target)) return true;
  // Built from a filename variable: system/$(basename "$f" .plist), system/${base}
  if (/basename/.test(target)) return true;
  return false;
}

export function findTccOrderingViolations(
  command: string,
): TccOrderingViolation[] {
  const violations: TccOrderingViolation[] = [];
  if (!command.trim()) return violations;

  // Inspection verbs veto everything. Blocking `ls /Applications/Foo.app` would be infuriating and
  // teaches people to reach for the escape hatch reflexively.
  const destructive = APP_DELETE.test(command);
  if (destructive && !TCC_RESET_PRESENT.test(command)) {
    const match = command.match(APP_DELETE);
    violations.push({
      kind: "app-delete-before-tcc-reset",
      detail: (match?.[0] ?? command).trim().slice(0, 160),
    });
  }

  const lc = command.match(LAUNCHCTL_TARGETED);
  if (lc?.[2] && launchdTargetLooksLikeFilename(lc[2])) {
    violations.push({
      kind: "launchd-target-is-filename",
      detail: lc[0].trim().slice(0, 160),
    });
  }

  return violations;
}

export function explainTccOrderingViolations(
  violations: TccOrderingViolation[],
): string {
  const parts: string[] = [];

  for (const v of violations) {
    if (v.kind === "app-delete-before-tcc-reset") {
      parts.push(
        [
          "[TCC ORDERING] About to delete an application bundle without resetting its privacy grants first.",
          "",
          `  ${v.detail}`,
          "",
          "tccutil resolves a bundle identifier through LaunchServices BEFORE touching the database.",
          "Once the .app is gone the identifier no longer resolves, every reset fails with",
          "-10814 kLSApplicationNotFoundErr, and the grant is stranded FOREVER: macOS never prunes",
          "these rows, and System Settings hides a row whose bundle will not resolve, so there is no",
          "GUI path either. The grant silently returns if the app is reinstalled with the same",
          "signing identity.",
          "",
          "Do this FIRST, while the bundle still resolves:",
          "  /usr/bin/tccutil reset All <bundle-id>",
          "  sqlite3 -readonly \"/Library/Application Support/com.apple.TCC/TCC.db\" \\",
          "    \"SELECT service FROM access WHERE client='<bundle-id>' AND auth_value=2;\"   # verify",
          "",
          "tccutil prints \"Successfully reset\" and exits 0 even when it deleted nothing, so verify",
          "against the database, not the exit code.",
        ].join("\n"),
      );
    } else {
      parts.push(
        [
          "[LAUNCHD LABEL] A launchctl target derived from a plist FILENAME.",
          "",
          `  ${v.detail}`,
          "",
          "launchctl addresses a job by the Label INSIDE the plist, which frequently differs from the",
          "filename. Targeting the filename returns ESRCH, prints nothing alarming, and leaves a live",
          "KeepAlive job running — usually just before its binary gets deleted out from under it.",
          "",
          "Resolve the Label first, and refuse to guess if there is not one:",
          "  label=\"$(/usr/libexec/PlistBuddy -c 'Print :Label' \"$plist\")\"",
          "  [ -n \"$label\" ] || { echo 'no Label key — refusing to guess'; exit 1; }",
          "  launchctl bootout \"system/$label\"",
        ].join("\n"),
      );
    }
  }

  parts.push(
    `\nIf this is genuinely correct, add a marker with a reason of at least 10 characters:\n  TCC-ORDERING-OK: <why this ordering is safe here>`,
  );
  return parts.join("\n\n");
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("TCC-GRANT-ORDERING-GUARD");
  if (!input) return;

  const { tool_name, tool_input } = input;
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = (tool_input as { command?: string }).command || "";

  if (INSPECTION_ONLY.test(command) && !APP_DELETE.test(command)) {
    allow();
    return;
  }

  if (hasFileWideEscapeHatchMarkerInContent(command, TCC_ORDERING_ESCAPE_HATCH)) {
    allow();
    return;
  }

  const violations = findTccOrderingViolations(command);
  if (violations.length === 0) {
    allow();
    return;
  }

  deny(explainTccOrderingViolations(violations));
}

main().catch((err) => {
  // Fail OPEN. A guard that blocks work when its own logic throws is worse than the bug it prevents.
  trackHookError(
    "pretooluse-tcc-grant-ordering-guard",
    err instanceof Error ? err.message : String(err),
  );
  allow();
});
