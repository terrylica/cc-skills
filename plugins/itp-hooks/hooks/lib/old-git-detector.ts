/**
 * Old-git detector — finds git invocations that would run hooks through a git too old for
 * config-based hooks, and resolves which git binary each would run.
 *
 * Config-based hooks (`hook.<name>.event` / `hook.<name>.command` in ~/.gitconfig) are honoured
 * only by Git >= 2.54. An older git, such as Apple's /usr/bin/git, reads the same config and
 * silently runs none of those hooks, so every gate defined that way is skipped without a word.
 *
 * Pure apart from two filesystem reads the caller can replace in tests: resolving `git` on PATH and
 * asking a binary for its version. Statically lexes the command through the shared invocation
 * walker, so quoted text, comments and heredocs fed to cat never count, and `sudo`/`env`/`bash -c`
 * wrappers are seen through. Remote commands (`ssh host 'git commit'`) are skipped: they run the
 * remote host's git, which this machine cannot judge.
 *
 * Spoke: plugins/itp-hooks/docs/old-git-guard.md
 */

import { walkShellInvocations } from "./shell-command-invocation-walker.ts";

/** Lowest git that runs config-based hooks. Mirrored in hooks/sessionstart-git-version-check.sh (a test keeps them equal). */
export const GIT_CONFIG_HOOKS_MIN_VERSION: readonly [number, number] = [2, 54];

/**
 * Subcommands that fire hooks a gate can hang on: commit (pre-commit, commit-msg), push
 * (pre-push), merge/pull (pre-merge-commit, commit-msg), rebase (pre-rebase, post-rewrite),
 * cherry-pick/revert (commit-msg), am (applypatch-msg, pre-applypatch). Everything else, notably
 * status/log/diff/fetch/show, is left alone.
 */
export const HOOK_FIRING_SUBCOMMANDS: ReadonlySet<string> = new Set([
  "commit",
  "push",
  "merge",
  "rebase",
  "cherry-pick",
  "am",
  "revert",
  "pull",
]);

/** git global options that take their value as the NEXT word (`git -C dir commit`). */
const GLOBAL_OPTIONS_WITH_SEPARATE_VALUE: ReadonlySet<string> = new Set([
  "-C",
  "-c",
  "--git-dir",
  "--work-tree",
  "--namespace",
  "--super-prefix",
  "--config-env",
  "--exec-path",
]);

export interface GitHookInvocation {
  /** The program word as written: `git`, `/usr/bin/git`, `./bin/git`. */
  readonly programAsWritten: string;
  readonly subcommand: string;
  /** Where the invocation sits: plain command, `bash -c` script, pueue task, heredoc. */
  readonly context: string;
}

/**
 * The subcommand of a git invocation, skipping global options. `--exec-path` without `=` is a
 * query when it is the last word, and consuming one word too many there is harmless.
 */
export function gitSubcommand(args: readonly string[]): string | undefined {
  let i = 0;
  while (i < args.length) {
    const a = args[i];
    if (a === "--") return args[i + 1];
    if (!a.startsWith("-")) return a;
    i += GLOBAL_OPTIONS_WITH_SEPARATE_VALUE.has(a) ? 2 : 1;
  }
  return undefined;
}

/** Every hook-firing git invocation in `command` that runs on this machine. */
export function findHookFiringGitInvocations(command: string): GitHookInvocation[] {
  const found: GitHookInvocation[] = [];
  walkShellInvocations(command, /\bgit\b/, ({ program, programWord, args, context }) => {
    if (program !== "git") return;
    if (context === "ssh remote command") return;
    const sub = gitSubcommand(args.map((w) => w.value));
    if (sub === undefined || !HOOK_FIRING_SUBCOMMANDS.has(sub)) return;
    found.push({ programAsWritten: programWord.value, subcommand: sub, context });
  });
  return found;
}

/** `git version 2.50.1 (Apple Git-155)` → [2, 50]; undefined when unparseable. */
export function parseGitVersion(output: string): [number, number] | undefined {
  const m = /git version (\d+)\.(\d+)/.exec(output);
  return m ? [Number(m[1]), Number(m[2])] : undefined;
}

export function isBelowConfigHooksFloor(v: readonly [number, number]): boolean {
  const [maj, min] = GIT_CONFIG_HOOKS_MIN_VERSION;
  return v[0] < maj || (v[0] === maj && v[1] < min);
}

export interface ResolvedGit {
  readonly path: string;
  readonly versionText: string;
  readonly version: [number, number];
}

export interface OldGitFinding {
  readonly invocation: GitHookInvocation;
  readonly resolved: ResolvedGit;
  /** True when the command names the binary by path rather than relying on PATH. */
  readonly explicitPath: boolean;
}

export interface GitResolver {
  /** Absolute path of `git` as the shell would find it on PATH, or undefined. */
  whichGit(): string | undefined;
  /** `<binary> --version` output, or undefined when the probe fails. */
  versionOf(binaryPath: string): string | undefined;
}

/**
 * Hook-firing invocations whose git is below the floor. A git whose version cannot be learned is
 * allowed: the guard fails open rather than blocking work on its own uncertainty.
 */
export function findOldGitInvocations(command: string, resolver: GitResolver): OldGitFinding[] {
  const findings: OldGitFinding[] = [];
  for (const inv of findHookFiringGitInvocations(command)) {
    const explicitPath = inv.programAsWritten.includes("/");
    const path = explicitPath ? inv.programAsWritten : resolver.whichGit();
    if (!path) continue;
    const versionText = resolver.versionOf(path);
    if (!versionText) continue;
    const version = parseGitVersion(versionText);
    if (!version || !isBelowConfigHooksFloor(version)) continue;
    findings.push({ invocation: inv, resolved: { path, versionText: versionText.trim(), version }, explicitPath });
  }
  return findings;
}
