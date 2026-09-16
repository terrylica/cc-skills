#!/usr/bin/env node
/**
 * pretooluse-stale-checkout-claim-guard.mjs
 *
 * PreToolUse hook. Before PUBLISHING prose about a repository — `gh issue create/edit/comment`,
 * `gh pr create/edit/comment` — check how long it has been since this checkout last heard from its
 * remote. If that was long ago, refuse once and say to fetch.
 *
 * WHY STALENESS AND NOT COMMIT COUNT
 *
 * The obvious check is "how many commits behind is HEAD". It cannot work in a hook, because the
 * answer is computed against `@{u}`, a LOCAL ref that is itself only as fresh as the last fetch. A
 * checkout that has not fetched in a week reports zero commits behind and is maximally wrong. To get
 * a true count the hook would have to hit the network on every publishing command, which is latency
 * in the interactive path and a storm risk besides.
 *
 * So the measured quantity is the AGE OF THE LAST FETCH, read from the mtime of `.git/FETCH_HEAD`.
 * No network, no subprocess beyond locating the git dir, and it answers the question that actually
 * matters: HOW OLD IS MY VIEW OF THIS REPOSITORY? A claim about what a repository contains is only
 * as good as that number, and unlike the commit count it cannot be silently wrong in the reassuring
 * direction.
 *
 * WHAT THIS IS FOR
 *
 * Eon-Labs/alpha-forge#785 (2026-09-15) asserted, in a public issue arguing for a change in
 * statistical doctrine, that a particular function existed "only as three copy-pasted implementations
 * inside frozen evidence, with nothing importable from packages/". A reviewer refuted it: a shared
 * implementation had landed days earlier. The claim was true of the local checkout, which was
 * 47 COMMITS STALE, and false of the repository. The grep was run correctly; the tree it ran against
 * was old. Two further claims in the same session failed the same way.
 *
 * `git fetch` would have cost about two seconds. The guard exists because knowing the rule did not
 * help: the rule was written into that project's own notes earlier in the same session in which it
 * was broken for the third time.
 *
 * ESCAPE: put STALE-CHECKOUT-OK anywhere in the command. Deliberately available — plenty of published
 * prose says nothing about repository state, and the author is the only one who can tell.
 */

import { execSync } from "child_process";
import { readFileSync, statSync } from "fs";
import { join } from "path";

/** Beyond this, a claim about repository contents is not safe to publish unchecked. */
const STALE_AFTER_HOURS = 2;

let input;
try {
  input = JSON.parse(readFileSync(0, "utf-8"));
} catch {
  process.exit(0);
}

const { tool_name, tool_input } = input;
if (tool_name !== "Bash") process.exit(0);

const command = tool_input?.command || "";
if (command.includes("STALE-CHECKOUT-OK")) process.exit(0);

// Publishing prose only. `gh pr merge`, `gh issue list`, `gh pr checks` and friends are untouched.
if (!/\bgh\s+(issue|pr)\s+(create|edit|comment)\b/.test(command)) process.exit(0);

let gitDir;
try {
  gitDir = execSync("git rev-parse --absolute-git-dir 2>/dev/null", {
    encoding: "utf-8",
    timeout: 3000,
  }).trim();
} catch {
  process.exit(0); // not in a repository — nothing to be stale about
}
if (!gitDir) process.exit(0);

let hoursSinceFetch;
try {
  const fetchedAt = statSync(join(gitDir, "FETCH_HEAD")).mtimeMs;
  hoursSinceFetch = (Date.now() - fetchedAt) / 3_600_000;
} catch {
  // Never fetched in this clone. That is the most stale a checkout can be, not the least.
  hoursSinceFetch = Number.POSITIVE_INFINITY;
}

if (hoursSinceFetch < STALE_AFTER_HOURS) process.exit(0);

const age = Number.isFinite(hoursSinceFetch)
  ? `${Math.floor(hoursSinceFetch)}h ago`
  : "never in this clone";

const reason = `[gh-tools] This checkout last fetched ${age}. You are about to publish prose about a repository.

Any claim you make about what this repository contains — "X exists only in...", "there is no Y",
"N of the M files..." — describes the tree you can see, which may not be the tree others can.

    git fetch --all --prune && git status -sb

A 47-commit-stale checkout is how Eon-Labs/alpha-forge#785 came to assert that a function existed
only as copy-pasted evidence copies, when a shared implementation had already landed. The grep was
correct; the tree was old. A reviewer found it.

If this text makes no claim about repository state, add STALE-CHECKOUT-OK to the command.`;

console.log(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  }),
);
process.exit(0);
