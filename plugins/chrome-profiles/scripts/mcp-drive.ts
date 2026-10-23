#!/usr/bin/env bun
// mcp-drive.ts — drive a browser MCP server from Bash, with NO Claude Code restart.
//
// Two transports, one step format:
//   bun mcp-drive.ts ext <account-email> <steps.json>   the profile's Playwright Extension server
//                                                        (chrome-profile.sh playwright-mcp <email>;
//                                                        rides the stored token: no Allow dialog)
//   bun mcp-drive.ts cdp <steps.json>                    chrome-devtools-mcp --autoConnect against the
//                                                        everyday Chrome (sees EVERY profile's tabs; needs
//                                                        chrome://inspect remote debugging ON, and Chrome
//                                                        may ask "Allow remote debugging?" once)
//
// steps.json: [{ "tool": "<mcp tool>", "args": {...}, "quiet": false, "max": 4000 }, ...]
//   quiet: print only ok/ERROR and the result length, never its text (use for any step whose page may
//          hold a secret). Secrets never come back through a step: hand them off by download or vault.
//   max:   truncate printed text to this many characters (default 4000).
// Placeholders in any string arg (cdp mode): {{uid:REGEX}} -> uid of the first line of the LAST
// take_snapshot output matching REGEX (case-insensitive); {{page:REGEX}} -> page id (a number) from the
// LAST list_pages output. Page ids are renumbered per connection: always list_pages in the same run.
//
// Each run is one MCP session. In ext mode every run attaches to a FRESH tab, so a multi-step form must
// be driven inside one step (browser_run_code_unsafe with Playwright locators). That sandbox has no
// `process` and no dynamic import, so it cannot spawn a process: a secret leaves the page only by a
// Blob download (then `vault set --stdin` and delete the file).
// At the end of an ext-mode run its tab is closed (every run's tab used to stay open and pile up in the
// operator's Chrome). Set MCP_DRIVE_KEEP_TAB=1 to keep it, e.g. while a download it started is still writing.
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

type Step = { tool: string; args?: Record<string, unknown>; quiet?: boolean; max?: number };

function usage(): never {
  console.error("usage: mcp-drive.ts ext <account-email> <steps.json> | cdp <steps.json>");
  process.exit(2);
}
const [mode, a1, a2] = process.argv.slice(2);
let cmd: string[];
let stepsPath: string;
if (mode === "ext" && a1 && a2) {
  cmd = ["bash", join(dirname(import.meta.path), "chrome-profile.sh"), "playwright-mcp", a1];
  stepsPath = a2;
} else if (mode === "cdp" && a1) {
  cmd = ["npx", "-y", "chrome-devtools-mcp@latest", "--autoConnect", "--channel", "stable",
    "--userDataDir", `${process.env.HOME}/Library/Application Support/Google/Chrome`, "--no-usage-statistics"];
  stepsPath = a1;
} else usage();

const steps = JSON.parse(readFileSync(stepsPath, "utf8")) as Step[];
// The servers write console/snapshot logs into ./.playwright-mcp of their working directory; run them in a
// private temp dir so a run from inside a repository never leaves page content there (it tripped a leak
// scrub on 2026-10-18). Removed on exit.
const workDir = mkdtempSync(join(tmpdir(), "mcp-drive-"));
const child = spawn(cmd[0], cmd.slice(1), { stdio: ["pipe", "pipe", "pipe"], cwd: workDir });
child.stderr.on("data", () => {}); // server logs are noise and may echo page content; never printed

let buf = "";
const waiters = new Map<number, (m: any) => void>();
child.stdout.on("data", (d) => {
  buf += d.toString();
  for (let i = buf.indexOf("\n"); i >= 0; i = buf.indexOf("\n")) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    try {
      const m = JSON.parse(line);
      if (m.id !== undefined && waiters.has(m.id)) { waiters.get(m.id)!(m); waiters.delete(m.id); }
    } catch { /* not JSON-RPC */ }
  }
});
let nextId = 1;
function rpc(method: string, params: unknown, ms = 180_000): Promise<any> {
  const id = nextId++;
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return new Promise((res, rej) => {
    const t = setTimeout(() => rej(new Error(`timeout on ${method}`)), ms);
    waiters.set(id, (m) => { clearTimeout(t); res(m); });
  });
}

let lastSnap = "";
let lastPages = "";
function subst(v: unknown): unknown {
  if (typeof v === "string") {
    const whole = /^\{\{page:.+\}\}$/.test(v);
    const out = v.replace(/\{\{(uid|page):(.+?)\}\}/g, (_, kind: string, re: string) => {
      const src = kind === "uid" ? lastSnap : lastPages;
      const rx = new RegExp(re, "i");
      const line = src.split("\n").find((l) => rx.test(l));
      if (!line) throw new Error(`no ${kind} line matches /${re}/`);
      const m = kind === "uid" ? line.match(/uid=(\S+)/) : line.match(/^\s*(\d+):/);
      if (!m) throw new Error(`matched line has no ${kind}`);
      return m[1];
    });
    return whole ? Number(out) : out;
  }
  if (Array.isArray(v)) return v.map(subst);
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, subst(x)]));
  return v;
}

let code = 0;
try {
  await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "mcp-drive", version: "1" } });
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  for (const [n, s] of steps.entries()) {
    let args: unknown;
    try { args = subst(s.args ?? {}); } catch (e) { console.log(`[${n}] ${s.tool}: PLACEHOLDER ERROR ${e}`); code = 1; break; }
    const m = await rpc("tools/call", { name: s.tool, arguments: args });
    const isErr = !!(m.error || m.result?.isError);
    const text = m.error
      ? JSON.stringify(m.error)
      : (m.result?.content ?? []).filter((c: any) => c.type === "text").map((c: any) => c.text).join("\n");
    if (s.tool === "take_snapshot") lastSnap = text;
    if (s.tool === "list_pages") lastPages = text;
    if (s.quiet) console.log(`[${n}] ${s.tool}: ${isErr ? "ERROR" : "ok"} (${text.length} chars, suppressed)`);
    else console.log(`[${n}] ${s.tool}: ${isErr ? "ERROR" : "ok"}\n${text.slice(0, s.max ?? 4000)}`);
    if (isErr) { code = 1; break; }
  }
} catch (e) {
  console.error(String(e));
  code = 1;
}
// Ext mode opens a FRESH tab per run. Left open, every run adds a renderer to the operator's Chrome,
// and a long session of agent runs accumulated dozens of tabs and gigabytes (measured 2026-10-22:
// 8.7 GB across 70 renderers). Close this run's tab unless the caller asks to keep it.
if (mode === "ext" && process.env.MCP_DRIVE_KEEP_TAB !== "1") {
  try {
    await Promise.race([
      // browser_close only detaches in extension mode (measured: the tab stayed open), so close the
      // page itself. The connection drops with it, which is expected at this point.
      rpc("tools/call", { name: "browser_run_code_unsafe", arguments: { code: "async (page) => { await page.close(); }" } }),
      new Promise((r) => setTimeout(r, 5000)),
    ]);
  } catch {
    console.error("mcp-drive: could not close this run's tab; close it by hand");
  }
}
child.kill();
rmSync(workDir, { recursive: true, force: true });
process.exit(code);
