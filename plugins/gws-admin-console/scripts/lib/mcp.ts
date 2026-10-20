// mcp.ts — reach a signed-in Chrome profile through Microsoft's Playwright Extension MCP server.
//
// Two transports, one interface (`Browser.call(tool, args)`):
//   • StdioBrowser  — spawns `chrome-profile.sh playwright-mcp <email>` for this run only. The extension
//                     attaches the session to a FRESH tab, which stays open after the run.
//   • BridgeBrowser — talks to a long-lived bridge started by `gws-admin-console serve`, so successive
//                     runs share ONE tab (useful while a human passes a "verify it's you" prompt in it).
// The bridge answers GET /info with {account, workDir}; a client refuses a bridge that serves a different
// account, so a run can never drive the wrong identity's browser.
import { spawn, type ChildProcessWithoutNullStreams, execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";

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

/** Locate chrome-profile.sh from the sibling chrome-profiles plugin. */
export function chromeProfileScript(): string {
  const env = process.env.GWS_ADMIN_CHROME_PROFILE_SH;
  if (env) return env;
  try {
    const root = execFileSync("cc-plugin-root", ["chrome-profiles"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
    const p = join(root, "scripts", "chrome-profile.sh");
    if (root && existsSync(p)) return p;
  } catch {
    /* resolver absent: fall through to the sibling checkout layout */
  }
  const sibling = resolve(dirname(import.meta.path), "..", "..", "..", "chrome-profiles", "scripts", "chrome-profile.sh");
  if (existsSync(sibling)) return sibling;
  throw new Error("chrome-profiles plugin not found: install it, or set GWS_ADMIN_CHROME_PROFILE_SH");
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

  static async start(account: string, workDir: string): Promise<StdioSession> {
    const child = spawn("bash", [chromeProfileScript(), "playwright-mcp", account], { stdio: ["pipe", "pipe", "pipe"], cwd: workDir });
    const s = new StdioSession(child);
    const exited = new Promise<never>((_, rej) => child.once("exit", (c) => rej(new Error(`playwright-mcp exited (${c}) before initialising: is ${account} a Chrome profile with the Playwright Extension set up? (chrome-profile.sh doctor)`))));
    await Promise.race([s.rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "gws-admin-console", version: "1" } }, 60_000), exited]);
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

export class StdioBrowser implements Browser {
  readonly describe: string;
  private constructor(private s: StdioSession, readonly workDir: string, account: string) {
    this.describe = `stdio playwright-mcp for ${account}`;
  }
  static async open(account: string): Promise<StdioBrowser> {
    const workDir = mkdtempSync(join(tmpdir(), "gws-admin-console-"));
    mkdirSync(join(workDir, ".playwright-mcp"), { recursive: true });
    return new StdioBrowser(await StdioSession.start(account, workDir), workDir, account);
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
  private constructor(private base: string, readonly workDir: string, account: string) {
    this.describe = `bridge ${base} for ${account}`;
  }
  static async open(port: number, account: string): Promise<BridgeBrowser | null> {
    const base = `http://127.0.0.1:${port}`;
    let info: { account?: string; workDir?: string };
    try {
      const r = await fetch(`${base}/info`, { signal: AbortSignal.timeout(3000) });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      info = await r.json();
    } catch {
      return null; // nothing (or not ours) listening
    }
    if (!info.account || info.account.toLowerCase() !== account.toLowerCase()) {
      throw new Error(`the bridge on port ${port} serves ${info.account ?? "an unknown account"}, not ${account}: refusing to drive it`);
    }
    return new BridgeBrowser(base, info.workDir ?? tmpdir(), account);
  }
  async call(tool: string, args: Record<string, unknown> = {}, ms = 180_000): Promise<CallResult> {
    const r = await fetch(`${this.base}/`, { method: "POST", body: JSON.stringify({ tool, args, timeoutMs: ms }), signal: AbortSignal.timeout(ms + 5000) });
    return (await r.json()) as CallResult;
  }
  async close(): Promise<void> {
    /* the bridge outlives the run */
  }
}

/** Reuse a bridge on `port` when one serves `account`; otherwise open a stdio session for this run. */
export async function connect(account: string, port?: number): Promise<Browser> {
  if (port) {
    const b = await BridgeBrowser.open(port, account);
    if (b) return b;
  }
  return StdioBrowser.open(account);
}

/** Foreground bridge: one stdio session, served on 127.0.0.1:<port>. GET /quit stops it. */
export async function serve(account: string, port: number): Promise<void> {
  const workDir = mkdtempSync(join(tmpdir(), "gws-admin-console-bridge-"));
  mkdirSync(join(workDir, ".playwright-mcp"), { recursive: true });
  const s = await StdioSession.start(account, workDir);
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
      if (path === "/info") return Response.json({ account, workDir, pid: process.pid });
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
  console.log(JSON.stringify({ ok: true, serving: account, port, workDir, pid: process.pid }));
}
