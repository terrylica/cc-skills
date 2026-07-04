// webauth-agent.mjs — optional memory-only session agent (ssh-agent pattern).
//
// Holds the UNLOCKED github-web-<account> blob in RAM so repeated `pat` commands
// in one session reuse a single Touch-ID unlock (the operator's hard requirement:
// one tap, then nothing). The foreground `pat` process does the actual Touch-ID
// `vault get --gated` (correct GUI context) and PUTs the result here; later
// commands GET it with zero prompts. Nothing is written to disk; entries expire.
//
//   node webauth-agent.mjs serve     # run the agent (usually backgrounded)
//   (clients use the get/put/status/stop helpers below)

import net from "node:net";
import { existsSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const UID = process.getuid?.() ?? "u";
export const AGENT_SOCK = process.env.GH_PAT_AGENT_SOCK ?? join(tmpdir(), `gh-pat-webauth-${UID}.sock`);
const DEFAULT_TTL_MS = Number(process.env.GH_PAT_AGENT_TTL_MS ?? 8 * 60 * 60 * 1000); // session-ish: 8h
const fresh = (e) => e && e.expiresAt > Date.now();

// ---- client helpers (used by autosudo) -------------------------------------
function request(payload, { timeoutMs = 2000 } = {}) {
  return new Promise((resolve) => {
    if (!existsSync(AGENT_SOCK)) return resolve({ ok: false, reason: "no-agent" });
    const sock = net.connect(AGENT_SOCK);
    let buf = "";
    const done = (v) => {
      try {
        sock.destroy();
      } catch {
        /* noop */
      }
      resolve(v);
    };
    const t = setTimeout(() => done({ ok: false, reason: "timeout" }), timeoutMs);
    sock.on("connect", () => sock.end(JSON.stringify(payload)));
    sock.on("data", (d) => (buf += d));
    sock.on("end", () => {
      clearTimeout(t);
      try {
        done(JSON.parse(buf));
      } catch {
        done({ ok: false, reason: "bad-reply" });
      }
    });
    sock.on("error", () => {
      clearTimeout(t);
      done({ ok: false, reason: "no-agent" });
    });
  });
}

export const agentGet = (account) => request({ op: "get", account });
export const agentPut = (account, blob, ttlMs) => request({ op: "put", account, blob, ttlMs });
export const agentStatus = () => request({ op: "status" });
export const agentStop = () => request({ op: "stop" });
export const agentRunning = () => existsSync(AGENT_SOCK);

// ---- server ----------------------------------------------------------------
export function serve() {
  if (existsSync(AGENT_SOCK)) {
    try {
      unlinkSync(AGENT_SOCK);
    } catch {
      /* noop */
    }
  }
  const store = new Map(); // account -> { blob, expiresAt }

  const server = net.createServer((sock) => {
    let buf = "";
    sock.on("data", (d) => (buf += d));
    sock.on("end", () => {
      let req;
      try {
        req = JSON.parse(buf);
      } catch {
        return sock.end(JSON.stringify({ ok: false, reason: "bad-request" }));
      }
      switch (req.op) {
        case "get": {
          const e = store.get(req.account);
          return sock.end(JSON.stringify(fresh(e) ? { ok: true, blob: e.blob } : { ok: false, reason: "miss" }));
        }
        case "put": {
          store.set(req.account, { blob: req.blob, expiresAt: Date.now() + (req.ttlMs ?? DEFAULT_TTL_MS) });
          return sock.end(JSON.stringify({ ok: true }));
        }
        case "status": {
          const accounts = [...store.entries()].filter(([, e]) => fresh(e)).map(([a]) => a);
          return sock.end(JSON.stringify({ ok: true, accounts, pid: process.pid }));
        }
        case "stop": {
          sock.end(JSON.stringify({ ok: true, stopping: true }));
          server.close();
          try {
            unlinkSync(AGENT_SOCK);
          } catch {
            /* noop */
          }
          return process.exit(0);
        }
        default:
          return sock.end(JSON.stringify({ ok: false, reason: "unknown-op" }));
      }
    });
  });
  server.listen(AGENT_SOCK, () => console.error(`webauth-agent listening at ${AGENT_SOCK} (pid ${process.pid})`));
  for (const sig of ["SIGINT", "SIGTERM"]) {
    process.on(sig, () => {
      try {
        unlinkSync(AGENT_SOCK);
      } catch {
        /* noop */
      }
      process.exit(0);
    });
  }
}

if (import.meta.url === `file://${process.argv[1]}` && process.argv[2] === "serve") serve();
