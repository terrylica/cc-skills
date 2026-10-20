// mcp.ts — reach a browser through a Playwright MCP server, in either connection mode (lib/forge-chrome.mjs):
//   • extension — a signed-in profile of the operator's everyday Chrome, chosen by account email (chrome-profiles'
//                 Playwright Extension). The extension attaches each session to a FRESH tab, which stays open.
//   • cdp       — the persistent per-site forge profile on its own debug port (launched here if it is not up).
//
// Two transports, one interface (`Browser.call(tool, args)`):
//   • StdioBrowser  — spawns the mode's MCP server for this run only.
//   • BridgeBrowser — talks to a long-lived bridge started by `web-forge serve`, so successive runs share ONE tab
//                     (useful while a human passes a "verify it's you" prompt in it).
// The bridge answers GET /info with {target, workDir}; a client refuses a bridge that serves a different target,
// so a run can never drive the wrong identity's browser.
import { type ChildProcessWithoutNullStreams, spawn } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { launchChrome, mcpCommand } from "../../lib/forge-chrome.mjs";

export type Connect = "extension" | "cdp";

/** What to drive: an account's everyday-Chrome profile, or a per-site forge profile. */
export type Target = { mode: "extension"; account: string } | { mode: "cdp"; site: string };

/** Pure: a stable key for a target; a bridge serves exactly one. */
export function targetKey(t: Target): string {
  return t.mode === "extension" ? `extension:${t.account.toLowerCase()}` : `cdp:${t.site}`;
}

export interface CallResult {
  text: string;
  isError: boolean;
}

export interface Browser {
  readonly describe: string;
  /** Directory the MCP server writes into; screenshots must be saved under it. */
  readonly workDir: string;
  call(tool: string, args?: Record<string, unknown>, timeoutMs?: number): Promise<CallResult>;
  close(): Promise<void>;
}

function resultText(m: any): CallResult {
  if (m.error) return { text: JSON.stringify(m.error), isError: true };
  const text = (m.result?.content ?? [])
    .filter((c: any) => c.type === "text")
    .map((c: any) => c.text)
    .join("\n");
  return { text, isError: !!m.result?.isError };
}

/** One JSON-RPC session over a child's stdio. */
export class StdioSession {
  private buf = "";
  private nextId = 1;
  private waiters = new Map<number, (m: any) => void>();
  private constructor(private child: ChildProcessWithoutNullStreams) {
    child.stdout.on("data", (d) => {
      this.buf += d.toString();
      for (let i = this.buf.indexOf("\n"); i >= 0; i = this.buf.indexOf("\n")) {
        const line = this.buf.slice(0, i).trim();
        this.buf = this.buf.slice(i + 1);
        if (!line) continue;
        try {
          const m = JSON.parse(line);
          if (m.id !== undefined && this.waiters.has(m.id)) {
            this.waiters.get(m.id)!(m);
            this.waiters.delete(m.id);
          }
        } catch {
          /* not JSON-RPC */
        }
      }
    });
    // Server logs may echo page content: never printed.
    child.stderr.on("data", () => {});
  }

  static async start(target: Target, workDir: string): Promise<StdioSession> {
    if (target.mode === "cdp") await launchChrome(target.site);
    const [cmd, ...args] = mcpCommand(target.mode, target) as string[];
    const child = spawn(cmd!, args, { stdio: ["pipe", "pipe", "pipe"], cwd: workDir });
    const s = new StdioSession(child);
    const hint = target.mode === "extension" ? `is ${target.account} a Chrome profile with the Playwright Extension set up? (chrome-profile.sh doctor)` : `is the ${target.site} forge Chrome up?`;
    const exited = new Promise<never>((_, rej) => child.once("exit", (c) => rej(new Error(`playwright-mcp exited (${c}) before initialising: ${hint}`))));
    await Promise.race([s.rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "web-forge", version: "1" } }, 60_000), exited]);
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
    return s;
  }

  rpc(method: string, params: unknown, ms = 180_000): Promise<any> {
    const id = this.nextId++;
    this.child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    return new Promise((res, rej) => {
      const t = setTimeout(() => {
        this.waiters.delete(id);
        rej(new Error(`timeout after ${ms} ms on ${method}`));
      }, ms);
      this.waiters.set(id, (m) => {
        clearTimeout(t);
        res(m);
      });
    });
  }

  async call(tool: string, args: Record<string, unknown> = {}, ms?: number): Promise<CallResult> {
    return resultText(await this.rpc("tools/call", { name: tool, arguments: args }, ms));
  }

  onExit(fn: (code: number | null) => void): void {
    this.child.once("exit", fn);
  }

  kill(): void {
    this.child.kill();
  }
}

function privateWorkDir(prefix: string): string {
  const workDir = mkdtempSync(join(tmpdir(), prefix));
  mkdirSync(join(workDir, ".playwright-mcp"), { recursive: true });
  return workDir;
}

export class StdioBrowser implements Browser {
  readonly describe: string;
  private constructor(
    private s: StdioSession,
    readonly workDir: string,
    target: Target,
  ) {
    this.describe = `stdio playwright-mcp for ${targetKey(target)}`;
  }
  static async open(target: Target): Promise<StdioBrowser> {
    const workDir = privateWorkDir("web-forge-");
    return new StdioBrowser(await StdioSession.start(target, workDir), workDir, target);
  }
  call(tool: string, args: Record<string, unknown> = {}, ms?: number): Promise<CallResult> {
    return this.s.call(tool, args, ms);
  }
  async close(): Promise<void> {
    this.s.kill();
    rmSync(this.workDir, { recursive: true, force: true });
  }
}

export class BridgeBrowser implements Browser {
  readonly describe: string;
  private constructor(
    private base: string,
    readonly workDir: string,
    key: string,
  ) {
    this.describe = `bridge ${base} for ${key}`;
  }
  static async open(port: number, target: Target): Promise<BridgeBrowser | null> {
    const base = `http://127.0.0.1:${port}`;
    let info: { target?: string; workDir?: string };
    try {
      const r = await fetch(`${base}/info`, { signal: AbortSignal.timeout(3000) });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      info = await r.json();
    } catch {
      return null; // nothing (or not ours) listening
    }
    const want = targetKey(target);
    if (info.target !== want) throw new Error(`the bridge on port ${port} serves ${info.target ?? "an unknown target"}, not ${want}: refusing to drive it`);
    return new BridgeBrowser(base, info.workDir ?? tmpdir(), want);
  }
  async call(tool: string, args: Record<string, unknown> = {}, ms = 180_000): Promise<CallResult> {
    const r = await fetch(`${this.base}/`, { method: "POST", body: JSON.stringify({ tool, args, timeoutMs: ms }), signal: AbortSignal.timeout(ms + 5000) });
    return (await r.json()) as CallResult;
  }
  async close(): Promise<void> {
    /* the bridge outlives the run */
  }
}

/** Reuse a bridge on `port` when one serves `target`; otherwise open a stdio session for this run. */
export async function connect(target: Target, port?: number): Promise<Browser> {
  if (port) {
    const b = await BridgeBrowser.open(port, target);
    if (b) return b;
  }
  return StdioBrowser.open(target);
}

/** Foreground bridge: one stdio session, served on 127.0.0.1:<port>. GET /quit stops it. */
export async function serve(target: Target, port: number): Promise<void> {
  const workDir = privateWorkDir("web-forge-bridge-");
  const s = await StdioSession.start(target, workDir);
  const key = targetKey(target);
  const stop = (code: number) => {
    s.kill();
    rmSync(workDir, { recursive: true, force: true });
    process.exit(code);
  };
  s.onExit(() => stop(1));
  process.on("SIGTERM", () => stop(0));
  process.on("SIGINT", () => stop(0));
  Bun.serve({
    hostname: "127.0.0.1",
    port,
    idleTimeout: 255,
    async fetch(req) {
      const path = new URL(req.url).pathname;
      if (path === "/info") return Response.json({ target: key, workDir, pid: process.pid });
      if (path === "/quit") {
        setTimeout(() => stop(0), 100);
        return new Response("bye");
      }
      if (req.method !== "POST") return new Response("POST {tool,args}", { status: 405 });
      const { tool, args, timeoutMs } = (await req.json()) as { tool: string; args?: Record<string, unknown>; timeoutMs?: number };
      try {
        return Response.json(await s.call(tool, args ?? {}, timeoutMs));
      } catch (e) {
        return Response.json({ text: String(e), isError: true });
      }
    },
  });
  console.log(JSON.stringify({ ok: true, serving: key, port, workDir, pid: process.pid }));
}
