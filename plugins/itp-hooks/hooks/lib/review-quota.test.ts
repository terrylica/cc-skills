import { describe, expect, it } from "bun:test";
import {
  LIMIT,
  WINDOW_MS,
  classifyQuotaSpend,
  judge,
  mightSpend,
  quotaEscapeReason,
  type SpendEntry,
} from "./review-quota.ts";

const T0 = Date.parse("2026-09-08T20:00:00Z");

function entry(minutesAgo: number, sha: string): SpendEntry {
  return {
    at: new Date(T0 - minutesAgo * 60_000).toISOString(),
    sha,
    kind: "push",
    branch: "b",
  };
}

describe("classifyQuotaSpend", () => {
  it("meters a plain push, conditional on an open PR", () => {
    const spend = classifyQuotaSpend("git push");
    expect(spend?.kind).toBe("push");
    expect(spend?.onlyIfPrOpen).toBe(true);
  });

  it("meters a push written with global git flags before the subcommand", () => {
    // `git -c x=y push` and `git --no-pager push` are ordinary spellings; a regex anchored on
    // `git push` alone lets both through, and a missed push is a stolen place in the queue.
    expect(classifyQuotaSpend("git -c push.default=simple push")?.kind).toBe("push");
    expect(classifyQuotaSpend("git --no-pager push --force-with-lease")?.kind).toBe("push");
  });

  it("meters a push carrying an env prefix, which is how this repo pushes", () => {
    expect(classifyQuotaSpend('GH_ORGS="Eon-Labs" git push')?.kind).toBe("push");
  });

  it("METERS A DRAFT PR CREATE, which the sibling gate deliberately exempts", () => {
    // The load-bearing divergence. review-round-artifact's classify() returns null for --draft
    // because a draft is assumed not to be in front of anyone. Measured false: PRs 592-595 were
    // drafts throughout and each drew a verdict. Reusing that classifier would have made --draft a
    // one-flag bypass of this limiter.
    const spend = classifyQuotaSpend("gh pr create --draft --title x --body-file b.md");
    expect(spend?.kind).toBe("pr-create");
    expect(spend?.onlyIfPrOpen).toBe(false);
  });

  it("meters opening and reopening, which spend with no push at all", () => {
    // PR 592 was opened on a sixteen-day-old head and reviewed 108 minutes later.
    expect(classifyQuotaSpend("gh pr create --title x")?.onlyIfPrOpen).toBe(false);
    expect(classifyQuotaSpend("gh pr reopen 666")?.kind).toBe("pr-reopen");
  });

  it("meters update-branch, which creates a new head remotely", () => {
    // Measured on #692: merge commit ba2d441f at 19:26:26Z, verdict at 19:31:27Z.
    expect(classifyQuotaSpend("gh pr update-branch 692")?.kind).toBe("pr-update-branch");
  });

  it("does NOT meter leaving the queue", () => {
    expect(classifyQuotaSpend("gh pr ready --undo 666")).toBeNull();
    expect(classifyQuotaSpend("gh pr ready 666 --undo")).toBeNull();
  });

  it("does not meter unrelated traffic", () => {
    expect(classifyQuotaSpend("gh pr view 666 --json state")).toBeNull();
    expect(classifyQuotaSpend("gh pr list")).toBeNull();
    expect(classifyQuotaSpend("git status")).toBeNull();
    expect(classifyQuotaSpend("echo git push")).not.toBeNull(); // conservative: substring wins
  });

  it("prefilters cheaply without missing anything it later meters", () => {
    for (const command of [
      "git push",
      'GH_ORGS="Eon-Labs" git push',
      "gh pr create --draft",
      "gh pr reopen 1",
      "gh pr update-branch 1",
    ]) {
      expect(mightSpend(command)).toBe(true);
      expect(classifyQuotaSpend(command)).not.toBeNull();
    }
  });
});

describe("quotaEscapeReason", () => {
  it("requires a reason of real length", () => {
    expect(quotaEscapeReason('REVIEW_QUOTA_OK="short" git push')).toBeNull();
    expect(quotaEscapeReason('REVIEW_QUOTA_OK="release is blocked on this" git push')).toBe(
      "release is blocked on this",
    );
  });

  it("is absent from ordinary commands", () => {
    expect(quotaEscapeReason("git push")).toBeNull();
  });
});

describe("judge", () => {
  it("allows while under the limit", () => {
    const verdict = judge([entry(10, "a")], "new", T0);
    expect(verdict.allowed).toBe(true);
    expect(verdict.occupancy).toBe(1);
  });

  it("denies at the limit and says when a slot frees", () => {
    const verdict = judge([entry(10, "a"), entry(20, "b")], "new", T0);
    expect(verdict.allowed).toBe(false);
    expect(verdict.occupancy).toBe(LIMIT);
    // The oldest is 20 min old, so 40 min remain of its hour.
    expect(Math.round(verdict.retryAfterMs / 60_000)).toBe(40);
  });

  it("ignores spends that have aged out of the rolling window", () => {
    const verdict = judge([entry(61, "a"), entry(70, "b")], "new", T0);
    expect(verdict.allowed).toBe(true);
    expect(verdict.occupancy).toBe(0);
  });

  it("IS ROLLING, NOT A CLOCK HOUR", () => {
    // A fixed bucket would permit 2 at 13:59 and 2 more at 14:01. Both of these sit inside one
    // trailing hour and the third must be refused.
    const verdict = judge([entry(59, "a"), entry(1, "b")], "new", T0);
    expect(verdict.allowed).toBe(false);
  });

  it("charges DISTINCT HEADS, so a retry of the same commit is free", () => {
    // A rejected push, or a --force-with-lease of the same sha, presents no new head and can
    // produce no new review. Charging per command would bill a retry that cannot cost anything.
    const entries = [entry(10, "a"), entry(20, "b")];
    const retry = judge(entries, "a", T0);
    expect(retry.allowed).toBe(true);
    expect(retry.alreadyCharged).toBe(true);

    const fresh = judge(entries, "c", T0);
    expect(fresh.allowed).toBe(false);
  });

  it("counts two records of one sha once", () => {
    // Two commands can present the same head -- `gh pr ready` then `git push`. The reviewer would
    // produce one review, so the ledger must too.
    const verdict = judge([entry(5, "a"), entry(6, "a")], "new", T0);
    expect(verdict.occupancy).toBe(1);
    expect(verdict.allowed).toBe(true);
  });

  it("survives a ledger with unparseable timestamps rather than counting them as live", () => {
    const corrupt = [{ at: "not-a-date", sha: "x", kind: "push", branch: "b" } as SpendEntry, entry(5, "a")];
    const verdict = judge(corrupt, "new", T0);
    expect(verdict.occupancy).toBe(1);
  });

  it("uses the documented window width", () => {
    expect(WINDOW_MS).toBe(60 * 60 * 1000);
    const justInside = judge([entry(59.9, "a"), entry(59.8, "b")], "new", T0);
    expect(justInside.allowed).toBe(false);
  });
});
