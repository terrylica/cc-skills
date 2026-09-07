#!/usr/bin/env bun
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
 * "uninvited" would therefore carry 5 false positives per true positive. What it does instead is
 * make the blocking form COST one deliberate keystroke, and put the queried facts in front of the
 * human at the moment of the act. Converting a reflexive block into a considered one is the whole
 * claim; preventing anything is not.
 *
 * WHAT IT DELIBERATELY LEAVES ALONE:
 *   --approve   17 of these on other authors' PRs, 10 since 2026-08-21. The `main` ruleset requires
 *               1 approving review and GitHub forbids self-approval, so terrylica<->ChenLi0830 is a
 *               reciprocal approval pair and it is the ONLY way anything merges there. Gating it
 *               would deadlock the repository.
 *   --comment   Carries identical findings without gating. It is the intended fallback, so the
 *               honest description of this guard's effect is a RENAME, not a prevention.
 *   issues      `gh issue close` / `gh issue comment` on a collaborator's issue is ordinary triage
 *               (terrylica closed Mayweiwang's #441 and #442, and has 24 comments on #435). Scoping
 *               this to "mutating another author's artifact" would have swallowed all of it.
 *
 * WHY THE INVITATION FACT IS THE TIMELINE, NOT `requested_reviewers`. GitHub CLEARS a user from
 * `requested_reviewers` the moment they submit a review -- measured on #201 and #35, both of which
 * read `[]` after their INVITED reviews. Since 73% of review submissions in this repo are rounds
 * 2+, reading the live array would make legitimate re-review this guard's dominant false positive.
 * The durable fact is a `review_requested` event on the issue timeline.
 *
 * NO I/O HERE. Facts are injected by the caller, so every branch is reachable from a unit test and
 * the classifier can be mutation-tested without a network or a repository.
 */

import { COMMAND_POSITION, ghCommand, withoutQuotedSpans } from "./review-round-artifact.ts";

// ---------------------------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------------------------

/** Which door the blocking review is being submitted through. Reported in the deny message. */
export type ReviewDoor = "porcelain" | "rest-reviews" | "rest-review-events" | "graphql";

export interface BlockingReviewTarget {
  door: ReviewDoor;
  /** `owner/repo` when the command names it explicitly (`-R`, or a REST path). Else null. */
  repo: string | null;
  /** PR number when the command states it. Null when it is implied by the current branch. */
  number: number | null;
  /**
   * True when the command's blocking-ness could not be READ -- `--input file.json` puts the
   * `event` in a file the hook must not open at decision time. Absent data resolves to the
   * UNFAVOURABLE answer (Decision #484), so an opaque command is treated as blocking.
   */
  opaque: boolean;
}

const GH_PR_REVIEW = ghCommand(String.raw`pr\s+review\b`);
const GH_API = ghCommand(String.raw`api\b`);

/** `--request-changes`, and the `=true` spelling that a `(?=\s|$)` test would miss. */
const LONG_REQUEST_CHANGES = /(?:^|\s)--request-changes(?:=true)?(?=\s|$)/;

/**
 * Short flags for `gh pr review`. Go's pflag CLUSTERS boolean shorthands and lets the LAST one take
 * a value, so `-rb "needs work"` is `--request-changes --body "needs work"` and contains neither
 * the token `-r` nor `--request-changes`. Proven on a read-only control: `gh pr list -dq '.'`
 * parses as `--draft --jq .`.
 */
const REVIEW_VALUE_TAKING_SHORTHANDS = new Set(["b", "F", "R"]);
const REQUEST_CHANGES_SHORTHAND = "r";

/** True when a `-abc` style token requests changes once pflag clustering is accounted for. */
export function shorthandClusterRequestsChanges(token: string): boolean {
  const match = /^-([A-Za-z]+)$/.exec(token);
  if (!match) return false;
  for (const char of match[1]!) {
    if (char === REQUEST_CHANGES_SHORTHAND) return true;
    // A value-taking shorthand consumes the remainder of the cluster as its VALUE, so anything
    // after it is not a flag. `-br` is `--body "r"`, which does NOT request changes.
    if (REVIEW_VALUE_TAKING_SHORTHANDS.has(char)) return false;
  }
  return false;
}

/**
 * The slice of the command that belongs to `gh pr review`: from that `gh` up to the next
 * separator outside quotes.
 *
 * WITHOUT THIS SCOPING THE GUARD GATES `--approve`, which its own contract forbids because
 * approvals are the repo's only merge path. `shorthandClusterRequestsChanges` was run over every
 * whitespace token of the WHOLE command, and `-rf`, `-r`, `-lr` are extremely common elsewhere, so
 * measured: `gh pr review 591 --approve && grep -r TODO src` classified as a blocking review, as
 * did the same line with `rm -rf`, `cp -r` or `ls -r`. A guard that blocks approvals deadlocks the
 * repository, which is a worse outcome than the one it was built to prevent.
 */
function reviewSegment(command: string): string {
  const outer = GH_PR_REVIEW.exec(command);
  const inner = outer ? /(?:[\w./-]*\/)?gh\s+pr\s+review\b/i.exec(outer[0]) : null;
  const start = outer && inner ? outer.index + inner.index : 0;

  let single = false;
  let double = false;
  for (let i = start; i < command.length; i++) {
    const char = command[i]!;
    if (char === "'" && !double) single = !single;
    else if (char === '"' && !single) double = !double;
    else if (!single && !double && (char === "\n" || char === ";" || char === "&" || char === "|")) {
      return command.slice(start, i);
    }
  }
  return command.slice(start);
}

function porcelainRequestsChanges(command: string): boolean {
  const bare = withoutQuotedSpans(reviewSegment(command));
  if (LONG_REQUEST_CHANGES.test(bare)) return true;
  return bare.split(/\s+/).some(shorthandClusterRequestsChanges);
}

/**
 * PREDICATES USE `withoutQuotedSpans`. EXTRACTION MUST NOT.
 *
 * `withoutQuotedSpans` DELETES quoted text, which is exactly right for "is this a flag" (so that
 * `--body "mentions --request-changes"` is not read as a flag) and catastrophic for "what is this
 * flag's value" (so that `-R "owner/repo"` is not read as no repo at all). Three separate P0
 * fail-opens came from using the predicate helper for extraction, each one ALLOWING a blocking
 * review after querying the wrong pull request, or after failing to recognise the command at all:
 *
 *   -R "Eon-Labs/rangebar"        -> repo null -> fell back to the cwd repo -> allowed on ITS facts
 *   -f "event=REQUEST_CHANGES"    -> classified as NOT a review -> allowed with no network call
 *   'repos/O/R/pulls/N/reviews'   -> path erased -> same
 *
 * `dequote` removes the quote CHARACTERS and keeps the content, which is what an extractor needs.
 * It is deliberately not used for flag tests.
 */
export function dequote(command: string): string {
  return command.replace(/["']/g, "");
}

/** `-R owner/repo` / `--repo owner/repo`, which OUTRANKS the cwd. */
const EXPLICIT_REPO = /(?:^|\s)(?:-R|--repo)[= ]+([A-Za-z0-9._-]+\/[A-Za-z0-9._-]+)(?=\s|$)/;

/**
 * REST paths that submit or convert a review.
 *
 * The leading slash is OPTIONAL: `gh api repos/O/R/...` is the canonical spelling and
 * `gh api /repos/O/R/...` is equally accepted. Requiring the slash made every ordinary invocation
 * miss -- caught by the tests, not by reading, because the happy-path spelling I reached for first
 * was the one with the slash.
 */
// The preceding-character class INCLUDES `/`, because gh accepts a full endpoint URL and
// `https://api.github.com/repos/O/R/pulls/N/reviews` puts a slash immediately before `repos`.
// Verified read-only that gh really does accept it: `gh api https://api.github.com/rate_limit`
// returns 5000. This is the second time the same class of miss appeared in this one regex.
const REST_REVIEWS_PATH =
  /(?:^|[\s'"=/])\/?repos\/([A-Za-z0-9._-]+\/[A-Za-z0-9._-]+)\/pulls\/(\d+)\/reviews(?:\/(\d+)\/events)?/;

/**
 * `gh api` switches to POST as soon as ANY field flag is present, so requiring an explicit
 * `-X POST` would be decorative. Field flags: `-f/--field`, `-F/--raw-field` (note that `-F` means
 * something different here than it does for `gh pr review`).
 */
const REST_EVENT_REQUEST_CHANGES = /(?:^|\s)(?:-f|-F|--field|--raw-field)[= ]+event=REQUEST_CHANGES(?=\s|$)/i;
/**
 * Sources that put the event somewhere the hook cannot read: `--input file`, and gh's documented
 * magic `@` read on a field value (`-f event=@payload`, `-F event=@-`). All are opaque, not
 * innocent -- previously `-F event=@file` matched neither the event pattern nor `--input` and was
 * therefore allowed outright.
 */
const REST_INPUT_FILE = /(?:^|\s)--input(?:[= ]+\S+)?(?=\s|$)/;
const REST_EVENT_FROM_FILE = /(?:^|\s)(?:-f|-F|--field|--raw-field)[= ]+event=@/i;

const GRAPHQL_ADD_REVIEW = /addPullRequestReview/i;
const GRAPHQL_REQUEST_CHANGES = /REQUEST_CHANGES/;

/** A full PR URL names the repository as surely as `-R` does. */
const PR_URL_REPO = /github\.com\/([A-Za-z0-9._-]+\/[A-Za-z0-9._-]+)\/pull\/\d+/;

/**
 * `-R` was read but the URL form was not, so `gh pr review https://github.com/cli/cli/pull/148 -r`
 * produced `{repo: null, number: 148}` and the hook resolved author and invitation from the CWD's
 * repository -- a DIFFERENT project's #148 -- and could affirmatively ALLOW on its facts. The test
 * suite already exercised the URL form for the NUMBER, which is what made the gap invisible.
 */
function explicitRepo(command: string): string | null {
  const bare = dequote(command);
  return EXPLICIT_REPO.exec(bare)?.[1] ?? PR_URL_REPO.exec(bare)?.[1] ?? null;
}

/**
 * `gh pr review` flags that CONSUME the next token. Everything else is boolean, so an integer
 * following it is the positional PR number, not a value.
 *
 * The first version skipped any number whose previous token began with `-`, which made
 * `gh pr review -r 682` resolve to NO number. The hook then asked `gh pr view` with no argument,
 * which answers about the CURRENT BRANCH's pull request -- measured allowing a blocking review on
 * #682 because the branch's own PR happened to be self-authored.
 */
const REVIEW_VALUE_TAKING_FLAGS = new Set(["-b", "--body", "-F", "--body-file", "-R", "--repo"]);

/**
 * First bare integer that is not the value of a flag -- `gh pr review 656 --request-changes`.
 * A branch name or a URL yields null, and null means the caller must resolve it or refuse.
 */
export function explicitPrNumber(command: string): number | null {
  // SCAN ONLY FROM THE `gh` THAT STARTS THE REVIEW COMMAND. A wrapper's own numeric argument and
  // any earlier segment of a compound command otherwise donate their integer, and the guard then
  // queries a DIFFERENT pull request -- and can ALLOW on its facts, which is worse than missing
  // the command entirely. All three measured against a real uninvited target:
  //   timeout 15 gh pr review 682 ...   -> resolved 15  -> queried #15 (self-authored) -> ALLOW
  //   sleep 2 ; gh pr review 682 -r     -> resolved 2
  //   head 20 f.txt && gh pr review 682 -> resolved 20
  const segment = dequote(reviewSegment(command));

  const url = /github\.com\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\/pull\/(\d+)/.exec(segment);
  if (url) return Number(url[1]);

  const tokens = segment.split(/\s+/);
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i]!;
    if (!/^\d+$/.test(token)) continue;
    // Skip only a number that is genuinely a VALUE. Skipping every number preceded by any `-`
    // token made `gh pr review -r 682` resolve to no number at all, and the hook then asked about
    // the current branch's PR instead of #682.
    if (REVIEW_VALUE_TAKING_FLAGS.has(tokens[i - 1] ?? "")) continue;
    return Number(token);
  }
  return null;
}

/**
 * Classify a shell command. Returns null when it does not submit a blocking review at all, which
 * is the answer for essentially all traffic and costs one substring test.
 */
export function classifyBlockingReview(command: string): BlockingReviewTarget | null {
  // Cheap prefilter. Everything below is anchored at a COMMAND POSITION, so `echo "gh pr review"`
  // is not a match, but this test alone exits for the overwhelming majority of Bash calls.
  if (!command.includes("gh")) return null;

  if (GH_PR_REVIEW.test(command) && porcelainRequestsChanges(command)) {
    return {
      door: "porcelain",
      repo: explicitRepo(command),
      number: explicitPrNumber(command),
      opaque: false,
    };
  }

  if (GH_API.test(command)) {
    // DEQUOTED, not span-deleted. `-f "event=REQUEST_CHANGES"` and a quoted path are ordinary
    // shell, and deleting the span made classifyBlockingReview return null -- not opaque, not
    // denied, but "this is not a review at all", allowed with no network call. That single
    // substitution defeated two of the four doors.
    const bare = dequote(command);

    // The `graphql` endpoint must actually be named. Without it, any `gh api` call whose TEXT
    // merely contains both literals -- a --jq filter, a grep of this very file, a comment body
    // quoting the mutation -- was denied, including pure reads.
    if (
      /(?:^|\s)graphql(?=\s|$)/.test(bare) &&
      GRAPHQL_ADD_REVIEW.test(command) &&
      GRAPHQL_REQUEST_CHANGES.test(command)
    ) {
      // The GraphQL door carries a node id, not an owner/repo/number, so the caller cannot resolve
      // an author from it. It is reported opaque rather than silently allowed.
      return { door: "graphql", repo: null, number: null, opaque: true };
    }

    const path = REST_REVIEWS_PATH.exec(bare);
    if (path) {
      const door: ReviewDoor = path[3] ? "rest-review-events" : "rest-reviews";
      const target = { door, repo: path[1] ?? null, number: Number(path[2]), opaque: false };
      if (REST_EVENT_REQUEST_CHANGES.test(bare)) return target;
      // `--input file.json` hides the event in a file. Reading it here would be I/O in a pure
      // classifier AND would trust a file the command can rewrite between check and use.
      if (REST_INPUT_FILE.test(bare) || REST_EVENT_FROM_FILE.test(bare)) {
        return { ...target, opaque: true };
      }
    }
  }

  return null;
}

// ---------------------------------------------------------------------------------------------
// Escape hatch
// ---------------------------------------------------------------------------------------------

/**
 * The token must be a LEADING ASSIGNMENT at a command position, never a substring. A bare
 * substring test lets `--body "do not set PR_BLOCKING_REVIEW_OK=1 here"` disarm the guard, which
 * is the defect review-round-artifact.ts:47-55 records paying for.
 */
const ESCAPE_ASSIGNMENT_RUN = new RegExp(`${COMMAND_POSITION}`, "gi");

export const ESCAPE_TOKEN = "PR_BLOCKING_REVIEW_OK";

export function hasInvitationEscape(command: string): boolean {
  // SCAN THE QUOTE-STRIPPED COMMAND. Anchoring at a command position is not enough on its own,
  // because `;` and newline are command positions and BOTH occur freely inside a quoted review
  // body -- so `--body "...; PR_BLOCKING_REVIEW_OK=1 ..."` opened a synthetic command position
  // inside an argument and disarmed the guard. This is a predicate, not an extraction, so the
  // span-deleting helper is the right one: text inside quotes cannot grant the override.
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
      ...facts.map((f) => `  ${f}`),
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
