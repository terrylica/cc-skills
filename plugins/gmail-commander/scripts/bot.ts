// PROCESS-STORM-OK — Telegram bot daemon entry point (grammY long polling)
/**
 * Gmail Commander Bot — Telegram Bot Daemon
 *
 * Always-on daemon using grammY long polling.
 * Provides slash commands for email access and AI-powered free-text routing.
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

import { createTelegramBot, loadBotCredentials } from "./lib/bot-factory.js";
import { registerCommands, setCommandMenu } from "./lib/commands.js";
import { registerCallbacks, clearExpiredSessions, pendingSessions } from "./lib/callbacks.js";
import { loadBotState, setStateFile } from "./lib/state.js";
import { setAuditDir } from "./lib/audit.js";
import { auditLog } from "./lib/audit.js";
import { createDraft } from "./lib/gmail-client.js";
import { escapeHtml } from "./lib/telegram-format.js";
import { handleAgentQuery } from "./lib/agent-router.js";
import { acquireLock, releaseLock } from "./lib/session-guard.js";
import { join } from "path";

// --- Configuration ---

const PID_FILE = "/tmp/gmail-commander-bot.pid";

// Configure audit dir and state file from env or defaults
const auditDir = Bun.env.AUDIT_DIR || join(process.env.HOME || "~", "own", "amonic", "logs", "audit");
setAuditDir(auditDir);

const stateFile = Bun.env.BOT_STATE_FILE || join(process.env.HOME || "~", "own", "amonic", "logs", "bot-state.json");
setStateFile(stateFile);

// --- Main ---

async function main() {
  if (!acquireLock(PID_FILE)) {
    console.error("Another gmail-commander-bot instance is running. Exiting.");
    process.exit(1);
  }

  // Graceful shutdown
  const cleanup = () => {
    releaseLock(PID_FILE);
    auditLog("bot.shutdown");
    process.exit(0);
  };
  process.on("SIGINT", cleanup);
  process.on("SIGTERM", cleanup);

  try {
    const config = loadBotCredentials();
    const bot = createTelegramBot(config);
    const state = loadBotState();

    // Register commands and callbacks
    registerCommands(bot, state, config.chatId, pendingSessions);
    registerCallbacks(bot, state);

    // Handle text messages for pending sessions (compose/reply body input)
    bot.on("message:text", async (ctx) => {
      const chatId = ctx.chat.id;
      const text = ctx.message.text;
      const session = pendingSessions.get(chatId);

      if (!session) {
        // No pending session — route to Agent SDK
        await handleAgentQuery(ctx, text, state);
        return;
      }

      // Clear expired sessions
      clearExpiredSessions();
      if (!pendingSessions.has(chatId)) {
        await ctx.reply("<i>Session expired. Please start again.</i>", { parse_mode: "HTML" });
        return;
      }

      // Handle compose flow steps
      if (session.type === "compose") {
        switch (session.step) {
          case "to":
            session.to = text;
            session.step = "subject";
            await ctx.reply("<i>Subject:</i>", { parse_mode: "HTML" });
            return;
          case "subject":
            session.subject = text;
            session.step = "body";
            await ctx.reply("<i>Body:</i>", { parse_mode: "HTML" });
            return;
          case "body":
            // Create draft
            try {
              await createDraft({
                to: session.to!,
                subject: session.subject!,
                body: text,
                from: session.from,
              });
              state.incrementDrafts();
              state.save();
              pendingSessions.delete(chatId);

              await ctx.reply(
                `<b>Draft created!</b>\n\n` +
                `<b>To</b>: ${escapeHtml(session.to!)}\n` +
                `<b>From</b>: ${escapeHtml(session.from || "(default)")}\n` +
                `<b>Subject</b>: ${escapeHtml(session.subject!)}\n\n` +
                `Review it here:\n` +
                `  <a href="https://mail.google.com/mail/u/0/#drafts">Gmail Drafts</a>`,
                { parse_mode: "HTML" }
              );
              auditLog("bot.compose_draft", { to: session.to, subject: session.subject });
            } catch (error) {
              const msg = error instanceof Error ? error.message : String(error);
              pendingSessions.delete(chatId);
              await ctx.reply(`<b>Draft failed</b>: ${escapeHtml(msg)}`, { parse_mode: "HTML" });
              auditLog("bot.compose_error", { error: msg });
            }
            return;
        }
      }

      // Handle reply flow
      if (session.type === "reply" && session.step === "body") {
        try {
          await createDraft({
            to: session.to || "",
            subject: session.subject || "",
            body: text,
            from: session.from,
            replyTo: session.messageId,
          });
          state.incrementDrafts();
          state.save();
          pendingSessions.delete(chatId);

          await ctx.reply(
            `<b>Reply draft created!</b>\n\n` +
            `<b>To</b>: ${escapeHtml(session.to || "(auto-detected)")}\n` +
            `<b>Subject</b>: ${escapeHtml(session.subject || "(threaded)")}\n\n` +
            `Review it here:\n` +
            `  <a href="https://mail.google.com/mail/u/0/#drafts">Gmail Drafts</a>`,
            { parse_mode: "HTML" }
          );
          auditLog("bot.reply_draft", { messageId: session.messageId, to: session.to });
        } catch (error) {
          const msg = error instanceof Error ? error.message : String(error);
          pendingSessions.delete(chatId);
          await ctx.reply(`<b>Reply draft failed</b>: ${escapeHtml(msg)}`, { parse_mode: "HTML" });
          auditLog("bot.reply_error", { error: msg });
        }
        return;
      }
    });

    // Register native menu commands
    await setCommandMenu(bot);

    auditLog("bot.started", { chatId: config.chatId });
    console.error(`Gmail Commander Bot started (chat: ${config.chatId})`);

    // Start long polling
    bot.start({
      onStart: () => console.error("Bot is now polling..."),
    });

    // Periodic session cleanup (every 60s)
    setInterval(clearExpiredSessions, 60_000);

    // Periodic state save (every 5 min)
    setInterval(() => state.save(), 5 * 60_000);

  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    auditLog("bot.startup_error", { error: msg });
    console.error(`Fatal: ${msg}`);
    releaseLock(PID_FILE);
    process.exit(1);
  }
}

main();
