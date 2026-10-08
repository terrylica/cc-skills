// browser.mjs — Chrome lifecycle + CDP attach for the fine-grained PAT engine.
//
// Hard-won lessons codified here:
//   • Bun's connectOverCDP times out — this MUST run under node (the skill docs say so).
//   • Attach by resolving the webSocketDebuggerUrl from /json/version (retry loop),
//     mirroring plugins/gemini-deep-research/scripts/client.ts.
//   • Launch and teardown go through chrome-profiles' chrome-debug-port-control.sh, never `pkill -f`
//     (process-storm policy in ~/.claude/CLAUDE.md).
//
// The persistent --user-data-dir holds the GitHub *session cookie*: treat it as
// sensitive. Default lives outside the repo and is gitignored.

import { spawn, execFileSync } from "node:child_process";
import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

// ── launch / shutdown: the chrome-profiles plugin's chrome-debug-port-control.sh is the SSoT ──────
// It pins a non-default --user-data-dir (Chrome 136+ ignores the debug port otherwise), waits for the
// port, reports the profile ACTUALLY attached, and shuts down by the exact port flag. This harness keeps
// only what is its own: which profile and port, and the CDP attach.
function portControlScript() {
  const here = dirname(fileURLToPath(import.meta.url));
  const candidates = [
    process.env.CHROME_PROFILES_PORT_CONTROL,
    join(here, "../../../..", "chrome-profiles", "scripts", "chrome-debug-port-control.sh"), // repo / marketplace checkout
    join(homedir(), ".claude", "plugins", "marketplaces", "cc-skills", "plugins", "chrome-profiles", "scripts", "chrome-debug-port-control.sh"),
  ].filter(Boolean);
  const found = candidates.find((p) => existsSync(p));
  if (!found) throw new Error("chrome-profiles plugin not found (needed for chrome-debug-port-control.sh); install it from cc-skills");
  return found;
}
function portControl(action, { port, profile, chrome }) {
  return execFileSync("bash", [portControlScript(), action], {
    encoding: "utf8",
    env: { ...process.env, CHROME_DEBUG_PORT: String(port), CHROME_DEBUG_PROFILE: profile, ...(chrome ? { CHROME_DEBUG_BINARY: chrome } : {}) },
  });
}
/** Open a URL as a tab in the already-running instance on that profile. */
function openInProfile(chrome, profile, url) {
  if (!url) return;
  const child = spawn(chrome, [`--user-data-dir=${profile}`, url], { detached: true, stdio: "ignore" });
  child.unref();
}

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
 * Launch a visible Chrome with the persistent profile + CDP, through the shared port script, unless one is
 * already listening on the port (reuse it). Returns { pid, reused }.
 */
export async function launchChrome(openUrl = "https://github.com/settings/personal-access-tokens") {
  ensureDirs();
  const reused = Boolean(chromePidOnPort() && (await cdpReady()));
  if (!reused) portControl("up", { port: port(), profile: profileDir(), chrome: CHROME_BIN });
  if (!(await cdpReady())) throw new Error(`Chrome CDP did not come up on ${cdpUrl()}`);
  openInProfile(CHROME_BIN, profileDir(), openUrl);
  return { pid: chromePidOnPort(), reused };
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

/**
 * WHICH login is this profile signed in as? Non-disruptive: same cookie-jar
 * request as isAuthedViaRequest, no navigation of any visible tab. Returns the
 * login, or null when signed out / the marker could not be read.
 *
 * GOTCHA #12 — a session check is not an identity check. `isAuthedViaRequest`
 * answers "a session exists", never "whose". The engine DERIVES the profile
 * directory from the resolved account (`profile` for the shared account,
 * `profile-<account>` otherwise) and then trusts that binding, so a profile
 * signed in as somebody else passes every gate. Measured 2026-09-04:
 * `--account terrylica` selected the shared `profile`, which was signed in as
 * `work`. `doctor` printed "auth authenticated ✓"; `list` printed "(no
 * fine-grained tokens)" — a TRUE statement about work's empty token list,
 * read as a fact about terrylica's. A `create` would have minted the token on
 * work, and setOwner()'s catch-all would have swallowed the missing
 * `example-org` resource-owner option, yielding a silently wrong token.
 *
 * null is INCOMPLETE, never "matches" — callers must refuse, not proceed.
 */
export async function loggedInLoginViaRequest(ctx) {
  try {
    const res = await ctx.request.get("https://github.com/settings/personal-access-tokens", { maxRedirects: 5 });
    if (!res.ok() || res.url().includes("/login")) return null;
    const html = await res.text();
    const m =
      /<meta\s+name="user-login"\s+content="([^"]*)"/i.exec(html) ??
      /<meta\s+name="octolytics-actor-login"\s+content="([^"]*)"/i.exec(html);
    return m?.[1] || null;
  } catch {
    return null;
  }
}

/** Shut Chrome down through the shared port script (matches the exact port flag; never pkill -f). */
export async function teardown() {
  const pid = chromePidOnPort();
  if (!pid) return { killed: false, reason: "no listener on port" };
  portControl("down", { port: port(), profile: profileDir() });
  return { killed: chromePidOnPort() !== pid, pid };
}
