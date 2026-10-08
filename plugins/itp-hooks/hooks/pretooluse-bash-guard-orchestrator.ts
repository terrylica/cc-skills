#!/usr/bin/env bun
/**
 * PreToolUse:Bash guard orchestrator (#111).
 *
 * Every Bash call used to start one bun process per itp-hooks guard: 26 cold starts, all
 * unconditional. This runs the guards in ONE process. Each guard keeps its file, its standalone
 * entry point and its tests; the orchestrator imports its exported `main()` and runs it through
 * `runGuardMainInProcess()` (pretooluse-helpers.ts), which hands it the parsed input and captures
 * what it emits instead of printing it.
 *
 * Why not the hooks `if` field: measured 2026-10-01, `"if": "Bash(gh *)"` skipped the hook for
 * 9 of 15 realistic forms (bash -c, sh -c, an absolute path, env, command, time, eval, a heredoc
 * into bash, ssh). Every guard here matches its regex against the whole command string, so an
 * `if` filter would have silently narrowed them. Evidence: terrylica/cc-skills#111.
 *
 * Not included: the two guards that rewrite the command through `updatedInput`
 * (subprocess-stdin-inlet-guard, pueue-wrap-guard). Claude Code keeps only the last hook's
 * `updatedInput` (anthropics/claude-code#15897), so they stay separate entries, with
 * pueue-wrap-guard last, as the ordering audit requires.
 *
 * Aggregation follows Claude Code's own precedence for parallel hooks, deny > ask > allow:
 * - the first deny wins and stops the run;
 * - an ask is held while the remaining guards are checked for a deny;
 * - additionalContext from every guard that allowed is joined into the final response.
 * Each guard is crash-isolated and time-boxed. A guard that throws or overruns is skipped
 * (fail-open), exactly as a crashed or timed-out standalone hook was.
 */

import {
  dropOutputOutsideGuardRuns,
  parseStdinOrAllow,
  runGuardMainInProcess,
  trackHookError,
  type PreToolUseInput,
} from "./pretooluse-helpers.ts";
import { main as reviewRoundGate } from "./pretooluse-review-round-gate.ts";
import { main as reviewQuotaLimiter } from "./pretooluse-review-quota-limiter.ts";
import { main as processStormGuard } from "./pretooluse-process-storm-guard.mjs";
import { main as cwdDeletionGuard } from "./pretooluse-cwd-deletion-guard.ts";
import { main as uvEnforcementGuard } from "./pretooluse-uv-enforcement-guard.ts";
import { main as pthContaminationGuard } from "./pretooluse-pth-contamination-guard.ts";
import { main as pueueLocalGuard } from "./pretooluse-pueue-local-guard.ts";
import { main as cargoTtyGuard } from "./pretooluse-cargo-tty-guard.ts";
import { main as umbrellaNoRepoGuard } from "./pretooluse-umbrella-no-repo-guard.ts";
import { main as parquetDuckdbNudge } from "./pretooluse-parquet-duckdb-nudge.ts";
import { main as gitWorktreeGuard } from "./pretooluse-git-worktree-guard.ts";
import { main as gmailBodyGuard } from "./pretooluse-gmail-body-guard.ts";
import { main as githubHardWrapGuard } from "./pretooluse-github-hard-wrap-guard.ts";
import { main as markdownCommitHardWrapGuard } from "./pretooluse-markdown-commit-hard-wrap-guard.ts";
import { main as prReviewInvitationGuard } from "./pretooluse-pr-review-invitation-guard.ts";
import { main as prCitationEvidenceGuard } from "./pretooluse-pr-citation-evidence-guard.ts";
import { main as releaseNotesExtensivenessGuard } from "./pretooluse-release-notes-extensiveness-guard.ts";
import { main as typescriptLegacyInstallCommandGuard } from "./pretooluse-typescript-legacy-install-command-guard.ts";
import { main as headlessClaudePGuard } from "./pretooluse-headless-claude-p-guard.ts";
import { main as chromeDebugPortGuard } from "./pretooluse-chrome-debug-port-guard.ts";
import { main as broadProcessSignalGuard } from "./pretooluse-broad-process-signal-guard.ts";
import { main as tccGrantOrderingGuard } from "./pretooluse-tcc-grant-ordering-guard.ts";
import { main as piiPushGate } from "./pretooluse-pii-push-gate.ts";
import { main as pkillOptionAfterPatternGuard } from "./pretooluse-pkill-option-after-pattern-guard.ts";

const LOG_PREFIX = "[pretooluse-bash-guard-orchestrator]";

export interface BashGuardEntry {
  /** The guard's file name without extension; used in diagnostics. */
  name: string;
  /** The guard's exported standalone `main()`. */
  main: () => Promise<void>;
  /** Time budget. Each is the guard's former hooks.json timeout, less one second of slack. */
  timeoutMs: number;  /** What the guard enforces. Moved here from its former hooks.json entry. */
  description: string;
}

/** Order is the guards' former hooks.json order. Precedence does not depend on it. */
export const BASH_GUARD_REGISTRY: readonly BashGuardEntry[] = [
  { name: "pretooluse-review-round-gate", main: reviewRoundGate, timeoutMs: 4000, description: "Review-round gate - requires a local self-review record bound to the exact HEAD before gh pr ready / non-draft gh pr create, and before a push to a branch already in front of a reviewer. Also refuses a multi-line or >300 char inline --body in favour of --body-file. Measured motivation: 73% of this reviewer's attention is re-review, and PRs >900 lines cost 7.43 rounds against 1.36 for PRs <=400. No network: git and local files only, because a timed-out PreToolUse hook does not block. Override with REVIEW_ROUND_OK=\"<12+ chars>\", which asks rather than allowing and is logged." },
  { name: "pretooluse-review-quota-limiter", main: reviewQuotaLimiter, timeoutMs: 14000, description: "Caps reviews from a shared human reviewer at 2 per rolling hour, counted by distinct head sha on an open PR. Drafts are NOT exempt (measured)." },
  { name: "pretooluse-process-storm-guard", main: processStormGuard, timeoutMs: 4000, description: "" },
  { name: "pretooluse-cwd-deletion-guard", main: cwdDeletionGuard, timeoutMs: 4000, description: "" },
  { name: "pretooluse-uv-enforcement-guard", main: uvEnforcementGuard, timeoutMs: 4000, description: "" },
  { name: "pretooluse-pth-contamination-guard", main: pthContaminationGuard, timeoutMs: 4000, description: "" },
  { name: "pretooluse-pueue-local-guard", main: pueueLocalGuard, timeoutMs: 4000, description: "" },
  { name: "pretooluse-cargo-tty-guard", main: cargoTtyGuard, timeoutMs: 4000, description: "" },
  { name: "pretooluse-umbrella-no-repo-guard", main: umbrellaNoRepoGuard, timeoutMs: 4000, description: "" },
  { name: "pretooluse-parquet-duckdb-nudge", main: parquetDuckdbNudge, timeoutMs: 4000, description: "Nudge toward DuckDB for Parquet content analysis (soft, warn+allow)" },
  { name: "pretooluse-git-worktree-guard", main: gitWorktreeGuard, timeoutMs: 4000, description: "Enforces worktree-per-branch: denies bare branch creation (git checkout -b / switch -c / branch <new>, git-town hack|append|prepend, gh pr checkout) and steers to `git worktree add -b` or the EnterWorktree tool. Always allows `git worktree add`, switching to existing branches, branch list/delete/rename, and doc/echo/comment/commit-message mentions. Escape hatch: prefix with ALLOW_BARE_BRANCH=1. Fail-open. Spoke: docs/git-worktree-guard.md. ADR 2026-06-22." },
  { name: "pretooluse-gmail-body-guard", main: gmailBodyGuard, timeoutMs: 4000, description: "Denies a `gmail draft` / `draft-update` whose body would render badly in the recipient's inbox, before the bad draft is created. Two failure modes: (1) HARD-WRAP — the gmail CLI turns every authored newline into an HTML <br> (gmail-drafts.ts toHtmlBody), so a paragraph wrapped at ~72/80/100 cols renders as a column of short mid-sentence lines instead of reflowing; (2) RAW MARKDOWN — the CLI HTML-escapes the body and does not render markdown, so **bold**/`code`/[text](url)/# headings/|tables| show literally. Inspects inline --body and --body-file content. Escape hatch: GMAIL-BODY-OK anywhere in the command. Fail-open (missing/unreadable body-file skipped). Doctrine: gmail-commander/skills/gmail-access/SKILL.md 2026-07-22. Spoke: docs/gmail-body-guard.md." },
  { name: "pretooluse-github-hard-wrap-guard", main: githubHardWrapGuard, timeoutMs: 4000, description: "Denies `gh release|issue|pr` and `gh api` commands whose prose contains hard-wraps at a fixed column width. GFM renders every `\\n` as `<br>`, so prose wrapped at ~100 cols becomes columns of short mid-sentence lines instead of reflowing to the reader's window. Inspects --notes/--notes-file (release), --body/-b/--body-file/-F (issue/pr, including `pr review`), and for `gh api` writes to releases/issues/pulls the body=/notes= field (any quoting shape, including `-F body=@file`) or an --input envelope's .body; `--input` alone counts as a write because gh implies POST. Reads the body from the command's own HEREDOC when the file does not exist yet, which is the dominant write-then-publish-in-one-call pattern, and follows `--body \"$(cat f)\"` and `--body-file \"$VAR\"`. When a body file is missing AND this command demonstrably writes it by an unparseable means, it denies with 'split into two Bash calls' rather than failing open. Repair with `bun \"$(cc-plugin-root itp-hooks)/scripts/gfm-unwrap.ts\" <file>`. Non-regular files (FIFO, /dev/stdin, directory) are skipped unread so the hook cannot hang. Git objects are out of scope: 72-column wrapping is correct for a commit or annotated-tag message. Escape hatch: GH-HARD-WRAP-OK. Fail-open. Independent of release-notes-extensiveness-guard." },
  { name: "pretooluse-markdown-commit-hard-wrap-guard", main: markdownCommitHardWrapGuard, timeoutMs: 14000, description: "Denies a `git commit` that would ADD hard-wrapped prose (a paragraph broken mid-sentence at a fixed column) to a .md/.markdown file. The commit is the one boundary every authoring path crosses, including Markdown written by heredocs, Python and generator scripts that the Write/Edit-time reminder never sees (measured gap, 2026-10-01). Compares the version being committed against HEAD, whole file, NET-NEW wraps only (lib/markdown-net-new-hard-wraps.ts, shared with both reminders), so legacy wraps never block. Plain commit reads the index; -a/-am and `git commit <paths>` read the working tree. Follows `cd dir &&` and `git -C dir`. Commit messages are out of scope (git objects are not GFM). Repair: bun \"$(cc-plugin-root itp-hooks)/scripts/gfm-unwrap.ts\" <file>. Escapes: the MD-HARD-WRAP-OK marker as an HTML comment in the file (per file) or anywhere in the command (whole commit). Fail-open." },
  { name: "pretooluse-pr-review-invitation-guard", main: prReviewInvitationGuard, timeoutMs: 9000, description: "Denies a BLOCKING pull-request review (CHANGES_REQUESTED) on a PR you did not author and were never invited to review, so the blocking form costs one deliberate keystroke instead of being the default. Motivated by an agent posting CHANGES_REQUESTED on another author's PR on the strength of a premise it had invented ('waiting on my review'); no review request existed. The review's content was substantive and largely adopted, so the defect was its FORM and its PREMISE, not its findings. IT DOES NOT ADJUDICATE AND CANNOT: measured over ten months, all 6 of that reviewer's CHANGES_REQUESTED reviews on others' PRs were uninvited and 5 drew no objection (two went CHANGES_REQUESTED -> APPROVED within ~35 minutes, an ordinary round), so no fact available at command time separates the one complaint from the five non-complaints and a strict rule would carry 5 false positives per true positive. Deliberately untouched: `--approve` (17 on others' PRs, 10 since 2026-08-21; the ruleset requires 1 approval and GitHub forbids self-approval, so gating it would DEADLOCK the repo), `--comment` (the intended fallback -- the honest description of this guard's effect is a rename, not a prevention), and all `gh issue` traffic (closing a collaborator's issue is ordinary triage). Covers four doors: `gh pr review` porcelain including pflag shorthand clusters (`-rb`) and the `=true` spelling, the `gh api` REST `/pulls/N/reviews` write (no `-X POST` needed -- any field flag implies POST), the two-step `/reviews/{id}/events` submit, and `gh api graphql addPullRequestReview`; `--input` and GraphQL are opaque because the event sits in a file or payload, and opaque resolves to denied. The invitation fact is the durable `review_requested` TIMELINE event, never the live `requested_reviewers` array, which GitHub CLEARS the moment you submit a review (measured on #201 and #35) and which would therefore make legitimate round-2+ review -- 73% of review traffic here -- the dominant false positive. UNLIKE its sibling review-round-gate, this hook DOES make network calls, so every gap resolves to DENY (opaque command, unresolved author or actor, unqueryable timeline): a network check whose failure means 'permit' is Decision #484 reproduced inside a guard built to prevent it. Calls are bounded at 3s each and the child pid is killed directly, never via `pkill -f`. Escape hatch: PR_BLOCKING_REVIEW_OK=1 as a LEADING ASSIGNMENT at a command position, never a substring, so a body discussing the token cannot disarm it. Not a containment boundary: disableAllHooks, the web UI, and a hook timeout all reach GitHub without a verdict." },
  { name: "pretooluse-pr-citation-evidence-guard", main: prCitationEvidenceGuard, timeoutMs: 4000, description: "Denies `gh pr comment` / `gh pr review` (and the `gh api` writes to a PR's comments/reviews or the issues/N/comments endpoint GitHub models PR conversation on) whose body asserts a solution is best practice / state of the art / idiomatic / canonical / the standard / recommended / per the spec, WITHOUT the evidence the operator directive of 2026-09-02 requires: verbatim citations and quotes from authoritative online sources, including the URL links. Two conditions: (1) a normative claim with NO URL at all; (2) a normative claim citing URLs but quoting nothing from them (a `>` blockquote, a fenced block, or a quoted/inline-code span of >=25 chars counts; a bare `symbol` in backticks does not, or the check would be unreachable). Scope is deliberately narrow -- NOT `gh pr create`/`edit` (a PR description is authored before review and is not a resolution OF it), NOT issues, NOT releases -- because a guard that fires on 'LGTM' or 'rebased onto main' gets switched off and then protects nothing. `gh` must be at a COMMAND POSITION, so documenting or grepping for the command does not match. Shares lib/github-published-body-collector.ts with github-hard-wrap-guard, so it inherits the eight closed bypasses (gh api field quoting shapes, -F body=@file, --input envelopes, $(cat f) substitutions, $VAR paths, same-command heredoc writes) rather than re-deriving them. Checks SHAPE only and fetches nothing: verify content by fetching each URL this session and grepping the exact quote against the bytes you fetched, and note that on that skill's own measured run 64/64 URLs returned 200 and 64/64 quotes were verbatim while SEVEN citations still failed on scope or direction. Escape hatch: PR-CITATION-OK. Fail-open; an unreadable body is allowed (the hard-wrap guard already denies that shape)." },
  { name: "pretooluse-release-notes-extensiveness-guard", main: releaseNotesExtensivenessGuard, timeoutMs: 7000, description: "Hard-blocks release/tag commands whose notes are not extensive + human-readable (needs a narrative paragraph AND a point-form list). Covers `gh release create|edit` (--notes/--notes-file text), annotated semver `git tag -m/-F`, and semantic-release / `moon run repo:release-*` (inspects releasable commit BODIES since last tag — the notes source). Escape hatch: RELEASE-NOTES-OK: <≥10-char reason>. Fail-open. Doctrine: ~/.claude/release-notes-doctrine-CLAUDE.md. Spoke: docs/release-notes-extensiveness-guard.md. ADR 2026-07-21." },
  { name: "pretooluse-typescript-legacy-install-command-guard", main: typescriptLegacyInstallCommandGuard, timeoutMs: 4000, description: "Blocks Bash package-manager install commands (npm/bun/pnpm/yarn) that would install a pre-7 TypeScript version. Detects `typescript@<spec>` and `@typescript/native-preview@<spec>` tokens anywhere in the command. Reuses evaluateTypeScriptVersionSpecifier (shared evaluator with pretooluse-typescript-version-guard so the two guards cannot drift on what 'legacy' means). Sanctions the dual-install compat alias `@typescript/typescript6@^6.0.2` + `@typescript/native@npm:typescript@latest` for compiler-embedding tools (Volar/Vue/Svelte/Astro, Angular templates, typescript-eslint, ts-morph) that need the TypeScript 6.0 programmatic API (unavailable in 7.0, restored 7.1+). Escape hatches: ALLOW_LEGACY_TS=1 environment prefix OR ALLOW-LEGACY-TS inline marker (iter-111 canonical registry). SSoT: ~/.claude/typescript-latest-CLAUDE.md. ADR 2026-07-22 iter-92." },
  { name: "pretooluse-headless-claude-p-guard", main: headlessClaudePGuard, timeoutMs: 4000, description: "Checking headless claude -p usage..." },
  { name: "pretooluse-chrome-debug-port-guard", main: chromeDebugPortGuard, timeoutMs: 4000, description: "Chrome remote-debugging launch guard — blocks browser launches that provably cannot work, and one that is a security hole. Since Chrome 136 the --remote-debugging-port / --remote-debugging-pipe switches are REFUSED on the default user-data directory (a non-default dir gets a different encryption key, so CDP-attaching malware cannot decrypt the real profile). It earns a hard block rather than a doc entry because of the failure mode: not a flag error, but either \"DevTools remote debugging requires a non-default data directory\" or an automation client that connects, reports healthy, and hangs forever on a blank page — a confident wrong answer, this repo's standing bar for blocking. Three deterministic violations: (1) a remote-debugging launch with no --user-data-dir; (2) one whose --user-data-dir IS the platform default profile root, which fails identically but reads as compliant; (3) --remote-debugging-address bound off loopback, which hands full browser control — drive any page, read every cookie — to the network. Requires a POSITIVE browser-launch signal and vetoes on inspector/terminator verbs, so `pkill -f remote-debugging-port=9222`, `ps aux | grep`, and `curl http://127.0.0.1:9222/json/version` are never touched; a guard on a flag that commonly appears in kill and grep commands is one false positive away from being switched off. Escape CHROME-DEBUG-PORT-OK with a ≥10-character reason. Fails open. Spoke: ~/.claude/skills/browser-automation/references/doctrine.md; upstream: https://developer.chrome.com/blog/remote-debugging-port" },
  { name: "pretooluse-broad-process-signal-guard", main: broadProcessSignalGuard, timeoutMs: 4000, description: "Kill guard v2. Denies a kill/pkill/killall that is broad by construction: `kill -1` or `kill 0` as a TARGET (`kill -1 <pid>` is SIGHUP and passes), a shared runtime or host program by name (`pkill node`, `killall bun`, `pkill -f claude`, `kill $(pgrep python3)`), a user-wide `-u` with no process name, or a pkill pattern with under five literal characters (`pkill -f vite`, `pkill -f .`). Also inspects the text of SHELL SCRIPTS written with Write/Edit (by extension or shebang, including the on-disk shebang for an Edit) and applies both this check and v1's pkill option-order check there, closing v1's documented gap of a script written first and run second. Measured 2026-09-27: one pattern-aimed pkill SIGTERMed eight Claude Code sessions and every Electron app's crash reporter on the operator's Mac. Shares v1's static lexer (hooks/lib/shell-command-quote-aware-static-lexer.ts + shell-command-invocation-walker.ts), so it sees through $(...), sudo/env/timeout/xargs, bash -c, ssh remote commands, pueue add and heredocs fed to a shell, and ignores mere mentions. The deny message says to signal the PID you started. Escape BROAD-PROCESS-SIGNAL-OK: <>=10-char reason>. Fails open. Spoke: docs/broad-process-signal-guard.md." },
  { name: "pretooluse-tcc-grant-ordering-guard", main: tccGrantOrderingGuard, timeoutMs: 4000, description: "Blocks deleting a macOS application bundle before resetting its TCC privacy grants, and blocks addressing a launchd job by plist FILENAME instead of the Label inside the plist. Both mistakes report success at the moment they are made. Deleting first strands every grant permanently: tccutil resolves the bundle id through LaunchServices before touching the database, so after deletion every reset fails -10814, macOS never prunes the rows, and System Settings will not render a row whose bundle cannot resolve. Targeting the filename returns ESRCH and leaves a live KeepAlive job running, usually right before its binary is deleted out from under it. Escape: TCC-ORDERING-OK: <reason>." },
  { name: "pretooluse-pii-push-gate", main: piiPushGate, timeoutMs: 9000, description: "Blocks a git push whose ADDED lines carry secrets or, when the repository is not known to be private, personal detail. A push is the last reversible moment: rewriting history does not unpublish a value that forks, caches and mirrors already hold. Scans only added lines, because a repo's existing content legitimately contains its owner's handle and home paths, and a gate that fires on material the push cannot affect is one people learn to skip. Secrets block unconditionally; identity detail blocks only under PUBLIC or UNKNOWN. Visibility is READ from .git/claude-pii-visibility and never fetched: gh inside a hook has caused process storms on sleep/wake. UNKNOWN is treated as PUBLIC so that an unclassified repo fails loud rather than silently publishing. Escape: PII-GATE-OK: <reason>." },
  { name: "pretooluse-pkill-option-after-pattern-guard", main: pkillOptionAfterPatternGuard, timeoutMs: 4000, description: "Denies a pkill or pgrep whose option comes AFTER the first pattern (`pkill -f 'bun server.ts' -n`). macOS/BSD getopt stops at the first non-option argument, so the trailing `-n` becomes a SECOND PATTERN and pkill signals every process whose command line contains it. Measured 2026-09-27: that exact line SIGTERMed eight Claude Code sessions and every Electron app's crash reporter on the operator's Mac, and the apps then crash-looped their respawned reporters (macOS 15.8.1 refuses the respawn with KERN_INVALID_CAPABILITY) through 'quit unexpectedly' dialogs until relaunched. Statically lexes the command and looks through $(...), backticks, sudo/env/timeout/xargs wrappers, bash -c, ssh remote commands, pueue add and heredocs fed to a shell; ignores mere mentions (quoted text, comments, heredocs fed to cat/python/git), patterns after `--`, redirections, and sibling commands' flags (`| head -n 1`). The deny message carries the corrected invocation. Escape hatch PKILL-OPTION-ORDER-OK: <>=10-char reason>. Spoke: docs/pkill-option-after-pattern-guard.md." },
];

/**
 * Whole-run budget, kept under the orchestrator's 60 s hooks.json timeout. Guards run one after
 * another, so this caps the worst case where several of them overrun in a row.
 */
const TOTAL_BUDGET_MS = 50_000;

interface HookSpecificOutput {
  permissionDecision?: "allow" | "deny" | "ask";
  permissionDecisionReason?: string;
  additionalContext?: string;
  updatedInput?: unknown;
}

export interface AggregatedDecision {
  decision: "allow" | "deny" | "ask";
  /** Present for deny and ask: the deciding guard's own reason, verbatim. */
  reason?: string;
  /** The guard that decided a deny or ask. */
  decidedBy?: string;
  additionalContext: string[];
  /** Guards that threw or overran and were skipped (fail-open). */
  skipped: string[];
}

type GuardOutcome =
  | { kind: "ran"; responses: object[] }
  | { kind: "timeout" }
  | { kind: "error"; message: string };

async function runOne(entry: BashGuardEntry, input: PreToolUseInput, budgetMs: number): Promise<GuardOutcome> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<GuardOutcome>((resolve) => {
    timer = setTimeout(() => resolve({ kind: "timeout" }), budgetMs);
  });
  try {
    return await Promise.race([settle(entry, input), timeout]);
  } finally {
    clearTimeout(timer);
  }
}

/** Run one guard to completion and report a throw as an outcome rather than a rejection. */
async function settle(entry: BashGuardEntry, input: PreToolUseInput): Promise<GuardOutcome> {
  try {
    return { kind: "ran", responses: await runGuardMainInProcess(entry.main, input) };
  } catch (err: unknown) {
    return { kind: "error", message: err instanceof Error ? err.message : String(err) };
  }
}

/** Run every guard against one input and fold their responses into a single decision. */
export async function runBashGuards(
  input: PreToolUseInput,
  registry: readonly BashGuardEntry[] = BASH_GUARD_REGISTRY,
): Promise<AggregatedDecision> {
  const result: AggregatedDecision = { decision: "allow", additionalContext: [], skipped: [] };
  const deadline = Date.now() + TOTAL_BUDGET_MS;

  for (const entry of registry) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      result.skipped.push(entry.name);
      continue;
    }
    const outcome = await runOne(entry, input, Math.min(entry.timeoutMs, remaining));
    if (outcome.kind !== "ran") {
      const why = outcome.kind === "timeout" ? "timed out" : `threw: ${outcome.message}`;
      process.stderr.write(`${LOG_PREFIX} ${entry.name} ${why}; skipped (fail-open)\n`);
      trackHookError(`pretooluse-bash-guard-orchestrator/${entry.name}`, why);
      result.skipped.push(entry.name);
      continue;
    }
    for (const response of outcome.responses) {
      const hso = (response as { hookSpecificOutput?: HookSpecificOutput }).hookSpecificOutput ?? {};
      if (hso.updatedInput !== undefined) {
        process.stderr.write(`${LOG_PREFIX} ${entry.name} emitted updatedInput, which the orchestrator does not apply\n`);
      }
      if (hso.permissionDecision === "deny") {
        return { ...result, decision: "deny", reason: hso.permissionDecisionReason ?? "(no reason given)", decidedBy: entry.name };
      }
      if (hso.permissionDecision === "ask" && result.decision !== "ask") {
        result.decision = "ask";
        result.reason = hso.permissionDecisionReason ?? "(no reason given)";
        result.decidedBy = entry.name;
      }
      if (hso.additionalContext) result.additionalContext.push(hso.additionalContext);
    }
  }
  return result;
}

/** The single response the orchestrator prints, in the shape the guards' own helpers produce. */
export function toHookResponse(aggregated: AggregatedDecision): object {
  const hookSpecificOutput: Record<string, unknown> = {
    hookEventName: "PreToolUse",
    permissionDecision: aggregated.decision,
  };
  if (aggregated.reason !== undefined) hookSpecificOutput.permissionDecisionReason = aggregated.reason;
  if (aggregated.decision !== "deny" && aggregated.additionalContext.length > 0) {
    hookSpecificOutput.additionalContext = aggregated.additionalContext.join("\n\n");
  }
  return { hookSpecificOutput };
}

/** Print one line and exit once it is flushed, so an abandoned guard cannot keep the process alive. */
function emitAndExit(response: object): void {
  process.stdout.write(`${JSON.stringify(response)}\n`, () => process.exit(0));
}

async function orchestrate(): Promise<void> {
  const input = await parseStdinOrAllow("pretooluse-bash-guard-orchestrator");
  if (!input) {
    process.exit(0);
  }
  if (input.tool_name !== "Bash") {
    emitAndExit({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow" } });
    return;
  }
  dropOutputOutsideGuardRuns();
  const aggregated = await runBashGuards(input);
  if (aggregated.decision !== "allow") {
    process.stderr.write(`${LOG_PREFIX} ${aggregated.decision.toUpperCase()} from ${aggregated.decidedBy}\n`);
  }
  emitAndExit(toHookResponse(aggregated));
}

if (import.meta.main) {
  orchestrate().catch((err: unknown) => {
    const message = err instanceof Error ? err.message : String(err);
    trackHookError("pretooluse-bash-guard-orchestrator", message);
    emitAndExit({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow" } });
  });
}
