// PROCESS-STORM-OK
/**
 * Telegram Bot Factory (grammY)
 *
 * Creates and configures Telegram bot with HTML formatting and rate limiting.
 * Pattern from claude-telegram-sync/src/telegram/bot.ts.
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

import { Bot } from "grammy";
import { limit } from "@grammyjs/ratelimiter";

export interface BotConfig {
  token: string;
  chatId: number;
  rateLimit?: {
    timeFrame?: number;
    limit?: number;
  };
}

export function createTelegramBot(config: BotConfig): Bot {
  const bot = new Bot(config.token);

  const rateLimitConfig = config.rateLimit ?? {
    timeFrame: 1000,
    limit: 30, // Telegram's per-second limit
  };

  bot.use(
    limit({
      timeFrame: rateLimitConfig.timeFrame,
      limit: rateLimitConfig.limit,
      onLimitExceeded: async (ctx) => {
        console.error("Rate limit exceeded", {
          chatId: ctx.chat?.id,
          updateId: ctx.update.update_id,
        });
      },
    })
  );

  return bot;
}

export function loadBotCredentials(): BotConfig {
  const token = Bun.env.TELEGRAM_BOT_TOKEN || "";
  const chatId = parseInt(Bun.env.TELEGRAM_CHAT_ID || "0", 10);

  if (!token) throw new Error("Missing TELEGRAM_BOT_TOKEN");
  if (!chatId) throw new Error("Missing TELEGRAM_CHAT_ID");

  return { token, chatId };
}
