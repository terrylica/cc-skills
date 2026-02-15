// PROCESS-STORM-OK
// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Bot Shutdown Notification Hook (Stop event)
 *
 * Sends a "going offline" message to Telegram + Pushover when Claude Code
 * session ends. Only fires if the bot is running (checks PID file).
 *
 * Pushover is optional — gracefully skipped if credentials not set.
 */

import { existsSync, readFileSync } from "fs";
import { sendPushover } from "../scripts/lib/pushover";

const PID_FILE = "/tmp/calcom-commander-bot.pid";

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
  const pushoverToken = process.env.PUSHOVER_APP_TOKEN || Bun.env.PUSHOVER_APP_TOKEN;
  const pushoverUser = process.env.PUSHOVER_USER_KEY || Bun.env.PUSHOVER_USER_KEY;
  const pushoverSound = process.env.PUSHOVER_SOUND || Bun.env.PUSHOVER_SOUND || "dune";

  // Telegram notification
  if (token && chatId) {
    try {
      await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: chatId,
          text: "<i>Cal.com Commander session ending...</i>",
          parse_mode: "HTML",
        }),
      });
    } catch {
      // Best-effort notification
    }
  }

  // Pushover notification (normal priority — no emergency for shutdown)
  if (pushoverToken && pushoverUser) {
    try {
      await sendPushover(pushoverToken, pushoverUser, {
        title: "Cal.com Commander",
        message: "Session ending — bot going offline",
        priority: 0,
        sound: pushoverSound,
      });
    } catch {
      // Best-effort notification
    }
  }
}

main();
