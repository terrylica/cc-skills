#!/usr/bin/env bun
// PROCESS-STORM-OK: this module is pure. It spawns nothing, imports no child_process/Bun.spawn,
// and every loop here walks a fixed, already-parsed token array. The `for (const token of ...)`
// shape below is flagged by a heuristic that cannot see that.
/**
 * Pure core of the PR review-invitation gate: does this command submit a BLOCKING review, and is
 * the actor entitled to submit one?
 *
 * WHY THIS GATE EXISTS, AND WHY IT IS NARROW. On 2026-09-06 an agent posted CHANGES_REQUESTED on
 * Eon-Labs/alpha-forge#656 -- authored by the CEO -- on the strength of a premise it had invented
 * ("waiting on my review"). No request existed; one arrived 19h29m LATER. The review's CONTENT was
 * substantive and largely adopted. The defect was its FORM and its PREMISE, not its findings.
 *
 * SO THE GATE DOES NOT ADJUDICATE, AND CANNOT. Measured over ten months on that repo, all 6 of the
 * reviewer's CHANGES_REQUESTED reviews on other people's PRs were uninvited, and 5 drew no
 * objection (#591 and #587 went CHANGES_REQUESTED -> APPROVED within ~35 minutes, an ordinary
 * round). No fact available at command time separates #656 from those five. A gate that DENIED on
 * "uninvited" would carry 5 false positives per true positive. What it does instead is make the
 * blocking form COST one deliberate keystroke, and put the queried facts in front of the human at
 * the moment of the act. Preventing anything is not the claim.
 *
 * WHAT IT DELIBERATELY LEAVES ALONE:
 *   --approve   17 of these on other authors' PRs, 10 since 2026-08-21. The `main` ruleset requires
 *               1 approving review and GitHub forbids self-approval, so terrylica<->ChenLi0830 is a
 *               reciprocal approval pair and it is the ONLY way anything merges there. Gating it
 *               would deadlock the repository, which is worse than the harm this gate prevents.
 *   --comment   Carries identical findings without gating. The honest description of this guard's
 *               effect is a RENAME, not a prevention.
 *   issues      `gh issue close` / `gh issue comment` on a collaborator's issue is ordinary triage.
 *
 * WHY THE INVITATION FACT IS THE TIMELINE, NOT `requested_reviewers`. GitHub CLEARS a user from
 * `requested_reviewers` the moment they submit a review -- measured on #201 and #35, both of which
 * read `[]` after their INVITED reviews. Since 73% of review submissions here are rounds 2+,
 * reading the live array would make legitimate re-review this guard's dominant false positive.
 *
 * ---------------------------------------------------------------------------------------------
 * WHY THIS FILE TOKENIZES INSTEAD OF PATTERN-MATCHING, WRITTEN AFTER PAYING FOR IT THREE TIMES.
 *
 * The first three versions of this classifier ran regexes over three DIFFERENT manglings of the
 * command string: `withoutQuotedSpans` (deletes quoted spans, handles backslash escapes), a
 * `dequote` helper (removes quote characters, keeps content, NO escape handling), and a hand-rolled
 * quote scanner (NO escape handling). Because those three grammars disagreed with each other, every
 * round of fixes introduced new P0 fail-opens in the cases the previous round was not thinking
 * about. All measured end to end against a live uninvited target:
 *
 *   -R "owner/repo"                  -> repo erased       -> resolved the CWD repo         -> ALLOW
 *   -f "event=REQUEST_CHANGES"       -> not a review at all                                -> ALLOW
 *   timeout 15 gh pr review 682 ...  -> number 15         -> queried a self-authored PR    -> ALLOW
 *   --body "... /pull/679"           -> number 679        -> queried a self-authored PR    -> ALLOW
 *   --body 'don'\''t; ...' -r        -> segment truncated -> the flag never seen           -> ALLOW
 *   --approve && grep -r TODO        -> read as blocking  -> GATED an approval (deadlock)
 *
 * Every one of those is a quoting or scoping bug that a shell-correct tokenizer does not have, and
 * this directory already contained one: `shell-arg-extractor.ts`, whose own header says it is the
 * SSoT for "pull a flag's value out of a shell command string -- the pattern several PreToolUse
 * guards re-implement". Re-implementing it is exactly what produced every defect above.
 *
 * So: `readShellArg` does the parsing, once. A FLAG is an UNQUOTED token; a VALUE is whatever the
 * next token decodes to, quoted or not; a TARGET comes only from a POSITIONAL. Prose inside
 * `--body` is a value and can therefore never donate a target, name a flag, or fabricate a
 * command position.
 *
 * NO I/O HERE. Facts are injected, so every branch is unit-testable and mutation-testable.
 */

import { readShellArg, type ShellQuoteKind } from "./shell-arg-extractor.ts";
import { COMMAND_POSITION, withoutQuotedSpans } from "./review-round-artifact.ts";

// ---------------------------------------------------------------------------------------------
// Tokenizing
// ---------------------------------------------------------------------------------------------

interface Token {
  /** Shell-decoded value. */
  readonly value: string;
  readonly quote: ShellQuoteKind;
  /** Offset of the first character of the token in the source command. */
  readonly start: number;
  /** Offset just past the token. */
  readonly end: number;
  /** True when the run of blanks before this token contained a newline. */
  readonly afterNewline: boolean;
}

/** A token only counts as a FLAG when the shell would have seen it unquoted. */
const isBare = (token: Token): boolean => token.quote === "none";

function tokenize(command: string): Token[] {
  const tokens: Token[] = [];
  let cursor = 0;
  // Bounded: every iteration must advance, or a malformed command would spin forever inside a
  // PreToolUse hook, which is a hang rather than a verdict.
  while (cursor < command.length && tokens.length < 4096) {
    const read = readShellArg(command, cursor);
    if (!read || read.endIndex <= cursor) break;
    let start = cursor;
    while (start < command.length && (command[start] === " " || command[start] === "\t")) start++;
    const afterNewline = command.slice(cursor, start).includes("\n");

    // `readShellArg` reads shell ARGUMENTS, not operators, so `--approve;` arrives as ONE bare
    // token and the `;` never reaches the separator test -- which let `gh pr review 591 --approve;
    // ls -lr` pick up the `-r` from `ls` and gate an approval. An operator can only be an operator
    // when it is UNQUOTED, so splitting bare tokens on `; & |` is safe and quoted text is untouched.
    const pieces =
      read.quote === "none" && /[;&|]/.test(read.value)
        ? read.value.split(/([;&|]+)/).filter((piece) => piece.length > 0)
        : [read.value];

    for (const [index, piece] of pieces.entries()) {
      tokens.push({
        value: piece,
        quote: read.quote,
        start,
        end: read.endIndex,
        afterNewline: index === 0 ? afterNewline : false,
      });
    }
    cursor = read.endIndex;
  }
  return tokens;
}

/**
 * Does this token end the current simple command?
 *
 * `#` starts a comment, and a trailing `# ... -r ...` comment previously turned an approve into a
 * blocking review. A newline ends it too, which is why `afterNewline` exists: `readShellArg` skips
 * only spaces and tabs, so a newline never reaches the separator test on its own.
 */
function endsCommand(token: Token): boolean {
  if (token.afterNewline) return true;
  if (!isBare(token)) return false;
  return (
    token.value.startsWith("#") ||
    token.value === ";" ||
    token.value === "&&" ||
    token.value === "||" ||
    token.value === "|" ||
    token.value === "&" ||
    token.value.includes("\n")
  );
}

const basename = (path: string): string => path.slice(path.lastIndexOf("/") + 1);

/**
 * EVERY `gh <verb> <sub>` invocation in the command, each as its own argument list.
 *
 * Scanning only the FIRST match was itself a fail-open: `gh pr review 679 --approve; gh pr review
 * 682 --request-changes` was allowed in 13 ms because the classifier stopped at the approve.
 */
function ghInvocations(command: string, verb: string, sub: string): Token[][] {
  const tokens = tokenize(command);
  const found: Token[][] = [];
  for (let i = 0; i + 2 < tokens.length; i++) {
    const head = tokens[i]!;
    if (!isBare(head) || basename(head.value) !== "gh") continue;
    // `/graphql` is accepted by gh exactly as `graphql` is. This is the THIRD instance in this
    // file of the identical leading-slash miss; the REST path comment records the other two.
    const actual = tokens[i + 2]!.value;
    if (tokens[i + 1]!.value !== verb || (actual !== sub && actual !== `/${sub}`)) continue;
    const args: Token[] = [];
    for (let j = i + 3; j < tokens.length; j++) {
      if (endsCommand(tokens[j]!)) break;
      args.push(tokens[j]!);
    }
    found.push(args);
  }
  return found;
}

// ---------------------------------------------------------------------------------------------
// `gh pr review`
// ---------------------------------------------------------------------------------------------

export type ReviewDoor = "porcelain" | "rest-reviews" | "rest-review-events" | "graphql";

export interface BlockingReviewTarget {
  door: ReviewDoor;
  /** `owner/repo` when the command names it explicitly. Else null. */
  repo: string | null;
  /** PR number when the command states it. Null when it is implied by the current branch. */
  number: number | null;
  /** True when the command's blocking-ness could not be READ. Unknown resolves to blocked. */
  opaque: boolean;
}

/** `gh pr review` flags that consume the NEXT token as their value. */
const REVIEW_VALUE_TAKING_LONG = new Set(["--body", "--body-file", "--repo"]);
/** Their shorthand letters. A cluster ends at the first of these; the rest is that flag's value. */
const REVIEW_VALUE_TAKING_SHORTHANDS = new Set(["b", "F", "R"]);
const REQUEST_CHANGES_SHORTHAND = "r";

/** pflag accepts far more than `true` for a boolean: `1 t T true True TRUE y yes` all parse. */
const PFLAG_TRUE = /^(?:1|t|T|true|True|TRUE|y|Y|yes|YES)$/;

/**
 * True when a `-abc` style token requests changes once pflag clustering is accounted for.
 * `-rb "msg"` is `--request-changes --body msg`; `-br` is `--body "r"` and requests nothing.
 */
export function shorthandClusterRequestsChanges(token: string): boolean {
  const match = /^-([A-Za-z]+)$/.exec(token);
  if (!match) return false;
  for (const char of match[1]!) {
    if (char === REQUEST_CHANGES_SHORTHAND) return true;
    if (REVIEW_VALUE_TAKING_SHORTHANDS.has(char)) return false;
  }
  return false;
}

/** Does a bare token consume the following token as its value? Handles clusters like `-rF`. */
function consumesNextToken(token: Token): boolean {
  if (!isBare(token)) return false;
  const text = token.value;
  if (text.startsWith("--")) return REVIEW_VALUE_TAKING_LONG.has(text);
  const cluster = /^-([A-Za-z]+)$/.exec(text);
  if (!cluster) return false;
  // Only a cluster's LAST letter can take a value. `-rF x` is `--request-changes --body-file x`,
  // so `x` is consumed and cannot be mistaken for the positional PR number.
  return REVIEW_VALUE_TAKING_SHORTHANDS.has(cluster[1]!.at(-1)!);
}

const REPO_SLUG = /^(?:[A-Za-z0-9._-]+\/)?([A-Za-z0-9._-]+\/[A-Za-z0-9._-]+)$/;
const PR_URL = /^(?:https?:\/\/)?(?:www\.)?github\.com\/([A-Za-z0-9._-]+\/[A-Za-z0-9._-]+)\/pull\/(\d+)/;

interface ReviewArgs {
  requestsChanges: boolean;
  repo: string | null;
  number: number | null;
}

function splitInline(text: string): [string, string | null] {
  const joined = /^(--?[A-Za-z][A-Za-z-]*)=([\s\S]*)$/.exec(text);
  return joined ? [joined[1]!, joined[2]!] : [text, null];
}

/**
 * Walk one `gh pr review` argument list ONCE, classifying each token as flag, value or positional.
 *
 * This single pass replaces four separate regex scans that disagreed about quoting, and it is why
 * a URL or a `-R` written inside `--body` can no longer donate a target: such text is a VALUE, and
 * only POSITIONALS are consulted for the number and the repo.
 */
function readReviewArgs(args: Token[]): ReviewArgs {
  let requestsChanges = false;
  let repo: string | null = null;
  let number: number | null = null;
  const positionals: Token[] = [];

  for (let i = 0; i < args.length; i++) {
    const token = args[i]!;

    if (!isBare(token) || !token.value.startsWith("-")) {
      positionals.push(token);
      continue;
    }

    const [name, inlineValue] = splitInline(token.value);

    if (name === "--request-changes") {
      if (inlineValue === null || PFLAG_TRUE.test(inlineValue)) requestsChanges = true;
    } else if (inlineValue === null && shorthandClusterRequestsChanges(name)) {
      requestsChanges = true;
    }

    const namesRepo =
      name === "--repo" || (!name.startsWith("--") && /^-[A-Za-z]*R$/.test(name));
    if (namesRepo) {
      const raw = inlineValue ?? args[i + 1]?.value ?? null;
      // `-R [HOST/]OWNER/REPO` is the documented form, so an optional host segment is stripped.
      const slug = raw === null ? null : REPO_SLUG.exec(raw)?.[1] ?? null;
      if (slug) repo = slug;
    }

    if (inlineValue === null && consumesNextToken(token)) i++;
  }

  for (const positional of positionals) {
    const asUrl = PR_URL.exec(positional.value);
    if (asUrl) {
      repo = repo ?? asUrl[1]!;
      number = number ?? Number(asUrl[2]);
      continue;
    }
    if (number === null && /^\d+$/.test(positional.value)) number = Number(positional.value);
  }

  return { requestsChanges, repo, number };
}

/** Exported for tests: the PR number a `gh pr review` command names, or null. */
export function explicitPrNumber(command: string): number | null {
  for (const args of ghInvocations(command, "pr", "review")) {
    const read = readReviewArgs(args);
    if (read.number !== null) return read.number;
  }
  return null;
}

// ---------------------------------------------------------------------------------------------
// `gh api`
// ---------------------------------------------------------------------------------------------

const API_FIELD_FLAGS = new Set(["-f", "-F", "--field", "--raw-field"]);
const REST_REVIEWS_PATH =
  /(?:^|\/)repos\/([A-Za-z0-9._-]+\/[A-Za-z0-9._-]+)\/pulls\/(\d+)\/reviews(?:\/(\d+)\/events)?/;

function classifyGhApi(command: string): BlockingReviewTarget | null {
  for (const graphqlArgs of ghInvocations(command, "api", "graphql")) {
    const payload = graphqlArgs.map((token) => token.value).join(" ");
    if (/addPullRequestReview|submitPullRequestReview/i.test(payload) && /REQUEST_CHANGES/.test(payload)) {
      // A node id, not an owner/repo/number, so no author can be resolved from it.
      return { door: "graphql", repo: null, number: null, opaque: true };
    }
  }

  const tokens = tokenize(command);
  for (let i = 0; i + 1 < tokens.length; i++) {
    const head = tokens[i]!;
    if (!isBare(head) || basename(head.value) !== "gh" || tokens[i + 1]!.value !== "api") continue;

    const args: Token[] = [];
    for (let j = i + 2; j < tokens.length; j++) {
      if (endsCommand(tokens[j]!)) break;
      args.push(tokens[j]!);
    }

    let path: RegExpExecArray | null = null;
    let requestsChanges = false;
    let opaque = false;

    for (let k = 0; k < args.length; k++) {
      const token = args[k]!;
      const [name, inline] = splitInline(token.value);

      if (isBare(token) && API_FIELD_FLAGS.has(name)) {
        const value = inline ?? args[k + 1]?.value ?? "";
        if (/^event=REQUEST_CHANGES$/i.test(value)) requestsChanges = true;
        // gh's documented magic read: the value comes from a file or stdin, unreadable here.
        if (value.startsWith("event=@")) opaque = true;
        if (inline === null) k++;
        continue;
      }
      if (isBare(token) && name === "--input") {
        opaque = true;
        if (inline === null) k++;
        continue;
      }
      // The endpoint is a positional, and it may legitimately be quoted. A full URL
      // (`https://api.github.com/repos/...`) is accepted by gh, so the leading `/` is optional.
      path = path ?? REST_REVIEWS_PATH.exec(token.value);
    }

    if (!path) continue;
    if (!requestsChanges && !opaque) continue;
    return {
      door: path[3] ? "rest-review-events" : "rest-reviews",
      repo: path[1] ?? null,
      number: Number(path[2]),
      opaque: opaque && !requestsChanges,
    };
  }
  return null;
}

/**
 * Classify a shell command. Returns null when it does not submit a blocking review, which is the
 * answer for essentially all traffic and costs one substring test.
 */
export function classifyBlockingReview(command: string): BlockingReviewTarget | null {
  if (!command.includes("gh")) return null;

  for (const args of ghInvocations(command, "pr", "review")) {
    const read = readReviewArgs(args);
    if (!read.requestsChanges) continue;
    return { door: "porcelain", repo: read.repo, number: read.number, opaque: false };
  }

  return classifyGhApi(command);
}

// ---------------------------------------------------------------------------------------------
// Escape hatch
// ---------------------------------------------------------------------------------------------

const ESCAPE_ASSIGNMENT_RUN = new RegExp(`${COMMAND_POSITION}`, "gi");

export const ESCAPE_TOKEN = "PR_BLOCKING_REVIEW_OK";

/**
 * The token must be a LEADING ASSIGNMENT at a command position, never a substring, and never text
 * inside an argument. Anchoring alone was not enough: `;` and newline ARE command positions and
 * both occur freely inside a review body, so `--body "step one; PR_BLOCKING_REVIEW_OK=1"` opened a
 * synthetic command position inside a quoted argument and granted the override.
 */
export function hasInvitationEscape(command: string): boolean {
  const bare = withoutQuotedSpans(command);
  ESCAPE_ASSIGNMENT_RUN.lastIndex = 0;
  for (const match of bare.matchAll(ESCAPE_ASSIGNMENT_RUN)) {
    if (new RegExp(`\\b${ESCAPE_TOKEN}=`).test(match[0])) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------------------------
// Decision
// ---------------------------------------------------------------------------------------------

export interface InvitationFacts {
  /** The authenticated login, or null when it could not be determined. */
  actor: string | null;
  /** The PR's author, or null when the lookup failed, timed out, or the target was unresolvable. */
  author: string | null;
  /**
   * Whether the timeline carries a `review_requested` event naming the actor.
   * null means the question could not be ANSWERED, which is not the same as `false`.
   */
  invited: boolean | null;
}

export type Verdict = { decision: "allow" } | { decision: "deny"; reason: string };

const LIMITS = [
  `This is not a containment boundary. "disableAllHooks" switches it off, a review posted from`,
  `the web UI never passes through here, and a PreToolUse hook that TIMES OUT does not block --`,
  `Claude Code proceeds. The claim is that going around it is charged and visible, not that it`,
  `is impossible.`,
].join("\n");

function denial(headline: string, facts: string[]): Verdict {
  return {
    decision: "deny",
    reason: [
      headline,
      "",
      ...facts.map((fact) => `  ${fact}`),
      "",
      `--comment carries the same findings without gating anyone. If the blocking form is`,
      `genuinely right, re-run with ${ESCAPE_TOKEN}=1 as a leading assignment.`,
      "",
      LIMITS,
    ].join("\n"),
  };
}

/**
 * Every gap resolves to DENY, never to allow. A network call whose failure mode is "permit"
 * reproduces Decision #484 inside a guard built to prevent it -- which is exactly what
 * review-round-artifact.ts:23-27 warns about, and why that gate refuses to make network calls at
 * all. This one does make them, so it must fall the other way.
 */
export function decide(target: BlockingReviewTarget, facts: InvitationFacts): Verdict {
  if (target.opaque) {
    return denial(
      `Blocking review through the ${target.door} door, and this command does not state its event.`,
      [
        `door: ${target.door}`,
        `The event lives in a file or a GraphQL payload, so "is this blocking?" cannot be read`,
        `from the command. Unknown resolves to blocked, not to allowed.`,
      ],
    );
  }

  if (!facts.actor || !facts.author) {
    return denial(`Blocking review on a pull request whose author could not be determined.`, [
      `repo: ${target.repo ?? "unresolved"}`,
      `number: ${target.number ?? "unresolved (implied by the current branch)"}`,
      `actor: ${facts.actor ?? "unresolved"}`,
      `Absent data resolves to the unfavourable answer, so this is refused rather than allowed.`,
    ]);
  }

  if (facts.author === facts.actor) return { decision: "allow" };
  if (facts.invited === true) return { decision: "allow" };

  if (facts.invited === null) {
    return denial(`Blocking review on @${facts.author}'s pull request, invitation UNKNOWN.`, [
      `author: ${facts.author}`,
      `review_requested -> ${facts.actor}: could not be queried`,
      `A failed lookup is not evidence of an invitation.`,
    ]);
  }

  return denial(`Blocking review on a pull request you were not asked to review.`, [
    `author: ${facts.author} (you are ${facts.actor})`,
    `review_requested -> ${facts.actor}: none on the timeline`,
    `This is not forbidden, and it is not rare -- it is how most reviews here start. It is a`,
    `blocking action on someone else's work taken on your own initiative, which is a decision`,
    `worth making on purpose rather than by default.`,
  ]);
}
