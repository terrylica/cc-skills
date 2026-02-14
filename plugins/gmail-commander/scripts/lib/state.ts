// PROCESS-STORM-OK
/**
 * Bot State Persistence
 *
 * Tracks bot statistics and persists to disk as JSON.
 * Adapted from claude-telegram-sync/src/telegram/state.ts.
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

import { writeFileSync, readFileSync, existsSync, mkdirSync } from "fs";
import { dirname, join } from "path";
import { homedir } from "os";

export interface BotState {
  startedAt: Date;
  messagesReceived: number;
  commandsProcessed: number;
  agentQueries: number;
  agentFailed: number;
  digestsTriggered: number;
  draftsCreated: number;

  save(): void;
  incrementMessages(): void;
  incrementCommands(): void;
  incrementAgentQueries(): void;
  incrementAgentFailed(): void;
  incrementDigests(): void;
  incrementDrafts(): void;
}

let stateFilePath: string | undefined;

export function setStateFile(path: string): void {
  stateFilePath = path;
}

function getStateFile(): string {
  if (stateFilePath) return stateFilePath;
  const envPath = Bun.env.BOT_STATE_FILE;
  if (envPath) {
    stateFilePath = envPath;
    return envPath;
  }
  stateFilePath = join(homedir(), "own/amonic/logs/bot-state.json");
  return stateFilePath;
}

export function loadBotState(): BotState {
  const file = getStateFile();

  let data: Record<string, unknown> = {
    startedAt: new Date().toISOString(),
    messagesReceived: 0,
    commandsProcessed: 0,
    agentQueries: 0,
    agentFailed: 0,
    digestsTriggered: 0,
    draftsCreated: 0,
  };

  if (existsSync(file)) {
    try {
      const json = readFileSync(file, "utf-8");
      data = JSON.parse(json);
    } catch {
      // Start fresh
    }
  }

  const state: BotState = {
    startedAt: data.startedAt ? new Date(data.startedAt as string) : new Date(),
    messagesReceived: (data.messagesReceived as number) ?? 0,
    commandsProcessed: (data.commandsProcessed as number) ?? 0,
    agentQueries: (data.agentQueries as number) ?? 0,
    agentFailed: (data.agentFailed as number) ?? 0,
    digestsTriggered: (data.digestsTriggered as number) ?? 0,
    draftsCreated: (data.draftsCreated as number) ?? 0,

    save() {
      try {
        const dir = dirname(file);
        mkdirSync(dir, { recursive: true });
        const json = JSON.stringify(
          {
            startedAt: this.startedAt.toISOString(),
            messagesReceived: this.messagesReceived,
            commandsProcessed: this.commandsProcessed,
            agentQueries: this.agentQueries,
            agentFailed: this.agentFailed,
            digestsTriggered: this.digestsTriggered,
            draftsCreated: this.draftsCreated,
          },
          null,
          2
        );
        writeFileSync(file, json, "utf-8");
      } catch (error) {
        console.error("Failed to save state:", error);
      }
    },

    incrementMessages() { this.messagesReceived++; },
    incrementCommands() { this.commandsProcessed++; },
    incrementAgentQueries() { this.agentQueries++; },
    incrementAgentFailed() { this.agentFailed++; },
    incrementDigests() { this.digestsTriggered++; },
    incrementDrafts() { this.draftsCreated++; },
  };

  return state;
}
