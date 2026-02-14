// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Telegram HTML formatting + message sending utilities.
 */

import type { BotCredentials } from "./credentials";

export function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

export async function sendTelegramMessage(
  creds: BotCredentials,
  text: string,
  parseMode: "HTML" | "MarkdownV2" = "HTML"
): Promise<void> {
  await fetch(`https://api.telegram.org/bot${creds.botToken}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: creds.chatId,
      text,
      parse_mode: parseMode,
    }),
  });
}
