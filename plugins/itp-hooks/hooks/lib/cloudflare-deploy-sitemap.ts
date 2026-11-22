/**
 * Shared logic of the Cloudflare deploy → sitemap hooks (operator, 2026-11-15: "every time anything is created on
 * Cloudflare Workers, those links are sitemapped with full provenance ... reminded by a global hook for both of my
 * devices").
 *
 * - posttooluse-cloudflare-deploy-sitemap-reminder.ts records each deploy command in PENDING (with the session id)
 *   and reminds the agent to update the sitemap.
 * - stop-cloudflare-sitemap-pending.ts (a Stop subhook) blocks the end of a turn while this session has a deploy
 *   newer than the last sitemap update (LAST).
 *
 * Nothing account-, host- or URL-specific lives here (this repository is public). Each machine may hold
 * ~/.config/cf-sitemap/hook.json: { "update_command": "<how this machine updates the sitemap>" }. The update command
 * must leave LAST newer than the deploy: the sitemap tool writes it on the machine it runs on; a machine that runs it
 * remotely appends a local `mark` (see markCommand()).
 */

import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { type ShellInvocation, walkShellInvocations } from "./shell-command-invocation-walker.ts";

export const STATE_DIR = process.env.CF_SITEMAP_STATE ?? join(homedir(), ".local/state/cf-sitemap");
export const PENDING = join(STATE_DIR, "pending.jsonl");
export const LAST = join(STATE_DIR, "last-sitemap.json");
export const CONFIG = process.env.CF_SITEMAP_CONFIG ?? join(homedir(), ".config/cf-sitemap/hook.json");
export const MAX_BLOCKS = 3; // per deploy: a stuck sitemap must not trap a session forever

const WRANGLER = /^wrangler(?:@[\w.^~-]+)?$/;
const PACKAGE_RUNNERS = new Set(["npx", "bunx", "pnpx"]);
const SHELLS = new Set(["bash", "sh", "zsh"]);
const WRAPPER = "workers_deploy.sh"; // a repository's own wrapper around wrangler deploy

function base(path: string): string {
  return path.slice(path.lastIndexOf("/") + 1);
}

/** The words after `wrangler` when this invocation runs wrangler (directly, or through npx/bunx/pnpx or pnpm/yarn dlx). */
function wranglerArgs(inv: ShellInvocation): string[] | null {
  const args = inv.args.map((w) => w.value);
  if (WRANGLER.test(inv.program)) return args;
  let rest: string[] | null = null;
  if (PACKAGE_RUNNERS.has(inv.program)) rest = args;
  else if ((inv.program === "pnpm" || inv.program === "yarn") && args[0] === "dlx") rest = args.slice(1);
  if (!rest) return null;
  const i = rest.findIndex((t) => !t.startsWith("-"));
  return i >= 0 && WRANGLER.test(rest[i]) ? rest.slice(i + 1) : null;
}

/** The arguments of a deploy this invocation runs, or null: `wrangler [pages|versions] deploy …`, or the wrapper script
 * run directly or through a shell. */
function deployArgs(inv: ShellInvocation): string[] | null {
  const w = wranglerArgs(inv);
  if (w) {
    const at = w.indexOf("deploy");
    const before = at === -1 ? [] : w.slice(0, at).filter((t) => !t.startsWith("-"));
    return at !== -1 && before.every((t) => t === "pages" || t === "versions") ? w : null;
  }
  const args = inv.args.map((x) => x.value);
  if (base(inv.program) === WRAPPER) return args;
  if (SHELLS.has(inv.program)) {
    const i = args.findIndex((t) => !t.startsWith("-"));
    if (i >= 0 && base(args[i]) === WRAPPER) return args.slice(i + 1);
  }
  return null;
}

/** A command that publishes to Cloudflare Workers or Pages: an invocation the shell would actually run (found by the
 * shared walker, so a `cat`, `grep` or quoted text that only MENTIONS a deploy does not count), not a dry run or help,
 * and not the sitemap tool itself. */
export function isDeployCommand(cmd: string): boolean {
  if (!cmd) return false;
  if (/\bcfsm\.py\b/.test(cmd)) return false; // the sitemap tool deploys the sitemap itself and clears PENDING
  let found = false;
  walkShellInvocations(cmd, /wrangler|workers_deploy\.sh/, (inv) => {
    if (found) return;
    const args = deployArgs(inv);
    if (args && !args.some((t) => t === "--dry-run" || t === "-h" || t === "--help")) found = true;
  });
  return found;
}

export interface PendingEntry {
  at: string; // ISO time of the deploy
  session: string;
  cwd: string;
  command: string;
  blocks?: number;
}

export function readPending(): PendingEntry[] {
  if (!existsSync(PENDING)) return [];
  return readFileSync(PENDING, "utf8")
    .split("\n")
    .filter((l) => l.trim())
    .flatMap((l) => {
      try {
        return [JSON.parse(l) as PendingEntry];
      } catch {
        return [];
      }
    });
}

export function writePending(entries: PendingEntry[]): void {
  mkdirSync(STATE_DIR, { recursive: true });
  writeFileSync(PENDING, entries.map((e) => JSON.stringify(e)).join("\n") + (entries.length ? "\n" : ""));
}

export function recordDeploy(e: PendingEntry): void {
  mkdirSync(STATE_DIR, { recursive: true });
  appendFileSync(PENDING, JSON.stringify(e) + "\n");
}

/** Time of the last sitemap update on this machine, or 0. */
export function lastSitemapAt(): number {
  try {
    const at = JSON.parse(readFileSync(LAST, "utf8")).at;
    const t = Date.parse(at);
    return Number.isFinite(t) ? t : 0;
  } catch {
    return 0;
  }
}

export function updateCommand(): string {
  try {
    const c = JSON.parse(readFileSync(CONFIG, "utf8")).update_command;
    if (typeof c === "string" && c.trim()) return c.trim();
  } catch {
    // no config on this machine: the generic text below
  }
  return "the machine's sitemap update (set update_command in ~/.config/cf-sitemap/hook.json)";
}

/** Shell that marks the sitemap as updated on THIS machine (for an update run on another machine). */
export function markCommand(): string {
  return `mkdir -p ${STATE_DIR} && printf '{"at":"%s"}' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > ${LAST}`;
}

/** This session's deploys not yet covered by a sitemap update. */
export function outstanding(session: string, entries = readPending(), last = lastSitemapAt()): PendingEntry[] {
  return entries.filter((e) => e.session === session && Date.parse(e.at) > last);
}
