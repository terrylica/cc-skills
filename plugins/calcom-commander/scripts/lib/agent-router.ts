// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Free-text query routing via Agent SDK Haiku with Cal.com MCP tools.
 */

import type { Context } from "grammy";
import type { BotCredentials } from "./credentials";
import { CircuitBreaker } from "./circuit-breaker";
import { audit } from "./audit";

const CIRCUIT_FILE = "/tmp/calcom-commander-agent-circuit.json";
const QUERY_TIMEOUT = 120_000; // 2 minutes
const circuit = new CircuitBreaker(CIRCUIT_FILE);

let isExecuting = false;

export async function handleAgentQuery(ctx: Context, creds: BotCredentials): Promise<void> {
  if (isExecuting) {
    await ctx.reply("Already processing a query. Please wait.");
    return;
  }

  if (circuit.isOpen()) {
    await ctx.reply("Agent temporarily disabled (circuit breaker open). Try again in 10 minutes.");
    return;
  }

  const text = ctx.message?.text;
  if (!text) return;

  isExecuting = true;
  const timeoutId = setTimeout(() => {
    isExecuting = false;
  }, QUERY_TIMEOUT);

  try {
    await audit("agent.query", { text: text.slice(0, 100) });

    // TODO: Implement Agent SDK query with Cal.com MCP tools
    // const result = await query({
    //   model: creds.haikuModel,
    //   prompt: text,
    //   mcpServers: [createCalcomMcpServer(creds)],
    //   maxTurns: 3,
    // });

    await ctx.reply("Agent SDK routing not yet implemented. Use slash commands for now.");

    circuit.recordSuccess();
  } catch (err) {
    circuit.recordFailure();
    await audit("agent.error", { error: (err as Error).message });
    await ctx.reply("Error processing query. Please try again.");
  } finally {
    clearTimeout(timeoutId);
    isExecuting = false;
  }
}
