import { describe, expect, it } from "bun:test";
import {
  classifyBlockingReview,
  decide,
  ESCAPE_TOKEN,
  explicitPrNumber,
  hasInvitationEscape,
  shorthandClusterRequestsChanges,
  type BlockingReviewTarget,
} from "./pr-review-invitation.ts";

// Every case below that is marked BYPASS came from an adversarial pass that enumerated ways to
// submit a blocking review WITHOUT deliberately evading the guard -- ordinary alternative syntax an
// agent would plausibly type. They are the point of this file. A suite of happy paths would pass
// identically against a classifier that only matched the single literal spelling of #656.

const PORCELAIN = "gh pr review 656 --request-changes --body-file /tmp/findings.md";

const blocking = (command: string) => classifyBlockingReview(command);

describe("porcelain door", () => {
  it("catches the literal spelling that caused the incident", () => {
    const target = blocking(PORCELAIN);
    expect(target?.door).toBe("porcelain");
    expect(target?.number).toBe(656);
    expect(target?.opaque).toBe(false);
  });

  it("BYPASS: --request-changes=true parses for pflag but defeats a (?=\\s|$) token test", () => {
    expect(blocking("gh pr review 656 --request-changes=true")?.door).toBe("porcelain");
  });

  it("BYPASS: -r shorthand", () => {
    expect(blocking("gh pr review 656 -r -F body.md")?.door).toBe("porcelain");
  });

  it("BYPASS: -rb clusters --request-changes with a value-taking --body", () => {
    expect(blocking('gh pr review 656 -rb "needs work"')?.door).toBe("porcelain");
  });

  it("BYPASS: env -u prefix, which is this repo's own house style for registering hooks", () => {
    expect(blocking("env -u GH_TOKEN gh pr review 656 --request-changes")?.door).toBe("porcelain");
  });

  it("BYPASS: a QUOTED assignment value containing a space", () => {
    // The inherited `\S*` pattern stopped at the first space, so this matched no command position
    // at all and the guard allowed it silently. review-round-artifact.ts:47-55 records the fix.
    expect(blocking('GH_ORGS="Eon Labs" gh pr review 656 --request-changes')?.door).toBe("porcelain");
  });

  it("BYPASS: a command position after && , ; and a pipe", () => {
    expect(blocking("gh pr view 656 && gh pr review 656 -r")?.door).toBe("porcelain");
    expect(blocking("true; gh pr review 656 -r")?.door).toBe("porcelain");
  });

  it("reads a PR number out of a full URL", () => {
    expect(explicitPrNumber("gh pr review https://github.com/Eon-Labs/alpha-forge/pull/656 -r")).toBe(656);
  });

  it("honours an explicit -R, which outranks the cwd", () => {
    // Resolving from the cwd here would query a DIFFERENT repository's #656 and could
    // AFFIRMATIVELY ALLOW on a fact about the wrong pull request -- worse than missing it.
    expect(blocking("gh pr review -R Eon-Labs/alpha-forge 656 -r")?.repo).toBe("Eon-Labs/alpha-forge");
  });

  it("reports an unstated PR number as null rather than guessing", () => {
    expect(blocking("gh pr review --request-changes")?.number).toBeNull();
    expect(blocking("gh pr review my-branch-name -r")?.number).toBeNull();
  });
});

describe("P0 regressions: extraction must not use the predicate helper", () => {
  // Every case here was MEASURED allowing a real blocking review on Eon-Labs/alpha-forge#682
  // (author ChenLi0830, terrylica never invited) by resolving a DIFFERENT pull request and then
  // matching author === actor on it. An affirmative allow on a wrong fact is worse than a miss,
  // because the guard reports confidence it has not earned.

  it("a wrapper's numeric argument does not hijack the PR number", () => {
    // Measured: resolved 15, queried #15 (self-authored), ALLOWED a block on #682.
    expect(explicitPrNumber("timeout 15 gh pr review 682 -R Eon-Labs/alpha-forge --request-changes")).toBe(682);
    expect(explicitPrNumber("nice gh pr review 682 -r")).toBe(682);
  });

  it("an earlier segment of a compound command does not donate its integer", () => {
    expect(explicitPrNumber("sleep 2 ; gh pr review 682 -r")).toBe(682);
    expect(explicitPrNumber("head 20 f.txt && gh pr review 682 -r")).toBe(682);
  });

  it("a boolean flag before the positional does not swallow it", () => {
    // Measured: resolved null, so the hook asked about the CURRENT BRANCH's PR instead of #682.
    expect(explicitPrNumber("gh pr review -r 682")).toBe(682);
    expect(explicitPrNumber("gh pr review --request-changes 682")).toBe(682);
  });

  it("still skips a number that is genuinely a flag VALUE", () => {
    expect(explicitPrNumber("gh pr review 682 -R Eon-Labs/alpha-forge -b 42")).toBe(682);
    expect(explicitPrNumber("gh pr review --body-file 12 -r")).toBeNull();
  });

  it("a QUOTED -R value is still read, so the cwd repo is not silently substituted", () => {
    // Measured: repo null -> fell back to the cwd's repository -> allowed on ITS facts.
    expect(blocking('gh pr review 15 -R "Eon-Labs/rangebar" --request-changes')?.repo).toBe("Eon-Labs/rangebar");
    expect(blocking("gh pr review 15 -R 'Eon-Labs/rangebar' --request-changes")?.repo).toBe("Eon-Labs/rangebar");
  });

  it("a QUOTED event field is still a blocking review, not an unrecognised command", () => {
    // Measured: classified null -> allowed with no network call. Two of four doors defeated.
    expect(blocking('gh api repos/O/R/pulls/682/reviews -f "event=REQUEST_CHANGES"')?.door).toBe("rest-reviews");
    expect(blocking("gh api repos/O/R/pulls/682/reviews -f 'event=REQUEST_CHANGES'")?.door).toBe("rest-reviews");
  });

  it("a QUOTED REST path is still a blocking review", () => {
    expect(blocking('gh api "repos/O/R/pulls/682/reviews" -f event=REQUEST_CHANGES')?.door).toBe("rest-reviews");
  });
});

describe("P1 regressions: scoping, and doors that were ajar", () => {
  it("does not turn an --approve into a blocking review because -r appears elsewhere", () => {
    // THE WORST FALSE POSITIVE AVAILABLE: gating approvals deadlocks the repo, since the ruleset
    // requires one approval the author may not supply. Measured GATED before the segment scoping.
    expect(blocking("gh pr review 591 --approve && grep -r TODO src")).toBeNull();
    expect(blocking("rm -rf /tmp/scratch && gh pr review 682 --approve")).toBeNull();
    expect(blocking("gh pr review 591 --comment -F f.md && cp -r a b")).toBeNull();
    expect(blocking("gh pr review 591 --approve; ls -lr")).toBeNull();
  });

  it("still catches a blocking review that is followed by unrelated commands", () => {
    // The scoping must not become a bypass of its own.
    expect(blocking("gh pr review 682 -r && echo done")?.door).toBe("porcelain");
    expect(blocking("echo start; gh pr review 682 --request-changes")?.door).toBe("porcelain");
  });

  it("reads the repository out of a full PR URL, not just out of -R", () => {
    // Measured: repo null -> resolved a DIFFERENT project's #148 from the cwd -> affirmative allow.
    const target = blocking("gh pr review https://github.com/cli/cli/pull/148 --request-changes");
    expect(target?.repo).toBe("cli/cli");
    expect(target?.number).toBe(148);
  });

  it("catches the REST door written as a full endpoint URL", () => {
    // gh accepts it; verified read-only that `gh api https://api.github.com/rate_limit` works.
    expect(
      blocking("gh api https://api.github.com/repos/O/R/pulls/682/reviews -f event=REQUEST_CHANGES")?.door,
    ).toBe("rest-reviews");
  });

  it("treats gh's magic @file field read as opaque rather than innocent", () => {
    expect(blocking("gh api repos/O/R/pulls/682/reviews -F event=@payload.txt")?.opaque).toBe(true);
    expect(blocking("gh api repos/O/R/pulls/682/reviews -f event=@-")?.opaque).toBe(true);
  });
});

describe("porcelain door: what it must NOT catch", () => {
  it("leaves --approve alone, because gating it deadlocks the repo", () => {
    expect(blocking("gh pr review 656 --approve")).toBeNull();
    expect(blocking("gh pr review 656 -a")).toBeNull();
  });

  it("leaves --comment alone, because it is the intended fallback", () => {
    expect(blocking("gh pr review 656 --comment -F findings.md")).toBeNull();
  });

  it("does not fire on --request-changes appearing inside a quoted body", () => {
    expect(blocking('gh pr review 656 --comment --body "do not use --request-changes here"')).toBeNull();
  });

  it("does not fire on the string sitting in an argument rather than a command position", () => {
    expect(blocking('echo "gh pr review 656 --request-changes"')).toBeNull();
  });

  it("does not fire on -br, where r is the VALUE of --body, not a flag", () => {
    expect(shorthandClusterRequestsChanges("-br")).toBe(false);
    expect(shorthandClusterRequestsChanges("-Fr")).toBe(false);
  });

  it("ignores unrelated traffic without a network call", () => {
    expect(blocking("ls -la")).toBeNull();
    expect(blocking("git status")).toBeNull();
    expect(blocking("gh pr view 656 --json reviews")).toBeNull();
  });
});

describe("REST and GraphQL doors", () => {
  it("BYPASS: gh api posts a review with no -X POST, because a field flag implies POST", () => {
    const target = blocking(
      "gh api repos/Eon-Labs/alpha-forge/pulls/656/reviews -f event=REQUEST_CHANGES -f body=@b.md",
    );
    expect(target?.door).toBe("rest-reviews");
    expect(target?.repo).toBe("Eon-Labs/alpha-forge");
    expect(target?.number).toBe(656);
  });

  it("BYPASS: the two-step pending-review submit, via .../reviews/{id}/events", () => {
    const target = blocking(
      "gh api -X POST repos/Eon-Labs/alpha-forge/pulls/656/reviews/5124984588/events -f event=REQUEST_CHANGES",
    );
    expect(target?.door).toBe("rest-review-events");
  });

  it("BYPASS: --input hides the event in a file, so the command is opaque, not innocent", () => {
    const target = blocking("gh api -X POST repos/O/R/pulls/656/reviews --input /tmp/review.json");
    expect(target?.opaque).toBe(true);
  });

  it("BYPASS: the GraphQL door, invisible to a path-based /pulls/ matcher", () => {
    const target = blocking(
      "gh api graphql -f query='mutation{addPullRequestReview(input:{pullRequestId:\"PR_kw\",event:REQUEST_CHANGES}){clientMutationId}}'",
    );
    expect(target?.door).toBe("graphql");
    expect(target?.opaque).toBe(true);
  });

  it("does not fire on a read-only gh api call against the same path", () => {
    expect(blocking("gh api repos/Eon-Labs/alpha-forge/pulls/656/reviews")).toBeNull();
    expect(blocking("gh api repos/Eon-Labs/alpha-forge/pulls/656 --jq .user.login")).toBeNull();
  });

  it("does not fire on an APPROVE submitted through the REST door", () => {
    expect(blocking("gh api repos/O/R/pulls/656/reviews -f event=APPROVE")).toBeNull();
  });
});

describe("escape hatch", () => {
  it("accepts the token as a leading assignment at a command position", () => {
    expect(hasInvitationEscape(`${ESCAPE_TOKEN}=1 gh pr review 656 -r`)).toBe(true);
  });

  it("accepts it interleaved with other assignments and wrappers", () => {
    expect(hasInvitationEscape(`FOO=1 env ${ESCAPE_TOKEN}=1 gh pr review 656 -r`)).toBe(true);
  });

  it("REFUSES it as a substring inside an argument", () => {
    // A bare substring test is the weak house form, and it means a review body discussing the
    // token disarms the guard for that command.
    expect(hasInvitationEscape(`gh pr review 656 -r --body "do not set ${ESCAPE_TOKEN}=1 here"`)).toBe(false);
  });

  it("REFUSES it when a quoted body fabricates a command position before it", () => {
    // `;` and newline ARE command positions, and both occur freely inside a review body, so
    // anchoring alone was not enough: the token inside the quotes granted the override. Measured
    // as a live bypass of the very defect this hatch's docstring claimed to have fixed.
    expect(hasInvitationEscape(`gh pr review 656 -r --body "step one; ${ESCAPE_TOKEN}=1 is the override"`)).toBe(false);
    expect(hasInvitationEscape(`gh pr review 656 -r --body "line one\n${ESCAPE_TOKEN}=1 grants it"`)).toBe(false);
    expect(hasInvitationEscape(`gh pr review 656 -r --body 'a && ${ESCAPE_TOKEN}=1'`)).toBe(false);
  });

  it("still accepts it after a REAL separator outside quotes", () => {
    // The fix must not make the hatch unusable in a compound command.
    expect(hasInvitationEscape(`echo start; ${ESCAPE_TOKEN}=1 gh pr review 656 -r`)).toBe(true);
  });

  it("is absent from an ordinary command", () => {
    expect(hasInvitationEscape(PORCELAIN)).toBe(false);
  });
});

describe("decide: every gap resolves to deny", () => {
  const target: BlockingReviewTarget = {
    door: "porcelain",
    repo: "Eon-Labs/alpha-forge",
    number: 656,
    opaque: false,
  };

  it("allows a review of your own pull request", () => {
    expect(decide(target, { actor: "terrylica", author: "terrylica", invited: false }).decision).toBe("allow");
  });

  it("allows a review you were invited to, including round 2+", () => {
    // requested_reviewers is CLEARED by your own first submission, so the invitation fact must be
    // the durable timeline event. This case is 73% of review traffic in this repo.
    expect(decide(target, { actor: "terrylica", author: "ChenLi0830", invited: true }).decision).toBe("allow");
  });

  it("denies the uninvited blocking review that motivated the guard", () => {
    const verdict = decide(target, { actor: "terrylica", author: "ChenLi0830", invited: false });
    expect(verdict.decision).toBe("deny");
    if (verdict.decision !== "deny") throw new Error("unreachable");
    expect(verdict.reason).toContain("ChenLi0830");
    expect(verdict.reason).toContain("--comment");
    expect(verdict.reason).toContain(ESCAPE_TOKEN);
  });

  it("denies when the invitation could not be QUERIED, which is not the same as absent", () => {
    expect(decide(target, { actor: "terrylica", author: "ChenLi0830", invited: null }).decision).toBe("deny");
  });

  it("denies when the author could not be resolved", () => {
    expect(decide(target, { actor: "terrylica", author: null, invited: null }).decision).toBe("deny");
  });

  it("denies when the actor could not be resolved", () => {
    // Otherwise author === actor can never match and every review looks like someone else's.
    expect(decide(target, { actor: null, author: "ChenLi0830", invited: true }).decision).toBe("deny");
  });

  it("denies an opaque command even when the author is you", () => {
    // The event is unreadable, so "this is my own PR" does not establish that the action is safe:
    // the target itself came from a path the classifier could not fully read.
    const opaque: BlockingReviewTarget = { ...target, opaque: true };
    expect(decide(opaque, { actor: "terrylica", author: "terrylica", invited: true }).decision).toBe("deny");
  });

  it("states its own limits in the denial, rather than implying containment", () => {
    const verdict = decide(target, { actor: "terrylica", author: "ChenLi0830", invited: false });
    if (verdict.decision !== "deny") throw new Error("unreachable");
    expect(verdict.reason).toContain("not a containment boundary");
    expect(verdict.reason).toContain("TIMES OUT");
  });
});
