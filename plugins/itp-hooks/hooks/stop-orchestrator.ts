#!/usr/bin/env bun
/**
 * Stop hook orchestrator — runs the 5 itp-hooks Stop hooks in sequence
 * inside a single hook entry. Replaces 5 lines in the "Ran N stop hooks"
 * display with one.
 *
 * Each subhook receives the same stdin payload, gets its own subprocess
 * timeout, and is fully isolated — a crash or timeout in one does not
 * affect the others. We aggregate outputs:
 *
 *   - If any subhook returns `{decision: "block", reason: ...}`, the
 *     orchestrator emits that (first match wins; reasons accumulate
 *     when multiple subhooks block).
 *   - `additionalContext` from multiple subhooks concatenates with
 *     blank-line separators.
 *   - `stop-loop-stall-guard` is the only subhook that legitimately
 *     exits 2 (asyncRewake on detected stall). When it does, the
 *     orchestrator forwards exit 2 + its stderr verbatim — the
 *     orchestrator's own hook entry has `asyncRewake: true` so Claude
 *     Code does the async rewake exactly as before.
 *   - Other subhooks exiting non-zero are logged and treated as silent.
 *
 * Test override: set `SUBHOOKS_DIR` to point at a directory of mock
 * subhooks (named identically). The harness uses this.
 */

import { spawn } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// Single config object centralizing all env-var reads. Adding a new
// override = add a field here, not a scattered `process.env.X` call.
const config = {
  // Test override: point at a directory of mock subhooks. Default: this
  // script's own directory (production deployment).
  subhooksDir: process.env.SUBHOOKS_DIR ?? null,
  // Runner used to execute .ts subhooks. Defaults to `bun`; tests set
  // this to "" so mocks can be invoked directly via shebang. Avoids
  // PATH-shim tricks (which would recurse into the orchestrator itself
  // since its own shebang is `#!/usr/bin/env bun`).
  subhookRunner: process.env.SUBHOOK_RUNNER ?? "bun",
} as const;

interface SubHookConfig {
  name: string;
  script: string;
  timeoutMs: number;
  // True only for stop-loop-stall-guard — its exit 2 maps to orchestrator
  // exit 2, triggering Claude Code's asyncRewake. Other subhooks must
  // not be allowed to trigger asyncRewake (would dilute the signal).
  rewakeOnExit2?: boolean;
}

const SUBHOOKS: SubHookConfig[] = [
  { name: "subprocess-cleanup", script: "stop-subprocess-session-cleanup.ts", timeoutMs: 10000 },
  { name: "error-summary",      script: "stop-hook-error-summary.ts",          timeoutMs: 5000 },
  { name: "ty-check",            script: "stop-ty-project-check.ts",            timeoutMs: 15000 },
  { name: "markdown-lint",      script: "stop-markdown-lint.ts",                timeoutMs: 15000 },
  { name: "loop-stall-guard",   script: "stop-loop-stall-guard.ts",             timeoutMs: 15000, rewakeOnExit2: true },
];

interface SubHookResult {
  name: string;
  exitCode: number;
  stdout: string;
  stderr: string;
  timedOut: boolean;
}

async function runSubHook(cfg: SubHookConfig, dir: string, payload: string): Promise<SubHookResult> {
  return new Promise((resolve) => {
    const scriptPath = join(dir, cfg.script);
    // Pick runner from config: bun for .ts in production, empty for
    // direct shebang-based exec in tests.
    const runner = config.subhookRunner;
    const useRunner = runner && scriptPath.endsWith(".ts");
    const proc = useRunner
      ? spawn(runner, [scriptPath], { stdio: ["pipe", "pipe", "pipe"] })
      : spawn(scriptPath, [], { stdio: ["pipe", "pipe", "pipe"] });

    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];
    let timedOut = false;
    let settled = false;

    proc.stdout.on("data", (c: Buffer) => stdoutChunks.push(c));
    proc.stderr.on("data", (c: Buffer) => stderrChunks.push(c));

    const timer = setTimeout(() => {
      timedOut = true;
      try { proc.kill("SIGKILL"); } catch { /* ignore */ }
    }, cfg.timeoutMs);

    const finish = (exitCode: number) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({
        name: cfg.name,
        exitCode,
        stdout: Buffer.concat(stdoutChunks).toString("utf8"),
        stderr: Buffer.concat(stderrChunks).toString("utf8"),
        timedOut,
      });
    };

    proc.on("error", (err) => {
      stderrChunks.push(Buffer.from(`spawn error: ${err.message}\n`));
      finish(127);
    });
    proc.on("close", (code) => finish(code ?? 0));

    try {
      proc.stdin.write(payload);
      proc.stdin.end();
    } catch {
      // proc.on('error') will fire if spawn failed; ignore here.
    }
  });
}

interface AggregatedOutput {
  decision?: "block";
  reason?: string;
  additionalContext?: string;
}

function parseJSONOrEmpty(text: string): Record<string, unknown> {
  const trimmed = text.trim();
  if (!trimmed) return {};
  try {
    const parsed = JSON.parse(trimmed);
    return typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

async function main() {
  // Pull stdin (Stop hook payload).
  const payloadChunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    payloadChunks.push(Buffer.from(chunk));
  }
  const payload = Buffer.concat(payloadChunks).toString("utf8");

  // stop_hook_active loop guard — Claude Code sets this to true on a
  // re-fire after a previous block decision. Aggregating block-reasons
  // from subhooks could otherwise loop indefinitely (the same subhook
  // returns the same block on every pass). Allow the stop the second
  // time around. Silent exit 0 with empty body.
  try {
    const parsed = JSON.parse(payload);
    if (parsed?.stop_hook_active === true) {
      process.stdout.write("{}");
      return;
    }
  } catch {
    // Invalid/empty payload — fall through, subhooks will handle (or fail
    // silently). Don't block on parse error.
  }

  // Resolve subhook directory. Default: this script's own dir.
  const here = dirname(fileURLToPath(import.meta.url));
  const subhooksDir = config.subhooksDir ?? here;

  // Run subhooks in sequence (same as the original 5 separate hook
  // entries — Claude Code ran them sequentially too, just at the
  // hook-entry layer instead of inside one process).
  const results: SubHookResult[] = [];
  for (const cfg of SUBHOOKS) {
    results.push(await runSubHook(cfg, subhooksDir, payload));
  }

  // Aggregate.
  const aggregated: AggregatedOutput = {};
  const additionalContexts: string[] = [];
  const blockReasons: string[] = [];
  let rewakeRequested = false;
  let rewakeStderr = "";

  for (const r of results) {
    // Forward stderr from any subhook to our stderr (Claude Code shows
    // it in the hook output panel).
    if (r.stderr.trim()) {
      process.stderr.write(`[${r.name}] ${r.stderr}`);
      if (!r.stderr.endsWith("\n")) process.stderr.write("\n");
    }

    // exit-2 from loop-stall-guard → request orchestrator-level asyncRewake.
    const cfg = SUBHOOKS.find((s) => s.name === r.name);
    if (r.exitCode === 2 && cfg?.rewakeOnExit2) {
      rewakeRequested = true;
      rewakeStderr = r.stderr;
      continue;
    }

    // Other non-zero exits → log via stderr (already done above) and skip
    // any output parsing.
    if (r.exitCode !== 0) {
      if (r.timedOut) {
        process.stderr.write(`[${r.name}] timed out after ${cfg?.timeoutMs ?? "?"}ms\n`);
      }
      continue;
    }

    // Parse JSON output and merge.
    const parsed = parseJSONOrEmpty(r.stdout);
    if (parsed.decision === "block") {
      const reason = typeof parsed.reason === "string" ? parsed.reason : "(no reason given)";
      blockReasons.push(`[${r.name}] ${reason}`);
    }
    if (typeof parsed.additionalContext === "string" && parsed.additionalContext.trim()) {
      additionalContexts.push(parsed.additionalContext);
    }
  }

  // If loop-stall-guard fired, propagate exit 2 verbatim — Claude Code's
  // asyncRewake on the orchestrator's hook entry handles the rest.
  if (rewakeRequested) {
    if (rewakeStderr.trim() && !rewakeStderr.endsWith("\n")) process.stderr.write("\n");
    process.exit(2);
  }

  if (blockReasons.length > 0) {
    aggregated.decision = "block";
    aggregated.reason = blockReasons.join("\n\n");
  }
  if (additionalContexts.length > 0) {
    aggregated.additionalContext = additionalContexts.join("\n\n");
  }

  // Empty object = silent allow. JSON.stringify({}) when nothing matters.
  process.stdout.write(JSON.stringify(aggregated));
}

main().catch((err) => {
  // Fail open — orchestrator crash should not wedge the agent.
  process.stderr.write(`[stop-orchestrator] fatal: ${err?.message ?? err}\n`);
  process.stdout.write("{}");
  process.exit(0);
});
