// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Cal.com Commander Bot — Always-on Telegram daemon (grammY long polling).
 *
 * Provides slash commands for booking management + AI-powered free-text routing.
 * Runs via launchd KeepAlive (com.terryli.calcom-commander-bot).
 *
 * Entry point: bun run scripts/bot.ts
 */

import { Bot } from "grammy";
import { limit } from "@grammyjs/ratelimiter";
import { sessionGuard } from "./lib/session-guard";
import { loadBotCredentials } from "./lib/credentials";
import { registerCommands } from "./lib/commands";
import { registerCallbacks } from "./lib/callbacks";
import { handleAgentQuery } from "./lib/agent-router";
import { saveState, loadState } from "./lib/state";
import { audit } from "./lib/audit";

const PID_FILE = "/tmp/calcom-commander-bot.pid";
const STATE_SAVE_INTERVAL = 5 * 60 * 1000; // 5 minutes
const CLEANUP_INTERVAL = 60 * 1000; // 1 minute

async function main() {
  // Single-instance guard
  await sessionGuard(PID_FILE);

  const creds = loadBotCredentials();
  const bot = new Bot(creds.botToken);

  // Rate limiting
  bot.use(limit({ timeFrame: 1000, limit: 30 }));

  // Auth guard — only respond to authorized chat
  bot.use(async (ctx, next) => {
    if (String(ctx.chat?.id) !== creds.chatId) return;
    await next();
  });

  // Register slash commands and inline keyboard callbacks
  registerCommands(bot, creds);
  registerCallbacks(bot, creds);

  // Free-text messages → Agent SDK routing
  bot.on("message:text", async (ctx) => {
    await handleAgentQuery(ctx, creds);
  });

  // State management
  const state = loadState();
  state.startedAt = new Date().toISOString();

  const stateInterval = setInterval(() => saveState(state), STATE_SAVE_INTERVAL);
  const cleanupInterval = setInterval(() => {
    // Cleanup expired pending sessions, stale callbacks
  }, CLEANUP_INTERVAL);

  // Graceful shutdown
  const shutdown = async () => {
    clearInterval(stateInterval);
    clearInterval(cleanupInterval);
    saveState(state);
    await bot.stop();
    const fs = await import("fs");
    try { fs.unlinkSync(PID_FILE); } catch {}
    process.exit(0);
  };

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);

  await audit("bot.started", { pid: process.pid });
  console.log("Cal.com Commander bot started");

  // Start long polling
  await bot.start();
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
