#!/usr/bin/env bun
/**
 * zai — one enum-driven CLI for the WHOLE verified Z.ai GLM Coding Plan (Pro) surface.
 *
 *   zai chat "..."                 # fast by default (thinking disabled)
 *   zai chat --deep "..."          # deep reasoning (thinking enabled, effort=high)
 *   zai chat --effort max --file big.txt "summarize"   # 1M-context consult from a file/stdin
 *   zai vision --image shot.png "what error is shown?"  # image analysis (glm-4.6v)
 *   zai websearch "GLM-5.2 release date"                # bundled web_search_prime MCP tool
 *   zai read https://example.com                        # bundled web_reader MCP tool
 *   zai models | zai quota | zai doctor
 *
 * All facts here were EMPIRICALLY VERIFIED 2026-07-21 (see references/CAPABILITIES.md).
 * Key: GLM_API_KEY | ZAI_API_KEY env, else Self-Custody Secrets `vault get glm api_key` (NOT 1Password).
 * Proxy is stripped in-process (a local MITM proxy breaks direct z.ai calls).
 */
for (const k of ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "ALL_PROXY", "all_proxy"]) {
  delete process.env[k];
}
import { execFileSync } from "node:child_process";
import { basename } from "node:path";

const CODING = "https://api.z.ai/api/coding/paas/v4";
const MCP = "https://api.z.ai/api/mcp";
const QUOTA_URL = "https://api.z.ai/api/monitor/usage/quota/limit";
const MAX_OUTPUT = 131072; // verified hard ceiling (200000 → error 1210)

// Pinned LATEST models per area — single home (DRY). Verified newest 2026-07-21: no glm-5.3/5.5/6/pro/
// max/flash, and no vision model newer than glm-4.6v (only glm-4.5v/glm-4.6v exist). `zai models`
// drift-checks the live catalog against these; port here when Z.ai ships a newer id.
const CHAT_MODEL = "glm-5.2"; // flagship chat + reasoning (thinking mode)
const VISION_MODEL = "glm-4.6v"; // newest multimodal

let cachedKey: string | null = null;
function key(): string {
  if (cachedKey) return cachedKey;
  const env = process.env.GLM_API_KEY ?? process.env.ZAI_API_KEY;
  if (env?.trim()) { cachedKey = env.trim(); return cachedKey; }
  try {
    cachedKey = execFileSync("vault", ["get", "glm", "api_key"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
    if (!cachedKey) throw new Error("empty");
    return cachedKey;
  } catch (e) {
    throw new Error(`no Z.ai key: set GLM_API_KEY or store in SCS (\`vault set --stdin glm api_key\`). (${(e as Error).message.slice(0, 60)})`, { cause: e });
  }
}

const log = (s: string) => process.stdout.write(s + "\n");
const err = (s: string) => process.stderr.write(s + "\n");

// ---- flag parsing -----------------------------------------------------------
interface Flags { model?: string; deep: boolean; effort?: string; max: number; stream: boolean; file?: string; temp?: number; json: boolean; image: string[]; recency?: string; size?: string; location?: string; domain?: string; rest: string[]; }
function parse(argv: string[]): Flags {
  const f: Flags = { deep: false, max: 4096, stream: false, json: false, image: [], rest: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    const next = () => argv[++i]!;
    if (a === "--deep") f.deep = true;
    else if (a === "--fast") f.deep = false;
    else if (a === "--stream") f.stream = true;
    else if (a === "--json") f.json = true;
    else if (a === "--model") f.model = next();
    else if (a === "--effort") { f.effort = next(); f.deep = true; }
    else if (a === "--max") f.max = Math.min(MAX_OUTPUT, Math.max(1, parseInt(next(), 10) || 4096));
    else if (a === "--file") f.file = next();
    else if (a === "--temp") f.temp = parseFloat(next());
    else if (a === "--image") f.image.push(next());
    else if (a === "--recency") f.recency = next();
    else if (a === "--size") f.size = next();
    else if (a === "--location") f.location = next();
    else if (a === "--domain") f.domain = next();
    else f.rest.push(a);
  }
  return f;
}

async function readContext(file: string | undefined): Promise<string> {
  if (!file) return "";
  if (file === "-") return await Bun.stdin.text();
  return await Bun.file(file).text();
}

// ---- reasoning body: fast (disabled) vs deep (enabled + effort) -------------
function thinkBody(f: Flags): Record<string, unknown> {
  if (f.deep) {
    const b: Record<string, unknown> = { thinking: { type: "enabled" } };
    b.reasoning_effort = f.effort ?? "high"; // low|medium|high|max (verified)
    return b;
  }
  return { thinking: { type: "disabled" } }; // reasoning_tokens=0, full budget on the answer
}

// ---- chat -------------------------------------------------------------------
async function cmdChat(f: Flags): Promise<number> {
  const model = f.model ?? CHAT_MODEL;
  const ctx = await readContext(f.file);
  const ask = f.rest.join(" ").trim();
  if (!ask && !ctx) { err("usage: zai chat [--deep|--effort L] [--file P|-] [--stream] \"prompt\""); return 2; }
  const content = ctx ? `${ctx}\n\n${ask}` : ask;
  const body: Record<string, unknown> = {
    model, messages: [{ role: "user", content }], max_tokens: f.max, temperature: f.temp ?? 0.6,
    ...thinkBody(f),
    ...(f.json ? { response_format: { type: "json_object" } } : {}),
    ...(f.stream ? { stream: true } : {}),
  };
  const headers = { Authorization: `Bearer ${key()}`, "Content-Type": "application/json" };
  if (f.stream) {
    const r = await fetch(`${CODING}/chat/completions`, { method: "POST", headers, body: JSON.stringify(body) });
    if (!r.ok) { err(`HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`); return 1; }
    const reader = (r.body as ReadableStream<Uint8Array>).getReader();
    const dec = new TextDecoder();
    let buf = "";
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      for (;;) {
        const nl = buf.indexOf("\n");
        if (nl < 0) break;
        const line = buf.slice(0, nl).trim(); buf = buf.slice(nl + 1);
        if (!line.startsWith("data:")) continue;
        const p = line.slice(5).trim();
        if (p === "[DONE]") continue;
        try { const d = JSON.parse(p); const piece = d?.choices?.[0]?.delta?.content ?? ""; if (piece) process.stdout.write(piece); } catch { /* skip */ }
      }
    }
    process.stdout.write("\n");
    return 0;
  }
  const r = await fetch(`${CODING}/chat/completions`, { method: "POST", headers, body: JSON.stringify(body) });
  const txt = await r.text();
  if (!r.ok) { err(`HTTP ${r.status}: ${txt.slice(0, 300)}`); return 1; }
  const d = JSON.parse(txt);
  const msg = d?.choices?.[0]?.message ?? {};
  log((msg.content ?? "").trim() || `(no content; finish=${d?.choices?.[0]?.finish_reason}; reasoning_tokens=${d?.usage?.completion_tokens_details?.reasoning_tokens})`);
  return 0;
}

// ---- vision (coding endpoint, vision model) ---------------------------------
const MIME: Record<string, string> = { png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp" };
async function toImageUrl(src: string): Promise<string> {
  if (/^https?:\/\//.test(src) || src.startsWith("data:")) return src;
  const b64 = Buffer.from(await Bun.file(src).arrayBuffer()).toString("base64");
  const ext = basename(src).split(".").pop()?.toLowerCase() ?? "png";
  return `data:${MIME[ext] ?? "image/png"};base64,${b64}`;
}
async function cmdVision(f: Flags): Promise<number> {
  if (f.image.length === 0) { err('usage: zai vision --image <path|url> "question"'); return 2; }
  const model = f.model ?? VISION_MODEL; // verified vision models: glm-4.6v (newest), glm-4.5v
  const parts: unknown[] = [{ type: "text", text: f.rest.join(" ").trim() || "Describe this image." }];
  for (const src of f.image) parts.push({ type: "image_url", image_url: { url: await toImageUrl(src) } });
  const body = { model, messages: [{ role: "user", content: parts }], max_tokens: f.max, ...thinkBody(f) };
  const r = await fetch(`${CODING}/chat/completions`, { method: "POST", headers: { Authorization: `Bearer ${key()}`, "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const txt = await r.text();
  if (!r.ok) { err(`HTTP ${r.status}: ${txt.slice(0, 300)}`); return 1; }
  log((JSON.parse(txt)?.choices?.[0]?.message?.content ?? "").trim());
  return 0;
}

// ---- MCP over HTTP+SSE (web_search_prime, web_reader) -----------------------
function parseSse(text: string): any {
  let data: any = null;
  for (const line of text.split("\n")) if (line.startsWith("data:")) { try { data = JSON.parse(line.slice(5).trim()); } catch { /* skip */ } }
  return data;
}
async function mcpRpc(server: string, method: string, params: unknown, sid?: string): Promise<{ sid?: string; data: any }> {
  const headers: Record<string, string> = { Authorization: `Bearer ${key()}`, "Content-Type": "application/json", Accept: "application/json, text/event-stream" };
  if (sid) headers["mcp-session-id"] = sid;
  const r = await fetch(`${MCP}/${server}/mcp`, { method: "POST", headers, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) });
  return { sid: r.headers.get("mcp-session-id") ?? sid, data: parseSse(await r.text()) };
}
async function mcpTool(server: string, name: string, args: Record<string, unknown>): Promise<string> {
  const init = await mcpRpc(server, "initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "zai-cli", version: "1" } });
  await mcpRpc(server, "notifications/initialized", {}, init.sid);
  const res = await mcpRpc(server, "tools/call", { name, arguments: args }, init.sid);
  const content = res.data?.result?.content;
  if (Array.isArray(content)) return content.map((c: any) => c.text ?? "").join("\n");
  return JSON.stringify(res.data?.result ?? res.data, null, 2);
}
async function cmdWebSearch(f: Flags): Promise<number> {
  const q = f.rest.join(" ").trim();
  if (!q) { err('usage: zai websearch [--recency oneWeek] [--size high] [--location us] "query"'); return 2; }
  const args: Record<string, unknown> = { search_query: q };
  if (f.recency) args.search_recency_filter = f.recency;
  if (f.size) args.content_size = f.size;
  if (f.location) args.location = f.location;
  if (f.domain) args.search_domain_filter = f.domain;
  log(await mcpTool("web_search_prime", "web_search_prime", args));
  return 0;
}
async function cmdRead(f: Flags): Promise<number> {
  const url = f.rest[0];
  if (!url) { err("usage: zai read <url>"); return 2; }
  log(await mcpTool("web_reader", "webReader", { url }));
  return 0;
}

// ---- models / quota / doctor ------------------------------------------------
async function cmdModels(): Promise<number> {
  const r = await fetch(`${CODING}/models`, { headers: { Authorization: `Bearer ${key()}` } });
  const d = (await r.json()) as any;
  const ids = (d?.data ?? []).map((m: any) => m.id).filter(Boolean);
  log(`Z.ai coding-plan models (${ids.length}):`);
  for (const id of ids) log(`  ${id}`);
  log("\nVision models (verified, not always in /models): glm-4.6v, glm-4.5v");
  log("Server-side aliases: glm-5→glm-5.2, glm-5.1→glm-5.2, glm-4.5-air→glm-4.7");
  log(`\nPinned latest (verified 2026-07-21): chat/reasoning=${CHAT_MODEL} · vision=${VISION_MODEL}`);
  const newer = ids.filter((id: string) => /^glm-(5\.[3-9]|[6-9])(\D|$)/.test(id));
  log(newer.length ? `⚠️  catalog has newer chat ids than the pin: ${newer.join(", ")} — port CHAT_MODEL in zai.ts` : "✓ no chat model in catalog newer than the pin");
  return 0;
}
async function cmdQuota(): Promise<number> {
  const r = await fetch(QUOTA_URL, { headers: { Authorization: `Bearer ${key()}` } });
  const d = (await r.json()) as any;
  const limits = d?.data?.limits ?? [];
  log(`Z.ai plan level: ${d?.data?.level ?? "?"}`);
  for (const l of limits) {
    log(`  ${l.type} unit=${l.unit} number=${l.number} used=${l.percentage ?? l.currentValue ?? 0}%${l.usageDetails ? " " + JSON.stringify(l.usageDetails) : ""}`);
  }
  return 0;
}
async function cmdDoctor(): Promise<number> {
  try {
    const k = key();
    log(`key: resolved (${k.length} chars)`);
  } catch (e) { err(`key: ${(e as Error).message}`); return 1; }
  const r = await fetch(`${CODING}/chat/completions`, { method: "POST", headers: { Authorization: `Bearer ${key()}`, "Content-Type": "application/json" }, body: JSON.stringify({ model: CHAT_MODEL, messages: [{ role: "user", content: "Reply: OK" }], max_tokens: 8, thinking: { type: "disabled" } }) });
  log(`coding endpoint (${CHAT_MODEL}): HTTP ${r.status} ${r.ok ? "✓" : "✗ " + (await r.text()).slice(0, 120)}`);
  return r.ok ? 0 : 1;
}

// ---- dispatch ---------------------------------------------------------------
const HELP = `zai — Z.ai GLM Coding Plan CLI (verified surface)

  chat [--deep|--fast|--effort low|medium|high|max] [--model glm-5.2] [--file P|-] [--stream] [--json] [--max N] "prompt"
  vision --image <path|url> [--model glm-4.6v] [--deep] "question"
  websearch [--recency oneDay|oneWeek|oneMonth|oneYear] [--size medium|high] [--location cn|us] [--domain d] "query"
  read <url>                     # web_reader MCP
  models | quota | doctor

Modes: fast = thinking:disabled (default). deep = thinking:enabled + reasoning_effort (default high).
Big context: --file feeds up to ~1M input tokens. Max output 131072. Key: GLM_API_KEY | vault get glm api_key.`;

async function main(): Promise<number> {
  const [cmd, ...rest] = Bun.argv.slice(2);
  const f = parse(rest);
  switch (cmd) {
    case "chat": return cmdChat(f);
    case "vision": return cmdVision(f);
    case "websearch": return cmdWebSearch(f);
    case "read": return cmdRead(f);
    case "models": return cmdModels();
    case "quota": return cmdQuota();
    case "doctor": return cmdDoctor();
    default: log(HELP); return cmd ? 0 : 2;
  }
}

try {
  process.exitCode = await main();
} catch (e) {
  err(`ERROR: ${e instanceof Error ? e.message : String(e)}`);
  process.exitCode = 1;
}
