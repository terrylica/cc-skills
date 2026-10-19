#!/usr/bin/env bun
/**
 * PreToolUse hook: old-git guard.
 *
 * Denies a hook-firing git command (commit, push, merge, pull, rebase, cherry-pick, revert, am;
 * also `git -C <dir> …`) when the git that would run is older than 2.54, including an explicit
 * `/usr/bin/git` on macOS, which is Apple's 2.50. Config-based hooks (`hook.<name>.event` in
 * ~/.gitconfig) need Git >= 2.54; an older git reads that config and silently runs none of them,
 * so every hook defined there is skipped without a word.
 *
 * Which git: an explicit path is probed as written; a bare `git` is resolved on this hook's PATH,
 * which is inherited from the same environment as the Bash tool. Versions are cached per session in
 * the temp directory, keyed by binary path, mtime and size, so an upgrade mid-session is noticed and
 * the steady-state cost is one stat. No network.
 *
 * Read-only git (status, log, diff, fetch, show, …) is never checked. Remote commands
 * (`ssh host 'git commit'`) are skipped. Fails open on any error or an unreadable version.
 *
 * Escape: OLD-GIT-OK: <>=10-char reason>. Spoke: docs/old-git-guard.md.
 */

import { mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  type EscapeHatchMarkerDetectionConfiguration,
  hasFileWideEscapeHatchMarkerInContent,
} from "./lib/escape-hatch-marker-detection-iter107.ts";
import {
  GIT_CONFIG_HOOKS_MIN_VERSION,
  type GitResolver,
  type OldGitFinding,
  findOldGitInvocations,
} from "./lib/old-git-detector.ts";
import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";

const HOOK_NAME = "pretooluse-old-git-guard";
const VERSION_PROBE_TIMEOUT_MS = 2000;

const OLD_GIT_ESCAPE_HATCH: Pick<
  EscapeHatchMarkerDetectionConfiguration,
  "markerNameTokenIncludingSuffix" | "requireMinimumReasonCharacterCountAfterColonOrZeroForOptional"
> = {
  markerNameTokenIncludingSuffix: "OLD-GIT-OK",
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
};

type VersionCache = Record<string, string>;

/** Resolver that probes real binaries, caching each version per session. */
export function cachingGitResolver(sessionId: string): GitResolver {
  const dir = join(tmpdir(), "itp-hooks-old-git-guard");
  const file = join(dir, `${sessionId.replace(/[^A-Za-z0-9_-]/g, "_") || "no-session"}.json`);
  let cache: VersionCache | undefined;
  const load = (): VersionCache => {
    if (cache) return cache;
    try {
      cache = JSON.parse(readFileSync(file, "utf8")) as VersionCache;
    } catch {
      cache = {};
    }
    return cache;
  };
  return {
    whichGit: () => Bun.which("git", { PATH: process.env.PATH ?? "" }) ?? undefined,
    versionOf: (binaryPath) => {
      let key: string;
      try {
        const st = statSync(binaryPath);
        key = `${binaryPath}|${st.mtimeMs}|${st.size}`;
      } catch {
        return undefined;
      }
      const c = load();
      if (c[key]) return c[key];
      const r = Bun.spawnSync([binaryPath, "--version"], {
        stdout: "pipe",
        stderr: "ignore",
        timeout: VERSION_PROBE_TIMEOUT_MS,
      });
      const text = r.success ? r.stdout.toString().trim() : "";
      if (!text) return undefined;
      c[key] = text;
      try {
        mkdirSync(dir, { recursive: true });
        writeFileSync(file, JSON.stringify(c));
      } catch {
        /* cache is an optimisation only */
      }
      return text;
    },
  };
}

export function explainOldGitFindings(findings: readonly OldGitFinding[]): string {
  const floor = GIT_CONFIG_HOOKS_MIN_VERSION.join(".");
  const lines = [
    `[OLD-GIT GUARD] Blocked: this git is too old to run the hooks configured in ~/.gitconfig (config-based hooks need git >= ${floor}).`,
  ];
  for (const f of findings) {
    const how = f.explicitPath ? "named explicitly" : "first on PATH";
    const where = f.invocation.context === "command" ? "" : ` (inside a ${f.invocation.context})`;
    lines.push(
      `  git ${f.invocation.subcommand}${where} would run ${f.resolved.path} (${how}): ${f.resolved.versionText}`,
    );
  }
  lines.push(
    `A git older than ${floor} reads the hook.<name>.event entries and silently runs none of them, so the commit, push or rebase would bypass every gate defined there.`,
    "Fix: run the same command with /opt/homebrew/bin/git, or put Homebrew first on PATH " +
      '(export PATH="/opt/homebrew/bin:$PATH") and use plain `git`. On Linux, install git >= ' +
      `${floor} and make it the first git on PATH.`,
    "Spoke: plugins/itp-hooks/docs/old-git-guard.md\n" +
      "Override (only when no hook gate applies to this repository) with OLD-GIT-OK: <>=10-character reason>",
  );
  return lines.join("\n\n");
}

export async function main(): Promise<void> {
  const input = await parseStdinOrAllow("OLD-GIT-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command: string = tool_input.command || "";
  if (!/\bgit\b/.test(command)) {
    allow();
    return;
  }
  if (hasFileWideEscapeHatchMarkerInContent(command, OLD_GIT_ESCAPE_HATCH)) {
    allow();
    return;
  }

  const findings = findOldGitInvocations(command, cachingGitResolver(input.session_id ?? ""));
  if (findings.length === 0) {
    allow();
    return;
  }
  deny(explainOldGitFindings(findings));
}

if (import.meta.main) {
  main().catch((err) => {
    // Fail OPEN: a guard that blocks work when its own logic throws is worse than the gap it closes.
    trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
    allow();
  });
}
