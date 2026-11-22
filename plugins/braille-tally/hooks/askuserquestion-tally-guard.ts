#!/usr/bin/env bun
/**
 * PreToolUse guard: every AskUserQuestion carries a Braille Tally on each option.
 *
 * For each question it requires:
 *   1. every option label to start with a tally (2-6 Braille cells, one per axis) and one space, the same number of cells
 *      on every option of that question;
 *   2. the options to be in rank order: no later option beats an earlier one on every axis at once (Pareto order), so the
 *      first option is both the recommended and a top-ranked one.
 *
 * No legend is required in the question text (operator, 2026-11-20): AskUserQuestion always uses the default axes,
 * Importance · Urgency · Simplicity, so a legend line there is only a preamble the reader has to skip.
 *
 * DENY, never repair: the guard says exactly what to change and hands the call back.
 *
 * Escape hatch: the token BRAILLE-TALLY-EXEMPT anywhere in the tool input, for a question whose options cannot be ranked.
 * It is named in skills/braille-tally/SKILL.md and here, deliberately NOT in the deny message, so a retry that echoes the
 * message cannot silence the guard.
 *
 * Fail-open everywhere: unparseable stdin, an unexpected payload or a thrown error allows the call. A guard that crashes
 * must never block the user's own question UI.
 */
import { leadingTally, outOfRank, tally } from "../lib/tally.ts";

export const ESCAPE_TOKEN = "BRAILLE-TALLY-EXEMPT";

interface Option { label?: unknown; description?: unknown }
interface Question { question?: unknown; header?: unknown; options?: unknown }

/** The problems with one AskUserQuestion input, as plain sentences; empty means it passes. */
export function problems(input: unknown): string[] {
  if (!input || typeof input !== "object") return [];
  let serialized = "";
  try { serialized = JSON.stringify(input) ?? ""; } catch { return []; }
  if (serialized.includes(ESCAPE_TOKEN)) return [];
  const questions = (input as { questions?: unknown }).questions;
  if (!Array.isArray(questions)) return [];
  const out: string[] = [];
  questions.forEach((q: Question, qi) => {
    if (!q || typeof q !== "object" || !Array.isArray(q.options)) return;
    const name = typeof q.header === "string" && q.header ? `"${q.header}"` : `question ${qi + 1}`;
    const opts = (q.options as Option[]).map((o) => (o && typeof o.label === "string" ? o.label : ""));
    const parsed = opts.map((l) => leadingTally(l));
    const missing = opts.filter((_, i) => !parsed[i]);
    if (missing.length) {
      out.push(`${name}: ${missing.length} option label(s) do not start with a Braille Tally and one space: ${missing.map((l) => JSON.stringify(l)).join(", ")}.`);
      return;
    }
    const sizes = new Set(parsed.map((p) => p!.levels.length));
    if (sizes.size > 1) out.push(`${name}: every option needs the same number of cells (one per axis); found ${[...sizes].join(" and ")}.`);
    if (sizes.size === 1) {
      const bad = outOfRank(parsed.map((p) => p!.levels));
      if (bad) {
        const [i, j] = bad;
        out.push(`${name}: options are out of rank: option ${j + 1} (${tally(parsed[j]!.levels)}) beats option ${i + 1} (${tally(parsed[i]!.levels)}) on every axis, so it must come first. Order options by Pareto front, then by urgency.`);
      }
    }
  });
  return out;
}

export function denyMessage(found: string[]): string {
  return [
    "Every AskUserQuestion option carries a Braille Tally (braille-tally plugin): each option label starts with one Braille cell per axis, then a space, e.g. \"⣿⣶⣴ Keep the guard (Recommended)\".",
    "Level n (1-8) is the cell with n dots: ⡀ ⣀ ⣠ ⣤ ⣴ ⣶ ⣾ ⣿. Axes, always in this order: Importance (how much it serves the goal), Urgency (how soon it matters), Simplicity (how little it takes). No legend line in the question.",
    "Problems:",
    ...found.map((f) => `- ${f}`),
    "Fix the labels, then ask again. `bun \"$(cc-plugin-root braille-tally)/scripts/braille-tally.ts\" tally 8 6 5` prints a tally.",
  ].join("\n");
}

if (import.meta.main) {
  try {
    const raw = await Bun.stdin.text();
    const payload = JSON.parse(raw) as { tool_name?: string; tool_input?: unknown };
    if (payload.tool_name && payload.tool_name !== "AskUserQuestion") process.exit(0);
    const found = problems(payload.tool_input);
    if (found.length) {
      console.log(JSON.stringify({
        hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: denyMessage(found) },
      }));
    }
  } catch {
    // fail open
  }
  process.exit(0);
}
