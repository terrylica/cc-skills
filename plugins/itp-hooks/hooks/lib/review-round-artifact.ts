#!/usr/bin/env bun
/**
 * Pure core of the review-round gate: command classification and artifact validation.
 *
 * WHY THIS GATE EXISTS, IN NUMBERS. On Eon-Labs/alpha-forge, across 22 reviewed PRs from one
 * author, review submissions by the reviewer split like this:
 *
 *     PRs <= 400 changed lines   n=11   mean 1.36 review rounds   15 events total
 *     PRs  > 900 changed lines   n=7    mean 7.43 review rounds   52 events total
 *
 * Five PRs, all over 900 lines, accounted for 63% of every review event spent on that author's
 * work. Over a wider window of 40 merged PRs, 110 of 150 review submissions were rounds 2+ --
 * 73% of the reviewer's attention is RE-review, with Spearman rho ~ 0.71 between churn and rounds.
 *
 * So the scarce resource is not pull requests, it is ROUNDS. A cap on how many PRs may be open
 * meters ~27% of the load and leaves the rest untouched; worse, a queue-depth cap starves a bursty
 * reviewer (the same reviewer cleared 10 PRs in a single 7-hour sitting) and is shapeable into the
 * very flood it forbids -- two at the top of the hour, two at the end.
 *
 * This gate meters the transition to reviewable instead, and requires that a local adversarial
 * pass has happened AT THE EXACT COMMIT being shown to the reviewer.
 *
 * WHY EVERYTHING HERE IS LOCAL. A PreToolUse hook that times out does NOT block -- Claude Code
 * proceeds. So any check depending on a network call (`gh pr list`) resolves, when offline or rate
 * limited or slow, to ALLOW. That is Decision #484 -- absent data resolving to the favourable
 * answer -- reproduced inside a guard built to prevent it. Every input here is `git rev-parse`,
 * `git diff`, or a local file.
 *
 * WHAT THIS FILE DELIBERATELY DOES NOT DO: any I/O. Git and filesystem access are injected by the
 * caller, so the whole decision surface is testable without a repository and can be mutation-tested
 * without touching disk.
 */

import { createHash } from "node:crypto";

// ---------------------------------------------------------------------------------------------
// Command classification
// ---------------------------------------------------------------------------------------------

/**
 * Reused verbatim from pretooluse-pr-citation-evidence-guard.ts:86.
 *
 * Assignments and wrappers INTERLEAVE (`FOO=1 sudo env BAR=2 gh ...`), and a fixed-order pattern
 * matched only the first arrangement. Anchoring at a command position also means `echo "run gh pr
 * ready"` is not a match -- the string sits in an argument, not at the head of a command.
 */
// AN ASSIGNMENT VALUE MAY BE QUOTED AND MAY CONTAIN SPACES. The inherited pattern used `\S*` for
// the value, which stops at the first space -- so `GH_ORGS="Eon Labs" gh pr create …` did not match
// a command position at all and the guard silently ALLOWED it. Any quoted assignment with a space
// was a total bypass, including the guard's own override prefix, which made the override resolve to
// `allow` instead of `ask`. Found by the end-to-end test, not by reading; `FOO=bar` (unquoted) works
// either way, which is why the unit cases missed it.
//
// The same `\S*` appears in pretooluse-pr-citation-evidence-guard.ts:86, which this pattern was
// copied from, so that guard is likely bypassable the same way.
const COMMAND_POSITION = String.raw`(?:^|[\n;&|(){}]|&&|\|\|)\s*(?:(?:sudo|env|command|time)\s+|[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|\S*)\s+)*`;

/** Match `gh` by BASENAME, so `/opt/homebrew/bin/gh` and `"$GH"` are not free bypasses. */
const ghCommand = (rest: string) =>
  new RegExp(`${COMMAND_POSITION}(?:[\\w./-]*/)?gh\\s+${rest}`, "i");

const gitCommand = (rest: string) =>
  new RegExp(`${COMMAND_POSITION}(?:[\\w./-]*/)?git\\s+${rest}`, "i");

const GH_PR_READY = ghCommand(String.raw`pr\s+ready\b`);
const GH_PR_CREATE = ghCommand(String.raw`pr\s+create\b`);
const GIT_PUSH = gitCommand(String.raw`push\b`);

/**
 * Flags are tested against the command with QUOTED SPANS REMOVED.
 *
 * Whitespace boundaries are not enough, and the mutation harness is what proved it: in
 * `gh pr create --title "add a --draft flag to signal"` the substring ` --draft ` has a space on
 * both sides, so a `(?:^|\s)--draft(?=\s|$)` test matches text inside the TITLE and silently
 * exempts a non-draft PR from the gate. Stripping quoted spans first is what makes "is this a
 * flag" mean flag rather than "does this text appear anywhere".
 */
function withoutQuotedSpans(command: string): string {
  return command.replace(/'[^']*'/g, " '' ").replace(/"(?:\\.|[^"\\])*"/g, ' "" ');
}

const DRAFT_FLAG = /(?:^|\s)--draft(?:=true)?(?=\s|$)/;

/** `gh pr ready --undo` CONVERTS TO draft, i.e. it removes work from the queue. Never gate it. */
const READY_UNDO = /(?:^|\s)--undo(?=\s|$)/;

const hasFlag = (command: string, flag: RegExp) => flag.test(withoutQuotedSpans(command));

export type GatedKind = "pr-ready" | "pr-create" | "push" | "inline-body";

export interface Classification {
  readonly kind: GatedKind | null;
  /** Why this command was picked up, quoted back to the operator so a misfire is diagnosable. */
  readonly matched: string;
}

/**
 * Bodies published with `--body` inline rather than `--body-file`.
 *
 * The threshold is deliberate: a one-line `--body "Rebased; CI green."` must pass. Only a
 * multi-line or long body is gated, because that is the shape that (a) is worth reviewing before
 * it is published and (b) trips the existing same-repo-branch guard's shell tokenisation when it
 * contains parentheses or backticks.
 */
const INLINE_BODY_MAX = 300;
const BODY_FLAG = /--body(?:=|\s+)(['"])([\s\S]*?)\1/;

const PUBLISHES_A_BODY = ghCommand(
  String.raw`(?:pr\s+(?:create|comment|review)|issue\s+(?:create|comment))\b`,
);

export function classify(command: string): Classification {
  if (hasFlag(command, READY_UNDO) && GH_PR_READY.test(command)) {
    return { kind: null, matched: "" };
  }

  // INLINE BODY IS CHECKED FIRST, and the order is load-bearing rather than incidental. It is a
  // precondition on HOW the command is written, independent of whether a self-review record
  // exists -- so evaluating `pr-create` first meant a command with a valid artifact published a
  // 301-character inline body unchallenged. Caught by the case table, not by reading.
  //
  // It also applies to `--draft`, because the objection is that the body is composed in the same
  // command that publishes it, and that is true whether or not a reviewer sees it yet.
  if (PUBLISHES_A_BODY.test(command)) {
    const body = command.match(BODY_FLAG);
    if (body) {
      const value = body[2];
      if (value.includes("\n") || value.length > INLINE_BODY_MAX) {
        return { kind: "inline-body", matched: `--body with ${value.length} chars` };
      }
    }
  }

  const readyMatch = command.match(GH_PR_READY);
  if (readyMatch) return { kind: "pr-ready", matched: readyMatch[0].trim() };

  const createMatch = command.match(GH_PR_CREATE);
  if (createMatch && !hasFlag(command, DRAFT_FLAG)) {
    return { kind: "pr-create", matched: createMatch[0].trim() };
  }

  const pushMatch = command.match(GIT_PUSH);
  if (pushMatch) return { kind: "push", matched: pushMatch[0].trim() };

  return { kind: null, matched: "" };
}

// ---------------------------------------------------------------------------------------------
// The escape hatch
// ---------------------------------------------------------------------------------------------

/**
 * Anchored at the START of the command only.
 *
 * git-worktree-guard.ts anchors its own override loosely and that is a measured bypass: the token
 * appearing anywhere -- including inside a `--body` or a heredoc -- disarms it. Requiring it in the
 * environment-assignment position means the operator must actually prefix the command.
 *
 * Resolves to `ask`, never `allow`: a bypass should cost a human decision and be recorded, which is
 * what makes going around this gate charged and visible rather than free and silent.
 */
const OVERRIDE = /^\s*REVIEW_ROUND_OK=(?:"([^"]{12,})"|'([^']{12,})')\s+\S/;

export function overrideReason(command: string): string | null {
  const m = command.match(OVERRIDE);
  if (!m) return null;
  return (m[1] ?? m[2] ?? "").trim() || null;
}

// ---------------------------------------------------------------------------------------------
// The artifact
// ---------------------------------------------------------------------------------------------

export interface ReviewRoundArtifact {
  schema: number;
  head_sha: string;
  base_sha: string;
  diff_sha256: string;
  recorded_at: string;
  files: { path: string; verdict: string }[];
}

export interface RepoFacts {
  readonly headSha: string;
  readonly baseSha: string;
  readonly diffText: string;
  readonly changedPaths: readonly string[];
}

export const MIN_VERDICT_CHARS = 24;

export function sha256(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

export interface ValidationResult {
  readonly ok: boolean;
  readonly failures: readonly string[];
}

/**
 * Structural validation only.
 *
 * The teachback measurement on this repository is unambiguous about which kind of check survives:
 * pattern-matching checks failed 6 of 7 adversarial cases, structural ones failed 0 of 28. So every
 * rule below compares a recorded value against a value derived independently from git, and none of
 * them inspects the PROSE of a verdict beyond its length and distinctness.
 *
 * S5 is the one that costs something to fake. Writing one honest sentence per file is cheap; writing
 * the SAME sentence for six files is the cheapest possible ritual, and it is decidable by string
 * comparison.
 */
export function validateArtifact(
  artifact: ReviewRoundArtifact | null,
  facts: RepoFacts,
): ValidationResult {
  const failures: string[] = [];

  // S0 -- absence is refusal. "No artifact" must never read as "nothing to check"; that is the
  // exact shape of Decision #484 and it is the single most important line in this file.
  if (artifact === null) {
    return { ok: false, failures: ["no self-review record exists for this commit"] };
  }

  if (artifact.schema !== 1) {
    failures.push(`unknown artifact schema ${artifact.schema}; expected 1`);
  }

  // S1 -- exact, never a prefix. A 7-character abbreviation would let an artifact recorded at an
  // ancestor commit satisfy a later one.
  if (artifact.head_sha !== facts.headSha) {
    failures.push(
      `recorded at ${short(artifact.head_sha)} but HEAD is ${short(facts.headSha)} — the pass predates the code`,
    );
  }

  // S2 -- catches an artifact written BEFORE the last edit, which S1 alone cannot see when the
  // edit is uncommitted and HEAD has not moved.
  const actualDiffHash = sha256(facts.diffText);
  if (artifact.diff_sha256 !== actualDiffHash) {
    failures.push("the diff has changed since the pass was recorded");
  }

  // S3 -- EXACT SET EQUALITY, not superset and not subset. A superset check lets a file be added
  // after the pass; a subset check lets the record name files it never examined.
  const recorded = new Set(artifact.files.map((f) => f.path));
  const changed = new Set(facts.changedPaths);
  const unexamined = [...changed].filter((p) => !recorded.has(p));
  const phantom = [...recorded].filter((p) => !changed.has(p));
  if (unexamined.length > 0) {
    failures.push(`${unexamined.length} changed file(s) have no recorded verdict: ${unexamined.slice(0, 3).join(", ")}`);
  }
  if (phantom.length > 0) {
    failures.push(`${phantom.length} recorded file(s) are not in the diff: ${phantom.slice(0, 3).join(", ")}`);
  }

  // S4 -- a verdict has to say something.
  const tooShort = artifact.files.filter((f) => f.verdict.trim().length < MIN_VERDICT_CHARS);
  if (tooShort.length > 0) {
    failures.push(`${tooShort.length} verdict(s) under ${MIN_VERDICT_CHARS} characters`);
  }

  // S5 -- all-identical verdicts are ritual, not review.
  if (artifact.files.length > 1) {
    const distinct = new Set(artifact.files.map((f) => f.verdict.trim()));
    if (distinct.size !== artifact.files.length) {
      failures.push("verdicts are not distinct — the same text is reused across files");
    }
  }

  return { ok: failures.length === 0, failures };
}

function short(sha: string): string {
  return sha.slice(0, 8) || "(empty)";
}
