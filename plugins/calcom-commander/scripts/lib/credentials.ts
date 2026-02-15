// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Load bot credentials from environment variables.
 */

export interface BotCredentials {
  botToken: string;
  chatId: string;
  haikuModel: string;
  calcomOpUuid: string;
  // Optional Pushover dual-channel notifications
  pushoverToken?: string;
  pushoverUser?: string;
  pushoverSound?: string;
}

export function loadBotCredentials(): BotCredentials {
  const botToken = process.env.TELEGRAM_BOT_TOKEN;
  const chatId = process.env.TELEGRAM_CHAT_ID;
  const haikuModel = process.env.HAIKU_MODEL;
  const calcomOpUuid = process.env.CALCOM_OP_UUID;

  if (!botToken) throw new Error("TELEGRAM_BOT_TOKEN not set");
  if (!chatId) throw new Error("TELEGRAM_CHAT_ID not set");
  if (!haikuModel) throw new Error("HAIKU_MODEL not set");
  if (!calcomOpUuid) throw new Error("CALCOM_OP_UUID not set");

  // Pushover is optional — Telegram-only operation still works
  const pushoverToken = process.env.PUSHOVER_APP_TOKEN || undefined;
  const pushoverUser = process.env.PUSHOVER_USER_KEY || undefined;
  const pushoverSound = process.env.PUSHOVER_SOUND || "dune";

  return { botToken, chatId, haikuModel, calcomOpUuid, pushoverToken, pushoverUser, pushoverSound };
}
