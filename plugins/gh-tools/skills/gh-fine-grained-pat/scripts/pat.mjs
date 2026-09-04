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
//   patch-password --account A  re-store A's gated password (passkey KEPT); fixes a missed register dialog [--force] [--totp]
//   agent start|stop|status  memory-only session agent: one Touch-ID unlock lasts the session
//   accounts              list accounts provisioned for autonomous web-auth
//   quit                  kill the debug Chrome (specific PID; no pkill -f)
//
// AUTONOMOUS: GH_PAT_AUTONOMOUS=1 + a resolved account (--account | repo host-alias
// | spec owner) lets create/rotate clear GitHub sudo mode via the gated credential.
// SECURITY: a token value is NEVER printed to stdout/chat. `create` writes it to
// a 0600 file (--out) or pipes it into `vault set` (--vault scope:dot.path).

import { existsSync, mkdirSync, readFileSync, writeFileSync, chmodSync } from "node:fs";
import { spawn, spawnSync, execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { homedir } from "node:os";
import {
  profileDir,
  cdpUrl,
  launchChrome,
  connect,
  gotoSettings,
  isAuthedViaRequest,
  loggedInLoginViaRequest,
  chromePidOnPort,
  teardown,
  ensureDirs,
} from "./browser.mjs";

const sleep = (msec) => new Promise((r) => setTimeout(r, msec));
import { createToken, listTokens, inspectToken, deleteToken } from "./form.mjs";
import { resolveAccount, addProvisioned, listProvisioned, isProvisioned, vaultItemName } from "./identity.mjs";
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
  // GOTCHA #19 — an over-long description is rejected by the SERVER, silently.
  // GitHub's description textarea sets no maxlength (maxLength === -1), so the
  // browser types the whole thing happily; the POST is then dropped and the
  // form re-renders with its defaults and NO error text anywhere on the page.
  // The failure is indistinguishable from "the form was filled wrong", and it
  // cost several rounds of chasing the owner and expiration controls, both of
  // which a trace had already proven correct at submit time. Measured
  // 2026-09-04: 4272 chars failed repeatedly, 191 chars succeeded immediately
  // with every other field identical. Fail here, before the browser opens.
  if ((s.description ?? "").length > 1000)
    die(
      `spec.description is ${s.description.length} chars; GitHub silently drops the submission when it is too long ` +
        `(no error is shown and no token is created). Keep it under ~1000 chars and move long-form rationale to spec.notes.`,
    );
  const exp = s.expiration ?? 30;
  // 366 is the lifetime cap an ORGANISATION resource owner can impose; when it
  // does, GitHub removes "No expiration" from the menu entirely (measured
  // 2026-09-04 against doorward-systems), so org-owned specs need this value.
  const okExp = exp === "none" || [7, 30, 60, 90, 366].includes(exp) || /^\d{4}-\d{2}-\d{2}$/.test(exp);
  if (!okExp) die(`spec.expiration must be 7|30|60|90|366 | "YYYY-MM-DD" | "none" (got ${JSON.stringify(exp)})`);
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
  // `--account` used to be honoured by create/login/quit ONLY. list, inspect and
  // delete never set GH_PAT_ACCOUNT, so they silently read the SHARED profile no
  // matter which account you named — and then labelled the result with the
  // account you asked for. Measured 2026-09-04: `list --account terrylica`
  // printed "(no fine-grained tokens)" while reading a profile signed in as
  // work, whose token list genuinely is empty. A true sentence about the wrong
  // account is indistinguishable from a fact about the right one, and it also
  // disarmed the identity guard below (no GH_PAT_ACCOUNT ⇒ nothing to compare).
  // Resolve here, at the one chokepoint every session-using verb passes through,
  // and BEFORE launchChrome() — profileDir()/port() are derived from it.
  if (!process.env.GH_PAT_ACCOUNT) {
    const f = flag("--account");
    const { account } = resolveAccount({ account: typeof f === "string" ? f : undefined });
    if (account) process.env.GH_PAT_ACCOUNT = account;
  }
  await launchChrome();
  const { browser, ctx } = await connect();
  if (requireAuth && !(await isAuthedViaRequest(ctx))) {
    // Autonomous FULL login (extends ADR 2026-06-26 beyond sudo-only): when the
    // session cookie has expired, navigating to settings redirects to /login,
    // whose "Sign in with a passkey" button is already covered by autosudo's
    // tryPasskey regex. One Touch-ID unlock of the gated blob re-arms the
    // profile cookie; the manual `pat login` path remains the fallback.
    // (Found live 2026-07-19: expired cookie + GH_PAT_AUTONOMOUS=1 died here
    // without ever reaching the autonomous machinery.)
    const account = process.env.GH_PAT_ACCOUNT;
    if (process.env.GH_PAT_AUTONOMOUS === "1" && account) {
      console.error(`• session expired — attempting autonomous login as '${account}'…`);
      const loginPage = await gotoSettings(ctx);
      try {
        const { autonomousSudo } = await import("./autosudo.mjs");
        await autonomousSudo(loginPage, account);
      } catch (e) {
        console.error(`autonomous login failed (${e.message})`);
      }
      if (await isAuthedViaRequest(ctx)) {
        console.error(`✓ autonomous login (${account})`);
        return { browser, ctx, page: await gotoSettings(ctx) };
      }
    }
    await browser.close();
    die("not logged in. Run `node scripts/pat.mjs login`, sign into GitHub in the Chrome window, then retry.");
  }
  await assertProfileIdentity(ctx, browser);
  const page = await gotoSettings(ctx);
  return { browser, ctx, page };
}

// GOTCHA #12 — the profile↔account binding is DERIVED, never verified.
// browser.mjs picks the profile dir from GH_PAT_ACCOUNT; nothing has ever
// checked that the session inside it belongs to that account. Assert it before
// any read or write, because both directions are dangerous: a `create` mints on
// the wrong account, and `list`/`inspect` report the wrong account's tokens as
// this account's (a false "(no fine-grained tokens)" is how this was found —
// 2026-09-04, shared profile signed in as work while resolving terrylica).
// Escape hatch is deliberately explicit and named, never silent.
async function assertProfileIdentity(ctx, browser) {
  const want = process.env.GH_PAT_ACCOUNT;
  if (!want || process.env.GH_PAT_SKIP_IDENTITY_CHECK === "1") return;
  const have = await loggedInLoginViaRequest(ctx);
  if (have === null) {
    await browser.close();
    die(
      `could not read the signed-in GitHub login from profile\n  ${profileDir()}\n` +
        `That is INCOMPLETE, not a match — refusing to act as '${want}' on an unidentified session.\n` +
        `Fix: node scripts/pat.mjs login --account ${want}`,
    );
  }
  if (have.toLowerCase() !== want.toLowerCase()) {
    await browser.close();
    die(
      `profile/account MISMATCH — refusing to act.\n` +
        `  resolved account : ${want}\n` +
        `  profile          : ${profileDir()}\n` +
        `  signed in as     : ${have}\n` +
        `A token would have been minted on '${have}', and list/inspect would report ${have}'s\n` +
        `tokens as ${want}'s. Fix one of:\n` +
        `  • sign that profile out of '${have}', then: node scripts/pat.mjs login --account ${want}\n` +
        `  • use an isolated profile: GH_PAT_PROFILE_DIR=~/.local/share/gh-pat-automation/profile-${want} \\\n` +
        `      GH_PAT_CDP_PORT=<free-port> node scripts/pat.mjs login --account ${want}\n` +
        `Override (NOT recommended): GH_PAT_SKIP_IDENTITY_CHECK=1`,
    );
  }
}

async function cmdLogin() {
  const a = flag("--account");
  if (a && a !== true) process.env.GH_PAT_ACCOUNT = a;
  ensureDirs();
  const { reused } = await launchChrome();
  const { browser, ctx } = await connect();
  if (await isAuthedViaRequest(ctx)) {
    // GOTCHA #12: "already authenticated" must name WHO. Short-circuiting on a
    // session that belongs to a different login is how the wrong account got
    // used for a mint (2026-09-04). A mismatch here is the operator's cue to
    // sign out, so say so instead of declaring "Ready."
    const who = await loggedInLoginViaRequest(ctx);
    const want = process.env.GH_PAT_ACCOUNT;
    if (want && !who) {
      await browser.close();
      die(
        `a session exists in profile ${profileDir()} but its signed-in login could not be read.\n` +
          `That is INCOMPLETE, not a match — refusing to declare '${want}' ready.`,
      );
    }
    if (want && who.toLowerCase() !== want.toLowerCase()) {
      await browser.close();
      die(
        `profile ${profileDir()} is already signed in as '${who}', not '${want}'.\n` +
          `\`login\` will not silently accept the wrong identity. Sign out of '${who}' in the\n` +
          `Chrome window and re-run, or give '${want}' its own profile:\n` +
          `  GH_PAT_PROFILE_DIR=~/.local/share/gh-pat-automation/profile-${want} \\\n` +
          `  GH_PAT_CDP_PORT=<free-port> node scripts/pat.mjs login --account ${want}`,
      );
    }
    // No invented token when the login is unreadable and no account was named:
    // absent is a state — render nothing rather than a placeholder.
    console.log(
      who
        ? `✓ already authenticated as '${who}' (profile reused: ${reused}). Ready.`
        : `✓ already authenticated (profile reused: ${reused}). Ready.`,
    );
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
  // Honour --account so `doctor --account <a>` reports THAT account's profile
  // and can surface a profile/account mismatch (GOTCHA #12).
  const acct = flag("--account");
  if (acct && acct !== true) process.env.GH_PAT_ACCOUNT = acct;
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
      const authed = await isAuthedViaRequest(ctx);
      rows.push(["auth", authed ? "authenticated ✓" : "NOT logged in (run login)"]);
      // "authenticated" says a session exists, not WHOSE. Naming the login is
      // the whole point: a profile signed in as the wrong account passed every
      // check here on 2026-09-04 (GOTCHA #12 in browser.mjs).
      if (authed) {
        const who = await loggedInLoginViaRequest(ctx);
        const want = process.env.GH_PAT_ACCOUNT;
        if (!who) {
          // An unreadable identity is an instrument failure, not a value.
          rows.push(["signed in as", "could not read meta[name=user-login] — INCOMPLETE, not a match"]);
        } else if (want && who.toLowerCase() !== want.toLowerCase()) {
          rows.push(["signed in as", `${who}  🔴 MISMATCH — resolved account is '${want}'`]);
        } else {
          rows.push(["signed in as", who]);
        }
      }
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

/** Is this login an Organization rather than a User? Unauthenticated public API. */
async function isOrganisationLogin(login) {
  try {
    const r = await fetch(`https://api.github.com/users/${encodeURIComponent(login)}`, {
      headers: { accept: "application/vnd.github+json", "user-agent": "gh-fine-grained-pat" },
    });
    if (!r.ok) return false; // unknown ⇒ keep the account ⇒ the guard still applies
    return (await r.json()).type === "Organization";
  } catch {
    return false; // fail CLOSED: an unreachable API must not silently disarm the guard
  }
}

async function doCreate({ replace, rotate }) {
  const spec = loadSpec(args[1]);
  if (rotate && !flag("--vault") && !flag("--out"))
    die("rotate needs a sink: --vault <scope>:<dot.path> (recommended) or --out <file>");
  // Resolve the account BEFORE launching the browser so the per-account
  // profile/port is selected (terrylica/shared keeps the original).
  const { account, source } = resolveAccount({ account: flag("--account"), owner: spec.owner });
  // `spec.owner` is a RESOURCE OWNER and may be an ORGANISATION — and nobody is
  // ever *signed in as* an organisation. Taking it as the account selects a
  // profile that cannot exist (`profile-<org>`, hence "not logged in") and trips
  // the profile/account identity guard for a reason that is not a real mismatch.
  // `--account` and the origin host-alias name a real login, so both stay
  // authoritative; only the spec-owner fallback is screened. Screening fails
  // CLOSED — an unreachable api.github.com leaves the value in force.
  let resolvedAccount = account;
  if (account && source === "spec-owner" && (await isOrganisationLogin(account))) {
    console.error(`• spec owner '${account}' is an organisation, not a login — using the signed-in account instead.`);
    console.error(`  Pass --account <login> to name the GitHub user whose token this is.`);
    resolvedAccount = null;
  }
  if (resolvedAccount) process.env.GH_PAT_ACCOUNT = resolvedAccount;
  const { browser, ctx, page } = await session();
  try {
    // assertProfileIdentity() can only compare when an account was resolved. A
    // MINT is the one operation that must never run against an unverified
    // identity — measured 2026-09-04, `create` from a non-repo cwd declined the
    // organisation spec-owner, fell through with no account, and went on to mint
    // against whoever happened to be signed in (`work`), stopped only by an
    // unrelated sudo prompt. Name the identity or refuse.
    const signedInAs = await loggedInLoginViaRequest(ctx);
    if (!signedInAs) die("could not read the signed-in GitHub login — refusing to mint against an unidentified session.");
    if (!process.env.GH_PAT_ACCOUNT)
      die(
        `no account resolved, and this profile is signed in as '${signedInAs}'.\n` +
          `Refusing to mint a credential against an unconfirmed identity.\n` +
          `Re-run naming it explicitly:  --account ${signedInAs}`,
      );
    console.error(`• minting as GitHub user '${signedInAs}'; resource owner '${spec.owner ?? signedInAs}'`);
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

// patch-password --account <a>: re-store the gated password for an already-
// registered account WITHOUT re-capturing a passkey (which would leave a
// duplicate passkey on GitHub). Reads the blob once (one Touch ID), preserves
// the passkey, re-prompts the password (+ optional TOTP), re-stores. Idempotent:
// skips if a password is already set unless --force. Secrets never reach chat.
async function cmdPatchPassword() {
  const account = flag("--account");
  if (!account || account === true) die("usage: patch-password --account <login> [--force] [--totp]");
  let blob;
  try {
    blob = JSON.parse(execFileSync("vault", ["get", "--gated", vaultItemName(account)], { encoding: "utf8" }));
  } catch (e) {
    die(`could not read gated blob for ${account} (Touch ID denied, or not provisioned — run \`register --account ${account}\` first): ${e.message}`);
  }
  if (!blob.passkey?.credentialId) die(`gated blob for ${account} has no passkey — run \`register --account ${account}\` instead`);
  if (!has("--force") && typeof blob.password === "string" && blob.password.length >= 6) {
    console.log(`✓ ${account}: password already set (${blob.password.length} chars), passkey present. Nothing to do (use --force to overwrite).`);
    return;
  }
  const pw = promptSecret(`GitHub password for '${account}' (stored gated; password+TOTP fallback). Type carefully:`);
  if (!pw) die("no password entered — blob unchanged");
  blob.password = pw;
  if (has("--totp")) {
    const seed = promptSecret(`TOTP base32 seed for '${account}' (blank to leave unchanged):`);
    if (seed) blob.totpSeed = seed;
  }
  storeGatedBlob(account, blob);
  console.log(`✓ ${account}: password updated (${pw.length} chars), passkey kept, totp ${blob.totpSeed ? "set" : "none"}.`);
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
  "patch-password": cmdPatchPassword,
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
