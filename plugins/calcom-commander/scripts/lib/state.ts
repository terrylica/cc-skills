// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Bot statistics persistence.
 */

import { existsSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { dirname } from "path";

const STATE_FILE = process.env.BOT_STATE_FILE || `${process.env.HOME}/own/amonic/state/calcom-bot-state.json`;

export interface BotState {
  startedAt: string;
  messagesReceived: number;
  commandsProcessed: number;
  agentQueries: number;
  errors: number;
}

export function loadState(): BotState {
  try {
    if (existsSync(STATE_FILE)) {
      return JSON.parse(readFileSync(STATE_FILE, "utf-8"));
    }
  } catch {}
  return {
    startedAt: new Date().toISOString(),
    messagesReceived: 0,
    commandsProcessed: 0,
    agentQueries: 0,
    errors: 0,
  };
}

export function saveState(state: BotState): void {
  try {
    const dir = dirname(STATE_FILE);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  } catch {
    // Best-effort state save
  }
}
