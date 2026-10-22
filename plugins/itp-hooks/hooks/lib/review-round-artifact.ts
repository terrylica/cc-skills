#!/usr/bin/env bun
/**
 * Pure core of the review-round gate: command classification and artifact validation.
 *
 * WHY THIS GATE EXISTS, IN NUMBERS. On example-org/research-repo, across 22 reviewed PRs from one
 * author, review submissions by the reviewer split like this:
 *
 *     PRs <= 400 changed lines   n=11   mean 1.36 review rounds   15 events total
 *     PRs  > 900 changed lines   n=7    mean 7.43 review rounds   52 events total
 *
 * Five PRs, all over 900 lines, accounted for 63% of every review event spent on that author's
 * work. Over a wider window of 40 merged PRs, 110 of 150 review submissions were rounds 2+ --
 * 73% of the reviewer's attention is RE-review, with Spearman rho ~ 0.71 between churn and rounds.
 *
 * So the scarce resource is not pull requests, it is ROUNDS. A cap on how many PRs may be open
 * meters ~27% of the load and leaves the rest untouched; worse, a queue-depth cap starves a bursty
 * reviewer (the same reviewer cleared 10 PRs in a single 7-hour sitting) and is shapeable into the
 * very flood it forbids -- two at the top of the hour, two at the end.
 *
 * This gate meters the transition to reviewable instead, and requires that a local adversarial
 * pass has happened AT THE EXACT COMMIT being shown to the reviewer.
 *
 * WHY EVERYTHING HERE IS LOCAL. A PreToolUse hook that times out does NOT block -- Claude Code
 * proceeds. So any check depending on a network call (`gh pr list`) resolves, when offline or rate
 * limited or slow, to ALLOW. That is Decision #484 -- absent data resolving to the favourable
 * answer -- reproduced inside a guard built to prevent it. Every input here is `git rev-parse`,
 * `git diff`, or a local file.
 *
 * WHAT THIS FILE DELIBERATELY DOES NOT DO: any I/O. Git and filesystem access are injected by the
 * caller, so the whole decision surface is testable without a repository and can be mutation-tested
 * without touching disk.
 */

import { createHash } from "node:crypto";

import { homedir } from "node:os";
import { resolve as resolvePath } from "node:path";
import { splitShellWords, withoutNonShellHeredocBodies } from "./shell-arg-extractor.ts";
import { lexShellCommands } from "./shell-command-quote-aware-static-lexer.ts";
import {
  basename as invocationBasename,
  skipAssignmentsAndWrappers,
  walkShellInvocations,
  type ShellInvocation,
  type Word,
} from "./shell-command-invocation-walker.ts";

// ---------------------------------------------------------------------------------------------
// Command classification
// ---------------------------------------------------------------------------------------------

/**
 * Reused verbatim from pretooluse-pr-citation-evidence-guard.ts:86.
 *
 * Assignments and wrappers INTERLEAVE (`FOO=1 sudo env BAR=2 gh ...`), and a fixed-order pattern
 * matched only the first arrangement. Anchoring at a command position also means `echo "run gh pr
 * ready"` is not a match -- the string sits in an argument, not at the head of a command.
 */
// AN ASSIGNMENT VALUE MAY BE QUOTED AND MAY CONTAIN SPACES. The inherited pattern used `\S*` for
// the value, which stops at the first space -- so `GH_ORGS="Eon Labs" gh pr create …` did not match
// a command position at all and the guard silently ALLOWED it. Any quoted assignment with a space
// was a total bypass, including the guard's own override prefix, which made the override resolve to
// `allow` instead of `ask`. Found by the end-to-end test, not by reading; `FOO=bar` (unquoted) works
// either way, which is why the unit cases missed it.
//
// The same `\S*` appears in pretooluse-pr-citation-evidence-guard.ts:86, which this pattern was
// copied from, so that guard is likely bypassable the same way.
//
// EXPORTED because a COPY of this pattern drifted, measurably. pr-citation-evidence-guard kept its
// own; the quoted-assignment fix above happened to land in both, but two LATER corrections -- the
// wrapper's own flags (`env -u X gh`) and matching `gh` by BASENAME (`/opt/homebrew/bin/gh`) -- landed
// only here, so that guard silently allowed both spellings plus `nice gh`. Its copy is now deleted
// and it imports these symbols, as does pretooluse-pr-review-invitation-guard.ts.
//
// CORRECTION, recorded because I asserted the opposite: an earlier version of this comment claimed
// the `\S*` defect was "still live in pr-citation-evidence-guard.ts:86". It was not -- that file
// carried the fixed alternation already. I repeated an agent's finding without running it. The
// drift was real but in two different corrections than the one I named.
//
// Same rule, one home -- see `matchNoteIds` in notes-commander's notes-core.ts for the precedent.
//
// A WRAPPER'S OWN FLAGS ARE PART OF THE WRAPPER. `env` was accepted but `env -u GH_TOKEN` was not,
// so `env -u GH_TOKEN gh pr review --request-changes` put `gh` outside every command position and
// matched nothing at all. That spelling is not exotic here -- every entry in this plugin's hooks.json
// was registered as `env -u AI_AGENT -u CLAUDECODE bun ...` until 2026-10-02. Found by a
// test in pr-review-invitation.test.ts, and it applies to every guard sharing this constant.
// `-u/-C/-S` take a value, `-i/-v` do not, so they cannot share one pattern without the value-less
// form swallowing the command it is supposed to leave behind.
const WRAPPER = String.raw`(?:env\s+(?:(?:-[iv]+|--ignore-environment)\s+|(?:-[uCS]|--unset|--chdir|--split-string)(?:=\S+|\s+\S+)\s+)*|(?:sudo|command|time|nice)\s+|timeout\s+-?[\d.]+[smhd]?\s+)`;

export const COMMAND_POSITION = String.raw`(?:^|[\n;&|(){}]|&&|\|\|)\s*(?:${WRAPPER}|[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|\S*)\s+)*`;

/** Match `gh` by BASENAME, so `/opt/homebrew/bin/gh` and `"$GH"` are not free bypasses. */
export const ghCommand = (rest: string) =>
  new RegExp(`${COMMAND_POSITION}(?:[\\w./-]*/)?gh\\s+${rest}`, "i");

const gitCommand = (rest: string) =>
  new RegExp(`${COMMAND_POSITION}(?:[\\w./-]*/)?git\\s+${rest}`, "i");

const GH_PR_READY = ghCommand(String.raw`pr\s+ready\b`);
const GH_PR_CREATE = ghCommand(String.raw`pr\s+create\b`);
/**
 * `git push`, also after git's GLOBAL options (`git -C ../wt push`, `git -c k=v push`). Without them
 * `git -C <worktree> push` was not recognised as a push at all, so a push to a branch in front of a
 * reviewer went unmetered whenever it was written from another checkout (2026-10-17).
 */
const GIT_PUSH = gitCommand(
  // A quoted value (`-C "../my wt"`) is one shell word with spaces in it; matching it as \S+ left
  // such a push unrecognised and therefore unmetered (found in review, 2026-10-17).
  String.raw`(?:(?:-[Cc]\s+(?:"[^"]*"|'[^']*'|\S+)|--[\w-]+(?:=\S+)?)\s+)*push\b`,
);

/**
 * Flags are tested against the command with QUOTED SPANS REMOVED.
 *
 * Whitespace boundaries are not enough, and the mutation harness is what proved it: in
 * `gh pr create --title "add a --draft flag to signal"` the substring ` --draft ` has a space on
 * both sides, so a `(?:^|\s)--draft(?=\s|$)` test matches text inside the TITLE and silently
 * exempts a non-draft PR from the gate. Stripping quoted spans first is what makes "is this a
 * flag" mean flag rather than "does this text appear anywhere".
 */
export function withoutQuotedSpans(command: string): string {
  return command.replace(/'[^']*'/g, " '' ").replace(/"(?:\\.|[^"\\])*"/g, ' "" ');
}

const DRAFT_FLAG = /(?:^|\s)--draft(?:=true)?(?=\s|$)/;

/** `gh pr ready --undo` CONVERTS TO draft, i.e. it removes work from the queue. Never gate it. */
const READY_UNDO = /(?:^|\s)--undo(?=\s|$)/;

export const hasFlag = (command: string, flag: RegExp) => flag.test(withoutQuotedSpans(command));

/**
 * `pr-undraft` is NOT gated. It is here because collapsing it to `null` -- which is what the first
 * version did -- makes it indistinguishable from `ls -la`, and the gate then has no moment at which
 * to notice that the branch left the review queue.
 *
 * The consequence of that collapse was measured: the reviewable bit survived `gh pr ready --undo`
 * forever, so every push to a re-drafted PR stayed fully gated while this file's own comment
 * asserted that `--undo` "removes work from the queue". The comment described an intent the code
 * did not implement. Naming the transition is what lets the gate act on it.
 */
export type CommandKind = "pr-ready" | "pr-create" | "push" | "inline-body" | "pr-undraft";

/** @deprecated Retained so existing imports keep compiling; prefer {@link CommandKind}. */
export type GatedKind = CommandKind;

export interface Classification {
  readonly kind: CommandKind | null;
  /** Why this command was picked up, quoted back to the operator so a misfire is diagnosable. */
  readonly matched: string;
}

/**
 * Bodies published with `--body` inline rather than `--body-file`.
 *
 * The threshold is deliberate: a one-line `--body "Rebased; CI green."` must pass. Only a
 * multi-line or long body is gated, because that is the shape that (a) is worth reviewing before
 * it is published and (b) trips the existing same-repo-branch guard's shell tokenisation when it
 * contains parentheses or backticks.
 */
const INLINE_BODY_MAX = 300;
const BODY_FLAG = /--body(?:=|\s+)(['"])([\s\S]*?)\1/;

const PUBLISHES_A_BODY = ghCommand(
  String.raw`(?:pr\s+(?:create|comment|review)|issue\s+(?:create|comment))\b`,
);

/**
 * Classify by WHAT THE SHELL WOULD RUN, not by what the text mentions (cc-skills#21).
 *
 * The command-position regexes below ({@link classifyByCommandText}) run on raw text, so a quoted
 * string that merely MENTIONS a gated command counted as running it. Measured 2026-10-19, each
 * denied with "No valid self-review record for HEAD": a `grep -n "…|gh pr create…"` pattern, a
 * `jq --arg c "cd $d && gh pr create …"` test input, and a quoted string passed to a probe.
 *
 * So the decision is made on the invocations the shared static walker reports
 * (shell-command-invocation-walker.ts, the lexer the kill guards use). It never visits quoted
 * arguments, comments, or heredocs fed to `cat`; it does look through assignments, `sudo`/`env`/
 * `nice`/`timeout`, `$(…)`, `bash -c '…'`, `ssh host '…'` and heredocs fed to a shell. Flags are
 * read as WORDS of the gated invocation, so `--draft` or `--undo` inside a title or body is a
 * value, never a flag; the `--body` length check reads that word's value.
 *
 * FAIL CLOSED. Whenever the walk is not known to be complete -- an unclosed quote, `$(` or
 * heredoc, the recursion limit, or a shell started behind a reserved word (`then bash <<EOF`,
 * whose heredoc the walker does not attribute to a shell) -- the old text classifier decides,
 * exactly as before this change. The walker can only make the gate quieter on input it fully lexed.
 */
export function classify(rawCommand: string): Classification {
  let incomplete = false;
  const invocations: ResolvedInvocation[] = [];
  walkShellInvocations(
    rawCommand,
    WALK_PREFILTER,
    (invocation) => {
      const resolved = resolveInvocation(invocation);
      if (resolved === "opaque") incomplete = true;
      else if (resolved !== null) invocations.push(resolved);
    },
    () => {
      incomplete = true;
    },
  );
  if (incomplete) return classifyByCommandText(rawCommand);

  const gh = (noun: string, verbs: readonly string[]) =>
    invocations.filter(
      (inv) => inv.program === "gh" && inv.args[0]?.value === noun && verbs.includes(inv.args[1]?.value ?? ""),
    );

  // Same precedence as the text classifier: undraft, then inline body, ready, create, push.
  const ready = gh("pr", ["ready"]);
  const undo = ready.find((inv) => ghFlagWords(inv, READY_VALUE_FLAGS).some((w) => w.value === "--undo"));
  if (undo) return { kind: "pr-undraft", matched: `${display(undo, 2)} --undo` };

  for (const inv of [...gh("pr", ["create", "comment", "review"]), ...gh("issue", ["create", "comment"])]) {
    const body = inlineBodyText(inv);
    if (body !== null && (body.includes("\n") || body.length > INLINE_BODY_MAX)) {
      return { kind: "inline-body", matched: `--body with ${body.length} chars` };
    }
  }

  if (ready.length > 0) return { kind: "pr-ready", matched: display(ready[0]!, 2) };

  const create = gh("pr", ["create"]).find(
    (inv) => !ghFlagWords(inv, PR_CREATE_FLAGS_TAKING_A_VALUE).some((w) => /^--draft(?:=true)?$/.test(w.value)),
  );
  if (create) return { kind: "pr-create", matched: display(create, 2) };

  for (const inv of invocations) {
    if (inv.program !== "git") continue;
    const verb = gitSubcommandIndex(inv.args);
    if (verb !== -1 && inv.args[verb]!.value === "push") return { kind: "push", matched: display(inv, verb + 1) };
  }

  return { kind: null, matched: "" };
}

/** Tested on each (sub)script before lexing; `gh` matches case-insensitively, as the regex did. */
const WALK_PREFILTER = /\b(?:gh|git)\b/i;

/**
 * Shell reserved words that may precede a command (`if git push; then gh pr ready; fi`,
 * `{ gh pr create; }`, `! git push`). The walker treats them as program names; the gate looks past
 * them, because the command after one runs. Compared on the RAW word: a quoted `"if"` is no keyword.
 */
const RESERVED_WORDS: ReadonlySet<string> = new Set(["!", "{", "if", "then", "else", "elif", "do", "while", "until"]);

/** Programs whose arguments or heredocs the walker recurses into only when they are the program. */
const NESTING_PROGRAMS: ReadonlySet<string> = new Set(["bash", "sh", "zsh", "dash", "ksh", "ssh", "pueue"]);

interface ResolvedInvocation {
  /** Lower-cased basename, so `/opt/homebrew/bin/gh` and `GH` are `gh`, as the regex had it. */
  readonly program: string;
  readonly words: Word[];
  readonly args: Word[];
  readonly context: ShellInvocation["context"];
}

function resolveInvocation(invocation: ShellInvocation): ResolvedInvocation | "opaque" | null {
  let words: Word[] = [invocation.programWord, ...invocation.args];
  let behindReservedWord = false;
  while (words.length > 0 && RESERVED_WORDS.has(words[0]!.raw)) {
    behindReservedWord = true;
    const rest = words.slice(1);
    const k = skipAssignmentsAndWrappers(rest);
    if (k === -1) return null;
    words = rest.slice(k);
  }
  if (words.length === 0) return null;
  const program = invocationBasename(words[0]!.value).toLowerCase();
  // The walker only nests into a shell or ssh that IS the program word; behind a reserved word its
  // `-c` script and heredoc would go unseen, so let the text classifier decide.
  if (behindReservedWord && NESTING_PROGRAMS.has(program)) return "opaque";
  return { program, words, args: words.slice(1), context: invocation.context };
}

/** `gh pr ready` flags that consume the next word. */
const READY_VALUE_FLAGS: ReadonlySet<string> = new Set(["-R", "--repo"]);

/**
 * The FLAG words of a `gh <noun> <verb>` invocation: the value of a value-taking flag is skipped
 * (`--title --draft` titles a PR "--draft"; it does not make it a draft), and `--` ends the flags.
 */
function ghFlagWords(inv: ResolvedInvocation, valueFlags: ReadonlySet<string>): Word[] {
  const flags: Word[] = [];
  for (let i = 2; i < inv.args.length; i += 1) {
    const w = inv.args[i]!;
    if (w.value === "--") break;
    if (!w.value.startsWith("-")) continue;
    flags.push(w);
    if (valueFlags.has(w.value)) i += 1;
  }
  return flags;
}

/**
 * The text of an inline `--body` / `--body=` value, or null. The decoded value is measured; the
 * word's SOURCE is used instead when it is longer or holds a newline the value lost, because
 * `--body "$(cat <<'EOF' …)"` decodes to a `$(…)` placeholder while the body is composed right there.
 */
function inlineBodyText(inv: ResolvedInvocation): string | null {
  for (let i = 2; i < inv.args.length; i += 1) {
    const w = inv.args[i]!;
    let value: string;
    let raw: string;
    if (w.value === "--body") {
      const next = inv.args[i + 1];
      if (next === undefined) return null;
      ({ value, raw } = next);
    } else if (w.value.startsWith("--body=")) {
      value = w.value.slice("--body=".length);
      raw = w.raw.slice(w.raw.indexOf("=") + 1);
    } else continue;
    const source = /^(['"]).*\1$/s.test(raw) ? raw.slice(1, -1) : raw;
    return source.length > value.length || (source.includes("\n") && !value.includes("\n")) ? source : value;
  }
  return null;
}

/** git global options that consume the next word (`git -C dir push`, `git -c k=v push`). */
const GIT_OPTIONS_TAKING_A_VALUE: ReadonlySet<string> = new Set([
  "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env",
]);

/** Index of git's subcommand after its global options (`--no-pager` takes none), or -1. */
function gitSubcommandIndex(args: readonly Word[]): number {
  let a = 0;
  while (a < args.length && args[a]!.value.startsWith("-")) {
    a += GIT_OPTIONS_TAKING_A_VALUE.has(args[a]!.value) ? 2 : 1;
  }
  return a < args.length ? a : -1;
}

/** The program word plus the next `argCount` words as written, and where the walker found them. */
function display(inv: ResolvedInvocation, argCount: number): string {
  const text = inv.words.slice(0, argCount + 1).map((w) => w.raw).join(" ");
  return inv.context === "command" ? text : `${text} (in ${inv.context})`;
}

/**
 * The pre-#21 classifier: command-position regexes over the command text. Kept as the FAIL-CLOSED
 * path for input the walker could not lex completely; on such input it decides exactly as before.
 */
function classifyByCommandText(rawCommand: string): Classification {
  // Heredoc bodies written to a file (`cat > body.md <<'EOF'`) are text, not commands: a PR body
  // that mentions `gh pr create` must not be classified as one (2026-10-19). Bodies fed to a shell stay.
  const command = withoutNonShellHeredocBodies(rawCommand);
  if (hasFlag(command, READY_UNDO) && GH_PR_READY.test(command)) {
    return { kind: "pr-undraft", matched: "gh pr ready --undo" };
  }

  // INLINE BODY IS CHECKED FIRST, and the order is load-bearing rather than incidental. It is a
  // precondition on HOW the command is written, independent of whether a self-review record
  // exists -- so evaluating `pr-create` first meant a command with a valid artifact published a
  // 301-character inline body unchallenged. Caught by the case table, not by reading.
  //
  // It also applies to `--draft`, because the objection is that the body is composed in the same
  // command that publishes it, and that is true whether or not a reviewer sees it yet.
  if (PUBLISHES_A_BODY.test(command)) {
    const body = command.match(BODY_FLAG);
    if (body) {
      const value = body[2];
      if (value.includes("\n") || value.length > INLINE_BODY_MAX) {
        return { kind: "inline-body", matched: `--body with ${value.length} chars` };
      }
    }
  }

  const readyMatch = command.match(GH_PR_READY);
  if (readyMatch) return { kind: "pr-ready", matched: readyMatch[0].trim() };

  const createMatch = command.match(GH_PR_CREATE);
  if (createMatch && !hasFlag(command, DRAFT_FLAG)) {
    return { kind: "pr-create", matched: createMatch[0].trim() };
  }

  const pushMatch = command.match(GIT_PUSH);
  if (pushMatch) return { kind: "push", matched: pushMatch[0].trim() };

  return { kind: null, matched: "" };
}

/**
 * `gh pr ready [<number> | <url> | <branch>]` -- the positional argument, or null when omitted.
 *
 * WHY THIS EXISTS: the gate used to treat `gh pr ready --undo 666` as if it concerned the branch
 * of the directory it was run from. It does not. Measured on 2026-09-08: five PRs were re-drafted
 * in a row from a single worktree, and only that worktree's branch lost its reviewable mark. Four
 * marks were left stale (a false demand for a fresh self-review record) and -- the direction that
 * actually matters -- the branch that DID get unmarked was not the one leaving the queue, so its
 * subsequent pushes went unmetered. An argument the code accepted and ignored.
 *
 * Deliberately NOT built on {@link withoutQuotedSpans}, and deliberately not on a private
 * tokeniser either. `withoutQuotedSpans` answers "is this a flag" by replacing quoted spans with
 * empty ones -- correct for a predicate, fatal for extraction, since `gh pr ready "my branch"`
 * would yield the empty string. And splitting on whitespace, which is what the first version of
 * this did, cuts `"my branch"` in half; the tests caught it. {@link splitShellWords} in the
 * neighbouring module already joins adjacent quoted and bare segments the way the shell does, so
 * it is the one home for this. Re-deriving it here would be the same mistake as every other
 * duplicated grammar in this plugin.
 *
 * A token that is a shell substitution (`$PR`, `$(...)`) is returned verbatim and will fail to
 * resolve downstream -- the safe direction, because the caller unmarks nothing on failure.
 */
/** `gh` flags that consume the NEXT word, which therefore is not the positional argument. */
const READY_FLAGS_TAKING_A_VALUE: ReadonlySet<string> = new Set(["-R", "--repo"]);

export function undraftTarget(command: string): string | null {
  const words = splitShellWords(command);

  for (let i = 0; i < words.length; i += 1) {
    const head = words[i]!;
    if (head.isOperator || !head.firstSegmentBare) continue;
    // Basename match, for the same reason `ghCommand` does it: `/opt/homebrew/bin/gh` is not a
    // different tool.
    if ((head.value.split("/").pop() ?? "").toLowerCase() !== "gh") continue;
    if (words[i + 1]?.value !== "pr" || words[i + 2]?.value !== "ready") continue;

    for (let j = i + 3; j < words.length; j += 1) {
      const arg = words[j]!;
      // The command ended before any positional argument: `gh` will fall back to the current
      // branch, and so must the caller.
      if (arg.isOperator) return null;
      // A redirection is not an argument, and guessing past one risks returning `2>/tmp/x` as a
      // PR. Stopping yields null, which unmarks nothing.
      if (/[<>]/.test(arg.value)) return null;
      // Quoting is stripped before `gh` parses argv, so `'--undo'` is still the flag --undo --
      // this test is about what gh sees, not about shell word structure.
      if (arg.value.startsWith("-")) {
        // `--repo=owner/name` carries its value inline and consumes no following word.
        if (arg.value.startsWith("--") && arg.value.includes("=")) continue;
        if (READY_FLAGS_TAKING_A_VALUE.has(arg.value)) j += 1;
        continue;
      }
      return arg.value;
    }
    return null;
  }
  return null;
}

/**
 * The branch a `gh pr create` names with `--head` / `-H` / `--head=`, or null when it names none.
 *
 * WHY THE GATE NEEDS IT. The gate read the repository and HEAD from the session's cwd. A PR opened
 * from a worktree names its branch with `--head` while the session stands in the main checkout on
 * `main`, so the gate measured `main` (zero changed files, no record) and denied a branch whose
 * self-review WAS recorded in its worktree (2026-09-28, example-org/relay-monitor#133: the
 * record existed at the pushed commit and only the override got the PR open). Inside the worktree,
 * the harness's worktree isolation can refuse git outright, so "cd there first" is not a remedy.
 *
 * A fork-style `owner:branch` is returned as its branch part: only a local worktree can answer for
 * it, and the worktree knows the branch name, not the owner.
 */
const PR_CREATE_FLAGS_TAKING_A_VALUE: ReadonlySet<string> = new Set([
  "-R", "--repo", "-B", "--base", "-t", "--title", "-b", "--body", "-F", "--body-file",
  "-a", "--assignee", "-l", "--label", "-m", "--milestone", "-p", "--project", "-r", "--reviewer",
  "-T", "--template",
]);

export function prCreateHeadBranch(command: string): string | null {
  const words = splitShellWords(command);

  // `gh` must be in COMMAND position (start, after an operator, or after `VAR=value` prefixes):
  // in `echo gh pr create --head x` it is an argument, and nothing is submitted.
  let atCommandPosition: boolean = true;
  for (let i = 0; i < words.length; i += 1) {
    const head = words[i]!;
    if (head.isOperator) {
      atCommandPosition = true;
      continue;
    }
    const wasAtCommandPosition: boolean = atCommandPosition;
    atCommandPosition = wasAtCommandPosition && /^[A-Za-z_][A-Za-z0-9_]*=/.test(head.value);
    if (!wasAtCommandPosition || !head.firstSegmentBare) continue;
    if ((head.value.split("/").pop() ?? "").toLowerCase() !== "gh") continue;
    if (words[i + 1]?.value !== "pr" || words[i + 2]?.value !== "create") continue;

    for (let j = i + 3; j < words.length; j += 1) {
      const arg = words[j]!;
      if (arg.isOperator) return null;
      let value: string | undefined;
      if (arg.value === "--head" || arg.value === "-H") {
        // The value is the NEXT word; an operator there means the flag had no value.
        const next = words[j + 1];
        value = next === undefined || next.isOperator ? undefined : next.value;
      } else if (arg.value.startsWith("--head=")) value = arg.value.slice("--head=".length);
      else if (PR_CREATE_FLAGS_TAKING_A_VALUE.has(arg.value)) {
        j += 1;
        continue;
      } else continue;
      if (value === undefined || value === "") return null;
      const branch = value.includes(":") ? value.slice(value.indexOf(":") + 1) : value;
      return branch === "" ? null : branch;
    }
    return null;
  }
  return null;
}

/**
 * The base branch a `gh pr create` names with `--base` / `-B` / `--base=`, or null.
 *
 * The record CLI and the gate must measure the SAME diff, and a stacked PR's diff is against its
 * base, not against the default branch. Same word walk as {@link prCreateHeadBranch}.
 */
export function prCreateBaseBranch(command: string): string | null {
  return ghFlagValue(command, ["pr", "create"], ["--base", "-B"]);
}

/** The `--repo` / `-R` a `gh pr …` command names, or null. Passed through to `gh pr view`. */
export function ghRepoFlag(command: string): string | null {
  return (
    ghFlagValue(command, ["pr", "ready"], ["--repo", "-R"]) ??
    ghFlagValue(command, ["pr", "create"], ["--repo", "-R"])
  );
}

function ghFlagValue(command: string, verb: readonly string[], aliases: readonly string[]): string | null {
  const words = splitShellWords(command);
  for (let i = 0; i < words.length; i += 1) {
    const head = words[i]!;
    if (head.isOperator || !head.firstSegmentBare) continue;
    if ((head.value.split("/").pop() ?? "").toLowerCase() !== "gh") continue;
    if (verb.some((v, k) => words[i + 1 + k]?.value !== v)) continue;
    for (let j = i + 1 + verb.length; j < words.length; j += 1) {
      const arg = words[j]!;
      if (arg.isOperator) return null;
      for (const alias of aliases) {
        if (arg.value === alias) {
          const next = words[j + 1];
          return next === undefined || next.isOperator || next.value === "" ? null : next.value;
        }
        if (alias.startsWith("--") && arg.value.startsWith(`${alias}=`)) {
          return arg.value.slice(alias.length + 1) || null;
        }
      }
    }
    return null;
  }
  return null;
}

/**
 * `gh pr ready [<number> | <url> | <branch>]`: the positional argument, with or without `--undo`.
 * {@link undraftTarget} already skips every flag, `--undo` included, so this is the same walk; the
 * second name exists so the ready path does not read as if it were about undrafting.
 */
export const prReadyTarget = undraftTarget;

const DIRECTORY_CHANGERS: ReadonlySet<string> = new Set(["cd", "pushd"]);

/**
 * Expand the forms of a directory argument that are knowable from the command text alone (`~`,
 * `$HOME`, `${HOME}`, `$PWD`) and resolve it against `base`. Null for anything else that the shell
 * would expand (`$DIR`, `$(…)`, backticks, `-`): guessing a directory is how a gate measures the
 * wrong repository, so an unknown directory means "not located" and the caller keeps its cwd.
 */
export function resolveDirectoryArgument(value: string, base: string, home: string = homedir()): string | null {
  let v = value;
  if (v === "~" || v.startsWith("~/")) v = home + v.slice(1);
  v = v.replace(/^\$(?:\{HOME\}|HOME)(?=\/|$)/, home).replace(/^\$(?:\{PWD\}|PWD)(?=\/|$)/, base);
  if (v === "" || v === "-" || /[$`]/.test(v)) return null;
  return resolvePath(base, v);
}

/**
 * The directory the gated command (`gh pr ready|create`, `git push`) actually runs in, or null when
 * the command text does not move it away from the session's cwd.
 *
 * WHY. The gate used to read the repository, HEAD and branch from the SESSION's cwd. An agent
 * standing in the main checkout writes `cd ../repo-feature && gh pr ready 12`, or
 * `git -C ../repo-feature push`; the gate then measured `main` in the main checkout, found no
 * record for it, and denied, although the record existed at the exact head of the worktree the
 * command ran in (2026-10-17: every `gh pr create`/`ready` from a worktree needed the override).
 *
 * Follows `cd DIR` / `pushd DIR` in order up to the gated command, and `git -C DIR`. Assignments
 * and wrappers (`env`, `nice`, `timeout`, …) are skipped the way every other guard sharing the
 * invocation walker skips them. A directory that cannot be resolved from the text alone stops the
 * walk with null, so an unknown directory never widens what the gate allows: the caller keeps the
 * session cwd, which is the old behaviour.
 */
/**
 * True when every `cd`/`pushd` in the command changes the directory of what FOLLOWS it for sure:
 * no subshell or brace group anywhere (`(cd x && true); git push` runs the push in the original
 * directory), no `popd`, and every directory change chained with `&&` (after `cd x;` or a newline
 * a failed cd would leave the gated command in the session's cwd). Found in review, 2026-10-17:
 * without this, a record in another worktree could approve a push made from the session's checkout.
 */
function directoryChangesAreUnconditional(rawCommand: string): boolean {
  // A `(` or `{` in a heredoc body written to a file is prose, not a group (2026-10-19: a PR body
  // containing "(now 25 guards)" sent the gate back to the session cwd and denied a valid record).
  // Word offsets below index THIS string, so it must be the one sliced, never rawCommand.
  const command = withoutNonShellHeredocBodies(rawCommand);
  const words = splitShellWords(command);
  let atCommandPosition = true;
  let lastProgram: string | null = null;
  for (const w of words) {
    const raw = command.slice(w.start, w.end);
    if (w.isOperator || w.precededByNewline) {
      if ((lastProgram === "cd" || lastProgram === "pushd") && !(w.isOperator && w.value === "&&")) return false;
      if (w.isOperator) {
        atCommandPosition = true;
        lastProgram = null;
        continue;
      }
      atCommandPosition = true;
      lastProgram = null;
    }
    // A bare `(`, `{`, `)` or `}` at a word boundary opens or closes a group; `$(…)` inside a word
    // is a substitution, not a group.
    if (w.firstSegmentBare && (/^[({]/.test(raw) || (/[)}]$/.test(raw) && !/\$\(|\$\{/.test(raw)))) return false;
    if (!atCommandPosition) continue;
    if (w.firstSegmentBare && /^[A-Za-z_][A-Za-z0-9_]*=/.test(w.value)) continue;
    atCommandPosition = false;
    lastProgram = invocationBasename(w.value);
    if (lastProgram === "popd") return false;
  }
  return true;
}

export function gatedCommandDirectory(command: string, sessionCwd: string, home: string = homedir()): string | null {
  // Grouping, popd, or a cd not chained by `&&`: the text cannot say for certain which directory
  // the gated command runs in, so it is not located and the session cwd stands (the old behaviour).
  if (!directoryChangesAreUnconditional(command)) return null;
  const { commands } = lexShellCommands(command);
  let dir = sessionCwd;
  let moved = false;
  for (const words of commands) {
    const k = skipAssignmentsAndWrappers(words);
    if (k === -1) continue;
    const program = invocationBasename(words[k]!.value);
    const args = words.slice(k + 1).map((w) => w.value);

    if (DIRECTORY_CHANGERS.has(program)) {
      const target = args.find((a) => !a.startsWith("-") || a === "-");
      const next = target === undefined ? home : resolveDirectoryArgument(target, dir, home);
      if (next === null) return null;
      dir = next;
      moved = true;
      continue;
    }

    if (program === "git") {
      let a = 0;
      let gitDir: string | null = null;
      while (a < args.length && args[a]!.startsWith("-")) {
        if (args[a] === "-C" && a + 1 < args.length) {
          const resolved = resolveDirectoryArgument(args[a + 1]!, gitDir ?? dir, home);
          if (resolved === null) return null;
          gitDir = resolved;
          a += 2;
          continue;
        }
        // `-c key=value` and `--git-dir=…`/`--work-tree=…` take values; skip them conservatively.
        a += args[a] === "-c" ? 2 : 1;
      }
      if (args[a] === "push") return gitDir ?? (moved ? dir : null);
      continue;
    }

    if (program === "gh" && args[0] === "pr" && (args[1] === "ready" || args[1] === "create")) {
      return moved ? dir : null;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------------------------
// The escape hatch
// ---------------------------------------------------------------------------------------------

/**
 * Anchored at the START of the command only.
 *
 * git-worktree-guard.ts anchors its own override loosely and that is a measured bypass: the token
 * appearing anywhere -- including inside a `--body` or a heredoc -- disarms it. Requiring it in the
 * environment-assignment position means the operator must actually prefix the command.
 *
 * Resolves to `ask`, never `allow`: a bypass should cost a human decision and be recorded, which is
 * what makes going around this gate charged and visible rather than free and silent.
 */
const OVERRIDE = /^\s*REVIEW_ROUND_OK=(?:"([^"]{12,})"|'([^']{12,})')\s+\S/;

export function overrideReason(command: string): string | null {
  const m = command.match(OVERRIDE);
  if (!m) return null;
  return (m[1] ?? m[2] ?? "").trim() || null;
}

// ---------------------------------------------------------------------------------------------
// The artifact
// ---------------------------------------------------------------------------------------------

export interface ReviewRoundArtifact {
  schema: number;
  head_sha: string;
  base_sha: string;
  diff_sha256: string;
  recorded_at: string;
  files: { path: string; verdict: string }[];
}

export interface RepoFacts {
  readonly headSha: string;
  readonly baseSha: string;
  /** Display name of the ref the base was resolved from (`github/main`); optional for fixtures. */
  readonly baseRef?: string;
  readonly diffText: string;
  readonly changedPaths: readonly string[];
}

export const MIN_VERDICT_CHARS = 24;

export function sha256(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

export interface ValidationResult {
  readonly ok: boolean;
  readonly failures: readonly string[];
}

/**
 * Structural validation only.
 *
 * The teachback measurement on this repository is unambiguous about which kind of check survives:
 * pattern-matching checks failed 6 of 7 adversarial cases, structural ones failed 0 of 28. So every
 * rule below compares a recorded value against a value derived independently from git, and none of
 * them inspects the PROSE of a verdict beyond its length and distinctness.
 *
 * S5 is the one that costs something to fake. Writing one honest sentence per file is cheap; writing
 * the SAME sentence for six files is the cheapest possible ritual, and it is decidable by string
 * comparison.
 */
export function validateArtifact(
  artifact: ReviewRoundArtifact | null,
  facts: RepoFacts,
): ValidationResult {
  const failures: string[] = [];

  // S0 -- absence is refusal. "No artifact" must never read as "nothing to check"; that is the
  // exact shape of Decision #484 and it is the single most important line in this file.
  if (artifact === null) {
    return { ok: false, failures: ["no self-review record exists for this commit"] };
  }

  if (artifact.schema !== 1) {
    failures.push(`unknown artifact schema ${artifact.schema}; expected 1`);
  }

  // S1 -- exact, never a prefix. A 7-character abbreviation would let an artifact recorded at an
  // ancestor commit satisfy a later one.
  if (artifact.head_sha !== facts.headSha) {
    failures.push(
      `recorded at ${short(artifact.head_sha)} but HEAD is ${short(facts.headSha)} — the pass predates the code`,
    );
  }

  // S2 -- catches an artifact written BEFORE the last edit, which S1 alone cannot see when the
  // edit is uncommitted and HEAD has not moved.
  const actualDiffHash = sha256(facts.diffText);
  if (artifact.diff_sha256 !== actualDiffHash) {
    failures.push("the diff has changed since the pass was recorded");
  }

  // S3 -- EXACT SET EQUALITY, not superset and not subset. A superset check lets a file be added
  // after the pass; a subset check lets the record name files it never examined.
  const recorded = new Set(artifact.files.map((f) => f.path));
  const changed = new Set(facts.changedPaths);
  const unexamined = [...changed].filter((p) => !recorded.has(p));
  const phantom = [...recorded].filter((p) => !changed.has(p));
  if (unexamined.length > 0) {
    failures.push(`${unexamined.length} changed file(s) have no recorded verdict: ${unexamined.slice(0, 3).join(", ")}`);
  }
  if (phantom.length > 0) {
    failures.push(`${phantom.length} recorded file(s) are not in the diff: ${phantom.slice(0, 3).join(", ")}`);
  }

  // S4 -- a verdict has to say something.
  const tooShort = artifact.files.filter((f) => f.verdict.trim().length < MIN_VERDICT_CHARS);
  if (tooShort.length > 0) {
    failures.push(`${tooShort.length} verdict(s) under ${MIN_VERDICT_CHARS} characters`);
  }

  // S5 -- all-identical verdicts are ritual, not review.
  if (artifact.files.length > 1) {
    const distinct = new Set(artifact.files.map((f) => f.verdict.trim()));
    if (distinct.size !== artifact.files.length) {
      failures.push("verdicts are not distinct — the same text is reused across files");
    }
  }

  return { ok: failures.length === 0, failures };
}

function short(sha: string): string {
  return sha.slice(0, 8) || "(empty)";
}
