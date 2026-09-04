#!/usr/bin/env bun
/**
 * PreToolUse gate: work does not reach a human reviewer until a local adversarial pass has been
 * recorded AT THE EXACT COMMIT being shown.
 *
 * Measured motivation is in lib/review-round-artifact.ts. The short version: 73% of this
 * reviewer's attention is RE-review, and PRs over 900 lines cost 7.43 rounds each against 1.36 for
 * PRs under 400. Rounds are the scarce resource, not pull requests -- so this meters the
 * transition to reviewable and each subsequent push, rather than capping how many PRs may be open.
 *
 * WHAT IT CANNOT DO, said plainly here because the deny message says it too: this is not a
 * containment boundary. `"disableAllHooks": true` in any settings file switches off this guard and
 * every other one, `gh api` and a browser reach GitHub without touching a gated command string, and
 * a PR opened outside this gate is never recorded so its pushes go unmetered. The claim is that
 * going around it is CHARGED AND VISIBLE, not that it is impossible.
 */

import { allow, ask, deny, parseStdinOrAllow } from "./pretooluse-helpers.ts";
import { trackHookError } from "./lib/hook-error-tracker.ts";
import {
  classify,
  overrideReason,
  validateArtifact,
  type GatedKind,
} from "./lib/review-round-artifact.ts";
import {
  collectFacts,
  identifyRepo,
  isBranchReviewable,
  markBranchReviewable,
  readArtifact,
  recordOverride,
} from "./lib/review-round-state.ts";

const RECORD_COMMAND = 'bun "$(cc-plugin-root itp-hooks)/hooks/lib/review-round-cli.ts" record';

function limitsBlock(): string {
  return [
    "",
    "Limits: this gate sees only what you record and what git can tell it. It cannot see the",
    "reviewer's queue, does not apply to a PR opened outside it (web UI, gh api), and is switched",
    'off entirely by "disableAllHooks": true in any settings file.',
  ].join("\n");
}

function denyMessage(kind: GatedKind, matched: string, failures: readonly string[]): string {
  const what =
    kind === "pr-ready"
      ? "marking this PR ready for review"
      : kind === "pr-create"
        ? "opening this PR for review"
        : "pushing to a branch that is already in front of a reviewer";

  return [
    `[REVIEW-ROUND-GATE] No valid self-review record for HEAD — ${what}.`,
    "",
    "Why: 73% of this reviewer's attention is re-review (110 of 150 submissions across 40 PRs),",
    "and PRs over 900 lines cost 7.43 rounds each against 1.36 for PRs under 400. A local",
    "adversarial pass at this exact commit is what converts a round he pays for into one you do.",
    "",
    "Found:",
    ...failures.slice(0, 3).map((f) => `    ${f}`),
    ...(failures.length > 3 ? [`    …and ${failures.length - 3} more.`] : []),
    "",
    `Matched: ${matched}`,
    "",
    "Fix: audit the diff, then record it (local only, no network):",
    `    ${RECORD_COMMAND} --file 'path=what you checked and what survived' …`,
    "  Or keep it out of the queue for now:  gh pr create --draft …",
    limitsBlock(),
    "",
    'Override: prefix with REVIEW_ROUND_OK="<reason, 12+ chars>" — this ASKS rather than allowing',
    "silently, and is written to the override log.",
  ].join("\n");
}

function inlineBodyMessage(matched: string): string {
  return [
    "[REVIEW-ROUND-GATE] Publish the body from a file, not inline.",
    "",
    "Why: an inline multi-line --body is composed in the same command that publishes it, so nothing",
    "can inspect it first. It also trips the same-repo-branch guard's shell tokenisation when it",
    "contains parentheses or backticks, which denies with a misleading message about forks.",
    "",
    `Found: ${matched}`,
    "",
    "Fix: write the body to a file, then publish it:",
    "    (write /tmp/body.md with the Write tool)",
    "    gh pr comment <n> --body-file /tmp/body.md",
    "",
    "A short single-line --body is fine and is not gated.",
    "",
    'Override: prefix with REVIEW_ROUND_OK="<reason, 12+ chars>".',
  ].join("\n");
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow();
  if (input.tool_name !== "Bash") return allow();

  const command = String(input.tool_input?.command ?? "");
  if (!command) return allow();

  // Cheap prefilter. The overwhelming majority of Bash commands leave here without spawning git.
  if (!/\bgh\b/.test(command) && !/\bgit\s+push\b/.test(command)) return allow();

  const { kind, matched } = classify(command);
  if (kind === null) return allow();

  const cwd = input.cwd ?? process.cwd();
  const repo = identifyRepo(cwd);
  // Not a git repo, or detached HEAD: nothing to anchor an artifact to. Fail OPEN rather than
  // block work the gate cannot reason about.
  if (repo === null) return allow();

  const reason = overrideReason(command);
  if (reason !== null) {
    recordOverride(repo, kind, reason, command);
    return ask(
      `[REVIEW-ROUND-GATE] Override requested for ${kind}: "${reason}"\n\n` +
        "Recorded in the override log. Approve to proceed.",
    );
  }

  if (kind === "inline-body") return deny(inlineBodyMessage(matched));

  // A push only counts as a review round once the branch is actually in front of someone.
  if (kind === "push" && !isBranchReviewable(repo)) return allow();

  const facts = collectFacts(cwd);
  // No resolvable base branch. Same reasoning as a missing repo: fail open rather than block with
  // a remedy the operator cannot perform.
  if (facts === null) return allow();

  const verdict = validateArtifact(readArtifact(repo), facts);
  if (!verdict.ok) return deny(denyMessage(kind, matched, verdict.failures));

  // Allowed, and the transition is now observable: remember that this branch is reviewable so
  // subsequent pushes are metered too.
  if (kind === "pr-ready" || kind === "pr-create") markBranchReviewable(repo);
  return allow();
}

main().catch((error) => {
  // FAIL OPEN, but COUNTABLY. A guard that blocks work when its own logic throws is worse than the
  // defect it prevents; a guard that fails open silently is indistinguishable from no guard. The
  // audit code makes silent disarmament something you can `grep -c`.
  try {
    // Signature is (hookName, message, sessionId?) — a third argument of options would be read as
    // a session id and silently mis-file the entry.
    trackHookError(
      "pretooluse-review-round-gate",
      `REVIEW_ROUND_GATE_FAILOPEN: ${error instanceof Error ? error.stack ?? error.message : String(error)}`,
    );
  } catch {
    // never let the tracker itself block
  }
  allow();
});
