// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Telegram slash command handlers + command menu SSoT.
 */

import type { Bot } from "grammy";
import type { BotCredentials } from "./credentials";

export const BOT_COMMANDS = [
  { command: "bookings", description: "Show upcoming bookings" },
  { command: "today", description: "Today's schedule" },
  { command: "search", description: "Search bookings" },
  { command: "eventtypes", description: "List event types" },
  { command: "availability", description: "Check availability" },
  { command: "status", description: "Bot status and stats" },
  { command: "help", description: "Show all commands" },
] as const;

export function registerCommands(bot: Bot, _creds: BotCredentials): void {
  bot.api.setMyCommands([...BOT_COMMANDS]);

  bot.command("help", async (ctx) => {
    const lines = BOT_COMMANDS.map((c) => `/${c.command} — ${c.description}`);
    await ctx.reply(`<b>Cal.com Commander</b>\n\n${lines.join("\n")}`, { parse_mode: "HTML" });
  });

  bot.command("status", async (ctx) => {
    const uptime = process.uptime();
    const hours = Math.floor(uptime / 3600);
    const mins = Math.floor((uptime % 3600) / 60);
    await ctx.reply(
      `<b>Bot Status</b>\nUptime: ${hours}h ${mins}m\nPID: ${process.pid}`,
      { parse_mode: "HTML" }
    );
  });

  // TODO: Implement remaining commands using calcom-cli subprocess calls
  bot.command("bookings", async (ctx) => {
    await ctx.reply("Fetching bookings...");
    // exec calcom-cli bookings list
  });

  bot.command("today", async (ctx) => {
    await ctx.reply("Fetching today's schedule...");
    // exec calcom-cli bookings list --status upcoming
  });

  bot.command("search", async (ctx) => {
    await ctx.reply("Search not yet implemented. Use: /search <query>");
  });

  bot.command("eventtypes", async (ctx) => {
    await ctx.reply("Fetching event types...");
    // exec calcom-cli event-types list
  });

  bot.command("availability", async (ctx) => {
    await ctx.reply("Availability check not yet implemented.");
  });
}
