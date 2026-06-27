#!/usr/bin/env node
// pat.mjs — engine CLI for declarative, browser-automated GitHub fine-grained PATs.
//
// There is NO API to create fine-grained PATs (web UI only), so this drives the
// UI over CDP. Login is one-time: a persistent Chrome profile keeps the session.
//
// COMMANDS
//   login                 launch visible Chrome; you log into GitHub once
//   doctor                health check (runtime, chrome, profile, auth)
//   create <spec.json>    create a token from a spec  [--out FILE | --vault S:dot] [--replace] [--keep-open]
//   rotate <spec.json>    revoke the same-named token, create a replacement, store it (--vault | --out required)
//   list                  list fine-grained tokens (id + name)
//   inspect <name>        read back a token's settings (verification)
//   delete <name>         revoke a token
//   register --account A  one-time: capture a passkey + password/TOTP for account A into the gated vault (autonomous sudo)
//   agent start|stop|status  memory-only session agent: one Touch-ID unlock lasts the session
//   accounts              list accounts provisioned for autonomous web-auth
//   quit                  kill the debug Chrome (specific PID; no pkill -f)
//
// AUTONOMOUS: GH_PAT_AUTONOMOUS=1 + a resolved account (--account | repo host-alias
// | spec owner) lets create/rotate clear GitHub sudo mode via the gated credential.
// SECURITY: a token value is NEVER printed to stdout/chat. `create` writes it to
// a 0600 file (--out) or pipes it into `vault set` (--vault scope:dot.path).

import { existsSync, mkdirSync, readFileSync, writeFileSync, chmodSync } from "node:fs";
import { spawn, spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { homedir } from "node:os";
import {
  profileDir,
  cdpUrl,
  launchChrome,
  connect,
  gotoSettings,
  isAuthedViaRequest,
  chromePidOnPort,
  teardown,
  ensureDirs,
} from "./browser.mjs";

const sleep = (msec) => new Promise((r) => setTimeout(r, msec));
import { createToken, listTokens, inspectToken, deleteToken } from "./form.mjs";
import { resolveAccount, addProvisioned, listProvisioned, isProvisioned } from "./identity.mjs";
import { agentStatus, agentStop, agentRunning, AGENT_SOCK } from "./webauth-agent.mjs";
import { openWebAuthn, mountAuthenticator, getCredentials, serializeCredential, removeAuthenticator } from "./webauthn.mjs";

const args = process.argv.slice(2);
const cmd = args[0];
const flag = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? (args[i + 1] ?? true) : undefined;
};
const has = (name) => args.includes(name);
const die = (m) => {
  console.error(`pat: ${m}`);
  process.exit(1);
};

function loadSpec(path) {
  if (!path || !existsSync(path)) die(`spec file not found: ${path}`);
  let spec;
  try {
    spec = JSON.parse(readFileSync(path, "utf8"));
  } catch (e) {
    die(`spec is not valid JSON: ${e.message}`);
  }
  validateSpec(spec);
  return spec;
}

// Lightweight structural validation (the JSON Schema is the formal SSoT).
function validateSpec(s) {
  if (!s.name || typeof s.name !== "string") die("spec.name (string) is required");
  if (s.name.length > 40) die("spec.name exceeds 40 chars");
  const exp = s.expiration ?? 30;
  const okExp = exp === "none" || [7, 30, 60, 90].includes(exp) || /^\d{4}-\d{2}-\d{2}$/.test(exp);
  if (!okExp) die(`spec.expiration must be 7|30|60|90 | "YYYY-MM-DD" | "none" (got ${JSON.stringify(exp)})`);
  const ra = s.repositoryAccess;
  if (ra) {
    if (!["public", "all", "selected"].includes(ra.mode)) die(`spec.repositoryAccess.mode invalid: ${ra.mode}`);
    if (ra.mode === "selected" && !(Array.isArray(ra.repos) && ra.repos.length))
      die("repositoryAccess.mode 'selected' requires a non-empty repos[]");
    for (const r of ra.repos ?? []) if (!/^[^/]+\/[^/]+$/.test(r)) die(`repo must be owner/name: ${r}`);
  }
  for (const grp of ["repository", "account"]) {
    const o = s.permissions?.[grp] ?? {};
    for (const [k, v] of Object.entries(o)) {
      if (!["read", "write"].includes(v)) die(`permission '${k}' must be 'read' or 'write' (got ${v})`);
      if (/^metadata$/i.test(k)) die("do not list 'Metadata' — it is auto-required read-only");
    }
  }
}

function writeSecure(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, value, { mode: 0o600 });
  chmodSync(path, 0o600);
}

function masked(token) {
  return `${token.slice(0, 11)}… (${token.length} chars)`;
}

// Connect + ensure authenticated for commands that need a session.
async function session({ requireAuth = true } = {}) {
  await launchChrome();
  const { browser, ctx } = await connect();
  if (requireAuth && !(await isAuthedViaRequest(ctx))) {
    await browser.close();
    die("not logged in. Run `node scripts/pat.mjs login`, sign into GitHub in the Chrome window, then retry.");
  }
  const page = await gotoSettings(ctx);
  return { browser, ctx, page };
}

async function cmdLogin() {
  const a = flag("--account");
  if (a && a !== true) process.env.GH_PAT_ACCOUNT = a;
  ensureDirs();
  const { reused } = await launchChrome();
  const { browser, ctx } = await connect();
  if (await isAuthedViaRequest(ctx)) {
    console.log(`✓ already authenticated (profile reused: ${reused}). Ready.`);
    await browser.close();
    return;
  }
  // Bring the visible tab to the sign-in page ONCE, then never touch it again —
  // auth is polled via the cookie store, so your half-typed form is never reloaded.
  await gotoSettings(ctx);
  console.log(`A Chrome window is open at GitHub. Log in at your own pace (incl. 2FA).`);
  console.log(`The page will NOT reload while you type. Session persists in:\n  ${profileDir()}`);
  console.log("Waiting for sign-in (up to 10 min)…");
  for (let i = 0; i < 120; i++) {
    await sleep(5000);
    if (await isAuthedViaRequest(ctx)) {
      console.log("✓ authenticated. You won't need to log in again until the cookie expires.");
      await browser.close();
      return;
    }
  }
  await browser.close();
  die("timed out waiting for login. Re-run `node scripts/pat.mjs login`.");
}

async function cmdDoctor() {
  const rows = [];
  rows.push(["node", `${process.version}`]);
  let pw = "MISSING";
  try {
    const m = await import("playwright-core");
    pw = typeof m.chromium === "object" ? "ok" : "unexpected";
  } catch {
    /* missing */
  }
  rows.push(["playwright-core", pw]);
  rows.push(["chrome", existsSync("/Applications/Google Chrome.app") ? "ok" : "MISSING"]);
  rows.push(["profile", existsSync(profileDir()) ? profileDir() : `absent (run login)`]);
  const pid = chromePidOnPort();
  rows.push(["cdp", pid ? `up (pid ${pid}, ${cdpUrl()})` : "not running"]);
  if (pid) {
    try {
      const { browser, ctx } = await connect();
      rows.push(["auth", (await isAuthedViaRequest(ctx)) ? "authenticated ✓" : "NOT logged in (run login)"]);
      await browser.close();
    } catch (e) {
      rows.push(["auth", `connect failed: ${e.message}`]);
    }
  } else {
    rows.push(["auth", "unknown (chrome not running)"]);
  }
  for (const [k, v] of rows) console.log(`  ${k.padEnd(16)}${v}`);
}

// Secure token sink — NEVER prints the value (only a masked confirmation).
function emitToken(token, spec, verb) {
  const out = flag("--out");
  const vault = flag("--vault");
  if (vault) {
    const [scope, dot] = String(vault).split(":");
    if (!scope || !dot) die("--vault expects <scope>:<dot.path>");
    const r = spawnSync("vault", ["set", scope, dot, token], { stdio: ["ignore", "inherit", "inherit"] });
    if (r.status !== 0) die("vault set failed");
    console.log(`✓ '${spec.name}' ${verb} → vault ${scope}.${dot}  ${masked(token)}`);
  } else {
    const path = out || `/tmp/.gh-pat-${spec.name}.value`;
    writeSecure(path, token);
    console.log(`✓ '${spec.name}' ${verb} → ${path} (0600)  ${masked(token)}`);
    console.log(`  next: vault set <scope> <dot.path> "$(cat ${path})" && shred -u ${path}`);
  }
}

async function doCreate({ replace, rotate }) {
  const spec = loadSpec(args[1]);
  if (rotate && !flag("--vault") && !flag("--out"))
    die("rotate needs a sink: --vault <scope>:<dot.path> (recommended) or --out <file>");
  // Resolve the account BEFORE launching the browser so the per-account
  // profile/port is selected (terrylica/shared keeps the original).
  const { account, source } = resolveAccount({ account: flag("--account"), owner: spec.owner });
  if (account) process.env.GH_PAT_ACCOUNT = account;
  const { browser, page } = await session();
  try {
    const existing = (await listTokens(page)).find((t) => t.name === spec.name);
    if (existing) {
      if (!replace) die(`a token named '${spec.name}' already exists (id ${existing.id}). Use --replace (or the 'rotate' verb) to recreate.`);
      console.error(`• revoking existing '${spec.name}' (id ${existing.id})`);
      await deleteToken(page, spec.name);
    } else if (rotate) {
      console.error(`• no existing '${spec.name}' — creating fresh`);
    }
    if (process.env.GH_PAT_AUTONOMOUS === "1") console.error(`• account: ${account ?? "(logged-in)"} [${source}]`);
    console.error(`• ${rotate ? "rotating" : "creating"} '${spec.name}'…`);
    const token = await createToken(page, spec, { account });
    emitToken(token, spec, rotate ? "rotated" : "created");
  } finally {
    if (!has("--keep-open")) await browser.close();
  }
}

const cmdCreate = () => doCreate({ replace: has("--replace"), rotate: false });
const cmdRotate = () => doCreate({ replace: true, rotate: true });

async function cmdList() {
  const { browser, page } = await session();
  try {
    const toks = await listTokens(page);
    if (!toks.length) console.log("(no fine-grained tokens)");
    for (const t of toks) console.log(`  ${t.id.padEnd(12)}${t.name}`);
  } finally {
    await browser.close();
  }
}

async function cmdInspect() {
  const name = args[1];
  if (!name) die("usage: inspect <name>");
  const { browser, page } = await session();
  try {
    const info = await inspectToken(page, name);
    if (!info.found) return void console.log(`(no token named '${name}')`);
    console.log(`token:   ${name} (id ${info.id})`);
    console.log(`repos:   ${info.repos.join(", ") || "(none listed)"}`);
    const expMatch = info.text.match(/(No expiration|never expires?|Expires on [A-Za-z0-9 ,]+)/i);
    console.log(`expiry:  ${expMatch ? expMatch[1] : "(see detail page)"}`);
  } finally {
    await browser.close();
  }
}

async function cmdDelete() {
  const name = args[1];
  if (!name) die("usage: delete <name>");
  const { browser, page } = await session();
  try {
    const ok = await deleteToken(page, name);
    console.log(ok ? `✓ deleted '${name}'` : `could not delete '${name}' (not found?)`);
  } finally {
    await browser.close();
  }
}

async function cmdQuit() {
  const a = flag("--account");
  if (a && a !== true) process.env.GH_PAT_ACCOUNT = a;
  const r = await teardown();
  console.log(r.killed ? `✓ Chrome (pid ${r.pid}) terminated` : `nothing to terminate (${r.reason ?? "no pid"})`);
}

// ---- autonomous web-auth (ADR 2026-06-26) ----------------------------------
const TOUCHID_BIN = join(homedir(), ".claude", "tools", "vault", "touchid", "vault-touchid");
function promptSecret(label) {
  const r = spawnSync(
    "osascript",
    ["-e", `display dialog ${JSON.stringify(label)} default answer "" with hidden answer with title "pat register"`, "-e", "text returned of result"],
    { encoding: "utf8" },
  );
  return r.status === 0 ? r.stdout.replace(/\n$/, "") : "";
}
function storeGatedBlob(account, blob) {
  if (!existsSync(TOUCHID_BIN)) die(`vault-touchid not built at ${TOUCHID_BIN} (compile it; see SCS tiered ADR)`);
  const r = spawnSync(TOUCHID_BIN, ["set", `vault-gated-github-web-${account}`, process.env.USER ?? "vault"], {
    input: JSON.stringify(blob),
  });
  if (r.status !== 0) die("gated store failed (vault-touchid set)");
}

// register --account <a>: one-time ceremony — capture a passkey via a virtual
// authenticator + password/TOTP, store as ONE gated blob. Touch-ID gated tier.
async function cmdRegister() {
  const account = flag("--account");
  if (!account || account === true) die("usage: register --account <login>");
  process.env.GH_PAT_ACCOUNT = account; // per-account profile/port
  const { browser, ctx, page } = await session();
  const client = await openWebAuthn(page);
  const authenticatorId = await mountAuthenticator(client);
  try {
    await page.goto("https://github.com/settings/security", { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(1500);
    console.error(`A Chrome window is open at GitHub → Account security for '${account}'.`);
    console.error('If "Confirm access" (sudo) appears, complete it. Then click "Add passkey" (I will also try to);');
    console.error("complete any GitHub prompt — the virtual authenticator captures the new passkey.");
    console.error("Waiting up to 8 min for a passkey credential to appear…");
    // Best-effort: click "Add passkey" ourselves (the operator can also click it).
    try {
      await page.getByRole("button", { name: /^Add passkey$/i }).first().click({ timeout: 4000 });
    } catch {
      try {
        await page.getByRole("link", { name: /^Add passkey$/i }).first().click({ timeout: 4000 });
      } catch {
        /* operator will click */
      }
    }
    let cred = null;
    for (let i = 0; i < 96 && !cred; i++) {
      await page.waitForTimeout(5000);
      // keep nudging the dialog's confirm button if present
      await page.evaluate(() => {
        const b = [...document.querySelectorAll("button")].find((x) => x.offsetParent !== null && /^Add passkey$/i.test((x.textContent || "").trim()));
        if (b) b.click();
      }).catch(() => {});
      const creds = await getCredentials(client, authenticatorId);
      if (creds.length) cred = serializeCredential(creds[0]);
    }
    if (!cred) die("no passkey credential captured — re-run register (complete the Add-passkey prompt in the window)");
    console.error(`✓ captured passkey (rpId ${cred.rpId})`);
    const password = promptSecret(`GitHub password for '${account}' (stored gated; for the password+TOTP fallback):`);
    const totpSeed = promptSecret(`GitHub TOTP base32 seed for '${account}' (from 2FA 'set up using an app' → text code):`);
    storeGatedBlob(account, { passkey: cred, password, totpSeed });
    addProvisioned(account);
    console.log(`✓ '${account}' provisioned → gated vault item github-web-${account} (Touch-ID required to use). Registry updated.`);
    console.log(`  NOTE: GitHub often invalidates the session once right after adding a passkey. If a later run`);
    console.log(`  shows "not logged in", run \`pat login --account ${account}\` ONE more time — it persists after that.`);
  } finally {
    await removeAuthenticator(client, authenticatorId);
    void ctx;
    if (!has("--keep-open")) await browser.close();
  }
}

async function cmdAgent() {
  const sub = args[1] ?? "status";
  if (sub === "start") {
    if (agentRunning()) return void console.log(`agent already running (${AGENT_SOCK})`);
    const child = spawn(process.execPath, [new URL("./webauth-agent.mjs", import.meta.url).pathname, "serve"], {
      detached: true,
      stdio: "ignore",
    });
    child.unref();
    return void console.log(`✓ webauth-agent started (${AGENT_SOCK}) — one Touch-ID unlock now lasts the session`);
  }
  if (sub === "stop") {
    const r = await agentStop();
    return void console.log(r.ok ? "✓ agent stopped" : "no agent running");
  }
  const r = await agentStatus();
  console.log(r.ok ? `agent up (pid ${r.pid}); unlocked: ${r.accounts.join(", ") || "(none)"}` : "agent not running");
}

function cmdAccounts() {
  const prov = listProvisioned();
  console.log(prov.length ? `provisioned (autonomous web-auth): ${prov.join(", ")}` : "no accounts provisioned (run: pat register --account <login>)");
  void isProvisioned;
}

function help() {
  const lines = readFileSync(new URL("./pat.mjs", import.meta.url), "utf8").split("\n");
  const out = [];
  for (let i = 1; i < lines.length && lines[i].startsWith("//"); i++) out.push(lines[i].replace(/^\/\/ ?/, ""));
  console.log(out.join("\n"));
}

const table = {
  login: cmdLogin,
  doctor: cmdDoctor,
  create: cmdCreate,
  rotate: cmdRotate,
  list: cmdList,
  inspect: cmdInspect,
  delete: cmdDelete,
  register: cmdRegister,
  agent: cmdAgent,
  accounts: cmdAccounts,
  quit: cmdQuit,
};

const fn = table[cmd];
if (!fn) {
  help();
  process.exit(cmd ? 1 : 0);
}
Promise.resolve()
  .then(fn)
  .catch((e) => {
    console.error(`pat: ${e.message}`);
    process.exit(1);
  });
