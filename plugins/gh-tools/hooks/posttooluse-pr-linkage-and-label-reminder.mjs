#!/usr/bin/env node
/**
 * posttooluse-pr-linkage-and-label-reminder.mjs
 *
 * PostToolUse hook. After a pull request is created or edited, report TWO things the author cannot
 * see from the command they just ran:
 *
 *   1. WHICH ISSUES GITHUB WILL CLOSE when the PR merges.
 *   2. WHETHER THE PR HAS ANY LABELS.
 *
 * NON-BLOCKING. Always exits 0. It reports; it never refuses.
 *
 * WHY THIS ASKS GITHUB INSTEAD OF READING THE BODY
 *
 * The obvious implementation greps the body for `closes|fixes|resolves #N` and warns. That cannot
 * work, for a reason worth stating: the keyword is usually INTENTIONAL. `Fixes #123` is the correct
 * way to link a bug fix, so a guard that fires on it is noise the author learns to ignore, and a
 * guard that blocks it is wrong.
 *
 * The failure this exists to catch is the opposite one — a closing link nobody meant to create. It
 * was found on Eon-Labs/alpha-forge#787 (2026-09-15), whose body contained the sentence:
 *
 *     rejected two of the three fixes #788 first proposed
 *
 * "fixes" there is an ordinary English noun. GitHub's parser sees `fixes #788`, and the PR silently
 * acquired a promise to close an unrelated P2 issue on merge. Nothing in the diff, the title or the
 * review would have shown it; `closingIssuesReferences` was the only place it was visible. The same
 * sentence pattern then recurred twice more while the first instance was being explained — once in a
 * verbatim quotation of the offending sentence, once in the phrase "does not fix #788" — which is the
 * argument for a machine check rather than a rule to remember.
 *
 * So the hook reports GitHub's OWN parse, after the fact. That has no false-positive class at all: it
 * states what will happen, and the author decides whether that is what they meant. A regex over the
 * body could only guess.
 *
 * The label half is included because it needs the same API call, and because a PR with no labels is
 * invisible to every label-based filter a repository uses for triage.
 *
 * PROCESS-STORM RULES: one `gh` call, bounded by a PID-specific timeout via execSync. No pkill, no
 * retry loop, no unbounded concurrency. Fails silent on any error — a reminder that cannot run is not
 * a reason to interrupt the session.
 */

import { execSync } from "child_process";
import { readFileSync } from "fs";

let input;
try {
  input = JSON.parse(readFileSync(0, "utf-8"));
} catch {
  process.exit(0);
}

const { tool_name, tool_input, tool_output } = input;
if (tool_name !== "Bash") process.exit(0);

const command = tool_input?.command || "";
if (!/\bgh\s+pr\s+(create|edit)\b/.test(command)) process.exit(0);

// `gh pr create` prints the new PR's URL; `gh pr edit N` names the number in the command. Take
// whichever is available, preferring the command so an edit is never misread as its own output.
function resolvePullRequest() {
  const edit = command.match(/\bgh\s+pr\s+edit\s+(\d+)/);
  const repoFlag = command.match(/--repo[=\s]+(\S+)/);
  const repo = repoFlag ? repoFlag[1].replace(/['"]/g, "") : null;
  if (edit) return { number: edit[1], repo };

  const text = typeof tool_output === "string" ? tool_output : JSON.stringify(tool_output ?? "");
  const url = text.match(/https:\/\/github\.com\/([^/\s]+\/[^/\s]+)\/pull\/(\d+)/);
  if (url) return { number: url[2], repo: repo ?? url[1] };
  return null;
}

const target = resolvePullRequest();
if (!target) process.exit(0);

let view;
try {
  const repoFlag = target.repo ? `--repo ${target.repo}` : "";
  const raw = execSync(
    `gh pr view ${target.number} ${repoFlag} --json number,labels,closingIssuesReferences,title 2>/dev/null`,
    { encoding: "utf-8", timeout: 10000 },
  );
  view = JSON.parse(raw);
} catch {
  process.exit(0); // offline, unauthenticated, or not a PR — say nothing
}

const labels = (view.labels ?? []).map((label) => label.name);
const closing = (view.closingIssuesReferences ?? []).map((issue) => issue.number);

const notes = [];

if (closing.length > 0) {
  notes.push(
    `MERGING THIS WILL CLOSE: ${closing.map((n) => `#${n}`).join(", ")}`,
    `   Confirm every one of those is meant to be closed by this PR.`,
    `   A closing link can be created by accident: an ordinary sentence such as`,
    `   "two of the three fixes #788 first proposed" is parsed as the keyword "fixes".`,
    `   To reference an issue WITHOUT closing it, break the adjacency ("fixes that #788")`,
    `   or wrap the phrase in backticks, which suppresses reference parsing.`,
  );
} else {
  notes.push(
    `NO ISSUE WILL BE CLOSED by merging this PR.`,
    `   If it implements an issue, add "Closes #N" so the issue closes on merge.`,
    `   If it is evidence or groundwork for an issue that must stay open, this is correct —`,
    `   reference the issue in the body instead, which cross-links without closing.`,
  );
}

if (labels.length === 0) {
  notes.push(
    ``,
    `NO LABELS.`,
    `   A PR with no labels is invisible to every label-based triage filter.`,
    `   gh pr edit ${target.number} --add-label "<label>"`,
    `   gh label list${target.repo ? ` --repo ${target.repo}` : ""}   # what this repo offers`,
  );
}

if (notes.length === 0) process.exit(0);

const reason = `[gh-tools] PR #${view.number} — linkage and labels

${notes.join("\n")}

Labels now: ${labels.length > 0 ? labels.join(", ") : "(none)"}`;

console.log(JSON.stringify({ decision: "block", reason }));
process.exit(0);
