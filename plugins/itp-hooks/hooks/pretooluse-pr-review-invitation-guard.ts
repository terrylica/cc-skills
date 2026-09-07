#!/usr/bin/env bun
/**
 * PreToolUse: make a BLOCKING pull-request review a deliberate act rather than a default one.
 *
 * The decision surface is in lib/pr-review-invitation.ts and takes no I/O. This file is the thin
 * shell around it: read stdin, run the cheap classifier, and only if that says "blocking review"
 * spend up to three bounded `gh` calls learning who authored the PR and whether the actor was ever
 * invited to review it.
 *
 * WHY IT QUERIES AT ALL, WHEN THE SIBLING GATE REFUSES TO. review-round-artifact.ts:23-27 makes
 * every input local, because a PreToolUse hook that times out does NOT block, so a network check
 * resolves on failure to ALLOW -- Decision #484 reproduced inside a guard. That reasoning is
 * correct and it is exactly why this guard inverts the fallback: every gap here resolves to DENY.
 * The thing being replaced is an agent's ASSERTION about who asked for a review, and no local file
 * carries that fact, so the call has to happen. What must not happen is the call's failure quietly
 * meaning yes.
 *
 * WHAT IT CANNOT DO, said here because the denial text says it too: this is not a containment
 * boundary. `"disableAllHooks": true` switches it off, a review submitted from the web UI never
 * passes through a command string, and if this hook exceeds its timeout Claude Code proceeds
 * without a verdict. The claim is that going around it is charged and visible, not that it is
 * impossible.
 *
 * A KNOWN, DELIBERATE GAP. The invitation test accepts ANY `review_requested` event naming the
 * actor, including a months-old one, rather than requiring it to post-date the actor's most recent
 * review. Tightening it would catch a stale invitation being reused, but getting it wrong blocks
 * legitimate round-2+ review, which is 73% of review traffic in this repo. The permissive
 * direction is the one whose failure mode is a missed nudge rather than a blocked colleague.
 */

import {
  allow,
  deny,
  parseStdinOrAllow,
  trackHookError,
} from "./pretooluse-helpers.ts";
import {
  classifyBlockingReview,
  decide,
  hasInvitationEscape,
  type InvitationFacts,
} from "./lib/pr-review-invitation.ts";

const HOOK = "pretooluse-pr-review-invitation-guard";

/**
 * Per-call ceiling. THREE sequential calls happen on the slow path (actor, pr view, timeline), so
 * the worst case is 3x this plus bun start-up, and it must fit inside the `hooks.json` timeout
 * with real margin. At 3000 the worst case was 9.0 s against a 10 s budget -- under a second of
 * headroom, and a hook that overruns its budget renders NO verdict, which is a silent permit.
 */
const CALL_TIMEOUT_MS = 2500;

/**
 * Run `gh` with a hard bound, and kill THIS pid rather than pattern-matching.
 *
 * PR #576 in alpha-forge shipped the shell version of this after finding an UNBOUNDED `gh repo
 * view` inside a PreToolUse hook. The process-storm rules on this machine also forbid `pkill -f`
 * for gh, because the pattern matches processes this hook did not start.
 *
 * Returns null on non-zero exit, timeout, or a missing/unauthenticated `gh`. Null is a question
 * the guard could not answer, and the caller treats that as unfavourable -- never as "no".
 */
async function gh(args: string[], cwd: string): Promise<string | null> {
  let proc: ReturnType<typeof Bun.spawn> | null = null;
  try {
    proc = Bun.spawn(["gh", ...args], {
      cwd,
      stdout: "pipe",
      stderr: "ignore",
      signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
    });

    // THE READ MUST BE RACED, NOT JUST THE SPAWN. Reading stdout to EOF waits for EVERY holder of
    // the pipe's write end to close it, so a `gh` that forks a descendant inheriting stdout (a
    // pager, a credential helper, an extension) leaves this await pending after gh itself exits.
    // AbortSignal on spawn does not interrupt an in-flight stream read, so the hook hung past its
    // own CALL_TIMEOUT_MS -- and a PreToolUse hook that exceeds the hooks.json timeout renders NO
    // verdict and Claude Code proceeds. An unbounded read is therefore a silent permit, which is
    // the one outcome this guard exists to prevent.
    const spawned = proc;
    // `proc` is declared outside the try so `finally` can kill it, which widens stdout to the
    // options-independent union. The spawn above pins it to "pipe", so this narrowing is sound.
    const read = new Response(spawned.stdout as ReadableStream<Uint8Array>).text();
    const timedOut = Symbol("timeout");
    const raced = await Promise.race([
      (async () => ({ text: await read, code: await spawned.exited }))(),
      new Promise<typeof timedOut>((resolve) =>
        setTimeout(() => resolve(timedOut), CALL_TIMEOUT_MS),
      ),
    ]);
    if (raced === timedOut) return null;
    return raced.code === 0 ? raced.text.trim() : null;
  } catch {
    return null;
  } finally {
    // Belt and braces: if the abort signal fired, the child should already be gone, but an
    // orphaned `gh` from a hook is the exact shape of the storm incident this machine has paid
    // for. Killing an already-exited pid is a no-op.
    try {
      proc?.kill();
    } catch {
      /* already reaped */
    }
  }
}

/** `{"login":"terrylica"}` style single-field extraction without a JSON dependency on gh's --jq. */
function jsonField(raw: string | null, field: string): string | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    const value = parsed[field];
    if (typeof value === "string") return value;
    if (value && typeof value === "object" && "login" in value) {
      const login = (value as { login?: unknown }).login;
      return typeof login === "string" ? login : null;
    }
    if (typeof value === "number") return String(value);
    return null;
  } catch {
    return null;
  }
}

const PR_URL = /github\.com\/([A-Za-z0-9._-]+\/[A-Za-z0-9._-]+)\/pull\/\d+/;

async function gatherFacts(
  cwd: string,
  repo: string | null,
  number: number | null,
): Promise<InvitationFacts> {
  const actor = await gh(["api", "user", "--jq", ".login"], cwd);

  // ONE call resolves author, canonical number and canonical repo, and it works whether or not the
  // command stated a number -- `gh pr review --request-changes` with no argument is the commonest
  // spelling, and refusing it outright would be a false positive on the reviewer's own PR.
  const viewArgs = ["pr", "view"];
  if (number !== null) viewArgs.push(String(number));
  if (repo) viewArgs.push("-R", repo);
  viewArgs.push("--json", "number,author,url");
  const view = await gh(viewArgs, cwd);

  const author = jsonField(view, "author");
  const resolvedNumber = jsonField(view, "number") ?? (number === null ? null : String(number));
  const resolvedRepo = repo ?? PR_URL.exec(jsonField(view, "url") ?? "")?.[1] ?? null;

  if (!actor || !author || !resolvedNumber || !resolvedRepo) {
    return { actor, author, invited: null };
  }

  // The DURABLE invitation fact. `requested_reviewers` is cleared by the act of reviewing, so it
  // reads empty for every legitimate round-2+ review; the timeline keeps the event forever.
  const timeline = await gh(
    [
      "api",
      `repos/${resolvedRepo}/issues/${resolvedNumber}/timeline`,
      "--paginate",
      "--jq",
      `[.[] | select(.event == "review_requested") | .requested_reviewer.login] | index("${actor}") != null`,
    ],
    cwd,
  );

  const invited = timeline === null ? null : timeline.includes("true");
  return { actor, author, invited };
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow(HOOK);
  if (!input) return;
  if (input.tool_name !== "Bash") return allow();

  const command = input.tool_input?.command;
  if (typeof command !== "string" || command.length === 0) return allow();

  // Cheap, local, no network. Exits here for essentially all traffic.
  const target = classifyBlockingReview(command);
  if (!target) return allow();

  if (hasInvitationEscape(command)) return allow();

  const facts = target.opaque
    ? { actor: null, author: null, invited: null }
    : await gatherFacts(input.cwd ?? process.cwd(), target.repo, target.number);

  const verdict = decide(target, facts);
  if (verdict.decision === "allow") return allow();
  return deny(verdict.reason);
}

main().catch((error: unknown) => {
  // A crash must not become a silent permit for the one action this guard exists to meter, but it
  // also must not wedge the session. Counting it is what makes a broken guard visible instead of
  // quietly absent -- an always-throwing hook that fails open is indistinguishable from one that
  // is working, which is how a guard rots into decoration.
  trackHookError(HOOK, `${HOOK}_FAILOPEN: ${error instanceof Error ? error.stack : String(error)}`);
  allow();
});
