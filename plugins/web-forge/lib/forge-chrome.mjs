// forge-chrome.mjs — where web-forge's browsers come from. Shared by BOTH runtimes:
//   • node forge scripts, through browser-forge.mjs (Playwright over CDP);
//   • the Bun recipe runner, scripts/web-forge.ts (Playwright MCP, `--connect cdp` or `--connect extension`).
// No Playwright import here, so Bun can load it without playwright-core.
//
// Two connection modes, one place that knows how to reach them:
//   • extension — a profile of the operator's everyday Chrome, chosen by account email, driven through Microsoft's
//     Playwright Extension: chrome-profiles' `chrome-profile.sh playwright-mcp <email>`.
//   • cdp       — a persistent per-SITE profile under ~/.local/share/web-forge/ on its own debug port, launched and
//     shut down by chrome-profiles' `chrome-debug-port-control.sh` (exact port flag, never pkill -f). A human
//     logs in once; the session persists in the profile, which is therefore credential-equivalent.
import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Locate a script of the sibling chrome-profiles plugin: an explicit env override, then `cc-plugin-root`, then the
 * repository / marketplace checkout layout next to this plugin.
 */
export function chromeProfilesScript(file, envName) {
  const fromEnv = envName ? process.env[envName] : undefined;
  if (fromEnv) return fromEnv;
  const candidates = [];
  try {
    const root = execFileSync("cc-plugin-root", ["chrome-profiles"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
    if (root) candidates.push(join(root, "scripts", file));
  } catch {
    /* resolver absent: fall through to the checkout layout */
  }
  const here = dirname(fileURLToPath(import.meta.url));
  candidates.push(join(here, "..", "..", "chrome-profiles", "scripts", file));
  candidates.push(join(homedir(), ".claude", "plugins", "marketplaces", "cc-skills", "plugins", "chrome-profiles", "scripts", file));
  const found = candidates.find((p) => existsSync(p));
  if (!found) throw new Error(`chrome-profiles plugin not found (needed for ${file}): install it from cc-skills${envName ? `, or set ${envName}` : ""}`);
  return found;
}

/** argv of the Playwright MCP server for each connection mode (pure; the stdio transport spawns it). */
export function mcpCommand(mode, { account, site } = {}) {
  if (mode === "extension") {
    if (!account) throw new Error("extension mode needs the account email whose Chrome profile to drive");
    return ["bash", chromeProfilesScript("chrome-profile.sh", "CHROME_PROFILES_PROFILE_SH"), "playwright-mcp", account];
  }
  if (mode === "cdp") {
    if (!site) throw new Error("cdp mode needs a site name (the per-site profile)");
    return ["npx", "-y", "@playwright/mcp@latest", "--cdp-endpoint", cdpUrl(site)];
  }
  throw new Error(`unknown connection mode "${mode}" (extension | cdp)`);
}

// ── cdp mode: per-site persistent profiles ─────────────────────────────────────────────────────────────
const BASE_DIR = join(homedir(), ".local", "share", "web-forge");
const BASE_PORT = Number(process.env.WEB_FORGE_CDP_PORT ?? 9250);
export const CHROME_BIN = process.env.WEB_FORGE_CHROME_BIN ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

const siteHash = (s) => [...s].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7) % 80;

/** Per-site persistent profile (login sessions survive across runs; the dir is sensitive). */
export function profileDir(site) {
  return process.env.WEB_FORGE_PROFILE_DIR ?? join(BASE_DIR, `profile-${site}`);
}
export function port(site) {
  return BASE_PORT + siteHash(site);
}
export const cdpUrl = (site) => `http://127.0.0.1:${port(site)}`;

function portControl(action, { port: p, profile, chrome }) {
  return execFileSync("bash", [chromeProfilesScript("chrome-debug-port-control.sh", "CHROME_PROFILES_PORT_CONTROL"), action], {
    encoding: "utf8",
    env: { ...process.env, CHROME_DEBUG_PORT: String(p), CHROME_DEBUG_PROFILE: profile, ...(chrome ? { CHROME_DEBUG_BINARY: chrome } : {}) },
  });
}

/** Open a URL as a tab in the already-running instance on that profile. */
function openInProfile(chrome, profile, url) {
  if (!url) return;
  const child = spawn(chrome, [`--user-data-dir=${profile}`, url], { detached: true, stdio: "ignore" });
  child.unref();
}

/** PID listening on the site's CDP port, or null. */
export function chromePidOnPort(site) {
  try {
    const out = execFileSync("/usr/sbin/lsof", ["-nP", `-iTCP:${port(site)}`, "-sTCP:LISTEN", "-t"], { encoding: "utf8" });
    const pid = out.split("\n").map((s) => s.trim()).filter(Boolean)[0];
    return pid ? Number(pid) : null;
  } catch {
    return null; // lsof non-zero = nothing listening
  }
}

export async function cdpReady(site) {
  try {
    return (await fetch(`${cdpUrl(site)}/json/version`)).ok;
  } catch {
    return false;
  }
}

/** Launch (or reuse) the visible per-site Chrome with CDP, through the shared port script. Returns { pid, reused }. */
export async function launchChrome(site, openUrl) {
  const dir = profileDir(site);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  const reused = Boolean(chromePidOnPort(site) && (await cdpReady(site)));
  if (!reused) portControl("up", { port: port(site), profile: dir, chrome: CHROME_BIN });
  if (!(await cdpReady(site))) throw new Error(`Chrome CDP not up on ${cdpUrl(site)}`);
  openInProfile(CHROME_BIN, dir, openUrl);
  return { pid: chromePidOnPort(site), reused };
}

/** Shut the site's Chrome down through the shared port script (matches the exact port flag; never pkill -f). */
export async function teardown(site) {
  const pid = chromePidOnPort(site);
  if (!pid) return { killed: false, reason: "no listener" };
  portControl("down", { port: port(site), profile: profileDir(site) });
  return { killed: chromePidOnPort(site) !== pid, pid };
}
