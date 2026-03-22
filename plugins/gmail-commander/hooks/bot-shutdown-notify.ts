// PROCESS-STORM-OK
/**
 * Bot Shutdown Notification Hook (Stop event)
 *
 * Sends a "going offline" message to Telegram when a Claude Code session
 * working in the gmail-commander project directory ends.
 * Only fires if the bot is running (checks PID file) AND the session cwd
 * is inside the gmail-commander project dir — prevents cross-project noise.
 *
 * Project dir is resolved from GMAIL_COMMANDER_PROJECT_DIR env var,
 * defaulting to ~/own/amonic.
 */

import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

const PID_FILE = "/tmp/gmail-commander-bot.pid";

const PROJECT_DIR =
  process.env.GMAIL_COMMANDER_PROJECT_DIR ?? join(homedir(), "own", "amonic");

interface StopHookInput {
  session_id?: string;
  cwd?: string;
}

async function readStdin(): Promise<StopHookInput> {
  const chunks: Uint8Array[] = [];
  for await (const chunk of Bun.stdin.stream()) {
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString("utf-8").trim();
  if (!raw) return {};
  try {
    return JSON.parse(raw) as StopHookInput;
  } catch {
    return {};
  }
}

async function main() {
  // Read hook input to get session cwd
  const input = await readStdin();
  const sessionCwd = input.cwd ?? "";

  // Only notify for sessions working inside the gmail-commander project dir.
  // This prevents "Gmail Commander session ending..." from appearing in
  // unrelated Claude Code sessions (e.g. thinking-watcher, calcom, etc.).
  if (sessionCwd && !sessionCwd.startsWith(PROJECT_DIR)) return;

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
