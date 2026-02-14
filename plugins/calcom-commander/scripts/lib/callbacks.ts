// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Inline keyboard callback handlers.
 */

import type { Bot } from "grammy";
import type { BotCredentials } from "./credentials";

export function registerCallbacks(bot: Bot, _creds: BotCredentials): void {
  bot.on("callback_query:data", async (ctx) => {
    const data = ctx.callbackQuery.data;

    // TODO: Handle callback data for inline keyboard buttons
    // e.g., "booking:view:123", "booking:cancel:123"
    if (data.startsWith("booking:view:")) {
      const bookingId = data.replace("booking:view:", "");
      await ctx.answerCallbackQuery({ text: `Viewing booking ${bookingId}...` });
      // exec calcom-cli bookings get <id>
    } else if (data.startsWith("booking:cancel:")) {
      const bookingId = data.replace("booking:cancel:", "");
      await ctx.answerCallbackQuery({ text: `Cancel booking ${bookingId}?` });
      // Confirm before cancelling
    } else {
      await ctx.answerCallbackQuery({ text: "Unknown action" });
    }
  });
}
