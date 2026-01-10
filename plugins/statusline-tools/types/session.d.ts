/**
 * Claude Code session JSONL entry types
 * Derived from ~/.claude/projects/*\/*.jsonl structure
 */

export interface SessionMessage {
  type: "user" | "assistant" | "file-history-snapshot" | "summary";
  uuid: string;
  parentUuid: string | null;
  sessionId: string;
  timestamp: string;
  message?: {
    role: "user" | "assistant";
    content: string | ContentBlock[];
  };
}

export interface ContentBlock {
  type: "text" | "thinking" | "tool_use" | "tool_result";
  text?: string;
  thinking?: string;
}

export interface SessionSummary {
  type: "summary";
  summary: string;
  leafUuid: string;
}

export interface SessionChainEntry {
  sessionId: string;
  shortId: string; // First 8 chars
  timestamp: Date;
}

export interface SessionCache {
  version: number;
  currentSessionId: string;
  chain: SessionChainEntry[];
  updatedAt: number; // Unix timestamp
}

export interface SessionMeta {
  sessionId: string;
  mtime: number; // File modification time
}
