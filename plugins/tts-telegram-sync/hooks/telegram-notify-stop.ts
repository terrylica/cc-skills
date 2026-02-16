#!/usr/bin/env bun
/**
 * Claude Code Stop Hook - Telegram Notification
 *
 * Sends session summary to Telegram when Claude Code session ends.
 *
 * ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
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

    // Find transcript file by scanning all project directories
    const projectsDir = join(
      process.env.HOME || "~",
      ".claude",
      "projects"
    );

    let transcriptPath = "";
    let finalSessionId = sessionId;

    const { readdirSync, statSync, existsSync } = await import("fs");

    // If we have a session ID, search for it across all project directories
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

    // If session not found or unknown, find the most recently modified .jsonl across all projects
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
                return {
                  name: f,
                  path: filePath,
                  mtime: statSync(filePath).mtimeMs
                };
              });
            allFiles.push(...files);
          } catch (e) {
            // Skip directories we can't read
          }
        }

        // Sort by modification time and get the most recent
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

    if (!transcriptPath) {
      trackHookError("telegram-notify-stop", "No transcript file found");
      process.exit(0);
    }

    // Write notification file for bot to pick up
    const notificationDir = join(
      process.env.HOME || "~",
      ".claude",
      "automation",
      "claude-telegram-sync",
      "state",
      "notifications"
    );

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
    process.exit(1);
  }
}

main();
