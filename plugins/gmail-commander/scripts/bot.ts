// PROCESS-STORM-OK — Telegram bot daemon entry point (grammY long polling)
/**
 * Gmail Commander Bot — Telegram Bot Daemon
 *
 * Always-on daemon using grammY long polling.
 * Provides slash commands for email access and AI-powered free-text routing.
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

/**
 * Build the fully-wired bot WITHOUT starting a transport.
 *
 * Extracted so there is exactly ONE definition of "what this bot does" shared by two very different
 * runtimes: the standalone long-polling daemon below, and the Restate `GmailBot` tenant on the mca
 * mini, which owns its own durable poll chain and feeds updates in via `bot.handleUpdate()`.
 * Duplicating the wiring into the tenant was the obvious alternative and was rejected: the
 * compose/reply session flow is ~90 lines of stateful branching, and two copies of it would drift
 * silently, with the divergence only ever showing up as a user-visible misbehaviour in one of them.
 *
 * Deliberately does NOT: acquire the PID lock, install signal handlers, start polling, or register
 * the periodic timers. Those belong to whoever owns the process lifecycle.
 */
export async function buildBot() {
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

  // Register native menu commands.
  //
  // NON-FATAL BY DESIGN. This is a NETWORK call, and letting it throw out of startup is what made
  // the laptop daemon crash-loop: `Fatal: Network request for 'setMyCommands' failed!` → exit 1 →
  // KeepAlive relaunch → repeat, every time the lid closed or wifi flapped. The command MENU is a
  // cosmetic affordance in Telegram's UI; every command still works without it. Trading a working
  // bot for a pretty menu was never the right trade.
  try {
    await setCommandMenu(bot);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    auditLog("bot.command_menu_failed", { error: msg });
    console.error(`Command menu registration failed (non-fatal, commands still work): ${msg}`);
  }

  return { bot, state, config };
}

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
    const { bot, state, config } = await buildBot();

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

// Only take over the process when RUN as a script. Importing this module (the Restate GmailBot
// tenant does exactly that, to reuse buildBot) must never acquire the PID lock or start a second
// long-poll — Telegram permits only ONE getUpdates consumer per token, so an accidental import
// would silently fight the real poller and make both unreliable.
if (import.meta.main) {
  main();
}
