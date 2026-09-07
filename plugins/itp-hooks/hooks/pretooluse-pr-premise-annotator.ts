#!/usr/bin/env bun
/**
 * PreToolUse on AskUserQuestion: label every pull request an option names with the facts the agent
 * would otherwise be asserting.
 *
 * WHY THIS EXISTS, AND WHY IT IS UPSTREAM OF THE OTHER GUARD. On 2026-09-06 an agent surveyed every
 * open PR and reported Eon-Labs/alpha-forge#656 as "waiting on my review". No request existed; one
 * arrived 19h29m LATER. That false premise reached the operator's menu as an innocuous-looking
 * option labelled "Review #656", was approved inside a batch, and became a blocking review on the
 * CEO's own pull request.
 *
 * Every guard written after that incident acts at the moment of the COMMAND. This one acts at the
 * moment of the DECISION, which is where the premise was actually manufactured. It does not block
 * anything and cannot produce a false positive in the usual sense: it appends queried facts and
 * gets out of the way.
 *
 * WHAT IT APPENDS, and why it is one line. The sibling
 * pretooluse-askuserquestion-option-line-terminator-guard DENIES any newline inside an option's
 * `label` or `description`, because Claude Code renders one as U+FFFD. So the annotation is a
 * single ` — ` separated clause, never a second paragraph.
 *
 * FAILURE IS COUNTED, NOT SILENT. `allowWithInput` validates the mutated input against
 * TOOL_SCHEMAS.AskUserQuestion; on any mismatch it calls `trackHookError` and falls back to a plain
 * `allow()`. That matters more here than anywhere else, because an annotator that quietly stops
 * annotating looks exactly like one that has nothing to say.
 */

import {
  allow,
  allowWithInput,
  parseStdinOrAllow,
  trackHookError,
} from "./pretooluse-helpers.ts";

const HOOK = "pretooluse-pr-premise-annotator";

/** Interactive dialog: keep the worst case short enough that the human does not notice. */
const CALL_TIMEOUT_MS = 2000;
/** A menu may name many PRs; only the first few are worth a round trip. */
const MAX_PRS = 3;

const PR_REFERENCE = /(?:https:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/pull\/(\d+)|#(\d+))/g;

interface PrFacts {
  author: string | null;
  invited: boolean | null;
}

async function gh(args: string[], cwd: string): Promise<string | null> {
  let proc: ReturnType<typeof Bun.spawn> | null = null;
  try {
    proc = Bun.spawn(["gh", ...args], {
      cwd,
      stdout: "pipe",
      stderr: "ignore",
      signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
    });
    const spawned = proc;
    const read = new Response(spawned.stdout as ReadableStream<Uint8Array>).text();
    const timedOut = Symbol("timeout");
    // The READ must be raced, not only the spawn: reading to EOF waits for every holder of the
    // pipe's write end, so a gh descendant inheriting stdout outlives gh itself and an
    // AbortSignal on spawn does not interrupt an in-flight stream read.
    const raced = await Promise.race([
      (async () => ({ text: await read, code: await spawned.exited }))(),
      new Promise<typeof timedOut>((resolve) => setTimeout(() => resolve(timedOut), CALL_TIMEOUT_MS)),
    ]);
    if (raced === timedOut) return null;
    return raced.code === 0 ? raced.text.trim() : null;
  } catch {
    return null;
  } finally {
    try {
      proc?.kill();
    } catch {
      /* already reaped */
    }
  }
}

async function factsFor(cwd: string, repo: string | null, number: string, actor: string | null): Promise<PrFacts> {
  const viewArgs = ["pr", "view", number];
  if (repo) viewArgs.push("-R", repo);
  viewArgs.push("--json", "author,url");
  const view = await gh(viewArgs, cwd);
  if (!view) return { author: null, invited: null };

  let author: string | null = null;
  let resolvedRepo = repo;
  try {
    const parsed = JSON.parse(view) as { author?: { login?: string }; url?: string };
    author = parsed.author?.login ?? null;
    resolvedRepo = repo ?? /github\.com\/([\w.-]+\/[\w.-]+)\/pull\//.exec(parsed.url ?? "")?.[1] ?? null;
  } catch {
    return { author: null, invited: null };
  }
  if (!actor || !resolvedRepo) return { author, invited: null };
  if (author === actor) return { author, invited: null };

  // The DURABLE invitation fact. `requested_reviewers` is cleared the moment you submit a review,
  // so it reads empty for every legitimate re-review; the timeline keeps the event.
  const timeline = await gh(
    [
      "api",
      `repos/${resolvedRepo}/issues/${number}/timeline`,
      "--paginate",
      "--jq",
      `[.[] | select(.event == "review_requested") | .requested_reviewer.login] | index("${actor}") != null`,
    ],
    cwd,
  );
  return { author, invited: timeline === null ? null : timeline.includes("true") };
}

/** One line, no newline, safe to append to an option description. */
function annotation(number: string, facts: PrFacts, actor: string | null): string {
  if (!facts.author) return `[#${number}: could not be resolved just now]`;
  if (actor && facts.author === actor) return `[#${number}: yours]`;
  const invitation =
    facts.invited === null
      ? "review request unknown"
      : facts.invited
        ? `review requested from ${actor}`
        : "no review requested from you";
  return `[#${number}: @${facts.author}'s, ${invitation}]`;
}

function referencesIn(text: string): Array<{ repo: string | null; number: string }> {
  const found: Array<{ repo: string | null; number: string }> = [];
  PR_REFERENCE.lastIndex = 0;
  for (const match of text.matchAll(PR_REFERENCE)) {
    found.push({ repo: match[1] ?? null, number: (match[2] ?? match[3])! });
  }
  return found;
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow(HOOK);
  if (!input) return;
  if (input.tool_name !== "AskUserQuestion") return allow();

  const questions = input.tool_input?.questions;
  if (!Array.isArray(questions)) return allow();

  const cwd = input.cwd ?? process.cwd();
  const wanted = new Map<string, { repo: string | null; number: string }>();

  for (const question of questions) {
    for (const option of (question as { options?: unknown[] }).options ?? []) {
      const text = `${(option as { label?: string }).label ?? ""} ${(option as { description?: string }).description ?? ""}`;
      for (const reference of referencesIn(text)) {
        const key = `${reference.repo ?? ""}#${reference.number}`;
        if (!wanted.has(key) && wanted.size < MAX_PRS) wanted.set(key, reference);
      }
    }
  }
  // No pull request named, so nothing to say and no network call. This is the common case.
  if (wanted.size === 0) return allow();

  const actor = await gh(["api", "user", "--jq", ".login"], cwd);
  // CONCURRENT, because this hook delays a dialog the human is waiting on. Sequential lookups
  // measured 6.2 s for three pull requests, which is long enough to feel broken; the concurrency is
  // bounded by MAX_PRS and every child is both timeout-bounded and killed, per the process-storm
  // rule that the bound must be on CONCURRENCY and not only on duration.
  const facts = new Map(
    await Promise.all(
      [...wanted].map(
        async ([key, reference]) =>
          [
            key,
            annotation(reference.number, await factsFor(cwd, reference.repo, reference.number, actor), actor),
          ] as const,
      ),
    ),
  );

  let changed = false;
  const annotated = questions.map((question) => {
    const typed = question as { options?: unknown[] };
    if (!Array.isArray(typed.options)) return question;
    return {
      ...typed,
      options: typed.options.map((option) => {
        const typedOption = option as { label?: string; description?: string };
        const text = `${typedOption.label ?? ""} ${typedOption.description ?? ""}`;
        const notes = referencesIn(text)
          .map((reference) => facts.get(`${reference.repo ?? ""}#${reference.number}`))
          .filter((note): note is string => Boolean(note));
        const unique = [...new Set(notes)];
        if (unique.length === 0) return option;
        changed = true;
        return { ...typedOption, description: `${typedOption.description ?? ""} — ${unique.join(" ")}` };
      }),
    };
  });

  if (!changed) return allow();
  return allowWithInput(HOOK, "AskUserQuestion", { ...input.tool_input, questions: annotated });
}

main().catch((error: unknown) => {
  trackHookError(HOOK, `${HOOK}_FAILOPEN: ${error instanceof Error ? error.stack : String(error)}`);
  allow();
});
