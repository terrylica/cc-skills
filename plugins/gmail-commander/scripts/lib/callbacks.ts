// PROCESS-STORM-OK
/**
 * Inline Keyboard Callback Handlers
 *
 * Handles button presses from email list Read/Reply buttons.
 * Pattern from claude-telegram-sync/src/telegram/commands.ts.
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

import { Bot } from "grammy";
import type { BotState } from "./state.js";
import { getCallbackData } from "./commands.js";
import { readEmail } from "./gmail-client.js";
import { escapeHtml } from "./telegram-format.js";
import { chunkTelegramHtml } from "./telegram-chunk.js";
import { auditLog } from "./audit.js";
import { InlineKeyboard } from "grammy";

/**
 * Pending compose/reply sessions — maps chatId to pending state.
 * Cleared after 5 minutes or after completion.
 */
export type PendingSession = {
  type: "compose" | "reply";
  step: "to" | "subject" | "body" | "alias";
  messageId?: string; // original message ID for replies
  to?: string;
  from?: string;
  subject?: string;
  expiresAt: number;
};

export const pendingSessions = new Map<number, PendingSession>();
const PENDING_TTL_MS = 5 * 60 * 1000; // 5 minutes

export function clearExpiredSessions(): void {
  const now = Date.now();
  for (const [chatId, session] of pendingSessions) {
    if (now >= session.expiresAt) {
      pendingSessions.delete(chatId);
    }
  }
}

/**
 * Register callback query handlers.
 */
export function registerCallbacks(bot: Bot, _state: BotState) {
  // Handle read:<index> — read an email from the list
  bot.callbackQuery(/^read:(\d+)$/, async (ctx) => {
    const index = ctx.match![1]!;
    const chatId = ctx.chat?.id;
    if (!chatId) return;

    const data = getCallbackData(chatId, index);
    if (!data) {
      await ctx.answerCallbackQuery({ text: "Session expired. Use /inbox again." });
      return;
    }

    await ctx.answerCallbackQuery({ text: `Reading email...` });

    try {
      const content = await readEmail(data.messageId);

      const keyboard = new InlineKeyboard()
        .text("Reply", `reply_direct:${data.messageId}`)
        .url("Open in Gmail", `https://mail.google.com/mail/u/0/#inbox/${data.messageId}`);

      const escaped = escapeHtml(content);
      // Reserve space for <pre></pre> tags (11 chars) in each chunk
      const chunks = chunkTelegramHtml(escaped, 4096 - 11).map(c => `<pre>${c}</pre>`);

      // First chunk with buttons
      await ctx.reply(chunks[0]!, {
        parse_mode: "HTML",
        reply_markup: keyboard,
      });

      // Additional chunks without buttons
      for (let i = 1; i < chunks.length; i++) {
        await ctx.reply(chunks[i]!, { parse_mode: "HTML" });
      }

      auditLog("bot.callback_read", { messageId: data.messageId });
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      await ctx.reply(`<b>Error reading email</b>: ${escapeHtml(msg)}`, { parse_mode: "HTML" });
      auditLog("bot.callback_read_error", { error: msg });
    }
  });

  // Handle reply:<index> — start reply flow from list button
  bot.callbackQuery(/^reply:(\d+)$/, async (ctx) => {
    const index = ctx.match![1]!;
    const chatId = ctx.chat?.id;
    if (!chatId) return;

    const data = getCallbackData(chatId, index);
    if (!data) {
      await ctx.answerCallbackQuery({ text: "Session expired. Use /inbox again." });
      return;
    }

    await ctx.answerCallbackQuery({ text: "Starting reply..." });

    // Set up pending reply session — go straight to body
    pendingSessions.set(chatId, {
      type: "reply",
      step: "body",
      messageId: data.messageId,
      to: data.from,
      subject: `Re: ${data.subject}`,
      expiresAt: Date.now() + PENDING_TTL_MS,
    });

    await ctx.reply(
      `<b>Reply to</b>: ${escapeHtml(data.from)}\n` +
      `<b>Subject</b>: Re: ${escapeHtml(data.subject)}\n\n` +
      `<i>Type your reply message:</i>`,
      { parse_mode: "HTML" }
    );

    auditLog("bot.callback_reply_start", { messageId: data.messageId });
  });

  // Handle reply_direct:<messageId> — start reply from read view
  bot.callbackQuery(/^reply_direct:(.+)$/, async (ctx) => {
    const messageId = ctx.match![1]!;
    const chatId = ctx.chat?.id;
    if (!chatId) return;

    await ctx.answerCallbackQuery({ text: "Starting reply..." });

    pendingSessions.set(chatId, {
      type: "reply",
      step: "body",
      messageId,
      expiresAt: Date.now() + PENDING_TTL_MS,
    });

    await ctx.reply(
      `<b>Replying to message</b>: <code>${escapeHtml(messageId)}</code>\n\n` +
      `<i>Type your reply message:</i>`,
      { parse_mode: "HTML" }
    );

    auditLog("bot.callback_reply_direct", { messageId });
  });
}
