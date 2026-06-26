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
//   quit                  kill the debug Chrome (specific PID; no pkill -f)
//
// SECURITY: a token value is NEVER printed to stdout/chat. `create` writes it to
// a 0600 file (--out) or pipes it into `vault set` (--vault scope:dot.path).

import { existsSync, mkdirSync, readFileSync, writeFileSync, chmodSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname } from "node:path";
import {
  PROFILE_DIR,
  DEBUG_DIR,
  CDP_URL,
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
  console.log(`The page will NOT reload while you type. Session persists in:\n  ${PROFILE_DIR}`);
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
  rows.push(["profile", existsSync(PROFILE_DIR) ? PROFILE_DIR : `absent (run login)`]);
  const pid = chromePidOnPort();
  rows.push(["cdp", pid ? `up (pid ${pid}, ${CDP_URL})` : "not running"]);
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
    console.error(`• ${rotate ? "rotating" : "creating"} '${spec.name}'…`);
    const token = await createToken(page, spec);
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
  const r = await teardown();
  console.log(r.killed ? `✓ Chrome (pid ${r.pid}) terminated` : `nothing to terminate (${r.reason ?? "no pid"})`);
}

function help() {
  console.log(readFileSync(new URL("./pat.mjs", import.meta.url), "utf8").split("\n").slice(2, 19).join("\n").replace(/^\/\/ ?/gm, ""));
}

const table = {
  login: cmdLogin,
  doctor: cmdDoctor,
  create: cmdCreate,
  rotate: cmdRotate,
  list: cmdList,
  inspect: cmdInspect,
  delete: cmdDelete,
  quit: cmdQuit,
};

const fn = table[cmd];
if (!fn) {
  help();
  process.exit(cmd ? 1 : 0);
}
fn().catch((e) => {
  console.error(`pat: ${e.message}`);
  process.exit(1);
});
