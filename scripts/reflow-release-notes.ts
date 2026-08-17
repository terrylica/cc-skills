#!/usr/bin/env bun
/**
 * reflow-release-notes — unwrap hard-wrapped prose before publishing a GitHub Release.
 *
 * GitHub renders release, issue and PR bodies with GFM hard line breaks: a single newline inside a
 * paragraph becomes a real `<br>`. Prose wrapped at a fixed column therefore renders as ragged,
 * mid-sentence breaks that ignore the reader's viewport instead of reflowing to it. It is invisible
 * in the source and shows up only on the published page.
 *
 * WHY THIS LIVES HERE. The doctrine (~/.claude/release-notes-doctrine-CLAUDE.md § "NEVER hard-wrap
 * the release body") says to enforce this in code rather than as a rule callers must remember, and
 * to port the reference implementation into the releasing repo. cc-skills previously enforced the
 * EXTENSIVENESS half of the doctrine in code (scripts/augment-release-notes.mjs measures narrative +
 * point form) while leaving the wrapping half to memory — so the published v26.0.1 body went out
 * hard-wrapped at ~68-71 columns, which `--check` on this file reproduces.
 *
 * The wrapping is not an authoring mistake to scold: git commit BODIES are correctly hard-wrapped at
 * ~72 columns, and release notes are assembled from them. The wrap is right in the commit and wrong
 * in the release, so the conversion belongs in the publisher.
 *
 * WHAT IS JOINED, AND WHAT IS NOT. Only PROSE is joined. Structure that depends on line boundaries is
 * preserved: fenced code blocks, headings, tables, blockquotes and horizontal rules.
 *
 * LIST ITEMS ARE JOINED TOO — this is the case everyone misses. A bullet whose text was wrapped must
 * fold back onto one line, because its tail is prose inside the item rather than a new block, so a
 * newline there also renders as a `<br>` mid-sentence. Paragraphs reflowing correctly while bullets
 * still break is the signature of a reflow that treats a list marker as "emit and move on" instead of
 * "start a joinable block". (The upstream reference at 459ecs/plaud implements this correctly but its
 * header comment lists "list items" among the things preserved verbatim, which reads as the opposite
 * of what its code does; corrected here.)
 *
 *   bun scripts/reflow-release-notes.ts < notes.md > flat.md
 *   bun scripts/reflow-release-notes.ts --check < notes.md   # exit 1 if it would change anything
 */

/**
 * A list item. It STARTS a block that later continuation lines join, because a wrapped bullet must
 * end up on one line — otherwise its tail renders as a `<br>` mid-sentence.
 */
const LIST_ITEM = /^\s*([-*+]\s|\d+[.)]\s)/;

/**
 * Single-line constructs. These stand alone: a following prose line begins a NEW block rather than
 * being absorbed (a heading must never swallow the paragraph beneath it).
 */
const STANDALONE = /^\s*(#{1,6}\s|>|\||---|\*\*\*|___|<)/;

/** A line that ends a paragraph on purpose: markdown's two-space hard break. */
const EXPLICIT_BREAK = /\s{2,}$/;

/**
 * Join hard-wrapped prose into one logical line per paragraph.
 * Blank lines remain the only paragraph separator, which is exactly how GFM reads them.
 */
export function reflowMarkdown(input: string): string {
  const lines = input.replace(/\r\n/g, "\n").split("\n");
  const out: string[] = [];
  let fenced = false;
  let building: string | null = null;

  const flush = () => {
    if (building !== null) out.push(building);
    building = null;
  };

  for (const line of lines) {
    if (/^\s*(```|~~~)/.test(line)) {
      flush();
      fenced = !fenced;
      out.push(line);
      continue;
    }
    if (fenced) {
      out.push(line);
      continue;
    }
    if (line.trim() === "") {
      flush();
      out.push("");
      continue;
    }
    if (STANDALONE.test(line) || EXPLICIT_BREAK.test(line)) {
      flush();
      out.push(line.replace(/\s+$/, ""));
      continue;
    }
    if (LIST_ITEM.test(line)) {
      // Start a joinable block so the item's wrapped tail folds back into the bullet.
      flush();
      building = line.trimEnd();
      continue;
    }
    // Prose — either a new paragraph, or the continuation of the paragraph/list item being built.
    building = building === null ? line.trimEnd() : `${building} ${line.trim()}`;
  }
  flush();
  return `${out
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trimEnd()}\n`;
}

/**
 * Compare CONTENT, ignoring trailing whitespace. GitHub keeps a trailing blank line on stored release
 * bodies, so a byte-exact comparison would report every already-flat release as still wrapped.
 */
export const normalizeForCompare = (s: string): string => s.replace(/\r\n/g, "\n").trimEnd();

/** True when `input` is already flat — i.e. reflowing would not change its content. */
export const isAlreadyFlat = (input: string): boolean =>
  normalizeForCompare(reflowMarkdown(input)) === normalizeForCompare(input);

if (import.meta.main) {
  const check = process.argv.includes("--check");
  const input = await Bun.stdin.text();
  const flat = reflowMarkdown(input);
  if (check) {
    if (isAlreadyFlat(input)) {
      console.error("[reflow-release-notes] already flat — no hard-wrapped prose found.");
      process.exit(0);
    }
    console.error("[reflow-release-notes] HARD-WRAPPED prose detected; reflowing would change this body.");
    process.exit(1);
  }
  process.stdout.write(flat);
}
