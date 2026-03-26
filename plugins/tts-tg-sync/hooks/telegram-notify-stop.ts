#!/usr/bin/env bun
/**
 * Claude Code Stop Hook - Telegram Notification
 *
 * Sends session summary to Telegram when Claude Code session ends.
 *
 * Hook input (stdin): JSON with session metadata
 * {
 *   "sessionId": "5a6aab44-acb2-49fa-bb0d-4d773e0b1a92",
 *   "cwd": "/Users/terryli/.claude",
 *   "slug": "whimsical-snacking-puppy"
 * }
 */

import { join } from "path";
import { trackHookError } from "../../itp-hooks/hooks/lib/hook-error-tracker.ts";

interface StopHookInput {
  session_id?: string;  // Claude Code uses snake_case
  sessionId?: string;   // Fallback
  cwd?: string;
  slug?: string;
  transcript_path?: string;  // Claude Code provides this directly
}

interface NotificationFile {
  sessionId: string;
  cwd: string;
  slug: string;
  timestamp: string;
  transcriptPath: string;
  itermSessionId?: string;
}

import { appendFileSync } from "fs";

function hookLog(msg: string) {
  appendFileSync("/tmp/telegram-stop-hook.log", `${new Date().toISOString()} ${msg}\n`);
}

async function main() {
  try {
    hookLog("[STOP-HOOK] triggered");

    // Read hook input from stdin
    const stdinBuffer = [];
    for await (const chunk of Bun.stdin.stream()) {
      stdinBuffer.push(chunk);
    }
    const stdin = Buffer.concat(stdinBuffer).toString("utf-8").trim();

    let input: StopHookInput = {};
    if (stdin) {
      try {
        input = JSON.parse(stdin);
      } catch (e) {
        trackHookError("telegram-notify-stop", `Failed to parse hook input: ${e}`);
      }
    }

    // Get session info from environment or input (Claude Code uses snake_case)
    const sessionId = input.session_id || input.sessionId || process.env.CLAUDE_SESSION_ID || "unknown";
    const cwd = input.cwd || process.env.CLAUDE_WORKSPACE_DIR || process.cwd();
    const slug = input.slug || "unknown";

    // Debug logging
    hookLog(`Hook input: ${stdin.slice(0, 200)}`);
    hookLog(`Session ID: ${sessionId}, CWD: ${cwd}`);

    // Use transcript_path from stdin (Claude Code provides it directly).
    // Fall back to filesystem scan only when transcript_path is absent.
    const { readdirSync, statSync, existsSync, mkdirSync } = await import("fs");

    let transcriptPath = input.transcript_path || "";
    let finalSessionId = sessionId;

    if (transcriptPath) {
      hookLog(`Using transcript_path from stdin: ${transcriptPath}`);
    } else {
      // Fallback: scan project directories for the session JSONL
      const projectsDir = join(process.env.HOME || "~", ".claude", "projects");

      if (sessionId !== "unknown") {
        try {
          const projectDirs = readdirSync(projectsDir);
          for (const dir of projectDirs) {
            const candidatePath = join(projectsDir, dir, `${sessionId}.jsonl`);
            if (existsSync(candidatePath)) {
              transcriptPath = candidatePath;
              hookLog(`Found session at: ${transcriptPath}`);
              break;
            }
          }
        } catch (e) {
          trackHookError("telegram-notify-stop", `Error searching for session: ${e}`);
        }
      }

      // Last resort: most recently modified .jsonl across all projects
      if (!transcriptPath) {
        try {
          const allFiles: { name: string; path: string; mtime: number }[] = [];
          const projectDirs = readdirSync(projectsDir);
          for (const dir of projectDirs) {
            const projectDir = join(projectsDir, dir);
            try {
              const stat = statSync(projectDir);
              if (!stat.isDirectory()) continue;
              const files = readdirSync(projectDir)
                .filter(f => f.endsWith(".jsonl") && !f.includes("subagents"))
                .map(f => {
                  const filePath = join(projectDir, f);
                  return { name: f, path: filePath, mtime: statSync(filePath).mtimeMs };
                });
              allFiles.push(...files);
            } catch { /* skip unreadable dirs */ }
          }
          allFiles.sort((a, b) => b.mtime - a.mtime);
          if (allFiles.length > 0 && allFiles[0]) {
            transcriptPath = allFiles[0].path;
            finalSessionId = allFiles[0].name.replace(".jsonl", "");
            hookLog(`Found most recent session: ${finalSessionId.slice(0, 8)} at ${transcriptPath}`);
          }
        } catch (e) {
          trackHookError("telegram-notify-stop", `Could not find session files: ${e}`);
        }
      }
    }

    if (!transcriptPath) {
      trackHookError("telegram-notify-stop", "No transcript file found");
      process.exit(0);
    }

    // Write notification file for claude-tts-companion to pick up.
    // The unified service watches ~/.claude/notifications/ (Config.swift).
    const notificationDir = join(
      process.env.HOME || "~",
      ".claude",
      "notifications"
    );
    mkdirSync(notificationDir, { recursive: true });

    // Extract iTerm2 session UUID (format: "w0t1p1:UUID")
    const rawItermId = process.env.ITERM_SESSION_ID || "";
    const itermSessionId = rawItermId.includes(":")
      ? rawItermId.split(":").pop()
      : rawItermId || undefined;

    const notification: NotificationFile = {
      sessionId: finalSessionId,
      cwd,
      slug,
      timestamp: new Date().toISOString(),
      transcriptPath,
      ...(itermSessionId && { itermSessionId }),
    };

    const notificationPath = join(notificationDir, `${finalSessionId}.json`);
    await Bun.write(notificationPath, JSON.stringify(notification, null, 2));

    hookLog(`[STOP-HOOK] wrote ${notificationPath} sessionId=${finalSessionId.slice(0, 8)}`);
    process.exit(0);
  } catch (error) {
    hookLog(`[STOP-HOOK] ERROR: ${error}`);
    console.error("Stop hook error:", error);
    process.exit(0); // fail-open: errors tracked via hookLog + trackHookError
  }
}

main();
