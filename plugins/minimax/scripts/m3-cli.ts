#!/usr/bin/env bun
/**
 * m3-cli — MiniMax-M3 capability tooling, one enum-driven CLI.
 *
 *   bun m3-cli.ts verify         # fast live drift check vs the locked snapshot (exit 0/1/2)
 *   bun m3-cli.ts probe [--out f]# full option/capability map (writes JSON)
 *   bun m3-cli.ts context-probe  # input-context ceiling + needle retrieval
 *   bun m3-cli.ts bench          # speed/quality: default thinking vs reasoning:"disabled"
 *
 * Pure Bun port of the former scripts/m3-{verify,probe,context-probe,bench}.py — no
 * Python / uv / requests / pillow runtime. The model under test is read dynamically
 * from the SSoT (MINIMAX_MODEL env, set by ~/.config/mise/config.toml); a prior model
 * version is never pinned in code.
 *
 * Key: MINIMAX_API_KEY env, else `op read` (MINIMAX_API_KEY_OP_PATH + MINIMAX_OP_ACCOUNT).
 * Proxy is bypassed in-process (MiniMax 502s through the local proxy) so callers need
 * not unset *_PROXY themselves.
 */

import { dirname, join } from "node:path";

// --- proxy bypass (mirror the Python Session.trust_env = False) -------------
for (const k of ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "ALL_PROXY", "all_proxy"]) {
  delete process.env[k];
}

enum Command {
  Verify = "verify",
  Probe = "probe",
  ContextProbe = "context-probe",
  Bench = "bench",
}

enum ExitCode {
  Ok = 0,
  Drift = 1,
  Error = 2,
}

const BASE = "https://api.minimax.io/v1";
const MODEL = process.env.MINIMAX_MODEL ?? "MiniMax-M3";
const OP_PATH_DEFAULT = "op://ggk4orq7rmcm7jinsb4ahygv7e/e54cb3ujopexslaq7loywpuycm/password";
const OP_ACCOUNT_DEFAULT = "K5BH72Z7O5BYXOGKBYT5FWTP2E";

const SCRIPTS_DIR = dirname(Bun.fileURLToPath(import.meta.url));
const PLUGIN_ROOT = dirname(SCRIPTS_DIR);
const FIXTURES_DIR = join(PLUGIN_ROOT, "references", "fixtures");

class UsageError extends Error {}
class AuthError extends Error {}

// --- key acquisition: env, then 1Password -----------------------------------
let cachedKey: string | null = null;
async function getKey(): Promise<string> {
  if (cachedKey) return cachedKey;
  const env = process.env.MINIMAX_API_KEY || process.env.MINIMAX_KEY;
  if (env?.trim()) {
    cachedKey = env.trim();
    return cachedKey;
  }
  const opPath = process.env.MINIMAX_API_KEY_OP_PATH ?? OP_PATH_DEFAULT;
  const opAccount = process.env.MINIMAX_OP_ACCOUNT ?? OP_ACCOUNT_DEFAULT;
  const proc = Bun.spawnSync(["op", "read", opPath, "--account", opAccount]);
  const out = proc.stdout.toString().trim();
  if (proc.exitCode !== 0 || !out) {
    throw new AuthError(`failed to read MiniMax API key from 1Password (path=${opPath})`);
  }
  cachedKey = out;
  return cachedKey;
}

// --- HTTP --------------------------------------------------------------------
interface ApiResponse {
  json: Record<string, unknown>;
  dt: number;
}

async function req(
  path: string,
  body?: Record<string, unknown>,
  method = "GET",
  timeoutMs = 90_000,
): Promise<ApiResponse> {
  const key = await getKey();
  const t0 = performance.now();
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  const init: RequestInit = {
    method,
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    signal: ctrl.signal,
  };
  if (body !== undefined) init.body = JSON.stringify(body);
  try {
    const r = await fetch(BASE + path, init);
    const dt = (performance.now() - t0) / 1000;
    const json = (await r.json().catch(() => ({ httpError: r.status }))) as Record<string, unknown>;
    return { json, dt };
  } catch (e) {
    return { json: { netError: String(e).slice(0, 160) }, dt: (performance.now() - t0) / 1000 };
  } finally {
    clearTimeout(timer);
  }
}

/** Small chat against MODEL with a trivial prompt; `extra` overrides any field. */
function chat(extra: Record<string, unknown>, timeoutMs = 90_000): Promise<ApiResponse> {
  return req(
    "/chat/completions",
    { model: MODEL, max_tokens: 8, messages: [{ role: "user", content: "hi" }], ...extra },
    "POST",
    timeoutMs,
  );
}

/** MiniMax error envelope: {error}, or HTTP-200 + base_resp.status_code != 0. */
function errOf(j: Record<string, unknown>): string | null {
  const err = j.error as { message?: string } | undefined;
  if (err) return err.message ?? "error";
  const baseResp = j.base_resp as { status_code?: number; status_msg?: string } | undefined;
  const code = baseResp?.status_code ?? 0;
  if (code !== 0) return `${code}: ${baseResp?.status_msg}`;
  if (j.httpError) return `http ${j.httpError}`;
  if (j.netError) return String(j.netError);
  return null;
}

// --- response shape helpers --------------------------------------------------
interface Choice {
  message?: { content?: string; tool_calls?: unknown; reasoning_content?: unknown; reasoning_details?: unknown };
  finish_reason?: string;
  reasoning?: unknown;
}
function choices(j: Record<string, unknown>): Choice[] {
  return (j.choices as Choice[] | undefined) ?? [];
}
function firstMessage(j: Record<string, unknown>): NonNullable<Choice["message"]> {
  return choices(j)[0]?.message ?? {};
}
function usage(j: Record<string, unknown>): { prompt_tokens?: number; completion_tokens?: number } {
  return (j.usage as { prompt_tokens?: number; completion_tokens?: number } | undefined) ?? {};
}

// ============================================================================
// verify — fast live drift check vs the locked capability snapshot
// ============================================================================
function latestSnapshotPath(): string {
  const override = process.env.M3_CAPABILITIES_SNAPSHOT;
  if (override) return override;
  const glob = new Bun.Glob("m3-capabilities-locked-*.json");
  const matches = [...glob.scanSync(FIXTURES_DIR)].toSorted(); // date-stamped → lexical sort = chronological
  const latest = matches.at(-1);
  if (!latest) throw new Error(`no m3-capabilities-locked-*.json under ${FIXTURES_DIR}`);
  return join(FIXTURES_DIR, latest);
}

async function cmdVerify(args: string[]): Promise<ExitCode> {
  const emitJson = args.includes("--json");
  if (args.includes("--help") || args.includes("-h")) {
    process.stdout.write(VERIFY_HELP);
    return ExitCode.Ok;
  }
  const unknown = args.find((a) => a !== "--json");
  if (unknown) throw new UsageError(`Unknown arg: ${unknown}`);

  const snapshotPath = latestSnapshotPath();
  const inv = (JSON.parse(await Bun.file(snapshotPath).text()).invariants ?? {}) as Record<string, unknown>;
  const ceiling = (inv.max_output_tokens as number | undefined) ?? 524288;

  // --- cheap live probes ---
  const models = await req("/models");
  const ids = new Set((((models.json.data as { id?: string }[] | undefined) ?? []).map((m) => m.id)).filter(Boolean));
  const inCatalog = ids.has(MODEL);

  const hsChat = await req(
    "/chat/completions",
    { model: "MiniMax-M3-highspeed", max_tokens: 8, messages: [{ role: "user", content: "hi" }] },
    "POST",
  );
  const highspeedExists = ids.has("MiniMax-M3-highspeed") || errOf(hsChat.json) === null;

  // n>1 no longer 400s but MiniMax SILENTLY DROPS it (still 1 choice). Count it
  // supported ONLY on true multi-sampling (>1 choice), not on error-absence.
  const n2 = await chat({ n: 2 });
  const supportsNgt1 = errOf(n2.json) === null && choices(n2.json).length > 1;

  // Output-token ceiling probed at the locked boundary in BOTH directions.
  const ceilingAccepted = errOf((await chat({ max_tokens: ceiling })).json) === null;
  const overCeilingRejected = errOf((await chat({ max_tokens: ceiling + 1 })).json) !== null;

  const rs = await chat({
    reasoning_split: true,
    max_tokens: 512,
    messages: [{ role: "user", content: "What is 2+2? Think briefly, then answer." }],
  });
  const rsMsg = firstMessage(rs.json);
  const reasoningSplitSeparates =
    ("reasoning_content" in rsMsg || "reasoning_details" in rsMsg) && !(rsMsg.content ?? "").includes("<think>");

  const checks: Record<string, [boolean, unknown]> = {
    in_catalog: [inCatalog, inv.in_catalog],
    highspeed_variant_exists: [highspeedExists, inv.highspeed_variant_exists],
    supports_n_gt_1: [supportsNgt1, inv.supports_n_gt_1],
    [`max_tokens==${ceiling} accepted`]: [ceilingAccepted, true],
    [`max_tokens>${ceiling} rejected`]: [overCeilingRejected, true],
    reasoning_split_separates_reasoning: [reasoningSplitSeparates, inv.reasoning_split_separates_reasoning],
  };

  const fetchFailed = !inCatalog && !models.json.data;
  const drift: Record<string, { observed: boolean; expected: unknown }> = {};
  for (const [k, [o, e]] of Object.entries(checks)) {
    if (o !== e) drift[k] = { observed: o, expected: e };
  }

  if (fetchFailed) {
    process.stderr.write("ERROR: could not fetch /v1/models — check connectivity / key\n");
    return ExitCode.Error;
  }

  const hasDrift = Object.keys(drift).length > 0;
  if (emitJson) {
    const checksOut: Record<string, { observed: boolean; expected: unknown }> = {};
    for (const [k, [o, e]] of Object.entries(checks)) checksOut[k] = { observed: o, expected: e };
    process.stdout.write(
      `${JSON.stringify({ model: MODEL, snapshot: snapshotPath.split("/").at(-1), checks: checksOut, drift, has_drift: hasDrift }, null, 2)}\n`,
    );
  } else {
    process.stdout.write(`m3-verify · ${MODEL} · snapshot ${snapshotPath.split("/").at(-1)}\n`);
    for (const [k, [o, e]] of Object.entries(checks)) {
      const flag = o === e ? "✅" : "🚨";
      process.stdout.write(`  ${flag} ${k.padEnd(38)} observed=${String(o).padEnd(6)} expected=${e}\n`);
    }
    if (hasDrift) {
      process.stdout.write(`\n🚨 DRIFT in ${Object.keys(drift).length} invariant(s) — review before bumping the snapshot:\n`);
      for (const [k, v] of Object.entries(drift)) process.stdout.write(`     ${k}: ${v.expected} → ${v.observed}\n`);
    } else {
      process.stdout.write("\n✅ No drift — live M3 matches the locked capability snapshot\n");
    }
  }
  return hasDrift ? ExitCode.Drift : ExitCode.Ok;
}

// ============================================================================
// probe — full option / capability map
// ============================================================================
interface ProbeRow {
  dt?: number;
  err: string | null;
  finish?: string;
  n_choices: number;
  tool_calls: unknown;
  content: string;
  msg_keys: string[];
  reasoning_present: boolean;
  reasoning_sample: string | null;
  prompt_tokens?: number;
  completion_tokens?: number;
}

async function probePost(body: Record<string, unknown>, timeoutMs = 120_000): Promise<ProbeRow> {
  const { json, dt } = await req("/chat/completions", body, "POST", timeoutMs);
  const ch = choices(json)[0] ?? {};
  const msg = ch.message ?? {};
  const u = usage(json);
  const reasoning = msg.reasoning_details ?? msg.reasoning_content ?? ch.reasoning ?? null;
  return {
    dt: Math.round(dt * 10) / 10,
    err: errOf(json),
    finish: ch.finish_reason,
    n_choices: choices(json).length,
    tool_calls: msg.tool_calls ?? null,
    content: (msg.content ?? "").slice(0, 300),
    msg_keys: Object.keys(msg).toSorted(),
    reasoning_present: reasoning !== null,
    reasoning_sample: reasoning !== null ? String(reasoning).slice(0, 150) : null,
    prompt_tokens: u.prompt_tokens,
    completion_tokens: u.completion_tokens,
  };
}

async function cmdProbe(args: string[]): Promise<ExitCode> {
  const out: Record<string, unknown> = {};
  const REASON_Q = [
    { role: "user", content: "A train goes 60km at 30km/h, then 60km at 60km/h. Average speed over the whole trip? Give the number." },
  ]; // ans 40

  // 1. THINKING / REASONING mode variants
  process.stdout.write("## thinking modes\n");
  const thinking: Record<string, ProbeRow> = {};
  const variants: Record<string, Record<string, unknown>> = {
    default: {},
    reasoning_effort_low: { reasoning_effort: "low" },
    reasoning_disabled: { reasoning: "disabled" },
    reasoning_adaptive: { reasoning: "adaptive" },
    reasoning_obj_enabled_false: { reasoning: { enabled: false } },
    reasoning_split: { reasoning_split: true },
    include_reasoning: { include_reasoning: true },
    thinking_false: { thinking: false },
  };
  for (const [name, extra] of Object.entries(variants)) {
    const res = await probePost({ model: MODEL, messages: REASON_Q, max_tokens: 2048, temperature: 0.2, ...extra });
    thinking[name] = res;
    process.stdout.write(
      `  ${name.padEnd(28)} ok=${res.err === null} dt=${res.dt} comp=${res.completion_tokens} rsn_present=${res.reasoning_present} err=${res.err}\n`,
    );
  }
  out.thinking = thinking;

  // 2. response_format (JSON)
  process.stdout.write("## response_format\n");
  const rf = await probePost({
    model: MODEL,
    messages: [{ role: "user", content: "Return an object with keys city and population for Tokyo." }],
    response_format: { type: "json_object" },
    max_tokens: 1024,
  });
  let parses = true;
  try {
    JSON.parse(rf.content);
  } catch {
    parses = false;
  }
  out.response_format = { json_object: { ...rf, parses } };
  process.stdout.write(`  json_object: ok=${rf.err === null} parses=${parses} content=${JSON.stringify(rf.content.slice(0, 80))}\n`);

  // 3. tools + tool_choice
  process.stdout.write("## tools/tool_choice\n");
  const TOOLS = [
    {
      type: "function",
      function: {
        name: "get_weather",
        description: "Get weather",
        parameters: { type: "object", properties: { city: { type: "string" } }, required: ["city"] },
      },
    },
  ];
  const forced = await probePost({
    model: MODEL,
    messages: [{ role: "user", content: "Hi" }],
    tools: TOOLS,
    tool_choice: { type: "function", function: { name: "get_weather" } },
    max_tokens: 512,
  });
  const none = await probePost({
    model: MODEL,
    messages: [{ role: "user", content: "Weather in Paris?" }],
    tools: TOOLS,
    tool_choice: "none",
    max_tokens: 512,
  });
  out.tools = { forced_choice: forced, choice_none: none };
  process.stdout.write(`  forced: tool_calls=${forced.tool_calls ? "YES" : "NO"} err=${forced.err}\n`);
  process.stdout.write(`  none:   tool_calls=${none.tool_calls ? "yes" : "no"} (want no) err=${none.err}\n`);

  // 4. VISION — static committed PNG fixture (replaces the old pillow generation)
  process.stdout.write("## vision\n");
  const pngPath = join(FIXTURES_DIR, "vision-banana-7295.png");
  const b64 = Buffer.from(await Bun.file(pngPath).arrayBuffer()).toString("base64");
  const visRow = await probePost({
    model: MODEL,
    max_tokens: 256,
    messages: [
      {
        role: "user",
        content: [
          { type: "text", text: "What exact text is written in this image? Reply with just the text." },
          { type: "image_url", image_url: { url: `data:image/png;base64,${b64}` } },
        ],
      },
    ],
  });
  const vision = { ...visRow, read_correct: visRow.content.includes("BANANA-7295") };
  out.vision = vision;
  process.stdout.write(`  vision: ok=${visRow.err === null} read_correct=${vision.read_correct} err=${visRow.err}\n`);

  // 5. param honoring sweep
  process.stdout.write("## param honoring\n");
  const params: Record<string, { accepted: boolean; err: string | null; n_choices: number }> = {};
  const sweep: Record<string, Record<string, unknown>> = {
    stop: { stop: ["STOP"] },
    n_2: { n: 2 },
    seed: { seed: 42 },
    presence_penalty: { presence_penalty: 1.0 },
    frequency_penalty: { frequency_penalty: 1.0 },
    logprobs: { logprobs: true, top_logprobs: 3 },
    top_p: { top_p: 0.5 },
  };
  for (const [name, extra] of Object.entries(sweep)) {
    const res = await probePost({ model: MODEL, messages: [{ role: "user", content: "Count: one two three STOP four five" }], max_tokens: 256, ...extra });
    params[name] = { accepted: res.err === null, err: res.err, n_choices: res.n_choices };
    process.stdout.write(`  ${name.padEnd(18)} accepted=${res.err === null} n_choices=${res.n_choices} err=${res.err}\n`);
  }
  out.params = params;

  // 6. output ceiling
  process.stdout.write("## output ceiling\n");
  const ceiling: Record<string, { accepted: boolean; err: string | null }> = {};
  for (const mt of [131072, 262144, 524288, 1048576]) {
    const res = await probePost({ model: MODEL, messages: [{ role: "user", content: "Reply: ok" }], max_tokens: mt }, 60_000);
    ceiling[String(mt)] = { accepted: res.err === null, err: res.err };
    process.stdout.write(`  max_tokens=${mt}: accepted=${res.err === null} err=${res.err}\n`);
  }
  out.max_tokens_ceiling = ceiling;

  const outIdx = args.indexOf("--out");
  const outPath = outIdx >= 0 ? args[outIdx + 1] : "m3_probe_results.json";
  if (!outPath) throw new UsageError("--out requires a path");
  await Bun.write(outPath, JSON.stringify(out, null, 2));
  process.stdout.write(`\nwrote ${outPath}\nDONE\n`);
  return ExitCode.Ok;
}

// ============================================================================
// context-probe — input-context ceiling + needle retrieval
// ============================================================================
const FILLER = "The quick brown fox jumps over the lazy dog. ";
const NEEDLE = "The SECRET-CODE is ZX9Q7-DELTA.";
const CHARS_PER_TOK = 4.5; // measured for this filler on the MiniMax tokenizer

async function contextRun(targetTok: number, maxOut: number, needle = true): Promise<Record<string, unknown>> {
  let bodyTxt = FILLER.repeat(Math.floor((targetTok * CHARS_PER_TOK) / FILLER.length));
  let q: string;
  if (needle) {
    const ins = Math.floor(bodyTxt.length * 0.8);
    bodyTxt = `${bodyTxt.slice(0, ins)} ${NEEDLE} ${bodyTxt.slice(ins)}`;
    q = "\n\nWhat is the SECRET-CODE? Reply with just the code.";
  } else {
    q = "\n\nReply: ok";
  }
  const { json, dt } = await req(
    "/chat/completions",
    { model: MODEL, messages: [{ role: "user", content: bodyTxt + q }], max_tokens: maxOut, temperature: 0, reasoning: "disabled" },
    "POST",
    240_000,
  );
  const err = errOf(json);
  const ch = choices(json)[0] ?? {};
  const content = ch.message?.content ?? "";
  return {
    target_tok: targetTok,
    accepted: err === null,
    prompt_tokens: usage(json).prompt_tokens,
    retrieved: needle ? content.includes("ZX9Q7-DELTA") : null,
    finish: ch.finish_reason,
    dt: Math.round(dt * 10) / 10,
    err,
  };
}

/** Parse a comma list of positive ints; "none"/"" → []. */
function parseIntList(s: string): number[] {
  return s
    .split(",")
    .map((x) => Number(x.trim()))
    .filter((n) => Number.isFinite(n) && n > 0);
}

async function cmdContextProbe(args: string[]): Promise<ExitCode> {
  const flag = (name: string): string | undefined => {
    const i = args.indexOf(name);
    return i >= 0 ? args[i + 1] : undefined;
  };
  const needle = parseIntList(flag("--needle") ?? "128000,400000");
  const ceiling = parseIntList(flag("--ceiling") ?? "512000,575000,700000");
  const reps = Math.max(1, Number(flag("--reps") ?? "1") || 1);

  process.stdout.write("=== needle retrieval (thinking OFF, max_tokens 256) ===\n");
  for (const tk of needle) {
    for (let r = 0; r < reps; r++) process.stdout.write(`${JSON.stringify(await contextRun(tk, 256))}\n`);
  }
  process.stdout.write("=== ceiling pin (needle off, max_tokens 32) ===\n");
  for (const tk of ceiling) {
    for (let r = 0; r < reps; r++) process.stdout.write(`${JSON.stringify(await contextRun(tk, 32, false))}\n`);
  }
  process.stdout.write("DONE\n");
  return ExitCode.Ok;
}

// ============================================================================
// bench — speed/quality for the SSoT model: default thinking vs reasoning:"disabled"
// ============================================================================
interface BenchTask {
  max: number;
  temp: number;
  sys: string | null;
  user: string;
}
interface BenchRun {
  dt?: number;
  err?: string | null;
  finish?: string;
  comp_tok?: number;
  tps?: number;
  vis?: string;
}

const THINK_RE = /<think>[\s\S]*?<\/think>\s*/g;
const JSON_SYS =
  'Output ONLY a JSON object: {"action":"long"|"short"|"flat","confidence":0..1,"reasoning":"one sentence","stop_loss_pct":num,"take_profit_pct":num}. No prose, no fences.';
const BENCH_TASKS: Record<string, BenchTask> = {
  short_tag: { max: 256, temp: 0.2, sys: "Output ONLY 3-5 comma-separated lowercase tags. No prose.", user: "Tag: 'AAPL beats Q2 earnings, stock jumps 8% after hours on strong iPhone sales'." },
  long_theory: { max: 1536, temp: 0.7, sys: null, user: "Explain the Black-Scholes model and the meaning of N(d1) and N(d2) in ~220 words." },
  reason_num: { max: 1536, temp: 0.2, sys: null, user: "A bond has modified duration 7. Its yield rises by 0.50%. Give the one-line first-order formula for the approximate % price change and the numeric result." },
  json_signal: { max: 1536, temp: 0.2, sys: JSON_SYS, user: "Setup: EURUSD broke above its 50-day MA on above-average volume, RSI 61." },
};
const BENCH_MODES: Record<string, Record<string, unknown>> = { default: {}, reasoning_disabled: { reasoning: "disabled" } };
const BENCH_REPS = 2;

async function benchCall(modeExtra: Record<string, unknown>, task: string): Promise<BenchRun> {
  const t = BENCH_TASKS[task]!;
  const msgs = [...(t.sys ? [{ role: "system", content: t.sys }] : []), { role: "user", content: t.user }];
  const { json, dt } = await req("/chat/completions", { model: MODEL, messages: msgs, max_tokens: t.max, temperature: t.temp, ...modeExtra }, "POST", 120_000);
  const err = errOf(json);
  if (err) return { err, dt: Math.round(dt * 100) / 100 };
  const ch = choices(json)[0] ?? {};
  const vis = (ch.message?.content ?? "").replace(THINK_RE, "").trim();
  const comp = usage(json).completion_tokens ?? 0;
  return {
    dt: Math.round(dt * 100) / 100,
    finish: ch.finish_reason,
    comp_tok: comp,
    tps: dt > 0 ? Math.round((comp / dt) * 10) / 10 : 0,
    vis: vis.slice(0, 240),
  };
}

function benchQuality(task: string, vis: string): string {
  if (task === "reason_num") return /[-−]?3\.5\s*%/.test(vis) ? "≈-3.5% correct" : "MISS (-3.5% not found)";
  if (task === "json_signal") {
    try {
      const d = JSON.parse(vis) as Record<string, unknown>;
      const ok = ["action", "confidence", "reasoning", "stop_loss_pct", "take_profit_pct"].every((k) => k in d);
      return ok ? "valid JSON" : "JSON parses, missing fields";
    } catch {
      return "INVALID JSON (try reasoning_split:true + fence-extract)";
    }
  }
  if (task === "long_theory") {
    const lower = vis.toLowerCase();
    const hits = ["d1", "d2", "n(", "volatil", "strike", "risk-free", "black"].filter((k) => lower.includes(k)).length;
    return `theory keywords ${hits}/7`;
  }
  return `${vis.length} chars`;
}

function median(xs: number[]): number {
  const s = xs.toSorted((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid]! : (s[mid - 1]! + s[mid]!) / 2;
}

async function cmdBench(): Promise<ExitCode> {
  process.stdout.write(`# m3-bench — model under test: ${MODEL} (SSoT: MINIMAX_MODEL)\n`);
  const results: Record<string, Record<string, Record<string, unknown>>> = {};
  for (const [mode, extra] of Object.entries(BENCH_MODES)) {
    process.stdout.write(`\n### ${MODEL} [${mode}]\n`);
    results[mode] = {};
    for (const task of Object.keys(BENCH_TASKS)) {
      const runs: BenchRun[] = [];
      for (let i = 0; i < BENCH_REPS; i++) runs.push(await benchCall(extra, task));
      runs.forEach((res, rep) => {
        process.stdout.write(`  ${task} r${rep}: dt=${res.dt}s tps=${res.tps} comp=${res.comp_tok} ${res.err ?? ""}\n`);
      });
      const ok = runs.filter((r) => r.err === undefined);
      if (ok.length) {
        const best = ok.reduce((a, b) => ((b.vis?.length ?? 0) > (a.vis?.length ?? 0) ? b : a));
        results[mode]![task] = {
          lat_med: Math.round(median(ok.map((r) => r.dt!)) * 100) / 100,
          tps_med: Math.round(median(ok.map((r) => r.tps!)) * 10) / 10,
          comp_tok: best.comp_tok,
          finish: best.finish,
          quality: benchQuality(task, best.vis ?? ""),
        };
      } else {
        results[mode]![task] = { error: runs[0]?.err };
      }
    }
  }

  process.stdout.write("\n=== SUMMARY (median latency / median TPS / quality) ===\n");
  for (const mode of Object.keys(BENCH_MODES)) {
    process.stdout.write(`\n${MODEL} [${mode}]\n`);
    for (const task of Object.keys(BENCH_TASKS)) {
      const r = results[mode]![task]!;
      if ("error" in r) {
        process.stdout.write(`  ${task.padEnd(12)} ERROR ${r.error}\n`);
      } else {
        process.stdout.write(
          `  ${task.padEnd(12)} lat=${String(r.lat_med).padStart(6)}s tps=${String(r.tps_med).padStart(5)} comp=${String(r.comp_tok).padStart(4)} fin=${String(r.finish).padEnd(6)} | ${r.quality}\n`,
        );
      }
    }
  }
  process.stdout.write("\nDONE\n");
  return ExitCode.Ok;
}

// ============================================================================
// dispatch
// ============================================================================
const VERIFY_HELP = `m3-cli verify — fast live drift check of MiniMax model capability invariants vs the locked snapshot.

Re-probes a CHEAP subset (catalog presence, highspeed-variant absence, true n>1 support,
output-token ceiling both directions, reasoning_split separation) and diffs against the latest
references/fixtures/m3-capabilities-locked-*.json snapshot.

Exit: 0 no drift · 1 drift · 2 fetch/key error
Flags: --json (structured output) · --help

Env: MINIMAX_MODEL (SSoT model id) · M3_CAPABILITIES_SNAPSHOT (override snapshot path) ·
     MINIMAX_API_KEY | MINIMAX_API_KEY_OP_PATH + MINIMAX_OP_ACCOUNT (1Password fallback)
`;

const TOP_HELP = `m3-cli — MiniMax-M3 capability tooling (Bun).

Usage: bun m3-cli.ts <command> [flags]

Commands:
  verify          fast live drift check vs the locked snapshot (exit 0/1/2)
  probe [--out f] full option/capability map (writes JSON; default m3_probe_results.json)
  context-probe   input-context ceiling + needle retrieval
                  flags: --needle <tok,list> --ceiling <tok,list> --reps <n> ("none" disables a phase)
  bench           speed/quality: default thinking vs reasoning:"disabled"

Model is read from MINIMAX_MODEL (SSoT). Key from MINIMAX_API_KEY or 1Password.
`;

const HANDLERS: Record<Command, (args: string[]) => Promise<ExitCode>> = {
  [Command.Verify]: cmdVerify,
  [Command.Probe]: cmdProbe,
  [Command.ContextProbe]: cmdContextProbe,
  [Command.Bench]: () => cmdBench(),
};

async function main(argv: string[]): Promise<ExitCode> {
  const [cmd, ...rest] = argv;
  if (!cmd || cmd === "--help" || cmd === "-h") {
    process.stdout.write(TOP_HELP);
    return cmd ? ExitCode.Ok : ExitCode.Error;
  }
  if (!Object.values(Command).includes(cmd as Command)) {
    throw new UsageError(`Unknown command: ${cmd}`);
  }
  return HANDLERS[cmd as Command](rest);
}

if (import.meta.main) {
  try {
    process.exitCode = await main(Bun.argv.slice(2));
  } catch (e) {
    if (e instanceof UsageError) {
      process.stderr.write(`${e.message}\n\n${TOP_HELP}`);
    } else if (e instanceof AuthError) {
      process.stderr.write(`ERROR: ${e.message}\n`);
    } else {
      process.stderr.write(`ERROR: ${e instanceof Error ? e.message : String(e)}\n`);
    }
    process.exitCode = ExitCode.Error;
  }
}
