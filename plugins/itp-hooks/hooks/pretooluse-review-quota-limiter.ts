#!/usr/bin/env bun
/**
 * PreToolUse limiter: at most N reviews per rolling hour from a SHARED reviewer queue.
 *
 * Measured motivation, the mechanism it models, and why drafts get no carve-out are all in
 * lib/review-quota.ts. The short version: the reviewer keys on a distinct head sha on an OPEN pull
 * request, other people queue behind the same reviewer, and on 2026-09-08 this author reached a
 * rolling-hour occupancy of 10 against a limit of 2.
 *
 * DELIBERATELY A SIBLING OF review-round-gate, NOT A CLAUSE INSIDE IT. Two placements inside that
 * gate were designed and both were wrong, which is why this file exists separately:
 *
 *   * above its `kind === "push" && !isBranchReviewable(repo)` filter, the quota would have charged
 *     every push on every scratch branch -- a review nobody performs;
 *   * beside its `markBranchReviewable` call, pushes would have been GATED by the quota and never
 *     RECORDED in it, because a push returns before reaching that line. The counter would have been
 *     fed only by pr-create and pr-ready while pushes -- the overwhelming majority of the spend --
 *     ran free against a counter that never moved.
 *
 * There is a third, decisive reason. That gate treats `gh pr ready --undo` as leaving the queue and
 * unmarks the branch. Drafting is measured NOT to stop reviews, so building on its notion of
 * "reviewable" would let `--undo` disable this limiter in one command.
 */

import { allow, ask, deny, parseStdinOrAllow } from "./pretooluse-helpers.ts";
import { trackHookError } from "./lib/hook-error-tracker.ts";
import { identifyRepo } from "./lib/review-round-state.ts";
import {
  LIMIT,
  METERED_REPOS,
  classifyQuotaSpend,
  formatWait,
  judge,
  mightSpend,
  pruneSpends,
  quotaEscapeReason,
  readSpends,
  recordQuotaOverride,
  recordSpend,
  type QuotaKind,
} from "./lib/review-quota.ts";

const HOOK_NAME = "REVIEW-QUOTA-LIMITER";

function run(args: string[], cwd: string): string | null {
  try {
    const proc = Bun.spawnSync(args, { cwd, stdout: "pipe", stderr: "ignore" });
    if (proc.exitCode !== 0) return null;
    return new TextDecoder().decode(proc.stdout).trim();
  } catch {
    return null;
  }
}

/**
 * Does this branch have an OPEN pull request?
 *
 * FAILS CLOSED ON PURPOSE. When `gh` cannot answer -- offline, rate limited, not authenticated --
 * this returns true and the command is metered. The opposite choice reproduces the incident
 * exactly: an unanswerable question resolving to the permissive answer, which is how an author ends
 * up at ten reviews in an hour believing the guard was watching.
 */
function hasOpenPullRequest(cwd: string): boolean {
  const state = run(["gh", "pr", "view", "--json", "state", "--jq", ".state"], cwd);
  if (state === null) return true;
  return state.toUpperCase() === "OPEN";
}

/** True when HEAD is already on the remote, so a push presents no new head and buys no review. */
function headAlreadyPushed(cwd: string): boolean {
  const head = run(["git", "rev-parse", "HEAD"], cwd);
  const upstream = run(["git", "rev-parse", "@{u}"], cwd);
  return head !== null && upstream !== null && head === upstream;
}

function denyMessage(
  kind: QuotaKind,
  matched: string,
  occupancy: number,
  retryAfterMs: number,
  slug: string,
): string {
  const what =
    kind === "push"
      ? "Pushing a new head to a branch with an open PR"
      : kind === "pr-create"
        ? "Opening a pull request"
        : kind === "pr-reopen"
          ? "Reopening a pull request"
          : kind === "pr-update-branch"
            ? "Updating the PR branch (this creates a new head remotely)"
            : "Marking a pull request ready";

  return [
    `[${HOOK_NAME}] ${slug} has used ${occupancy} of ${LIMIT} reviews in the last hour.`,
    "",
    `${what} would summon another one, and the reviewer is a SHARED queue -- other people's work`,
    "is waiting behind the same reviewer, so a burst from here jumps their place, not just ours.",
    "",
    `Blocked command: ${matched}`,
    `A slot frees in ${formatWait(retryAfterMs)}.`,
    "",
    "Three ways forward that cost nothing, in the order usually worth trying:",
    "",
    "  1. CLOSE the PR and keep working. Measured: no open PR, no review. Reopen it when the work",
    "     is genuinely converged, which spends one slot instead of one per intermediate fix.",
    "  2. Let the free reviewer do this round. The codex bot reviews without touching this quota,",
    "     so iterate against its findings and spend a slot only when you want the human verdict.",
    "  3. Wait and BATCH. Successive pushes within roughly 6-20 minutes coalesce -- the older head",
    "     is never dequeued -- so grouping fixes is cheaper than spacing them out.",
    "",
    "Note that DRAFTING DOES NOT HELP. It was measured on 2026-09-02: PRs 592-595 were drafts",
    "throughout and each drew a verdict anyway, one of them on a sixteen-day-old head with no push.",
    "",
    'Override: prefix with REVIEW_QUOTA_OK="<reason, 12+ chars>". It ASKS rather than allowing',
    "silently, and the reason is written to the override log.",
    "",
    'Limits: this cannot see the reviewer\'s queue. It is switched off by "disableAllHooks": true,',
    "and a PR opened through the web UI or `gh api` never reaches it.",
  ].join("\n");
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow(HOOK_NAME);
  if (!input) return;
  if (input.tool_name !== "Bash") return allow();

  const command = input.tool_input?.command;
  if (typeof command !== "string" || command.length === 0) return allow();

  // Cheap, local, no subprocess. Exits here for essentially all traffic.
  if (!mightSpend(command)) return allow();

  const spend = classifyQuotaSpend(command);
  if (spend === null) return allow();

  const cwd = input.cwd ?? process.cwd();
  const repo = identifyRepo(cwd);
  // Not a git repo, or detached HEAD. Nothing to key a ledger to; fail open rather than block work
  // this limiter cannot reason about.
  if (repo === null) return allow();
  if (!METERED_REPOS.has(repo.slug)) return allow();

  const reason = quotaEscapeReason(command);
  if (reason !== null) {
    recordQuotaOverride(repo.slug, reason, command);
    return ask(
      `[${HOOK_NAME}] Override requested: "${reason}"\n\n` +
        "Recorded in the override log. This spends a review from a queue other people are waiting\n" +
        "in. Approve to proceed.",
    );
  }

  if (spend.onlyIfPrOpen && !hasOpenPullRequest(cwd)) return allow();
  // A push that presents no new commit cannot produce a review, so it is not charged.
  if (spend.kind === "push" && headAlreadyPushed(cwd)) return allow();

  const head = run(["git", "rev-parse", "HEAD"], cwd);
  if (head === null) return allow();

  const now = Date.now();
  const verdict = judge(readSpends(repo.slug), head, now);
  if (!verdict.allowed) {
    return deny(denyMessage(spend.kind, spend.matched, verdict.occupancy, verdict.retryAfterMs, repo.slug));
  }

  // RECORDED ON THE PATH THAT ALLOWS, which is the whole correctness argument. Recording anywhere
  // else -- a later branch, a different kind -- yields a counter that gates commands it never
  // counts, and a limiter fed by nothing permits everything.
  if (!verdict.alreadyCharged) {
    recordSpend(repo.slug, {
      at: new Date(now).toISOString(),
      sha: head,
      kind: spend.kind,
      branch: repo.branch,
    });
    pruneSpends(repo.slug, now);
  }
  return allow();
}

main().catch((error) => {
  // FAIL OPEN, but COUNTABLY. A limiter that blocks work when its own logic throws is worse than
  // the burst it prevents; one that fails open silently is indistinguishable from no limiter.
  try {
    trackHookError(
      "pretooluse-review-quota-limiter",
      `REVIEW_QUOTA_LIMITER_FAILOPEN: ${error instanceof Error ? (error.stack ?? error.message) : String(error)}`,
    );
  } catch {
    // Nothing further to do; never let the audit path fail the command.
  }
  allow();
});
