#!/usr/bin/env bun
/**
 * po — TypeScript/Bun core for the private Pushover plugin.
 * Subcommands: send | emergency | sounds | render | loop-brief | doctor | quota
 *
 * Secrets via resolve_pushover_secret.sh (1Password op -> Keychain). Limits/rules from pushover_api_limits.json (SSoT).
 * Every send is preflighted (warn-or-refuse vs Pushover's silent failures), retried on transient
 * errors, and appended to a UUID-keyed JSONL audit trail (~/.local/state/pushover/po-audit.jsonl).
 *
 * Run with proxies unset so Pushover HTTPS bypasses the sandbox MITM proxy:
 *   env -u HTTPS_PROXY -u HTTP_PROXY bun pushover_core.ts <cmd> ...
 */
import { Resvg } from "@resvg/resvg-js";
import satori from "satori";
import { readFileSync, writeFileSync, appendFileSync, statSync, existsSync, mkdirSync } from "node:fs";
import { spawnSync } from "node:child_process";

const API = "https://api.pushover.net/1";
const FONT_PATH = process.env.PUSHOVER_RENDER_FONT_PATH ?? `${process.env.HOME}/Library/Fonts/JetBrainsMonoNerdFontMono-Regular.ttf`;
const BG = "#0d1117";
const FG = "#c9d1d9";
const HEADING: Record<string, string> = { "#": "#3fb950", "!": "#d29922", ">": "#58a6ff", ".": "#5a636e" };
const LIB_DIR = import.meta.dir;
const LIMITS: Record<string, any> = JSON.parse(readFileSync(`${LIB_DIR}/pushover_api_limits.json`, "utf8"));
const AUDIT_PATH = process.env.PUSHOVER_AUDIT_PATH ?? `${process.env.HOME}/.local/state/pushover/po-audit.jsonl`;

function creds(field: string): string {
  const r = spawnSync("bash", [`${LIB_DIR}/resolve_pushover_secret.sh`, field], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(`resolve_pushover_secret failed for '${field}': ${r.stderr ?? ""}`);
  return r.stdout.trim();
}
function tokenFor(app: string): string {
  return app === "main" ? creds("api_token_main") : creds("api_token_test");
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// retry transient network / 5xx with backoff (the sandbox 502 + Pushover blips)
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

function audit(record: Record<string, unknown>): void {
  const line = JSON.stringify({ ts: new Date().toISOString(), uuid: crypto.randomUUID(), ...record }) + "\n";
  try {
    mkdirSync(AUDIT_PATH.slice(0, AUDIT_PATH.lastIndexOf("/")), { recursive: true });
    appendFileSync(AUDIT_PATH, line);
  } catch (e) {
    console.error("po: audit write failed:", e instanceof Error ? e.message : e);
  }
}

type Args = { _: string[]; flags: Record<string, string>; bools: Set<string> };
function parseArgs(argv: string[]): Args {
  const _: string[] = [];
  const flags: Record<string, string> = {};
  const bools = new Set<string>();
  const boolNames = new Set(["emergency", "headed", "html", "monospace", "force"]);
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

// ---------- rendering (Satori + resvg) ----------
function classify(line: string): { color: string; text: string } {
  const prefix = line[0];
  if (line.length >= 2 && line[1] === " " && prefix !== undefined && HEADING[prefix] !== undefined) {
    return { color: HEADING[prefix]!, text: line.slice(2) };
  }
  return { color: FG, text: line };
}

function wrapToCols(text: string, cols: number): { color: string; text: string }[] {
  // Word-aware greedy wrap (`fold -s` semantics): pack whole words up to `cols`,
  // NEVER split mid-word. Only a single token that ALONE exceeds `cols` (URLs,
  // hashes, paths) is hard-broken. Lines that already fit keep their original
  // spacing untouched (preserves aligned tables). Greedy is correct for
  // left-aligned monospace; Knuth-Plass only helps justified paragraphs.
  const out: { color: string; text: string }[] = [];
  for (const logical of text.split("\n")) {
    const { color, text: content } = classify(logical);
    if (content.length === 0) { out.push({ color: FG, text: "" }); continue; }
    if (content.length <= cols) { out.push({ color, text: content }); continue; }
    let cur = "";
    for (let word of content.split(" ")) {
      while (word.length > cols) {
        if (cur) { out.push({ color, text: cur }); cur = ""; }
        out.push({ color, text: word.slice(0, cols) });
        word = word.slice(cols);
      }
      if (cur === "") cur = word;
      else if (cur.length + 1 + word.length <= cols) cur = cur + " " + word;
      else { out.push({ color, text: cur }); cur = word; }
    }
    if (cur) out.push({ color, text: cur });
  }
  return out;
}

type SatoriNode = { type: string; props: Record<string, unknown> };
function div(style: Record<string, unknown>, children: unknown): SatoriNode {
  return { type: "div", props: { style, children } };
}

async function renderReport(text: string, outPath: string, cols = 72): Promise<void> {
  const fontSize = 30;
  const charW = Math.round(fontSize * 0.6);
  const lineH = Math.round(fontSize * 1.42);
  const pad = 24;
  const items = wrapToCols(text, cols);
  // Auto-fit: `cols` is the MAX wrap width, not a fixed canvas width. Size the canvas to the
  // longest actual line so Pushover's fit-to-width scales the text UP instead of wasting
  // right-margin whitespace. Monospace ⇒ exact: width = maxChars × advance + 2·pad.
  const maxChars = items.reduce((m, it) => Math.max(m, it.text.length), 1);
  const effCols = Math.min(cols, maxChars);
  const width = effCols * charW + pad * 2;
  const height = items.length * lineH + pad * 2;
  const rows = items.map((it) =>
    div({ color: it.color, height: lineH, whiteSpace: "pre" }, it.text.length ? it.text : " "),
  );
  const root = div(
    { display: "flex", flexDirection: "column", width, height, padding: pad, backgroundColor: BG, fontFamily: "JBMono", fontSize },
    rows,
  );
  const fontData = readFileSync(FONT_PATH);
  const svg = await satori(root as unknown as Parameters<typeof satori>[0], {
    width,
    height,
    fonts: [{ name: "JBMono", data: fontData, weight: 400, style: "normal" }],
  });
  const png = new Resvg(svg, { fitTo: { mode: "original" } }).render().asPng();
  writeFileSync(outPath, png);
}

// ---------- Pushover HTTP ----------
async function poGet(path: string): Promise<any> {
  const res = await fetchRetry(`${API}/${path}`);
  return res.json();
}

async function validate(token: string, user: string, device: string): Promise<boolean> {
  const fd = new FormData();
  fd.set("token", token); fd.set("user", user); fd.set("device", device);
  const r = await fetchRetry(`${API}/users/validate.json`, { method: "POST", body: fd });
  const j: any = await r.json();
  return j.status === 1;
}

type SendOpts = {
  app: string; title?: string; message: string; priority?: number;
  attach?: string; sound?: string; url?: string; urlTitle?: string;
  html?: boolean; monospace?: boolean;
  retry?: number; expire?: number; validateFirst?: boolean; force?: boolean;
  // ttl (official API parameter, re-verified 2026-06-11): message
  // self-deletes from devices after N seconds. IGNORED by the API for
  // priority 2; needs device clients >= 4.0. Employ for routine/heartbeat
  // sends so they self-clean instead of piling up — part of the per-account
  // quota hygiene (one 10k/month pool shared across all fleet apps).
  ttl?: number;
};

// preflight: turn Pushover's SILENT failures into explicit warn (proceed) / error (refuse)
async function preflight(token: string, o: SendOpts): Promise<{ errors: string[]; warnings: string[] }> {
  const errors: string[] = [];
  const warnings: string[] = [];
  if (o.message.length > LIMITS.message_max) warnings.push(`message ${o.message.length}>${LIMITS.message_max} → will truncate (Pushover silently truncates)`);
  if (o.title && o.title.length > LIMITS.title_max) warnings.push(`title ${o.title.length}>${LIMITS.title_max} → will truncate`);
  if (o.urlTitle && o.urlTitle.length > LIMITS.url_title_max) warnings.push(`url_title >${LIMITS.url_title_max} → will truncate`);
  if (o.url && o.url.length > LIMITS.url_max) errors.push(`url ${o.url.length}>${LIMITS.url_max} → Pushover HTTP 400`);
  if (o.html && o.monospace) errors.push("html + monospace are mutually exclusive → HTTP 400");
  if (o.attach) {
    if (!existsSync(o.attach)) errors.push(`attachment not found: ${o.attach}`);
    else {
      const sz = statSync(o.attach).size;
      if (sz > LIMITS.attachment_max_bytes) errors.push(`attachment ${sz}B > ${LIMITS.attachment_max_bytes} → HTTP 413`);
    }
  }
  if (o.sound) {
    const sj: any = await poGet(`sounds.json?token=${token}`);
    if (!(o.sound in (sj.sounds ?? {}))) warnings.push(`sound '${o.sound}' not in account list → Pushover silently ignores it`);
  }
  return { errors, warnings };
}

async function sendMessage(o: SendOpts): Promise<any> {
  const token = tokenFor(o.app);
  const user = creds("user_key");
  const device = creds("device");

  const { errors, warnings } = await preflight(token, o);
  for (const w of warnings) console.error(`po: WARN ${w}`);
  if (errors.length && !o.force) {
    throw new Error(`po: preflight refused (use --force to override):\n  - ${errors.join("\n  - ")}`);
  }
  for (const e of errors) console.error(`po: FORCED past error: ${e}`);

  if (o.validateFirst !== false && !(await validate(token, user, device))) {
    throw new Error("po: validation failed (user/device)");
  }
  const fd = new FormData();
  fd.set("token", token); fd.set("user", user); fd.set("device", device);
  fd.set("message", o.message.slice(0, LIMITS.message_max));
  fd.set("priority", String(o.priority ?? 0));
  if (o.title) fd.set("title", o.title.slice(0, LIMITS.title_max));
  if (o.sound) fd.set("sound", o.sound);
  if (o.url) fd.set("url", o.url.slice(0, LIMITS.url_max));
  if (o.urlTitle) fd.set("url_title", o.urlTitle.slice(0, LIMITS.url_title_max));
  if (o.html) fd.set("html", "1");
  if (o.monospace) fd.set("monospace", "1");
  if (o.ttl && o.ttl > 0 && (o.priority ?? 0) < 2) fd.set("ttl", String(o.ttl));
  if ((o.priority ?? 0) === 2) {
    fd.set("retry", String(o.retry ?? LIMITS.priority2_retry_min));
    fd.set("expire", String(o.expire ?? 300));
  }
  if (o.attach) fd.set("attachment", new Blob([readFileSync(o.attach)]), "report.png");

  const res = await fetchRetry(`${API}/messages.json`, { method: "POST", body: fd });
  const remaining = res.headers.get("X-Limit-App-Remaining");
  const j: any = await res.json();
  audit({
    app: o.app, title: o.title ?? null, priority: o.priority ?? 0, sound: o.sound ?? null,
    attach: o.attach ?? null, message_len: o.message.length, status: j.status,
    request: j.request ?? null, receipt: j.receipt ?? null, remaining: remaining ? Number(remaining) : null,
    errors: j.errors ?? null,
  });
  if (remaining !== null && Number(remaining) < LIMITS.quota_warn_remaining) {
    console.error(`po: WARN quota low — ${remaining} messages left this month`);
  }
  if (j.status !== 1) throw new Error(`po: send failed: ${JSON.stringify(j.errors ?? j)}`);
  if (j.receipt) await pollReceipt(token, j.receipt, o.expire ?? 300);
  return j;
}

async function pollReceipt(token: string, receipt: string, expire: number): Promise<void> {
  const maxPolls = Math.floor(expire / 5) + 1;
  for (let i = 0; i < maxPolls; i++) {
    await sleep(5000);
    const j: any = await poGet(`receipts/${receipt}.json?token=${token}`);
    console.error(`  ack=${j.acknowledged} expired=${j.expired}`);
    if (j.acknowledged === 1 || j.expired === 1) {
      console.log(JSON.stringify({ acknowledged: j.acknowledged, acknowledged_at: j.acknowledged_at, expired: j.expired }));
      return;
    }
  }
}

// ---------- subcommands ----------
async function cmdSounds(a: Args): Promise<void> {
  const app = a.flags.app ?? "test";
  const j: any = await poGet(`sounds.json?token=${tokenFor(app)}`);
  if (j.status !== 1) throw new Error(`po sounds: ${JSON.stringify(j)}`);
  const sounds: Record<string, string> = j.sounds;
  const sub = a._[1] ?? "list";
  if (sub === "list") { for (const [k, v] of Object.entries(sounds)) console.log(`${k}\t${v}`); }
  else if (sub === "has") { const ok = (a._[2] ?? "") in sounds; console.log(ok ? "yes" : "no"); if (!ok) process.exit(1); }
  else if (sub === "resolve") { console.log((a._[2] ?? "") in sounds ? a._[2]! : (a._[3] ?? "")); }
  else throw new Error(`po sounds: unknown subcommand '${sub}'`);
}

async function cmdRender(a: Args): Promise<void> {
  const out = a.flags.out ?? "/tmp/po_report.png";
  const cols = a.flags.cols ? Number(a.flags.cols) : 72;
  const text = a.flags.in ? readFileSync(a.flags.in, "utf8") : readFileSync(0, "utf8");
  await renderReport(text, out, cols);
  console.log(out);
}

async function cmdSend(a: Args, emergency: boolean): Promise<void> {
  const j = await sendMessage({
    app: a.flags.app ?? "test",
    title: a.flags.title,
    message: a.flags.message ?? "",
    priority: emergency ? 2 : a.flags.priority ? Number(a.flags.priority) : 0,
    attach: a.flags.attach,
    sound: a.flags.sound,
    url: a.flags.url,
    urlTitle: a.flags["url-title"],
    html: a.bools.has("html"),
    monospace: a.bools.has("monospace"),
    retry: a.flags.retry ? Number(a.flags.retry) : undefined,
    expire: a.flags.expire ? Number(a.flags.expire) : undefined,
    // --ttl <seconds>: routine sends self-delete from devices (official
    // API param; the API ignores it on priority 2 and we skip setting it).
    ttl: a.flags.ttl ? Number(a.flags.ttl) : undefined,
    force: a.bools.has("force"),
  });
  console.log(JSON.stringify({ status: j.status, request: j.request, receipt: j.receipt ?? null }));
}

function sh(cmd: string, args: string[]): string {
  const r = spawnSync(cmd, args, { encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : "";
}

async function cmdLoopBrief(a: Args): Promise<void> {
  const kind = (a.flags.kind ?? "").toLowerCase();
  const reason = a.flags.reason ?? "";
  if (kind !== "blocked" && kind !== "done") throw new Error("po loop-brief: --kind blocked|done required");
  if (!reason) throw new Error("po loop-brief: --reason required");
  const proj = sh("basename", [process.cwd()]);
  const branch = sh("git", ["rev-parse", "--abbrev-ref", "HEAD"]) || "(not a git repo)";
  const status = sh("git", ["status", "-s"]);
  const commits = sh("git", ["log", "--oneline", "-5"]);
  const body = a.flags.body ? (a.flags.body === "-" ? readFileSync(0, "utf8") : readFileSync(a.flags.body, "utf8")) : "";
  const ku = kind.toUpperCase();
  const lines = [
    `# LOOP BRIEFING — ${ku}`,
    `. ${new Date().toISOString()}`,
    `> reason: ${reason}`,
    "",
    "# CONTEXT",
    `project : ${proj}`,
    `cwd     : ${process.cwd()}`,
    `branch  : ${branch}`,
    "",
    "# GIT STATUS",
    status || "(clean / n/a)",
    "",
    "# RECENT COMMITS",
    commits || "(n/a)",
    ...(body ? ["", "# DETAILS", body] : []),
  ].join("\n");
  const png = `/tmp/po_brief_${kind}.png`;
  await renderReport(lines, png);
  await sendMessage({
    app: a.flags.app ?? "test",
    title: a.flags.title ?? `Loop ${ku}: ${proj}`,
    message: `${ku} — ${reason}`,
    priority: kind === "blocked" || a.bools.has("emergency") ? 2 : 1,
    attach: png,
    sound: a.flags.sound,
  });
  console.error(`po loop-brief: sent ${ku} briefing`);
}

async function cmdQuota(a: Args): Promise<void> {
  const token = tokenFor(a.flags.app ?? "test");
  const q: any = await poGet(`apps/limits.json?token=${token}`);
  console.log(JSON.stringify({ limit: q.limit, remaining: q.remaining, reset: q.reset }, null, 2));
  if (typeof q.remaining === "number" && q.remaining < LIMITS.quota_warn_remaining) {
    console.error(`po: WARN only ${q.remaining} messages left this month`);
  }
}

async function cmdDoctor(a: Args): Promise<void> {
  const app = a.flags.app ?? "test";
  const report: Record<string, unknown> = {};
  for (const f of ["api_token_test", "api_token_main", "user_key", "device"]) {
    try { report[`cred_${f}`] = creds(f) ? "ok" : "EMPTY"; }
    catch { report[`cred_${f}`] = "FAIL"; }
  }
  let token = "", user = "", device = "";
  try { token = tokenFor(app); user = creds("user_key"); device = creds("device"); }
  catch (e) { report.creds_error = String(e instanceof Error ? e.message : e); }
  try { report.validate = (await validate(token, user, device)) ? "status=1" : "FAIL"; }
  catch (e) { report.validate = `ERROR ${e instanceof Error ? e.message : e}`; }
  // Quota semantics changed 2026-05-01 (Pushover blog 2026-04): limits are
  // PER-ACCOUNT, shared across all of the account's applications — the
  // limit/remaining reported here is the ACCOUNT pool, regardless of which
  // app token queries it. Exhaustion = HTTP 429 on sends. SSoT:
  // pushover_api_limits.json (quota_scope / quota_exhausted_status).
  try { const q: any = await poGet(`apps/limits.json?token=${token}`); report.quota = { limit: q.limit, remaining: q.remaining }; }
  catch { report.quota = "ERROR"; }
  try {
    const sj: any = await poGet(`sounds.json?token=${token}`);
    report.custom_sounds = ["po_fanfare", "po_uplift", "po_celebrate"].map((s) => `${s}:${s in (sj.sounds ?? {}) ? "ok" : "MISSING"}`);
  } catch { report.custom_sounds = "ERROR"; }
  report.deps = {
    bun: sh("which", ["bun"]) ? "ok" : "MISSING",
    uv: sh("which", ["uv"]) ? "ok" : "MISSING",
    chrome: existsSync("/Applications/Google Chrome.app") ? "ok" : "MISSING",
  };
  report.audit_log = existsSync(AUDIT_PATH) ? `ok (${statSync(AUDIT_PATH).size} B)` : "none yet";
  console.log(JSON.stringify(report, null, 2));
}

// ---------- dispatch ----------
const argv = process.argv.slice(2);
const cmd = argv[0];
const a = parseArgs(argv.slice(1));
try {
  if (cmd === "send") await cmdSend(a, false);
  else if (cmd === "emergency") await cmdSend(a, true);
  else if (cmd === "sounds") await cmdSounds({ ...a, _: [cmd, ...a._] });
  else if (cmd === "render") await cmdRender(a);
  else if (cmd === "loop-brief") await cmdLoopBrief(a);
  else if (cmd === "quota") await cmdQuota(a);
  else if (cmd === "doctor") await cmdDoctor(a);
  else { console.error("usage: po <send|emergency|sounds|render|loop-brief|quota|doctor> ..."); process.exit(2); }
} catch (e) {
  console.error(String(e instanceof Error ? e.message : e));
  process.exit(1);
}
