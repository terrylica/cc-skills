#!/usr/bin/env bun
/**
 * augment-release-notes — replace a GitHub Release's body with an extensive,
 * human-readable notes file, refusing to publish thin notes.
 *
 * Why: under the default semantic-release preset, generated notes are
 * subject-only. cc-skills fixes this in-generator via release.config.cjs
 * (body-preserving writerOpts). This helper is the MANUAL / cross-repo path:
 * for any repo (or a one-off fix-up), point it at a curated notes file and it
 * gates the file through the SAME extensiveness bar the itp-hooks
 * release-notes-extensiveness-guard enforces (narrative paragraph + point-form
 * list) before running `gh release edit`.
 *
 * The extensiveness measurement is imported from the guard's pure classifier —
 * ONE home for the rule, no re-implementation.
 *
 * Usage:
 *   bun scripts/augment-release-notes.mjs --tag <tag> --notes-file <path> [options]
 *
 * Options:
 *   --tag <tag>           Release tag to edit (e.g. v1.2.3).            [required]
 *   --notes-file <path>   Markdown file with the extensive notes.      [required]
 *   --repo <owner/repo>   Target repo (default: current repo via gh).
 *   --dry-run             Validate the notes file only; do not edit the release.
 *   --force               Edit even if the notes fail the extensiveness bar.
 *   --help                Show this help.
 *
 * Exit codes: 0 ok · 1 thin notes (not forced) · 2 usage/IO error.
 */

import { parseArgs } from "node:util";
import { readFileSync } from "node:fs";
import { measureNotesExtensiveness } from "../plugins/itp-hooks/hooks/release-notes-extensiveness-patterns.ts";

function printHelp() {
  // The banner above is the SSoT; keep this in sync with it.
  const header = "augment-release-notes — publish extensive GitHub Release notes (gated)";
  console.log(
    `${header}\n\n` +
      "Usage:\n  bun scripts/augment-release-notes.mjs --tag <tag> --notes-file <path> [options]\n\n" +
      "Options:\n" +
      "  --tag <tag>          Release tag to edit (required)\n" +
      "  --notes-file <path>  Markdown file with the extensive notes (required)\n" +
      "  --repo <owner/repo>  Target repo (default: current repo)\n" +
      "  --dry-run            Validate only; do not edit the release\n" +
      "  --force              Edit even if notes fail the extensiveness bar\n" +
      "  --help               Show this help",
  );
}

function fail(message, code = 2) {
  console.error(`[augment-release-notes] ${message}`);
  process.exit(code);
}

const { values } = parseArgs({
  options: {
    tag: { type: "string" },
    "notes-file": { type: "string" },
    repo: { type: "string" },
    "dry-run": { type: "boolean", default: false },
    force: { type: "boolean", default: false },
    help: { type: "boolean", default: false },
  },
  allowPositionals: false,
});

if (values.help) {
  printHelp();
  process.exit(0);
}
if (!values.tag) fail("missing --tag");
if (!values["notes-file"]) fail("missing --notes-file");

let notes;
try {
  notes = readFileSync(values["notes-file"], "utf8");
} catch (err) {
  fail(`cannot read --notes-file '${values["notes-file"]}': ${err instanceof Error ? err.message : err}`);
}

const measurement = measureNotesExtensiveness(notes);
if (!measurement.ok) {
  console.error("[augment-release-notes] notes are NOT extensive enough:");
  for (const reason of measurement.reasons) console.error(`  • ${reason}`);
  console.error(
    "  A release body needs BOTH a narrative paragraph AND a point-form list.\n" +
      "  See ~/.claude/release-notes-doctrine-CLAUDE.md. Re-run with --force to override.",
  );
  if (!values.force) process.exit(1);
  console.error("[augment-release-notes] --force set: proceeding despite thin notes.");
} else {
  console.log(
    `[augment-release-notes] notes pass the extensiveness bar ` +
      `(${measurement.bulletCount} bullets, ${measurement.narrativeChars}-char narrative).`,
  );
}

if (values["dry-run"]) {
  console.log("[augment-release-notes] --dry-run: not editing the release.");
  process.exit(0);
}

const ghArgs = ["release", "edit", values.tag, "--notes-file", values["notes-file"]];
if (values.repo) ghArgs.push("--repo", values.repo);

const proc = Bun.spawnSync(["gh", ...ghArgs], { stdout: "inherit", stderr: "inherit" });
if (proc.exitCode !== 0) fail(`gh release edit failed (exit ${proc.exitCode})`, proc.exitCode || 2);
console.log(`[augment-release-notes] ✓ ${values.tag} release body updated.`);
