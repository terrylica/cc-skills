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
