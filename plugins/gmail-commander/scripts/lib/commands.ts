// PROCESS-STORM-OK
/**
 * Telegram Command Handlers
 *
 * BOT_COMMANDS SSoT + slash command handlers for deterministic commands.
 * Pattern from claude-telegram-sync/src/telegram/commands.ts.
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

import { query } from "@anthropic-ai/claude-agent-sdk";
import { Bot, InlineKeyboard } from "grammy";
import type { BotState } from "./state.js";
import { listInboxEmails, searchEmails, readEmail, fetchRecentEmails, listDrafts } from "./gmail-client.js";
import { escapeHtml, formatEmailList, formatDigestHtml, formatEmailReadView } from "./telegram-format.js";
import { chunkTelegramHtml } from "./telegram-chunk.js";
import { parseTriageResponse, formatEmailsForTriage, isSkillContaminated, TRIAGE_SYSTEM_PROMPT, ANTI_SKILL_PREFIX } from "./triage.js";
import { auditLog } from "./audit.js";

/**
 * Command definitions — single source of truth for both
 * Telegram's native menu (setMyCommands) and handler registration.
 */
export const BOT_COMMANDS = [
  { command: "inbox", description: "Show recent inbox emails" },
  { command: "search", description: "Search emails (Gmail query syntax)" },
  { command: "read", description: "Read email by ID" },
  { command: "compose", description: "Compose a new email" },
  { command: "reply", description: "Reply to an email" },
  { command: "drafts", description: "List draft emails" },
  { command: "digest", description: "Run email digest now" },
  { command: "status", description: "Bot status and stats" },
  { command: "help", description: "Show all commands" },
] as const;

/**
 * Callback data lookup — maps short index to message IDs.
 * Telegram limits callback_data to 64 bytes, so we can't embed full IDs.
 * Keyed by chatId:index, ephemeral (cleared on each list invocation).
 */
const callbackLookup = new Map<string, { messageId: string; from: string; subject: string }>();
let callbackCounter = 0;

function registerCallback(chatId: number, messageId: string, from: string, subject: string): string {
  const key = `${chatId}:${++callbackCounter}`;
  callbackLookup.set(key, { messageId, from, subject });
  // Evict old entries
  if (callbackLookup.size > 200) {
    const first = callbackLookup.keys().next().value;
    if (first !== undefined) callbackLookup.delete(first);
  }
  return String(callbackCounter);
}

export function getCallbackData(chatId: number, index: string) {
  return callbackLookup.get(`${chatId}:${index}`);
}

function formatUptime(startedAt: Date): string {
  const ms = Date.now() - startedAt.getTime();
  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  if (hours > 0) return `${hours}h ${minutes % 60}m`;
  if (minutes > 0) return `${minutes}m ${seconds % 60}s`;
  return `${seconds}s`;
}

/**
 * Register commands with Telegram's native menu UI.
 */
export async function setCommandMenu(bot: Bot): Promise<void> {
  await bot.api.setMyCommands([...BOT_COMMANDS]);
  console.error(`Registered ${BOT_COMMANDS.length} commands with Telegram menu`);
}

/**
 * Register all command handlers with the bot.
 */
export function registerCommands(
  bot: Bot,
  state: BotState,
  authorizedChatId: number,
  sessions?: Map<number, { type: string; step: string; messageId?: string; to?: string; from?: string; subject?: string; expiresAt: number }>
) {
  // Auth guard — only respond to authorized chat
  bot.use(async (ctx, next) => {
    if (ctx.chat?.id !== authorizedChatId) {
      await ctx.reply("Unauthorized.");
      return;
    }
    state.incrementMessages();
    await next();
  });

  // /help
  bot.command("help", async (ctx) => {
    state.incrementCommands();
    const lines = BOT_COMMANDS.map((c) => `/${c.command} — ${c.description}`);
    await ctx.reply(
      `<b>Gmail Commander</b>\n\n${lines.join("\n")}\n\n<i>Or just type a question — AI will help!</i>`,
      { parse_mode: "HTML" }
    );
  });

  // /status
  bot.command("status", async (ctx) => {
    state.incrementCommands();
    await ctx.reply(
      `<b>Gmail Commander Status</b>\n\n` +
      `<b>Statistics</b>:\n` +
      `\u2022 Messages received: ${state.messagesReceived}\n` +
      `\u2022 Commands processed: ${state.commandsProcessed}\n` +
      `\u2022 Agent queries: ${state.agentQueries}\n` +
      `\u2022 Agent failed: ${state.agentFailed}\n` +
      `\u2022 Digests triggered: ${state.digestsTriggered}\n` +
      `\u2022 Drafts created: ${state.draftsCreated}\n` +
      `\u2022 Uptime: ${formatUptime(state.startedAt)}`,
      { parse_mode: "HTML" }
    );
  });

  // /inbox [count]
  bot.command("inbox", async (ctx) => {
    state.incrementCommands();
    const text = (ctx.message?.text || "").replace(/^\/inbox\s*/, "").trim();
    const count = parseInt(text, 10) || 10;

    const thinking = await ctx.reply("<i>Fetching inbox...</i>", { parse_mode: "HTML" });

    try {
      const emails = await listInboxEmails(Math.min(count, 50));
      const formatted = formatEmailList(emails);

      // Build inline keyboard with Read/Reply buttons
      const keyboard = new InlineKeyboard();
      for (let i = 0; i < Math.min(emails.length, 10); i++) {
        const email = emails[i]!;
        const cbId = registerCallback(ctx.chat.id, email.id, email.from, email.subject);
        keyboard.text(`Read #${i + 1}`, `read:${cbId}`).text(`Reply #${i + 1}`, `reply:${cbId}`).row();
      }

      const chunks = chunkTelegramHtml(`<b>Inbox</b> (${emails.length} emails)\n\n${formatted}`, 4096);

      // First chunk with buttons
      await ctx.api.editMessageText(ctx.chat.id, thinking.message_id, chunks[0]!, {
        parse_mode: "HTML",
        reply_markup: emails.length > 0 ? keyboard : undefined,
        link_preview_options: { is_disabled: true },
      });

      // Additional chunks without buttons
      for (let i = 1; i < chunks.length; i++) {
        await ctx.reply(chunks[i]!, {
          parse_mode: "HTML",
          link_preview_options: { is_disabled: true },
        });
      }

      auditLog("bot.inbox", { count: emails.length });
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      await ctx.api.editMessageText(ctx.chat.id, thinking.message_id,
        `<b>Error</b>: ${escapeHtml(msg)}`, { parse_mode: "HTML" });
      auditLog("bot.inbox_error", { error: msg });
    }
  });

  // /search <query>
  bot.command("search", async (ctx) => {
    state.incrementCommands();
    const query = (ctx.message?.text || "").replace(/^\/search\s*/, "").trim();

    if (!query) {
      await ctx.reply(
        `<b>Usage</b>: /search &lt;Gmail query&gt;\n\n` +
        `<b>Examples</b>:\n` +
        `/search from:alice\n` +
        `/search subject:meeting after:2026/02/01\n` +
        `/search is:unread has:attachment`,
        { parse_mode: "HTML" }
      );
      return;
    }

    const thinking = await ctx.reply(`<i>Searching: ${escapeHtml(query)}...</i>`, { parse_mode: "HTML" });

    try {
      const emails = await searchEmails(query);
      const formatted = formatEmailList(emails);

      const keyboard = new InlineKeyboard();
      for (let i = 0; i < Math.min(emails.length, 10); i++) {
        const email = emails[i]!;
        const cbId = registerCallback(ctx.chat.id, email.id, email.from, email.subject);
        keyboard.text(`Read #${i + 1}`, `read:${cbId}`).text(`Reply #${i + 1}`, `reply:${cbId}`).row();
      }

      const chunks = chunkTelegramHtml(
        `<b>Search</b>: <code>${escapeHtml(query)}</code> (${emails.length} results)\n\n${formatted}`,
        4096
      );

      await ctx.api.editMessageText(ctx.chat.id, thinking.message_id, chunks[0]!, {
        parse_mode: "HTML",
        reply_markup: emails.length > 0 ? keyboard : undefined,
        link_preview_options: { is_disabled: true },
      });

      for (let i = 1; i < chunks.length; i++) {
        await ctx.reply(chunks[i]!, {
          parse_mode: "HTML",
          link_preview_options: { is_disabled: true },
        });
      }

      auditLog("bot.search", { query, count: emails.length });
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      await ctx.api.editMessageText(ctx.chat.id, thinking.message_id,
        `<b>Error</b>: ${escapeHtml(msg)}`, { parse_mode: "HTML" });
      auditLog("bot.search_error", { query, error: msg });
    }
  });

  // /read <message_id>
  bot.command("read", async (ctx) => {
    state.incrementCommands();
    const messageId = (ctx.message?.text || "").replace(/^\/read\s*/, "").trim();

    if (!messageId) {
      await ctx.reply(
        `<b>Usage</b>: /read &lt;message_id&gt;\n\nGet message IDs from /inbox or /search.`,
        { parse_mode: "HTML" }
      );
      return;
    }

    const thinking = await ctx.reply("<i>Reading email...</i>", { parse_mode: "HTML" });

    try {
      const content = await readEmail(messageId);

      const keyboard = new InlineKeyboard()
        .text("Reply", `reply_direct:${messageId}`)
        .url("Open in Gmail", `https://mail.google.com/mail/u/0/#inbox/${messageId}`);

      const formatted = formatEmailReadView(content);
      const chunks = chunkTelegramHtml(formatted, 4096);

      await ctx.api.editMessageText(ctx.chat.id, thinking.message_id, chunks[0]!, {
        parse_mode: "HTML",
        reply_markup: keyboard,
      });

      for (let i = 1; i < chunks.length; i++) {
        await ctx.reply(chunks[i]!, { parse_mode: "HTML" });
      }

      auditLog("bot.read", { messageId });
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      await ctx.api.editMessageText(ctx.chat.id, thinking.message_id,
        `<b>Error</b>: ${escapeHtml(msg)}`, { parse_mode: "HTML" });
      auditLog("bot.read_error", { messageId, error: msg });
    }
  });

  // /digest [hours] — run triage pipeline inline
  bot.command("digest", async (ctx) => {
    state.incrementCommands();
    state.incrementDigests();

    const text = (ctx.message?.text || "").replace(/^\/digest\s*/, "").trim();
    const hours = parseInt(text, 10) || 6;

    const thinking = await ctx.reply(`<i>Running email digest (last ${hours}h)...</i>`, { parse_mode: "HTML" });

    try {
      const emails = await fetchRecentEmails(hours);

      if (emails.length === 0) {
        await ctx.api.editMessageText(ctx.chat.id, thinking.message_id,
          `<b>Digest</b> (${hours}h window)\n\n<i>No emails found. Inbox is clean.</i>`,
          { parse_mode: "HTML" });
        auditLog("bot.digest_silent", { hours, reason: "no_emails" });
        return;
      }

      await ctx.api.editMessageText(ctx.chat.id, thinking.message_id,
        `<i>Found ${emails.length} emails. Triaging with AI...</i>`,
        { parse_mode: "HTML" });

      const emailText = formatEmailsForTriage(emails);
      const prompt = `${ANTI_SKILL_PREFIX}Triage these ${emails.length} emails:\n\n${emailText}`;

      const model = Bun.env.HAIKU_MODEL;
      if (!model) throw new Error("HAIKU_MODEL not set in env");

      let triageText = "";
      const result = query({
        prompt,
        options: {
          model: model as "haiku",
          maxTurns: 1,
          persistSession: false,
          tools: [],
          settingSources: [],
          systemPrompt: TRIAGE_SYSTEM_PROMPT,
        },
      });

      for await (const message of result) {
        if (message.type === "assistant" && message.message?.content) {
          for (const block of message.message.content) {
            if (block.type === "text") {
              triageText += block.text;
            }
          }
        }
      }

      if (isSkillContaminated(triageText)) {
        auditLog("bot.digest_contaminated", { textLen: triageText.length });
        await ctx.api.editMessageText(ctx.chat.id, thinking.message_id,
          `<b>Digest Error</b>: AI response was contaminated. Try again.`,
          { parse_mode: "HTML" });
        return;
      }

      const items = parseTriageResponse(triageText);

      if (items.length === 0) {
        await ctx.api.editMessageText(ctx.chat.id, thinking.message_id,
          `<b>Digest</b> (${hours}h window)\n\n<i>No significant emails among ${emails.length} checked. All clear.</i>`,
          { parse_mode: "HTML" });
        auditLog("bot.digest_silent", { hours, totalEmails: emails.length, reason: "no_significant" });
        return;
      }

      const digestHtml = formatDigestHtml(items, emails.length);
      const chunks = chunkTelegramHtml(digestHtml, 4096);

      await ctx.api.editMessageText(ctx.chat.id, thinking.message_id, chunks[0]!, {
        parse_mode: "HTML",
        link_preview_options: { is_disabled: true },
      });

      for (let i = 1; i < chunks.length; i++) {
        await ctx.reply(chunks[i]!, {
          parse_mode: "HTML",
          link_preview_options: { is_disabled: true },
        });
      }

      auditLog("bot.digest_manual", {
        hours,
        totalEmails: emails.length,
        significantItems: items.length,
      });
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      try {
        await ctx.api.editMessageText(ctx.chat.id, thinking.message_id,
          `<b>Digest Error</b>: ${escapeHtml(msg)}`, { parse_mode: "HTML" });
      } catch {
        // Edit may fail if message was deleted
      }
      auditLog("bot.digest_error", { error: msg });
    }
  });

  // /compose — start compose flow
  bot.command("compose", async (ctx) => {
    state.incrementCommands();
    if (!sessions) {
      await ctx.reply("<i>Compose not available. Use the AI: just type your message.</i>", { parse_mode: "HTML" });
      return;
    }
    const PENDING_TTL_MS = 5 * 60 * 1000;

    sessions.set(ctx.chat.id, {
      type: "compose",
      step: "to",
      expiresAt: Date.now() + PENDING_TTL_MS,
    });

    await ctx.reply(
      `<b>Compose New Email</b>\n\n<i>To (email address):</i>`,
      { parse_mode: "HTML" }
    );
    auditLog("bot.compose_start");
  });

  // /reply <message_id> — start reply flow
  bot.command("reply", async (ctx) => {
    state.incrementCommands();
    const messageId = (ctx.message?.text || "").replace(/^\/reply\s*/, "").trim();

    if (!messageId) {
      await ctx.reply(
        `<b>Usage</b>: /reply &lt;message_id&gt;\n\nGet message IDs from /inbox or /search, or use the Reply button.`,
        { parse_mode: "HTML" }
      );
      return;
    }

    if (!sessions) {
      await ctx.reply("<i>Reply not available. Use the AI: just type your message.</i>", { parse_mode: "HTML" });
      return;
    }
    const PENDING_TTL_MS = 5 * 60 * 1000;

    sessions.set(ctx.chat.id, {
      type: "reply",
      step: "body",
      messageId,
      expiresAt: Date.now() + PENDING_TTL_MS,
    });

    await ctx.reply(
      `<b>Replying to</b>: <code>${escapeHtml(messageId)}</code>\n\n<i>Type your reply message:</i>`,
      { parse_mode: "HTML" }
    );
    auditLog("bot.reply_start", { messageId });
  });

  // /drafts — list draft emails
  bot.command("drafts", async (ctx) => {
    state.incrementCommands();
    const thinking = await ctx.reply("<i>Fetching drafts...</i>", { parse_mode: "HTML" });

    try {
      const drafts = await listDrafts(20);
      const formatted = formatEmailList(drafts);

      const keyboard = new InlineKeyboard();
      for (let i = 0; i < Math.min(drafts.length, 10); i++) {
        const draft = drafts[i]!;
        const cbId = registerCallback(ctx.chat.id, draft.id, draft.from, draft.subject);
        keyboard.text(`Read #${i + 1}`, `read:${cbId}`).row();
      }

      const chunks = chunkTelegramHtml(
        `<b>Drafts</b> (${drafts.length} found)\n\n${formatted}\n\n` +
        `<a href="https://mail.google.com/mail/u/0/#drafts">Open in Gmail</a>`,
        4096
      );

      await ctx.api.editMessageText(ctx.chat.id, thinking.message_id, chunks[0]!, {
        parse_mode: "HTML",
        reply_markup: drafts.length > 0 ? keyboard : undefined,
        link_preview_options: { is_disabled: true },
      });

      for (let i = 1; i < chunks.length; i++) {
        await ctx.reply(chunks[i]!, {
          parse_mode: "HTML",
          link_preview_options: { is_disabled: true },
        });
      }

      auditLog("bot.drafts", { count: drafts.length });
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      await ctx.api.editMessageText(ctx.chat.id, thinking.message_id,
        `<b>Error</b>: ${escapeHtml(msg)}`, { parse_mode: "HTML" });
      auditLog("bot.drafts_error", { error: msg });
    }
  });
}
