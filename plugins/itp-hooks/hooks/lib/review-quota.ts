/**
 * Rate limiting for a SHARED human review queue.
 *
 * WHY THIS EXISTS, measured on Eon-Labs/alpha-forge on 2026-09-08. The reviewer `ChenLi0830` is not
 * a private resource: other people's work queues behind the same reviewer, so a burst from one
 * author jumps every other queue. The CEO's instruction was "at most 2 reviews per hour".
 *
 *     peak rolling-hour occupancy   10   (limit 2)
 *     verdicts over quota           16 of 27
 *     budget available over 42h     84
 *     actually spent                27
 *
 * The last two lines are the point: the aggregate spend was well UNDER budget. The defect was
 * BURSTINESS -- 16 breaches inside one two-hour block, then nine hours of silence. So this caps the
 * rate and costs almost no throughput; it does not cap how much review you may ask for in a day.
 *
 * WHAT THE REVIEWER ACTUALLY KEYS ON, and every clause below follows from it:
 *
 *   a DISTINCT HEAD SHA ON AN OPEN PR.
 *
 * Three consequences, each measured rather than assumed:
 *
 *   1. DRAFTS ARE NOT EXEMPT. PRs 592-595 were opened as drafts on 2026-09-02, never readied (no
 *      `ready_for_review` event exists on any of them), and each drew a CHANGES_REQUESTED 57-126
 *      minutes later. This is why `classifyQuotaSpend` does NOT reuse `classify()` from
 *      review-round-artifact.ts: that classifier deliberately exempts `gh pr create --draft`, which
 *      would let `--draft` walk straight past this limiter.
 *   2. OPENING A PR IS ITSELF A SPEND, with no push at all. PR 592's head commit was dated
 *      2026-08-17, sixteen days before the PR was opened and reviewed. So `pr-create` and
 *      `pr-reopen` are metered even though they push nothing.
 *   3. NO OPEN PR MEANS NO REVIEW. That is the free workspace, and it is why a push is metered only
 *      when the branch has an open PR -- otherwise every push on every scratch branch would be
 *      charged for a review nobody is performing.
 *
 * COUNTING IS BY DISTINCT SHA, NOT BY COMMAND, and that is not a refinement -- it is what makes the
 * limiter agree with the thing it is modelling. Two measurements force it:
 *
 *   * 25 pushes produced 20 reviews. The 5 that produced none were each superseded by a newer push
 *     within 6-20 minutes, so the reviewer never dequeued the older head. Rapid follow-ups
 *     genuinely coalesce, and charging per command would bill for reviews that never happen.
 *   * A push that GitHub rejects, or a `--force-with-lease` retry of the same commit, presents no
 *     new head. Charging per command would bill a retry that cannot produce a review.
 *
 * WHAT IT CANNOT DO, stated here because the deny message says it too: this is not a containment
 * boundary. `"disableAllHooks": true` switches it off, `gh api` and the web UI reach GitHub without
 * a gated command string, and a PR opened outside it is never recorded. The claim is that going
 * around it is CHARGED AND VISIBLE, not that it is impossible.
 */

import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export const STATE_ROOT = join(homedir(), ".claude", "state", "review-quota");

/** Reviews per rolling window. The CEO's number, not a tunable default. */
export const LIMIT = 2;

/** Rolling, NOT a clock hour: a fixed 13:00-14:00 bucket permits 2 at 13:59 and 2 at 14:01. */
export const WINDOW_MS = 60 * 60 * 1000;

/**
 * Repositories whose reviewer is a shared queue.
 *
 * Deliberately an allowlist rather than "everywhere". On a solo repository nobody is waiting behind
 * you, so blocking a push there is friction with no beneficiary. Slugs are lowercase `owner/repo`,
 * matching `identifyRepo().slug`.
 */
export const METERED_REPOS: ReadonlySet<string> = new Set(["eon-labs/alpha-forge"]);

export type QuotaKind = "pr-create" | "pr-reopen" | "pr-ready" | "pr-update-branch" | "push";

export interface QuotaSpend {
  readonly kind: QuotaKind;
  readonly matched: string;
  /** Whether the spend is conditional on the branch already having an open PR. */
  readonly onlyIfPrOpen: boolean;
}

export interface SpendEntry {
  readonly at: string;
  readonly sha: string;
  readonly kind: QuotaKind;
  readonly branch: string;
}

const GIT_PUSH = /\bgit\s+(?:-[^\s]+\s+|--\S+\s+)*push\b/;
const GH_PR_CREATE = /\bgh\s+pr\s+create\b/;
const GH_PR_REOPEN = /\bgh\s+pr\s+reopen\b/;
const GH_PR_READY = /\bgh\s+pr\s+ready\b/;
const GH_PR_UPDATE_BRANCH = /\bgh\s+pr\s+update-branch\b/;
const READY_UNDO = /(^|\s)--undo(\s|$)/;

/**
 * The escape hatch ASKS rather than allowing silently, and requires a reason.
 *
 * A quota guard whose bypass is frictionless is a guard against nobody: the failure mode being
 * prevented is precisely an author deciding "just one more push" twelve times in an hour. The
 * reason is recorded so the override is greppable after the fact.
 */
const ESCAPE = /REVIEW_QUOTA_OK=(?:"([^"]{12,})"|'([^']{12,})'|(\S{12,}))/;

export function quotaEscapeReason(command: string): string | null {
  const match = command.match(ESCAPE);
  if (!match) return null;
  return match[1] ?? match[2] ?? match[3] ?? null;
}

/**
 * Which commands spend a review, and which of those depend on a PR already being open.
 *
 * `gh pr ready` is metered although it creates no new head. It is the one kind here whose cost is
 * UNMEASURED -- no case in the corpus isolates a draft-to-ready transition with no accompanying
 * push -- and it is counted because over-counting costs a wait while under-counting costs someone
 * else's place in the queue. Said plainly rather than presented as measured.
 */
export function classifyQuotaSpend(command: string): QuotaSpend | null {
  if (GH_PR_READY.test(command) && READY_UNDO.test(command)) return null; // leaving is never a spend

  const create = command.match(GH_PR_CREATE);
  // NO --draft CARVE-OUT. Measured: drafts are reviewed (PRs 592-595).
  if (create) return { kind: "pr-create", matched: create[0].trim(), onlyIfPrOpen: false };

  const reopen = command.match(GH_PR_REOPEN);
  if (reopen) return { kind: "pr-reopen", matched: reopen[0].trim(), onlyIfPrOpen: false };

  const update = command.match(GH_PR_UPDATE_BRANCH);
  if (update) return { kind: "pr-update-branch", matched: update[0].trim(), onlyIfPrOpen: true };

  const ready = command.match(GH_PR_READY);
  if (ready) return { kind: "pr-ready", matched: ready[0].trim(), onlyIfPrOpen: true };

  const push = command.match(GIT_PUSH);
  if (push) return { kind: "push", matched: push[0].trim(), onlyIfPrOpen: true };

  return null;
}

/** Cheap prefilter so the overwhelming majority of Bash traffic leaves before any subprocess. */
export function mightSpend(command: string): boolean {
  return /\bgh\s+pr\b/.test(command) || GIT_PUSH.test(command);
}

export interface Verdict {
  readonly allowed: boolean;
  /** Distinct heads already charged in the window, EXCLUDING `sha` if it is already among them. */
  readonly occupancy: number;
  /** Milliseconds until the oldest charged head leaves the window; 0 when allowed. */
  readonly retryAfterMs: number;
  /** True when this exact head is already charged, so the command is free. */
  readonly alreadyCharged: boolean;
}

export function judge(
  entries: readonly SpendEntry[],
  sha: string,
  nowMs: number,
  limit: number = LIMIT,
  windowMs: number = WINDOW_MS,
): Verdict {
  const live = entries
    .map((entry) => ({ entry, at: Date.parse(entry.at) }))
    .filter(({ at }) => Number.isFinite(at) && nowMs - at < windowMs);

  const distinct = new Set(live.map(({ entry }) => entry.sha));
  // A head already charged inside the window produces no NEW review, so re-presenting it is free.
  // This is what makes a rejected-and-retried push, and a force-push of the same commit, cost
  // nothing -- matching the reviewer, which keys on distinct head shas.
  if (distinct.has(sha)) {
    return { allowed: true, occupancy: distinct.size, retryAfterMs: 0, alreadyCharged: true };
  }

  if (distinct.size < limit) {
    return { allowed: true, occupancy: distinct.size, retryAfterMs: 0, alreadyCharged: false };
  }

  // Oldest head still inside the window: once it ages out, one slot frees.
  const oldest = Math.min(...live.map(({ at }) => at));
  return {
    allowed: false,
    occupancy: distinct.size,
    retryAfterMs: Math.max(0, windowMs - (nowMs - oldest)),
    alreadyCharged: false,
  };
}

function ledgerPath(slug: string): string {
  return join(STATE_ROOT, `${slug.replaceAll("/", "__")}.jsonl`);
}

export function readSpends(slug: string): SpendEntry[] {
  try {
    const text = readFileSync(ledgerPath(slug), "utf8");
    const out: SpendEntry[] = [];
    for (const line of text.split("\n")) {
      if (!line.trim()) continue;
      try {
        const row = JSON.parse(line) as SpendEntry;
        if (typeof row?.at === "string" && typeof row?.sha === "string") out.push(row);
      } catch {
        // A torn line is one lost observation, not a reason to discard the ledger. Skipping it
        // under-counts by at most one, which the caller compensates for by failing closed on an
        // unreadable ledger (see the hook) rather than on a single bad line.
      }
    }
    return out;
  } catch {
    return [];
  }
}

export function recordSpend(slug: string, entry: SpendEntry): void {
  const path = ledgerPath(slug);
  mkdirSync(dirname(path), { recursive: true });
  appendFileSync(path, `${JSON.stringify(entry)}\n`, "utf8");
}

export function recordQuotaOverride(slug: string, reason: string, command: string): void {
  const path = join(STATE_ROOT, "overrides.jsonl");
  mkdirSync(dirname(path), { recursive: true });
  appendFileSync(
    path,
    `${JSON.stringify({ at: new Date().toISOString(), slug, reason, command: command.slice(0, 500) })}\n`,
    "utf8",
  );
}

/** Drop entries older than a day so the ledger cannot grow without bound. Called opportunistically. */
export function pruneSpends(slug: string, nowMs: number): void {
  const path = ledgerPath(slug);
  const kept = readSpends(slug).filter((entry) => {
    const at = Date.parse(entry.at);
    return Number.isFinite(at) && nowMs - at < 24 * 60 * 60 * 1000;
  });
  try {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, kept.map((entry) => `${JSON.stringify(entry)}\n`).join(""), "utf8");
  } catch {
    // Pruning is housekeeping. Failing it must never fail the command.
  }
}

export function formatWait(ms: number): string {
  const minutes = Math.ceil(ms / 60000);
  return minutes <= 1 ? "under a minute" : `${minutes} minutes`;
}
