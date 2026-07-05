#!/usr/bin/env bun
/**
 * po-inbox — RECEIVE side of the private Pushover plugin (Bun/TypeScript).
 *
 * WHY THIS EXISTS
 *   pushover_core.ts only SENDS. Its audit log (po-audit.jsonl) records outbound
 *   messages only — it can never show what ARRIVED (e.g. the `noip-ddns`
 *   self-healer alerts that land in the native Pushover.app). To let a Claude Code
 *   session read incoming notifications, Pushover exposes the **Open Client API**
 *   (the same REST surface the desktop/mobile apps use to receive). This tool wraps
 *   it: register a dedicated client device once, then pull new messages on demand.
 *
 * ARCHITECTURE (mirror of the send side)
 *   - `register` (one-time, interactive): logs in with the ACCOUNT email+password via
 *     /1/users/login.json to mint a client `secret`, then registers an Open-Client
 *     device (os=O) via /1/devices.json. The account password is read from a MASKED
 *     prompt and used only in memory — NEVER stored or written to argv/transcript.
 *     Only the derived `secret` + `device_id` are persisted, via the SCS `vault`
 *     automation tier (agent-readable, so headless `pull` needs no Touch ID).
 *   - `pull` (on demand): GET /1/messages.json, append every message to
 *     po-inbox.jsonl (UUID-keyed, same dir as po-audit.jsonl), then ack them with
 *     /1/devices/{id}/update_highest.json so they aren't re-downloaded.
 *   - `list`: read back the local inbox JSONL (no network).
 *   - `doctor`: check creds + device registration + API reachability.
 *
 * SECRET HANDLING (SCS doctrine — see cc-skills/docs/self-custody-secrets.md)
 *   - Account password  = CROWN JEWEL → never stored; masked prompt, in-memory only.
 *   - client secret + device_id = automation token → `vault` scope `pushover`
 *     (agent-readable), because the headless pull must read them with no prompt.
 *
 * IMPORTANT CAVEATS
 *   - A freshly-registered Open-Client device only receives messages sent AFTER
 *     registration — it does NOT back-fill history already in the native app.
 *   - IMAP-style: messages.json returns the queue; you MUST update_highest to clear
 *     it, or the same messages return every pull.
 *   - Registering a client device may require a Pushover Desktop/Open-Client license
 *     on the account; if so, /1/devices.json returns an error — surfaced verbatim.
 *   - Run with proxies unset so Pushover HTTPS bypasses the sandbox MITM proxy:
 *       env -u HTTPS_PROXY -u HTTP_PROXY bun pushover_inbox.ts <cmd> ...
 *
 * USAGE
 *   env -u HTTPS_PROXY -u HTTP_PROXY bun pushover_inbox.ts register [--name claude-mac]
 *   env -u HTTPS_PROXY -u HTTP_PROXY bun pushover_inbox.ts pull [--json] [--limit N]
 *   bun pushover_inbox.ts list [--limit N] [--json]
 *   env -u HTTPS_PROXY -u HTTP_PROXY bun pushover_inbox.ts doctor
 */
import { appendFileSync, existsSync, mkdirSync, readFileSync, statSync } from "node:fs";
import { spawnSync } from "node:child_process";
import readline from "node:readline";

const API = "https://api.pushover.net/1";
const VAULT_SCOPE = "pushover";
const VAULT = `${process.env.HOME}/.local/bin/vault`;
const INBOX_PATH = process.env.PUSHOVER_INBOX_PATH ?? `${process.env.HOME}/.local/state/pushover/po-inbox.jsonl`;
const DEFAULT_DEVICE_NAME = "claude-mac";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ---------- tiny arg parser (matches pushover_core.ts style) ----------
type Args = { _: string[]; flags: Record<string, string>; bools: Set<string> };
function parseArgs(argv: string[]): Args {
  const _: string[] = [];
  const flags: Record<string, string> = {};
  const bools = new Set<string>();
  const boolNames = new Set(["json", "force"]);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a.startsWith("--")) {
      const key = a.slice(2);
      if (boolNames.has(key)) { bools.add(key); continue; }
      const next = argv[i + 1];
      if (next === undefined) throw new Error(`flag --${key} needs a value`);
      flags[key] = next; i++;
    } else { _.push(a); }
  }
  return { _, flags, bools };
}

// ---------- SCS vault (automation tier: agent-readable, no prompt) ----------
function vault(args: string[], input?: string): { status: number; out: string; err: string } {
  const r = spawnSync(VAULT, args, { encoding: "utf8", input });
  return { status: r.status ?? 1, out: (r.stdout ?? "").trim(), err: (r.stderr ?? "").trim() };
}
function vaultGet(path: string): string | null {
  const r = vault(["get", VAULT_SCOPE, path]);
  return r.status === 0 && r.out ? r.out : null;
}
function vaultSet(path: string, value: string): void {
  // Ensure the scope exists (idempotent; ignore "already exists").
  vault(["new-scope", VAULT_SCOPE, "Pushover Open-Client receive credentials (client secret + device id)"]);
  const r = vault(["set", VAULT_SCOPE, path, value]);
  if (r.status !== 0) throw new Error(`vault set ${VAULT_SCOPE} ${path} failed: ${r.err || r.out}`);
}

// ---------- TTY prompts (password never echoes / never hits argv) ----------
function ask(query: string): Promise<string> {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    rl.question(query, (ans) => { rl.close(); resolve(ans.trim()); });
  });
}

// Masked reader via raw mode — avoids readline internals (keeps both linters
// happy) and echoes nothing, so a password never appears on screen/argv/transcript.
function askHidden(query: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const stdin = process.stdin;
    process.stdout.write(query);
    stdin.setRawMode?.(true);
    stdin.resume();
    stdin.setEncoding("utf8");
    let input = "";
    const finish = (fn: () => void) => {
      stdin.setRawMode?.(false);
      stdin.pause();
      stdin.removeListener("data", onData);
      process.stdout.write("\n");
      fn();
    };
    const onData = (chunk: string) => {
      for (const c of chunk) {
        if (c === "\n" || c === "\r" || c === "") { finish(() => resolve(input.trim())); return; }
        if (c === "") { finish(() => reject(new Error("aborted"))); return; }
        if (c === "" || c === "\b") { input = input.slice(0, -1); continue; }
        input += c;
      }
    };
    stdin.on("data", onData);
  });
}

// ---------- HTTP with transient retry (sandbox 502 + Pushover blips) ----------
async function fetchRetry(url: string, init?: RequestInit, tries = 3): Promise<Response> {
  let lastErr: unknown;
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(url, init);
      if (r.status >= 500 && i < tries - 1) { await sleep(400 * (i + 1)); continue; }
      return r;
    } catch (e) {
      lastErr = e;
      if (i < tries - 1) await sleep(400 * (i + 1));
    }
  }
  throw lastErr instanceof Error ? lastErr : new Error(`fetch failed: ${url}`);
}

// ---------- Open Client API ----------
async function apiLogin(email: string, password: string, twofa?: string): Promise<string> {
  const fd = new FormData();
  fd.set("email", email);
  fd.set("password", password);
  if (twofa) fd.set("twofa", twofa);
  const r = await fetchRetry(`${API}/users/login.json`, { method: "POST", body: fd });
  const j: any = await r.json();
  if (j.status === 1 && j.secret) return j.secret as string;
  // Pushover signals 2FA-required via a 412 + a message mentioning two-factor.
  if (r.status === 412 || /two[- ]?factor|twofa/i.test(JSON.stringify(j))) {
    throw new Error("2FA_REQUIRED");
  }
  throw new Error(`login failed: ${JSON.stringify(j.errors ?? j)}`);
}

async function apiRegisterDevice(secret: string, name: string): Promise<string> {
  const fd = new FormData();
  fd.set("secret", secret);
  fd.set("name", name);
  fd.set("os", "O"); // "O" = Open Client
  const r = await fetchRetry(`${API}/devices.json`, { method: "POST", body: fd });
  const j: any = await r.json();
  if (j.status === 1 && j.id) return j.id as string;
  throw new Error(`device registration failed (HTTP ${r.status}): ${JSON.stringify(j.errors ?? j)}`);
}

type IncomingMsg = {
  id: number; message: string; title?: string; app?: string; aid?: number;
  priority?: number; sound?: string; url?: string; url_title?: string;
  date?: number; icon?: string; acked?: number; umid?: number; receipt?: string; html?: number;
};

async function apiFetchMessages(secret: string, deviceId: string): Promise<IncomingMsg[]> {
  const url = `${API}/messages.json?secret=${encodeURIComponent(secret)}&device_id=${encodeURIComponent(deviceId)}`;
  const r = await fetchRetry(url);
  const j: any = await r.json();
  if (j.status !== 1) throw new Error(`messages.json failed: ${JSON.stringify(j.errors ?? j)}`);
  return (j.messages ?? []) as IncomingMsg[];
}

async function apiUpdateHighest(secret: string, deviceId: string, highest: number): Promise<void> {
  const fd = new FormData();
  fd.set("secret", secret);
  fd.set("message", String(highest));
  const r = await fetchRetry(`${API}/devices/${encodeURIComponent(deviceId)}/update_highest.json`, { method: "POST", body: fd });
  const j: any = await r.json();
  if (j.status !== 1) throw new Error(`update_highest failed: ${JSON.stringify(j.errors ?? j)}`);
}

// ---------- local inbox JSONL ----------
function inboxAppend(records: Record<string, unknown>[]): void {
  if (!records.length) return;
  mkdirSync(INBOX_PATH.slice(0, INBOX_PATH.lastIndexOf("/")), { recursive: true });
  const body = records.map((rec) => JSON.stringify({ pulled_at: new Date().toISOString(), uuid: crypto.randomUUID(), ...rec })).join("\n") + "\n";
  appendFileSync(INBOX_PATH, body);
}
function isoFromUnix(sec?: number): string | null {
  return typeof sec === "number" ? new Date(sec * 1000).toISOString() : null;
}
function fmtRow(m: { date_iso?: string | null; app?: string; priority?: number; title?: string; message?: string }): string {
  const when = (m.date_iso ?? "").replace("T", " ").slice(0, 16);
  const app = (m.app ?? "?").slice(0, 14).padEnd(14);
  const pri = String(m.priority ?? 0).padStart(2);
  const title = (m.title ?? "").slice(0, 40);
  const msg = (m.message ?? "").replace(/\s+/g, " ").slice(0, 60);
  return `  ${when}  ${app} p${pri}  ${title ? title + " — " : ""}${msg}`;
}

// ---------- subcommands ----------
async function cmdRegister(a: Args): Promise<void> {
  const name = a.flags.name ?? DEFAULT_DEVICE_NAME;
  if (!/^[A-Za-z0-9_-]{1,25}$/.test(name)) {
    throw new Error(`--name '${name}' invalid: 1-25 chars, letters/digits/_/- only`);
  }
  if (vaultGet("client.device_id") && !a.bools.has("force")) {
    throw new Error("already registered (client.device_id present in vault). Re-run with --force to register a new device.");
  }
  console.error("po-inbox register — Pushover ACCOUNT login (password is masked, used once, never stored).");
  const email = await ask("  Pushover account email: ");
  const password = await askHidden("  Pushover account password: ");
  if (!email || !password) throw new Error("email and password are required");

  let secret: string;
  try {
    secret = await apiLogin(email, password);
  } catch (e) {
    if (e instanceof Error && e.message === "2FA_REQUIRED") {
      const twofa = await ask("  Two-factor code (2FA): ");
      secret = await apiLogin(email, password, twofa);
    } else { throw e; }
  }
  const deviceId = await apiRegisterDevice(secret, name);
  vaultSet("client.secret", secret);
  vaultSet("client.device_id", deviceId);
  vaultSet("client.device_name", name);
  vault(["manifest"]); vault(["sync"]); // keep the SCS index + iCloud mirror fresh
  console.error(`po-inbox: registered Open-Client device '${name}' (id stored in vault scope '${VAULT_SCOPE}').`);
  console.error("po-inbox: NOTE — only messages sent from now on will arrive; run `pull` to fetch them.");
  console.log(JSON.stringify({ registered: true, device_name: name }));
}

async function cmdPull(a: Args): Promise<void> {
  const secret = vaultGet("client.secret");
  const deviceId = vaultGet("client.device_id");
  if (!secret || !deviceId) throw new Error("not registered — run `pushover_inbox.ts register` first.");
  const msgs = await apiFetchMessages(secret, deviceId);
  const records = msgs.map((m) => ({
    id: m.id, app: m.app ?? null, aid: m.aid ?? null, title: m.title ?? null,
    message: m.message ?? "", priority: m.priority ?? 0, sound: m.sound ?? null,
    url: m.url ?? null, url_title: m.url_title ?? null, receipt: m.receipt ?? null,
    html: m.html ?? 0, date: m.date ?? null, date_iso: isoFromUnix(m.date),
  }));
  inboxAppend(records);
  if (records.length) {
    const highest = Math.max(...msgs.map((m) => m.id));
    await apiUpdateHighest(secret, deviceId, highest); // ack so they aren't re-pulled
  }
  const limit = a.flags.limit ? Number(a.flags.limit) : records.length;
  const shown = records.slice(-Math.max(0, limit));
  if (a.bools.has("json")) {
    console.log(JSON.stringify({ pulled: records.length, messages: shown }, null, 2));
  } else {
    console.error(`po-inbox: pulled ${records.length} new message(s)${records.length ? ` (acked up to id ${Math.max(...msgs.map((m) => m.id))})` : ""}.`);
    for (const m of shown) console.log(fmtRow(m));
  }
}

function readInbox(): Record<string, any>[] {
  if (!existsSync(INBOX_PATH)) return [];
  return readFileSync(INBOX_PATH, "utf8").split("\n").filter(Boolean).map((l) => {
    try { return JSON.parse(l); } catch { return null; }
  }).filter(Boolean) as Record<string, any>[];
}

async function cmdList(a: Args): Promise<void> {
  const all = readInbox();
  const limit = a.flags.limit ? Number(a.flags.limit) : 20;
  const shown = all.slice(-limit);
  if (a.bools.has("json")) { console.log(JSON.stringify(shown, null, 2)); return; }
  console.error(`po-inbox: ${all.length} message(s) in ${INBOX_PATH}; showing last ${shown.length}.`);
  for (const m of shown) console.log(fmtRow(m));
}

async function cmdDoctor(): Promise<void> {
  const report: Record<string, unknown> = {};
  report.vault_bin = existsSync(VAULT) ? "ok" : "MISSING (~/.local/bin/vault)";
  const secret = vaultGet("client.secret");
  const deviceId = vaultGet("client.device_id");
  report.registered = secret && deviceId ? "yes" : "NO — run `register`";
  report.device_name = vaultGet("client.device_name") ?? null;
  report.inbox_log = existsSync(INBOX_PATH) ? `ok (${statSync(INBOX_PATH).size} B)` : "none yet";
  if (secret && deviceId) {
    try { const m = await apiFetchMessages(secret, deviceId); report.api = `ok (${m.length} message(s) waiting)`; }
    catch (e) { report.api = `ERROR ${e instanceof Error ? e.message : e}`; }
  } else { report.api = "skipped (not registered)"; }
  console.log(JSON.stringify(report, null, 2));
}

// ---------- dispatch ----------
const argv = process.argv.slice(2);
const cmd = argv[0];
const a = parseArgs(argv.slice(1));
try {
  if (cmd === "register") await cmdRegister(a);
  else if (cmd === "pull") await cmdPull(a);
  else if (cmd === "list") await cmdList(a);
  else if (cmd === "doctor") await cmdDoctor();
  else { console.error("usage: pushover_inbox.ts <register|pull|list|doctor> ..."); process.exit(2); }
} catch (e) {
  console.error(String(e instanceof Error ? e.message : e));
  process.exit(1);
}
