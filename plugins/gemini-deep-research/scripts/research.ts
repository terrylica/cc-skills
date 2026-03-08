#!/usr/bin/env npx tsx
/**
 * Gemini Deep Research — Unified CLI Entrypoint
 *
 * Usage:
 *   npx tsx research.ts "your research query"
 *   npx tsx research.ts --health                   # Check Chrome CDP + Gemini login
 *   npx tsx research.ts --output /tmp/report.md "query"
 *   npx tsx research.ts --output-dir ~/reports "query"  # Auto-named file
 *   npx tsx research.ts --no-confirm "query"        # Don't auto-confirm plan
 *   npx tsx research.ts --firecrawl "query"          # Enable Firecrawl scraping
 *   npx tsx research.ts --timeout 45 "query"         # Max research time in minutes
 *
 * Prerequisites:
 *   1. Chrome running with --remote-debugging-port=9222
 *   2. Logged into gemini.google.com with Gemini Advanced subscription
 *   3. playwright-core installed (bun add playwright-core)
 */

import { chromium } from "playwright-core";
import { GeminiDeepResearchClient, type DeepResearchResult } from "./client.js";

// ── Parse CLI args ──

interface CliConfig {
  query: string;
  cdpUrl: string;
  autoConfirm: boolean;
  enableFirecrawl: boolean;
  firecrawlUrl: string;
  timeoutMin: number;
  outputPath: string | null;
  outputDir: string | null;
  healthCheck: boolean;
  skipPreflight: boolean;
}

function parseArgs(argv: string[]): CliConfig {
  const args = argv.slice(2);
  let cdpUrl = process.env.CHROME_CDP_URL ?? "http://127.0.0.1:9222";
  let autoConfirm = true;
  let enableFirecrawl = false;
  let firecrawlUrl = process.env.FIRECRAWL_URL ?? "http://localhost:3002";
  let timeoutMin = 30;
  let outputPath: string | null = null;
  let outputDir: string | null = null;
  let healthCheck = false;
  let skipPreflight = false;
  const positional: string[] = [];

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--cdp-url" && args[i + 1]) {
      cdpUrl = args[++i];
    } else if (arg === "--no-confirm") {
      autoConfirm = false;
    } else if (arg === "--firecrawl") {
      enableFirecrawl = true;
    } else if (arg === "--firecrawl-url" && args[i + 1]) {
      firecrawlUrl = args[++i];
      enableFirecrawl = true;
    } else if (arg === "--timeout" && args[i + 1]) {
      const val = parseInt(args[++i], 10);
      if (isNaN(val) || val <= 0 || val > 120) {
        console.error(`Error: --timeout must be 1-120 minutes, got: ${args[i]}`);
        process.exit(1);
      }
      timeoutMin = val;
    } else if (arg === "--output" && args[i + 1]) {
      outputPath = args[++i];
    } else if (arg === "--output-dir" && args[i + 1]) {
      outputDir = args[++i];
    } else if (arg === "--health") {
      healthCheck = true;
    } else if (arg === "--no-preflight") {
      skipPreflight = true;
    } else if (arg === "--help" || arg === "-h") {
      console.log(`Usage: npx tsx research.ts [options] "research query"

Commands:
  --health            Check Chrome CDP reachability + Gemini login state

Options:
  --cdp-url URL       Chrome CDP endpoint (default: $CHROME_CDP_URL or http://127.0.0.1:9222)
  --no-confirm        Don't auto-confirm the research plan
  --firecrawl         Enable Firecrawl scraping of share link
  --firecrawl-url URL Firecrawl endpoint (default: $FIRECRAWL_URL or http://localhost:3002)
  --timeout MINUTES   Max research time (default: 30)
  --output PATH       Write report to specific file path
  --output-dir DIR    Auto-save report to DIR/{date}-{slug}.md
  --no-preflight      Skip the preflight health check
  -h, --help          Show this help`);
      process.exit(0);
    } else if (!arg.startsWith("--")) {
      positional.push(arg);
    }
  }

  const query = positional.join(" ");
  if (!healthCheck && !query) {
    console.error('Error: No research query provided. Usage: npx tsx research.ts "your query"');
    process.exit(1);
  }

  return {
    query, cdpUrl, autoConfirm, enableFirecrawl, firecrawlUrl,
    timeoutMin, outputPath, outputDir, healthCheck, skipPreflight,
  };
}

// ── Health check ──

async function runHealthCheck(cdpUrl: string): Promise<boolean> {
  console.log("Checking Chrome CDP...");
  let healthy = false;

  // 1. CDP reachability
  try {
    const resp = await fetch(`${cdpUrl}/json/version`);
    const data = (await resp.json()) as { webSocketDebuggerUrl?: string; Browser?: string };
    console.log(`  CDP: REACHABLE at ${cdpUrl}`);
    console.log(`  Browser: ${data.Browser ?? "unknown"}`);

    // 2. Connect and check for Gemini page + login
    if (data.webSocketDebuggerUrl) {
      try {
        const browser = await chromium.connectOverCDP(data.webSocketDebuggerUrl);
        const ctx = browser.contexts()[0];
        const pages = ctx.pages();
        const geminiPage = pages.find((p) => p.url().includes("gemini.google.com"));

        if (geminiPage) {
          console.log(`  Gemini page: FOUND (${geminiPage.url()})`);

          const loginRequired = await geminiPage.evaluate(() => {
            return (
              document.body.innerText.includes("Sign in") &&
              !document.querySelector('[contenteditable="true"]')
            );
          });

          if (loginRequired) {
            console.log("  Login: REQUIRED — please log in manually in the Chrome window");
          } else {
            console.log("  Login: OK");
            healthy = true;
          }
        } else {
          console.log("  Gemini page: NOT FOUND — navigate to gemini.google.com/app");
        }

        await browser.close();
      } catch (connErr: unknown) {
        const msg = connErr instanceof Error ? connErr.message : String(connErr);
        console.log(`  Browser connection: FAILED — ${msg}`);
      }
    } else {
      console.log("  WebSocket URL: NOT FOUND in CDP response");
    }
  } catch {
    console.log(`  CDP: UNREACHABLE at ${cdpUrl}`);
    console.log(
      "\n  Launch Chrome with:\n" +
        '  /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome \\\n' +
        "    --remote-debugging-port=9222 \\\n" +
        '    --user-data-dir="$HOME/.openclaw/gemini-profile" \\\n' +
        '    "https://gemini.google.com/app"',
    );
  }

  console.log(`\nSTATUS: ${healthy ? "HEALTHY" : "UNHEALTHY"}`);
  return healthy;
}

// ── Slug generation ──

function toSlug(query: string): string {
  return query
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .replace(/\s+/g, "-")
    .slice(0, 60)
    .replace(/-+$/, "");
}

// ── Main ──

async function main() {
  const config = parseArgs(process.argv);

  if (config.healthCheck) {
    const healthy = await runHealthCheck(config.cdpUrl);
    process.exit(healthy ? 0 : 1);
  }

  // ── Preflight: verify Chrome + Gemini login before starting research ──
  if (!config.skipPreflight) {
    console.log("── Preflight ──\n");
    const healthy = await runHealthCheck(config.cdpUrl);
    if (!healthy) {
      console.error("\nPreflight failed. Fix the issues above before running research.");
      console.error("Run with --health to re-check after fixing.");
      process.exit(1);
    }
    console.log();
  }

  console.log(`╔══════════════════════════════════════════════════╗`);
  console.log(`║  Gemini Deep Research                            ║`);
  console.log(`╚══════════════════════════════════════════════════╝`);
  console.log(`Query: ${config.query.slice(0, 80)}${config.query.length > 80 ? "..." : ""}`);
  console.log(`CDP: ${config.cdpUrl} | Timeout: ${config.timeoutMin}min | Auto-confirm: ${config.autoConfirm}`);
  console.log();

  const client = new GeminiDeepResearchClient({
    cdpUrl: config.cdpUrl,
    maxResearchTimeMs: config.timeoutMin * 60 * 1000,
    autoConfirm: config.autoConfirm,
    enableFirecrawl: config.enableFirecrawl,
    firecrawlUrl: config.firecrawlUrl,
    onProgress: (msg) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${msg}`),
  });

  // Graceful shutdown on Ctrl+C
  const shutdown = async () => {
    console.log("\nShutting down...");
    await client.close();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  await client.init();
  const result: DeepResearchResult = await client.research(config.query);
  await client.close();

  // ── Output ──
  console.log("\n" + "═".repeat(60));

  if (result.completed) {
    console.log(`Status: COMPLETED in ${Math.round(result.durationMs / 1000)}s`);
    console.log(`Report: ${result.report.length} chars`);
    if (result.plan) console.log(`Plan: ${result.plan.length} chars`);
    if (result.shareLink) console.log(`Share: ${result.shareLink}`);
    if (result.firecrawlMarkdown) console.log(`Firecrawl: ${result.firecrawlMarkdown.length} chars`);
  } else {
    console.log(`Status: FAILED after ${Math.round(result.durationMs / 1000)}s`);
    console.log(`Error: ${result.error}`);
  }

  // Resolve output path
  let finalOutputPath = config.outputPath;
  if (!finalOutputPath && config.outputDir && result.report) {
    const { mkdirSync } = await import("fs");
    mkdirSync(config.outputDir, { recursive: true });
    const date = new Date().toISOString().split("T")[0];
    const slug = toSlug(config.query);
    finalOutputPath = `${config.outputDir}/${date}-${slug}.md`;
  }

  // Write report
  if (finalOutputPath && result.report) {
    const { writeFileSync } = await import("fs");
    const content = [
      `# Deep Research Report`,
      ``,
      `> Query: ${config.query}`,
      `> Duration: ${Math.round(result.durationMs / 1000)}s`,
      result.shareLink ? `> Share: ${result.shareLink}` : "",
      ``,
      result.plan ? `## Research Plan\n\n${result.plan}\n\n---\n` : "",
      result.report,
    ]
      .filter(Boolean)
      .join("\n");

    writeFileSync(finalOutputPath, content);
    console.log(`\nReport written to: ${finalOutputPath}`);
  } else if (result.report) {
    console.log("\n" + result.report.slice(0, 500) + "...\n");
    console.log(`(${result.report.length} chars total — use --output to save full report)`);
  }
}

main().catch((err) => {
  console.error(`Fatal: ${err.message}`);
  process.exit(1);
});
