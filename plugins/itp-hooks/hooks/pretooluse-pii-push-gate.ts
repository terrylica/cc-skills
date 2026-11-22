#!/usr/bin/env bun

/**
 * PreToolUse hook: block a `git push` that would publish secrets or personal detail.
 *
 * A push is the last reversible moment. Once a commit reaches a public remote, rewriting history
 * does not unpublish it — forks, caches, and mirrors keep it — so the only cheap fix is the one
 * available before the push.
 *
 * ── Why this scans ADDED LINES, not files ─────────────────────────────────────────────────────
 *
 * A repository's existing content legitimately contains its owner's handle and home paths. Scanning
 * whole files reported four "hard" matches on 2026-09-20 that were already public and that the push
 * did not introduce. A gate that fires on material it cannot affect is a gate people learn to skip.
 * The lines are those the push's own commits add, each commit read as its own diff (see
 * `pushedAddedLines`), so content the remote already has is never re-reported.
 *
 * ── Why severity depends on repository visibility ─────────────────────────────────────────────
 *
 * Identity detail is a LEAK in a public repo and entirely APPROPRIATE in a private sole-owner one —
 * a personal config repo exists to hold exactly that material. Applying the public policy there
 * produced six DO-NOT-PUSH findings on content the repo was created to store. SECRETS are different
 * and are unconditional: a live token belongs in no repository, private included.
 *
 * ── Why visibility comes from a CACHE FILE and not from `gh` ──────────────────────────────────
 *
 * Determining visibility really does require asking the forge, and this codebase forbids `gh`
 * inside hooks: it has caused process storms on sleep/wake, where a hook firing during a resume
 * spawns network calls that pile up faster than they retire. A hook must stay local and fast.
 *
 * So the hook READS `.git/claude-pii-visibility` and never populates it. Writing it is the job of
 * a tool the operator runs deliberately, outside hook context, where one `gh` call is safe.
 *
 * WHEN THE CACHE IS ABSENT, THE REPO IS TREATED AS PUBLIC. An unknown-visibility repo scanned under
 * the private policy would pass identity detail silently, and the failure would be invisible until
 * it was already published. Unknown therefore fails loud, in the direction that is recoverable.
 *
 * ── Deliberately NOT blocked ──────────────────────────────────────────────────────────────────
 *
 * Anything that is not a push; `git push --dry-run`; and any push whose added lines carry no match.
 * Escape hatch: `PII-GATE-OK: <reason of at least 10 characters>`.
 */

import {
  type EscapeHatchMarkerDetectionConfiguration,
  hasFileWideEscapeHatchMarkerInContent,
} from "./lib/escape-hatch-marker-detection-iter107.ts";
import {
  allow,
  deny,
  parseStdinOrAllow,
  trackHookError,
} from "./pretooluse-helpers.ts";

const PII_GATE_ESCAPE_HATCH: Pick<
  EscapeHatchMarkerDetectionConfiguration,
  | "markerNameTokenIncludingSuffix"
  | "requireMinimumReasonCharacterCountAfterColonOrZeroForOptional"
> = {
  markerNameTokenIncludingSuffix: "PII-GATE-OK",
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
};

export type Visibility = "PUBLIC" | "PRIVATE" | "UNKNOWN";

export interface PiiPattern {
  label: string;
  /** SECRET findings block regardless of visibility; IDENTITY only when the repo may be public. */
  severity: "secret" | "identity";
  regex: RegExp;
}

/**
 * A live credential belongs in no repository, so these apply even to a private one.
 * Ordered most-specific first so the reported label is the most informative match.
 */
export const SECRET_PATTERNS: PiiPattern[] = [
  {
    label: "GitHub token",
    severity: "secret",
    regex: /\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}/,
  },
  {
    label: "OpenAI-style key",
    severity: "secret",
    regex: /\bsk-[A-Za-z0-9_-]{20,}/,
  },
  { label: "AWS access key id", severity: "secret", regex: /\bAKIA[0-9A-Z]{16}\b/ },
  {
    label: "Slack token",
    severity: "secret",
    regex: /\bxox[baprs]-[A-Za-z0-9-]{10,}/,
  },
  {
    label: "Telegram bot token",
    severity: "secret",
    regex: /\b[0-9]{8,10}:AA[A-Za-z0-9_-]{30,}/,
  },
  {
    label: "private key block",
    severity: "secret",
    regex: /BEGIN (RSA |OPENSSH |EC |PGP |DSA )?PRIVATE KEY/,
  },
  {
    label: "credential assignment",
    severity: "secret",
    // Requires a plausible VALUE, not just the word. `password:` in prose is not a finding;
    // `password: hunter2hunter2` is. Placeholder values are excluded below.
    //
    // The value class is "12+ characters that are not whitespace or a quote", NOT an
    // alphanumeric class. An earlier version used [A-Za-z0-9/+_-], which stops dead at the
    // first symbol: `password: "Tr0ub4dor&3xKcd9uPPer"` matched only the 9 characters before
    // the ampersand, fell under the length threshold, and passed. A password generator's
    // output is exactly the kind of value most likely to contain symbols, so the old class
    // was weakest precisely where the secrets are strongest.
    regex:
      /\b(password|passwd|secret|api[_-]?key|access[_-]?token|client[_-]?secret)["']?\s*[:=]\s*["']?[^\s"']{12,}/i,
  },
];

/** Appropriate in a private personal repo; a leak in a public one. */
export const IDENTITY_PATTERNS: PiiPattern[] = [
  { label: "home directory path", severity: "identity", regex: /\/Users\/[a-z][a-z0-9_-]+/ },
  {
    label: "email address",
    severity: "identity",
    regex: /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/,
  },
  {
    label: "Tailscale IP",
    severity: "identity",
    regex: /\b100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.\d{1,3}\.\d{1,3}\b/,
  },
  {
    label: "private LAN IP",
    severity: "identity",
    regex: /\b(192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3})\b/,
  },
];

/**
 * Values that look like credentials but are documentation. Without this the gate fires on its own
 * examples and on every README that shows the shape of a config file — the fastest way to train
 * someone to reach for the escape hatch by reflex.
 */
const PLACEHOLDER = /(your[_-]?|example|sample|placeholder|redacted|xxxx|<[^>]+>|\$\{|\bfake\b|changeme|dummy|f{4,}|0{8,}|test[_-]?token)/i;

export interface PiiFinding {
  label: string;
  severity: "secret" | "identity";
  line: number;
  excerpt: string;
}

/**
 * `lines` are the ADDED lines of the push range, without their leading '+'.
 * `lineNumbers`, when supplied, maps each entry back to its position for reporting.
 */
export function findPiiFindings(
  lines: string[],
  visibility: Visibility,
): PiiFinding[] {
  const active: PiiPattern[] =
    visibility === "PRIVATE"
      ? SECRET_PATTERNS
      : [...SECRET_PATTERNS, ...IDENTITY_PATTERNS];

  const findings: PiiFinding[] = [];
  const seen = new Set<string>();

  lines.forEach((line, index) => {
    for (const pattern of active) {
      const match = line.match(pattern.regex);
      if (!match) continue;
      if (PLACEHOLDER.test(match[0])) continue;
      // One finding per label keeps a 4000-line push from producing 4000 findings,
      // which would bury the one that matters.
      if (seen.has(pattern.label)) continue;
      seen.add(pattern.label);
      findings.push({
        label: pattern.label,
        severity: pattern.severity,
        line: index + 1,
        excerpt: line.trim().slice(0, 120),
      });
    }
  });

  // Secrets first: they are unconditional and the most urgent thing to see.
  return findings.toSorted((a, b) =>
    a.severity === b.severity ? 0 : a.severity === "secret" ? -1 : 1,
  );
}

export function explainPiiFindings(
  findings: PiiFinding[],
  visibility: Visibility,
): string {
  const secrets = findings.filter((f) => f.severity === "secret");
  const identity = findings.filter((f) => f.severity === "identity");

  const parts: string[] = [
    `[PII GATE] This push adds content that should not be published. Repository visibility: ${visibility}${
      visibility === "UNKNOWN"
        ? " (treated as PUBLIC — no .git/claude-pii-visibility cache)"
        : ""
    }.`,
  ];

  if (secrets.length > 0) {
    parts.push(
      [
        "SECRETS — these block regardless of visibility. A live credential belongs in no repository:",
        ...secrets.map((f) => `  line ${f.line}  ${f.label}: ${f.excerpt}`),
        "",
        "Rotate the credential FIRST. Removing it from the diff does not un-leak a value that was",
        "already committed locally and may already exist in a reflog or a stash.",
      ].join("\n"),
    );
  }

  if (identity.length > 0) {
    parts.push(
      [
        "IDENTITY DETAIL — these block because the repository is not known to be private:",
        ...identity.map((f) => `  line ${f.line}  ${f.label}: ${f.excerpt}`),
        "",
        "If this repository IS private, cache that fact once so the gate stops asking:",
        "  gh repo view --json visibility --jq .visibility > \"$(git rev-parse --git-dir)/claude-pii-visibility\"",
        "",
        "Run it yourself, not from a hook: `gh` inside a hook has caused process storms on wake.",
      ].join("\n"),
    );
  }

  parts.push(
    "If this is genuinely intended, add a marker with a reason of at least 10 characters:\n  PII-GATE-OK: <why publishing this is correct>",
  );

  return parts.join("\n\n");
}

/**
 * True only for a real push. `--dry-run` publishes nothing and must not be blocked.
 *
 * Tokenised rather than pattern-matched, because git's GLOBAL options sit between `git` and the
 * subcommand and two of them take a separate argument. A regex like /git\s+(-\S+\s+)*push/ cannot
 * skip the `/repo` in `git -C /repo push` — the path is not option-shaped — so that form read as
 * "not a push" and sailed through the gate entirely. `-C` and `-c` are therefore consumed WITH
 * their argument, and `push` must be the first non-option token.
 */
export function isPublishingPush(command: string): boolean {
  for (const segment of command.split(/[;|&]+|\n/)) {
    const tokens = segment.trim().split(/\s+/).filter(Boolean);
    const gitIndex = tokens.findIndex((t) => t === "git" || t.endsWith("/git"));
    if (gitIndex === -1) continue;

    let i = gitIndex + 1;
    while (i < tokens.length) {
      const token = tokens[i] ?? "";
      if (token === "-C" || token === "-c") {
        i += 2; // these take a following argument
        continue;
      }
      if (token.startsWith("-")) {
        i += 1;
        continue;
      }
      break;
    }

    if (tokens[i] !== "push") continue;
    // Scoped to this segment: `git push --dry-run && git push` must still be caught.
    if (/--dry-run\b/.test(segment)) continue;
    return true;
  }
  return false;
}

export function readVisibility(gitDir: string): Visibility {
  try {
    // Bun's file API is synchronous-friendly, but a hook should not await filesystem
    // round-trips it can avoid; readFileSync keeps the whole hook on one tick.
    const fs = require("node:fs") as typeof import("node:fs");
    const raw = fs
      .readFileSync(`${gitDir}/claude-pii-visibility`, "utf8")
      .trim()
      .toUpperCase();
    if (raw === "PUBLIC" || raw === "PRIVATE") return raw;
    return "UNKNOWN";
  } catch {
    return "UNKNOWN";
  }
}

/**
 * The remote this branch pushes to: its configured upstream remote, else `origin`. `null` when the
 * repository has neither, so there is no published history to measure the push against.
 */
export function pushRemote(cwd: string): string | null {
  const { spawnSync } = require("node:child_process") as typeof import("node:child_process");
  const git = (args: string[]) => spawnSync("git", args, { cwd, encoding: "utf8" }).stdout?.trim() ?? "";
  const remotes = git(["remote"]).split("\n").filter(Boolean);
  const branch = git(["symbolic-ref", "--quiet", "--short", "HEAD"]);
  const configured = branch ? git(["config", `branch.${branch}.remote`]) : "";
  if (remotes.includes(configured)) return configured;
  return remotes.includes("origin") ? "origin" : null;
}

/**
 * Every line the commits a push of HEAD would publish add, each commit read as its own diff.
 *
 * What a push publishes is the commits the remote does not have yet: `HEAD --not --remotes=<remote>`.
 * The earlier tree diff against `@{u}` measured something else, and failed three ways:
 * - With `origin/main` as the upstream, every change main made after the branch point came back
 *   reversed, so a file main had DELETED read as added and was reported (2026-11-19).
 * - After merging main into a branch, the whole of main's new content read as added, though
 *   the remote already published it (2026-11-22, #104).
 * - A value added in one commit and removed in a later one netted out to nothing and passed,
 *   though the earlier commit still carried it to the remote.
 *
 * Merges are read as dense combined diffs (`--cc`): a line counts only when it is new against
 * EVERY parent (all `+` columns), i.e. written while resolving the merge. Lines either parent
 * already had are that parent's content: published, or scanned as their own commit in this range.
 *
 * `null` when the push cannot be measured (no remote, or git failed); the caller allows.
 */
export function pushedAddedLines(cwd: string): string[] | null {
  const remote = pushRemote(cwd);
  if (!remote) return null;
  const { spawnSync } = require("node:child_process") as typeof import("node:child_process");
  const log = spawnSync(
    "git",
    ["log", "-p", "--cc", "-U0", "--format=", "--no-color", "--no-ext-diff", "HEAD", "--not", `--remotes=${remote}`],
    { cwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
  if (log.status !== 0 || typeof log.stdout !== "string") return null;
  return addedLinesOfPatchLog(log.stdout);
}

/** The added lines of `git log -p --cc` output: plain diffs and dense combined diffs alike. */
export function addedLinesOfPatchLog(patch: string): string[] {
  const out: string[] = [];
  let columns = 0; // 0 = in a file header, where `+++ b/path` is not content
  for (const line of patch.split("\n")) {
    if (line.startsWith("diff ")) {
      columns = 0;
      continue;
    }
    const hunk = /^(@{2,}) /.exec(line);
    if (hunk) {
      columns = hunk[1].length - 1; // `@@` one parent, `@@@` two, …
      continue;
    }
    if (columns === 0 || line.length < columns) continue;
    if (/^\++$/.test(line.slice(0, columns))) out.push(line.slice(columns));
  }
  return out;
}

export async function main(): Promise<void> {
  const input = await parseStdinOrAllow("PII-PUSH-GATE");
  if (!input) return;

  const { tool_name, tool_input } = input;
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = (tool_input as { command?: string }).command || "";
  if (!isPublishingPush(command)) {
    allow();
    return;
  }

  if (hasFileWideEscapeHatchMarkerInContent(command, PII_GATE_ESCAPE_HATCH)) {
    allow();
    return;
  }

  const { spawnSync } = require("node:child_process") as typeof import("node:child_process");

  const gitDir = spawnSync("git", ["rev-parse", "--git-dir"], {
    encoding: "utf8",
  }).stdout?.trim();
  if (!gitDir) {
    allow();
    return;
  }

  const added = pushedAddedLines(process.cwd());
  if (added === null) {
    allow();
    return;
  }

  // No added lines in the commits the remote lacks means there is nothing to publish. Reporting
  // "clean" from an empty input is how a broken extraction stays green for a whole session,
  // so distinguish it explicitly rather than letting zero findings imply zero risk.
  if (added.length === 0) {
    allow();
    return;
  }

  const visibility = readVisibility(gitDir);
  const findings = findPiiFindings(added, visibility);

  if (findings.length === 0) {
    allow();
    return;
  }

  deny(explainPiiFindings(findings, visibility));
}

// Standalone entry point. The Bash orchestrator (#111) imports `main` and runs it in-process.
if (import.meta.main) void main().catch((err) => {
  // Fail OPEN. A gate that blocks every push when its own logic throws is worse than the
  // leak it prevents — it gets disabled wholesale, and then it prevents nothing.
  trackHookError(
    "pretooluse-pii-push-gate",
    err instanceof Error ? err.message : String(err),
  );
  allow();
});
