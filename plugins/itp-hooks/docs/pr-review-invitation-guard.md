# PR review-invitation guard

- **Hook**: `pretooluse-pr-review-invitation-guard.ts` (PreToolUse, matcher `Bash`)
- **Decision SSoT**: `hooks/lib/pr-review-invitation.ts` (pure — no I/O, so every branch is reachable from a unit test and the classifier is mutation-testable without a network or a repository)
- **Shared libs consumed**: `hooks/lib/review-round-artifact.ts` for `COMMAND_POSITION`, `ghCommand`, `withoutQuotedSpans`, `hasFlag` — **imported, never pasted** (see "The shared constant")
- **Tests**: `hooks/lib/pr-review-invitation.test.ts` (34 bun tests, most of them enumerated bypasses rather than happy paths)
- **Escape hatch**: `PR_BLOCKING_REVIEW_OK=1` as a **leading assignment at a command position**, never a substring
- **Timeout**: `10` in `hooks.json`. That field is **seconds**. Three bounded `gh` calls at 3 s each must fit, and measured end-to-end latency on the network path is 1.9–2.7 s.

## Why it exists

On 2026-09-06 an agent posted `CHANGES_REQUESTED` on Eon-Labs/alpha-forge#656 — authored by the CEO — on the strength of a premise it had invented: it reported the PR as "waiting on my review". No request existed. One arrived at 2026-09-07T05:22:34Z, **19 h 29 m later**.

The review's _content_ was substantive and largely adopted: the merged head commit is titled `Terry's review: make the erratum reachable from the ledger, and link the brain retraction`, and the corrected script's docstring cites `(#656 review)`. The defect was its **form** and its **premise**, not its findings.

So the thing worth gating is not the reviewing. It is the _blocking_ form being reached for by default, on a premise nobody checked.

## It does not adjudicate, and it cannot

Measured over ten months on that repo, **all 6** of the reviewer's `CHANGES_REQUESTED` reviews on other authors' PRs were uninvited, and **5 drew no objection** — #591 and #587 went `CHANGES_REQUESTED` → `APPROVED` within ~35 minutes, an ordinary round. #426, #536 and #541 likewise passed without complaint.

**No fact available at command time separates #656 from those five.** A rule that denied on "uninvited" would therefore carry five false positives per true positive, which is the profile of a guard that gets reflexively overridden and then protects nothing.

What this hook does instead is make the blocking form cost one deliberate keystroke, and put the two queried facts in front of the human at the moment of the act. Converting a reflexive block into a considered one is the whole claim. Preventing anything is not — and the denial text says so.

## What it deliberately leaves alone

| Surface                          | Why                                                                                                                                                                                                                                                                                                 |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--approve`                      | 17 of these on other authors' PRs, 10 since 2026-08-21. The `main` ruleset sets `required_approving_review_count: 1` and GitHub forbids self-approval, so terrylica ↔ ChenLi0830 is a reciprocal approval pair and it is the **only** way anything merges. Gating it would deadlock the repository. |
| `--comment`                      | Carries identical findings without gating anyone. It is the intended fallback, which makes the honest description of this guard's effect a **rename, not a prevention**.                                                                                                                            |
| `gh issue *`                     | Closing or commenting on a collaborator's issue is ordinary triage — terrylica closed Mayweiwang's #441 and #442 and has 24 comments on #435. Scoping this to "mutating another author's artifact" would have swallowed all of it.                                                                  |
| `gh pr close` / `merge` / `edit` | More consequential than a blocking review, and deliberately out of scope: this guard is about review _state_. Widening it is a separate decision, not an oversight.                                                                                                                                 |

## The invitation fact is the timeline, never `requested_reviewers`

GitHub **clears** a user from `requested_reviewers` the moment they submit a review. Measured on two live PRs where terrylica _was_ invited and did review: #201 and #35 both read `[]` afterwards.

Since 73 % of review submissions in this repo are rounds 2+ (`review-round-artifact.ts:12-13`), reading the live array would make **legitimate re-review this guard's dominant false positive**. The durable fact is a `review_requested` event on the issue timeline, and that is what the hook queries.

**Known, deliberate gap**: any such event counts, including a stale one that predates the actor's most recent review. Tightening it would catch a reused invitation, but getting it wrong blocks legitimate round-2+ review. The permissive direction fails as a missed nudge rather than a blocked colleague.

## Why this guard makes network calls when its sibling refuses to

`review-round-artifact.ts:23-27` keeps every input local, verbatim:

> A PreToolUse hook that times out does NOT block — Claude Code proceeds. So any check depending on a network call (`gh pr list`) resolves, when offline or rate limited or slow, to ALLOW. That is Decision #484 — absent data resolving to the favourable answer — reproduced inside a guard built to prevent it.

That reasoning is correct, and it is exactly why this guard **inverts the fallback**. The thing being replaced is an agent's _assertion_ about who asked for a review, and no local file carries that fact, so the call has to happen. What must not happen is its failure quietly meaning yes.

Every gap resolves to **deny**: opaque command, unresolved author, unresolved actor, unqueryable timeline. Calls are bounded at 3 s via `AbortSignal.timeout`, and the child pid is killed directly in a `finally` — never `pkill -f`, which matches processes this hook did not start. alpha-forge PR #576 shipped the shell equivalent after finding an unbounded `gh repo view` inside a PreToolUse hook.

## The four doors

A guard that covers only the porcelain spelling is decorative. All four are classified:

1. **Porcelain** — `gh pr review … --request-changes`, including `--request-changes=true` and pflag shorthand **clusters** (`-rb "msg"` is `--request-changes --body "msg"`; a value-taking shorthand consumes the rest of the cluster, so `-br` is _not_ a request-changes).
2. **REST** — `gh api …/pulls/N/reviews -f event=REQUEST_CHANGES`. No `-X POST` is required: `gh api` switches to POST as soon as any field flag is present, so a matcher demanding an explicit method would be decorative. The `/repos/` prefix is optional.
3. **Two-step submit** — `…/pulls/N/reviews/{id}/events`, the door used when attaching several inline findings to a pending review.
4. **GraphQL** — `gh api graphql … addPullRequestReview … REQUEST_CHANGES`, invisible to any path-based `/pulls/` matcher.

`--input file.json` and GraphQL are **opaque**: the event sits in a file or payload the hook must not open at decision time (it is I/O in a pure classifier, and the file can be rewritten between check and use). Opaque resolves to denied.

## The shared constant

Two defects in `COMMAND_POSITION` are relevant, and both spread by **copying**:

- The inherited `\S*` assignment value stopped at the first space, so `GH_ORGS="Eon Labs" gh …` matched no command position at all. Fixed in `review-round-artifact.ts`, still live in `pretooluse-pr-citation-evidence-guard.ts:86` — the same pattern, fixed in one of two copies.
- **A wrapper's own flags are part of the wrapper.** `env` was accepted but `env -u NAME` was not, so `env -u GH_TOKEN gh pr review --request-changes` put `gh` outside every command position and matched nothing. That spelling is this plugin's **own house style** — every `hooks.json` entry is `env -u AI_AGENT -u CLAUDECODE bun …` — so it is the form an agent copying local convention would most likely produce. Found by a test, not by reading. `review-round-gate` and `pr-citation-evidence-guard` carried the same hole.

The fix is pinned by six rows in `review-round-artifact.test.ts`. Reverting the constant turns **exactly 7 tests red** and nothing else, so those rows pin the diff rather than passing on both trees.

This guard therefore **imports** the primitives instead of pasting a third copy. `-u`/`-C`/`-S` take a value and `-i`/`-v` do not, which is why they cannot share one pattern: the value-less form would swallow the command it is supposed to leave behind.

## Verified end to end against live GitHub

A pair chosen to differ only in ground truth, not in command shape:

| PR   | Ground truth                                                 | Verdict  | Latency |
| ---- | ------------------------------------------------------------ | -------- | ------- |
| #426 | ChenLi0830's; blocked by terrylica 2026-09-03; never invited | **deny** | 1949 ms |
| #656 | ChenLi0830's; review requested 2026-09-07T05:22:34Z          | allow    | 2721 ms |

Had both denied, the guard would be reporting its own prior rather than reading the API. Controls: `ls -la`, `--approve` and `--comment` all allow in 12–13 ms with no network; the leading-assignment override allows in 21 ms.

## What it cannot do

Said here because the denial text says it too. This is **not a containment boundary**:

- `"disableAllHooks": true` in any settings file switches it off, along with every other guard.
- A review submitted from the GitHub web UI never passes through a command string.
- A PreToolUse hook that exceeds its timeout renders no verdict and Claude Code proceeds. `type: "script"` is the only hook kind whose failure blocks, and it is not in the settings schema union — so fail-open on timeout is **not a choice this guard gets to make**.

The claim is that going around it is charged and visible, not that it is impossible.
