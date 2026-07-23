// browser-forge.mjs — the canonical supervised-dashboard-automation harness (web-forge plugin).
//
// Provenance: generalized 2026-07-23 from gh-tools/gh-fine-grained-pat/scripts/browser.mjs (which
// stays untouched as that skill's battle-tested private copy) after the same harness drove a
// SECOND vendor's dashboard unchanged (Cloudflare token forge + GitHub OAuth-app forge for the
// curve-dental Access wall — see that repo's scripts/access-bootstrap/). Rule of two → canonical.
//
// Hard-won invariants (do not regress):
//   • node ONLY — Bun's connectOverCDP times out.
//   • Chrome 111+ needs --remote-allow-origins=* for the CDP websocket.
//   • Teardown kills the SPECIFIC pid listening on the port — never `pkill -f` (process-storm policy).
//   • Persistent per-SITE profiles hold real login sessions: treat every profile dir as sensitive.
//   • Secrets: DOM-extract → vault stdin sink. NEVER screenshot a secret-reveal page — a screenshot
//     read back by the agent puts the secret into the conversation context (learned the hard way).
//   • Mutating anything account-owned? assertIdentity() FIRST (wrong-account OAuth-app incident).
import { spawn, execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, rmSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { chromium } from "playwright-core";

const BASE_DIR = join(homedir(), ".local", "share", "web-forge");
const BASE_PORT = Number(process.env.WEB_FORGE_CDP_PORT ?? 9250);
const CHROME_BIN =
  process.env.WEB_FORGE_CHROME_BIN ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
export const VAULT_BIN = process.env.WEB_FORGE_VAULT_BIN ?? join(homedir(), ".local/bin/vault");

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const siteHash = (s) => [...s].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7) % 80;

/** Per-site persistent profile (login sessions survive across runs; dir is sensitive). */
export function profileDir(site) {
  return process.env.WEB_FORGE_PROFILE_DIR ?? join(BASE_DIR, `profile-${site}`);
}
export function port(site) {
  return BASE_PORT + siteHash(site);
}
const cdpUrl = (site) => `http://127.0.0.1:${port(site)}`;

/** PID listening on the site's CDP port, or null. */
export function chromePidOnPort(site) {
  try {
    const out = execFileSync("/usr/sbin/lsof", ["-nP", `-iTCP:${port(site)}`, "-sTCP:LISTEN", "-t"], {
      encoding: "utf8",
    });
    const pid = out.split("\n").map((s) => s.trim()).filter(Boolean)[0];
    return pid ? Number(pid) : null;
  } catch {
    return null; // lsof non-zero = nothing listening
  }
}

async function cdpReady(site) {
  try {
    return (await fetch(`${cdpUrl(site)}/json/version`)).ok;
  } catch {
    return false;
  }
}

/** Launch (or reuse) the visible per-site Chrome with CDP. Returns { pid, reused }. */
export async function launchChrome(site, openUrl) {
  const dir = profileDir(site);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  const existing = chromePidOnPort(site);
  if (existing && (await cdpReady(site))) return { pid: existing, reused: true };
  const args = [
    `--remote-debugging-port=${port(site)}`,
    "--remote-allow-origins=*",
    `--user-data-dir=${dir}`,
    "--no-first-run",
    "--no-default-browser-check",
    openUrl,
  ];
  const child = spawn(CHROME_BIN, args, { detached: true, stdio: "ignore" });
  child.unref();
  for (let i = 0; i < 60; i++) {
    if (await cdpReady(site)) break;
    await sleep(500);
  }
  if (!(await cdpReady(site))) throw new Error(`Chrome CDP not up on ${cdpUrl(site)} within 30s`);
  return { pid: chromePidOnPort(site), reused: false };
}

/** Attach Playwright over CDP. browser.close() only DISCONNECTS (Chrome keeps running). */
export async function connect(site) {
  let wsUrl = null;
  for (let i = 0; i < 20; i++) {
    try {
      const data = await (await fetch(`${cdpUrl(site)}/json/version`)).json();
      if (data.webSocketDebuggerUrl) {
        wsUrl = data.webSocketDebuggerUrl;
        break;
      }
    } catch {
      /* not ready */
    }
    await sleep(500);
  }
  if (!wsUrl) throw new Error(`no webSocketDebuggerUrl from ${cdpUrl(site)}/json/version`);
  const browser = await chromium.connectOverCDP(wsUrl);
  const ctx = browser.contexts()[0] ?? (await browser.newContext());
  return { browser, ctx };
}

/** Kill the site's Chrome by its SPECIFIC pid (TERM then KILL). Never pkill -f. */
export async function teardown(site) {
  const pid = chromePidOnPort(site);
  if (!pid) return { killed: false, reason: "no listener" };
  try {
    process.kill(pid, "SIGTERM");
  } catch {
    return { killed: false, reason: "already gone" };
  }
  await sleep(1500);
  if (chromePidOnPort(site) === pid) {
    try {
      process.kill(pid, "SIGKILL");
    } catch {
      /* gone */
    }
    await sleep(500);
  }
  return { killed: chromePidOnPort(site) !== pid, pid };
}

// ── supervised-run helpers ──────────────────────────────────────────────────────────────────────

/**
 * Poll an authenticated probe endpoint with the context's cookies until the human finishes logging
 * in — never navigates a visible tab (a half-typed login form must not be reloaded).
 *   ok(res) → truthy when authenticated (e.g. res.ok() && body.success).
 */
export async function waitForLogin(ctx, probeUrl, ok, { timeoutMs = 10 * 60_000, label = probeUrl } = {}) {
  const t0 = Date.now();
  process.stdout.write(`waiting for login: ${label}`);
  while (Date.now() - t0 < timeoutMs) {
    try {
      const res = await ctx.request.get(probeUrl, { maxRedirects: 0 });
      const verdict = await ok(res);
      if (verdict) {
        console.log("\n  ✓ session live");
        return verdict;
      }
    } catch {
      /* not yet */
    }
    process.stdout.write(".");
    await sleep(3000);
  }
  throw new Error(`timed out waiting for login at ${label}`);
}

/**
 * Identity-assertion preflight — call BEFORE any mutating step that creates an account-owned
 * resource. `actual` is site-specific (caller extracts it); this enforces the doctrine uniformly.
 * Mirrors the GitHub-Owner-Per-Path principle in the browser world.
 */
export function assertIdentity(actual, expected, resource) {
  if (!actual || actual !== expected) {
    // Render the extracted value VERBATIM (JSON-encoded: `"459ecs"` / `null`) — no invented tokens.
    throw new Error(
      `identity preflight FAILED: signed-in identity is ${JSON.stringify(actual)} but "${expected}" must own ${resource}. ` +
        "Re-log the automation Chrome into the right account, then re-run.",
    );
  }
}

/** Dismiss common cookie/consent overlays (OneTrust & friends) that swallow clicks. */
export async function dismissConsent(page) {
  const clicked = await page
    .evaluate(() => {
      const b = [...document.querySelectorAll("button")].find((x) =>
        /^(reject all|allow all|accept all|decline)$/i.test(x.textContent.trim()),
      );
      if (b) {
        b.click();
        return b.textContent.trim();
      }
      return null;
    })
    .catch(() => null);
  if (clicked) await sleep(1200);
  return clicked;
}

// ── screenshots (breadcrumbs for the supervising human/agent) ───────────────────────────────────

export const DEFAULT_SHOT_DIR = "/tmp/web-forge";

/** Breadcrumb screenshot. NEVER call on a secret-reveal page — DOM-extract instead. */
export async function shot(page, name, dir = DEFAULT_SHOT_DIR) {
  mkdirSync(dir, { recursive: true });
  const file = join(dir, `${Date.now()}-${name}.png`);
  await page.screenshot({ path: file, fullPage: false }).catch(() => {});
  console.log(`  [shot] ${file}`);
  return file;
}

/** End-of-run hygiene: purge every breadcrumb (some may show near-secret state). */
export function purgeShots(dir = DEFAULT_SHOT_DIR) {
  if (!existsSync(dir)) return 0;
  const files = readdirSync(dir).filter((f) => f.endsWith(".png"));
  for (const f of files) rmSync(join(dir, f), { force: true });
  return files.length;
}

// ── SCS vault sinks (values ride pipes, never argv/stdout/transcript) ───────────────────────────

export function vaultSet(scope, path, value) {
  return new Promise((resolve, reject) => {
    const p = spawn(VAULT_BIN, ["set", "--stdin", scope, path], { stdio: ["pipe", "inherit", "inherit"] });
    p.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`vault set ${scope} ${path} → exit ${code}`))));
    p.stdin.write(value);
    p.stdin.end();
  });
}

export function vaultGet(scope, path) {
  return new Promise((resolve, reject) => {
    const p = spawn(VAULT_BIN, ["get", scope, path], { stdio: ["ignore", "pipe", "inherit"] });
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.on("exit", (code) => (code === 0 ? resolve(out.trim()) : reject(new Error(`vault get ${scope} ${path} → exit ${code}`))));
  });
}

/** Minimal JSON API caller (bearer-style headers) for the idempotent-bootstrap half of a forge. */
export function apiCaller(baseUrl, headers) {
  return async (method, path, body) => {
    const opts = { method, headers: { "content-type": "application/json", ...headers } };
    if (body !== undefined) opts.body = JSON.stringify(body);
    const res = await fetch(`${baseUrl}${path}`, opts);
    const json = await res.json().catch(() => ({ success: false, errors: [{ message: `HTTP ${res.status} non-JSON` }] }));
    return { status: res.status, ...json };
  };
}
