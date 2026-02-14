// PROCESS-STORM-OK
/**
 * Bot Shutdown Notification Hook (Stop event)
 *
 * Sends a "going offline" message to Telegram when Claude Code session ends.
 * Only fires if the bot is running (checks PID file).
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

import { existsSync, readFileSync } from "fs";

const PID_FILE = "/tmp/gmail-commander-bot.pid";

async function main() {
  // Only notify if bot is actually running
  if (!existsSync(PID_FILE)) return;

  const pid = readFileSync(PID_FILE, "utf-8").trim();
  try {
    process.kill(Number(pid), 0); // Check if alive
  } catch {
    return; // Bot not running
  }

  const token = process.env.TELEGRAM_BOT_TOKEN || Bun.env.TELEGRAM_BOT_TOKEN;
  const chatId = process.env.TELEGRAM_CHAT_ID || Bun.env.TELEGRAM_CHAT_ID;
  if (!token || !chatId) return;

  try {
    await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        text: "<i>Gmail Commander session ending...</i>",
        parse_mode: "HTML",
      }),
    });
  } catch {
    // Best-effort notification
  }
}

main();
