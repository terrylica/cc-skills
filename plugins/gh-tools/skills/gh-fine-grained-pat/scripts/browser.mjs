// browser.mjs — Chrome lifecycle + CDP attach for the fine-grained PAT engine.
//
// Hard-won lessons codified here:
//   • Bun's connectOverCDP times out — this MUST run under node (the skill docs say so).
//   • Chrome 111+ rejects the CDP websocket without --remote-allow-origins=* .
//   • Attach by resolving the webSocketDebuggerUrl from /json/version (retry loop),
//     mirroring plugins/gemini-deep-research/scripts/client.ts.
//   • Teardown kills a SPECIFIC pid (lsof on the port), never `pkill -f`
//     (process-storm policy in ~/.claude/CLAUDE.md).
//
// The persistent --user-data-dir holds the GitHub *session cookie*: treat it as
// sensitive. Default lives outside the repo and is gitignored.

import { spawn, execFileSync } from "node:child_process";
import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { chromium } from "playwright-core";

// Multi-account: each account gets its OWN isolated profile + CDP port (derived
// from GH_PAT_ACCOUNT), matching the per-account gh-config isolation. The
// "shared" account (default terrylica) keeps the original profile/port for
// back-compat. GH_PAT_PROFILE_DIR / GH_PAT_CDP_PORT still override explicitly.
const BASE_PORT = Number(process.env.GH_PAT_CDP_PORT ?? 9222);
const SHARED_ACCOUNT = process.env.GH_PAT_SHARED_ACCOUNT ?? "terrylica";
const BASE_DIR = join(homedir(), ".local", "share", "gh-pat-automation");
export const DEBUG_DIR = process.env.GH_PAT_DEBUG_DIR ?? "/tmp/gh-pat-debug";
const CHROME_BIN =
  process.env.GH_PAT_CHROME_BIN ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const currentAccount = () => process.env.GH_PAT_ACCOUNT || null;
const isShared = () => {
  const a = currentAccount();
  return !a || a === SHARED_ACCOUNT;
};
const portOffset = (s) => 1 + ([...s].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7) % 40);

/** Per-account persistent profile dir (terrylica/shared keeps the original). */
export function profileDir() {
  if (process.env.GH_PAT_PROFILE_DIR) return process.env.GH_PAT_PROFILE_DIR;
  return isShared() ? join(BASE_DIR, "profile") : join(BASE_DIR, `profile-${currentAccount()}`);
}
/** Per-account CDP port (shared = BASE_PORT) so accounts never collide. */
export function port() {
  return isShared() ? BASE_PORT : BASE_PORT + portOffset(currentAccount());
}
export function cdpUrl() {
  return `http://127.0.0.1:${port()}`;
}

export function ensureDirs() {
  for (const d of [profileDir(), DEBUG_DIR]) if (!existsSync(d)) mkdirSync(d, { recursive: true });
}

/** PID of the process listening on the CDP port, or null. */
export function chromePidOnPort(p = port()) {
  try {
    const out = execFileSync("/usr/sbin/lsof", ["-nP", `-iTCP:${p}`, "-sTCP:LISTEN", "-t"], {
      encoding: "utf8",
    });
    const pid = out.split("\n").map((s) => s.trim()).filter(Boolean)[0];
    return pid ? Number(pid) : null;
  } catch {
    return null; // lsof returns non-zero when nothing is listening
  }
}

/** True once /json/version responds (Chrome's CDP endpoint is up). */
async function cdpReady() {
  try {
    const r = await fetch(`${cdpUrl()}/json/version`);
    return r.ok;
  } catch {
    return false;
  }
}

/**
 * Launch a visible Chrome with the persistent profile + CDP, unless one is
 * already listening on the port (reuse it). Returns { pid, reused }.
 */
export async function launchChrome(openUrl = "https://github.com/settings/personal-access-tokens") {
  ensureDirs();
  const existing = chromePidOnPort();
  if (existing && (await cdpReady())) return { pid: existing, reused: true };

  const args = [
    `--remote-debugging-port=${port()}`,
    "--remote-allow-origins=*",
    `--user-data-dir=${profileDir()}`,
    "--no-first-run",
    "--no-default-browser-check",
    openUrl,
  ];
  const child = spawn(CHROME_BIN, args, { detached: true, stdio: "ignore" });
  child.unref();

  for (let i = 0; i < 60; i++) {
    if (await cdpReady()) break;
    await sleep(500);
  }
  if (!(await cdpReady())) throw new Error(`Chrome CDP did not come up on ${cdpUrl()} within 30s`);
  return { pid: chromePidOnPort(), reused: false };
}

/** Resolve the webSocketDebuggerUrl (retrying) then attach Playwright. */
export async function connect() {
  let wsUrl = null;
  for (let i = 0; i < 20; i++) {
    try {
      const data = await (await fetch(`${cdpUrl()}/json/version`)).json();
      if (data.webSocketDebuggerUrl) {
        wsUrl = data.webSocketDebuggerUrl;
        break;
      }
    } catch {
      /* not ready */
    }
    await sleep(500);
  }
  if (!wsUrl) throw new Error(`Could not resolve webSocketDebuggerUrl from ${cdpUrl()}/json/version`);
  const browser = await chromium.connectOverCDP(wsUrl);
  const ctx = browser.contexts()[0] ?? (await browser.newContext());
  return { browser, ctx };
}

/** Reuse an existing GitHub tab if present, else open one. */
export async function gotoSettings(ctx, path = "https://github.com/settings/personal-access-tokens") {
  const pages = ctx.pages();
  const page = pages.find((p) => p.url().includes("github.com")) ?? (await ctx.newPage());
  await page.goto(path, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  return page;
}

/** Is the GitHub session authenticated? (login page redirect == not.) */
export async function isAuthenticated(page) {
  const url = page.url();
  if (url.includes("/login") || url.includes("/session")) return false;
  // The settings pages 302 to /login when signed out.
  return /github\.com\/settings\//.test(url);
}

/**
 * Non-disruptive auth check: hits a protected endpoint with the context's
 * cookies WITHOUT navigating any visible tab (so a half-typed login form is
 * never reloaded). Signed-out sessions redirect to /login.
 */
export async function isAuthedViaRequest(ctx) {
  try {
    const res = await ctx.request.get("https://github.com/settings/personal-access-tokens", { maxRedirects: 5 });
    return res.ok() && !res.url().includes("/login");
  } catch {
    return false;
  }
}

/** Kill Chrome by its specific PID (TERM, then KILL). Never pkill -f. */
export async function teardown(pid = chromePidOnPort()) {
  if (!pid) return { killed: false, reason: "no listener on port" };
  try {
    process.kill(pid, "SIGTERM");
  } catch {
    return { killed: false, reason: "process already gone" };
  }
  await sleep(1500);
  if (chromePidOnPort() === pid) {
    try {
      process.kill(pid, "SIGKILL");
    } catch {
      /* gone */
    }
    await sleep(500);
  }
  return { killed: chromePidOnPort() !== pid, pid };
}
