#!/usr/bin/env bun
/**
 * cron-tracker.ts
 *
 * PostToolUse hook: tracks CronCreate/CronDelete to persist active job IDs
 * for statusline display via ~/.claude/state/active-crons.json
 *
 * State file:  ~/.claude/state/active-crons.json
 * Log file:    ~/.claude/logs/cron-tracker.jsonl  (rotates at 1MB, keeps 3)
 *
 * Each entry includes the session ID and project folder where the cron was
 * created, so the statusline can show full context per job.
 *
 * State format:
 * Prompt files: ~/.claude/state/cron-prompts/{id}.md
 *   Full CronCreate prompt saved per job for iTerm2 hyperlink viewing.
 *   Deleted when the job is CronDeleted.
 *
 *   [{
 *     "id": "753d3dc5",
 *     "schedule": "* /1 * * * *",
 *     "description": "...",
 *     "session_id": "2e283bf9-...",   ← full UUID of originating session
 *     "project_path": "~/eon/...",    ← ~ -substituted project folder
 *     "prompt_file": "~/.claude/state/cron-prompts/753d3dc5.md"
 *     "created_at": "ISO"
 *   }]
 */

import {
  readFileSync,
  writeFileSync,
  appendFileSync,
  unlinkSync,
  mkdirSync,
  statSync,
  renameSync,
  existsSync,
} from "fs";
import { join } from "path";
import { homedir } from "os";

// ── Paths ──────────────────────────────────────────────────────────────────
const HOME = homedir();
const STATE_FILE = join(HOME, ".claude", "state", "active-crons.json");
const PROMPTS_DIR = join(HOME, ".claude", "state", "cron-prompts");
const HISTORY_DIR = join(HOME, ".claude", "state", "cron-history");  // NDJSON + versioned .md
const LOG_DIR = join(HOME, ".claude", "logs");
const LOG_FILE = join(LOG_DIR, "cron-tracker.jsonl");
const LOG_MAX_BYTES = 1 * 1024 * 1024; // 1 MB
const LOG_KEEP = 3;
const HISTORY_MAX_BYTES = 500 * 1024; // 500 KB per job NDJSON
const HISTORY_KEEP = 3;              // rotated copies
const HISTORY_VERSIONS_KEEP = 10;   // max .md snapshots per job

// ── JSONL logger with rotation ─────────────────────────────────────────────
function rotateLogs(): void {
  try {
    if (!existsSync(LOG_FILE)) return;
    if (statSync(LOG_FILE).size < LOG_MAX_BYTES) return;
    for (let i = LOG_KEEP; i >= 1; i--) {
      const src = i === 1 ? LOG_FILE : `${LOG_FILE}.${i - 1}`;
      const dst = `${LOG_FILE}.${i}`;
      if (existsSync(src)) {
        if (i === LOG_KEEP) try { Bun.spawnSync(["rm", "-f", dst]); } catch { /* ok */ }
        try { renameSync(src, dst); } catch { /* ok */ }
      }
    }
  } catch { /* never block */ }
}

// ── Prompt history: NDJSON log + versioned .md snapshots ──────────────────
function hashPrompt(prompt: string): string {
  let h = 0;
  for (let i = 0; i < prompt.length; i++) h = (Math.imul(31, h) + prompt.charCodeAt(i)) | 0;
  return (h >>> 0).toString(16).slice(0, 8);
}

function rotateHistory(ndjsonFile: string): void {
  try {
    if (!existsSync(ndjsonFile) || statSync(ndjsonFile).size < HISTORY_MAX_BYTES) return;
    for (let i = HISTORY_KEEP; i >= 1; i--) {
      const src = i === 1 ? ndjsonFile : `${ndjsonFile}.${i - 1}`;
      const dst = `${ndjsonFile}.${i}`;
      if (existsSync(src)) {
        if (i === HISTORY_KEEP) try { Bun.spawnSync(["rm", "-f", dst]); } catch { /* ok */ }
        try { renameSync(src, dst); } catch { /* ok */ }
      }
    }
  } catch { /* never block */ }
}

function savePromptVersion(
  jobId: string,
  schedule: string,
  humanSchedule: string,
  prompt: string,
  sessionId: string,
  projectPath: string,
  source: string
): { promptFile: string; changed: boolean } {
  const hash = hashPrompt(prompt);
  const ndjsonFile = join(HISTORY_DIR, `${jobId}.ndjson`);
  const versionsDir = join(HISTORY_DIR, jobId);

  mkdirSync(versionsDir, { recursive: true });

  // Check if prompt changed by reading last line of NDJSON
  let changed = true;
  try {
    if (existsSync(ndjsonFile)) {
      const result = Bun.spawnSync(["tail", "-1", ndjsonFile], { stdout: "pipe" });
      const last = result.stdout.toString().trim();
      if (last) {
        const lastEntry = JSON.parse(last);
        if (lastEntry.hash === hash) changed = false;
      }
    }
  } catch { /* treat as changed */ }

  const ts = new Date().toISOString();

  if (changed) {
    // Append to NDJSON machine log
    rotateHistory(ndjsonFile);
    appendFileSync(ndjsonFile,
      JSON.stringify({ ts, source, session_id: sessionId, project_path: projectPath,
                       schedule, hash, prompt }) + "\n"
    );

    // Write versioned human-readable .md snapshot
    // Filename: ISO timestamp (sortable) → ls -t gives newest first
    const safeTs = ts.replace(/[:.]/g, "-");
    const versionFile = join(versionsDir, `${safeTs}.md`);
    writeFileSync(versionFile, [
      `# Cron Job: ${jobId}`,
      ``,
      `**Version:** ${ts}`,
      `**Schedule:** \`${schedule}\` (${humanSchedule})`,
      `**Session:** ${sessionId}`,
      `**Project:** ${projectPath}`,
      `**Source:** ${source}`,
      ``,
      `## Prompt`,
      ``,
      prompt || "_No prompt_",
    ].join("\n"));

    // Prune oldest beyond HISTORY_VERSIONS_KEEP
    const result = Bun.spawnSync(
      ["bash", "-c", `ls -t "${versionsDir}"/*.md 2>/dev/null | tail -n +${HISTORY_VERSIONS_KEEP + 1}`],
      { stdout: "pipe" }
    );
    const toDelete = result.stdout.toString().trim().split("\n").filter(Boolean);
    for (const f of toDelete) try { unlinkSync(f); } catch { /* ok */ }
  }

  // Always update the current prompt file (for statusline hyperlink)
  const promptFile = join(PROMPTS_DIR, `${jobId}.md`);
  writeFileSync(promptFile, [
    `# Cron Job: ${jobId}`,
    ``,
    `**Schedule:** \`${schedule}\` (${humanSchedule})`,
    `**Session:** ${sessionId}`,
    `**Project:** ${projectPath}`,
    `**Last updated:** ${ts}`,
    ``,
    `## Prompt`,
    ``,
    prompt || "_No prompt_",
  ].join("\n"));

  return { promptFile, changed };
}

function logEvent(
  level: "info" | "warn" | "error",
  event: string,
  ctx: Record<string, unknown> = {}
): void {
  try {
    mkdirSync(LOG_DIR, { recursive: true });
    rotateLogs();
    appendFileSync(
      LOG_FILE,
      JSON.stringify({ ts: new Date().toISOString(), level, component: "cron-tracker", event, pid: process.pid, ...ctx }) + "\n"
    );
  } catch { /* silent fail */ }
}

// ── Resolve session ID from most-recently modified JSONL in project dir ────
// The session-chain-cache is written async by the statusline and can be stale.
// The most recently touched *.jsonl file in the project directory is always
// the active session — this matches what the statusline's JSONL ID display shows.
function resolveSessionId(cwd: string): string {
  try {
    const encoded = "-" + cwd.replace(/\//g, "-").replace(/^-/, "");
    const projectDir = join(HOME, ".claude", "projects", encoded);
    const result = Bun.spawnSync(
      ["bash", "-c", `ls -t "${projectDir}"/*.jsonl 2>/dev/null | head -1`],
      { stdout: "pipe", stderr: "pipe" }
    );
    const latest = result.stdout.toString().trim();
    if (!latest) return "";
    // Extract UUID from filename: /path/to/500fb350-....jsonl -> 500fb350-...
    return latest.replace(/^.*\//, "").replace(/\.jsonl$/, "");
  } catch {
    return "";
  }
}

// ── Parse hook input ───────────────────────────────────────────────────────
interface CronEntry {
  id: string;
  schedule: string;
  description: string;
  session_id: string;
  project_path: string;
  prompt_file: string;
  created_at: string;
}

let input: { tool_name: string; tool_input: Record<string, unknown>; tool_response: unknown };
try {
  input = JSON.parse(readFileSync(0, "utf-8"));
} catch {
  process.exit(0);
}

const { tool_name, tool_input, tool_response } = input;
if (tool_name !== "CronCreate" && tool_name !== "CronDelete" && tool_name !== "CronList") process.exit(0);

const cwd = process.cwd();
const sessionId = resolveSessionId(cwd);
const projectPath = cwd.replace(HOME, "~");

logEvent("info", "hook_fired", { tool_name, project_path: projectPath, session_id: sessionId.slice(0, 8) });

// ── Load + expire state ────────────────────────────────────────────────────
let entries: CronEntry[] = [];
try { entries = JSON.parse(readFileSync(STATE_FILE, "utf-8")); } catch { entries = []; }

// Layer 3 of 3: TTL backstop — entries older than 6 hours are expired.
// Reduced from 3 days to 6 hours (2026-03-29) after incident where a stale
// entry persisted indefinitely because this hook only fires on CronCreate/
// Delete/List events. Layers 1 (render-time GC) and 2 (Stop hook) handle
// the common case; this is the final safety net for edge cases.
const sixHoursAgo = Date.now() - 6 * 60 * 60 * 1000;
const before = entries.length;
entries = entries.filter((e) => new Date(e.created_at).getTime() > sixHoursAgo);
if (entries.length < before) logEvent("info", "expired_entries_removed", { count: before - entries.length });

// ── Handle CronCreate ──────────────────────────────────────────────────────
if (tool_name === "CronCreate") {
  // Response is a JSON object: {"id":"3cdac30e","humanSchedule":"Every 3 minutes",...}
  // Fall back to text match for older format: "Scheduled 3cdac30e (Every 3 minutes)"
  let id = "";
  let humanSchedule = "";
  const resp = tool_response as Record<string, unknown>;
  if (resp && typeof resp === "object" && typeof resp.id === "string") {
    id = resp.id;
    humanSchedule = (resp.humanSchedule as string) ?? "";
  } else {
    const responseText =
      typeof tool_response === "string"
        ? tool_response
        : (resp?.output as string) ?? JSON.stringify(tool_response);
    const idMatch = responseText.match(/Scheduled\s+([a-f0-9]{8})/i);
    if (!idMatch) {
      logEvent("warn", "id_parse_failed", { response_snippet: responseText.slice(0, 120) });
      process.exit(0);
    }
    id = idMatch[1];
  }

  const rawInput = typeof tool_input?.input === "string" ? (tool_input.input as string) : "";
  // Native field is "cron", not "schedule" (confirmed from JSONL transcript inspection)
  const schedule = (tool_input?.cron as string) ?? (tool_input?.schedule as string) ?? rawInput.split(":")[0]?.trim() ?? "";
  const fullPrompt: string = (
    (tool_input?.prompt as string) ??
    (tool_input?.description as string) ??
    rawInput.split(":").slice(1).join(":").trim() ??
    ""
  );
  const description = fullPrompt.slice(0, 80);

  // Save prompt with history tracking
  mkdirSync(PROMPTS_DIR, { recursive: true });
  const { promptFile } = savePromptVersion(id, schedule, humanSchedule, fullPrompt, sessionId, projectPath, "CronCreate");

  const isUpdate = entries.some((e) => e.id === id);
  entries = entries.filter((e) => e.id !== id);
  entries.push({
    id, schedule, description, session_id: sessionId,
    project_path: projectPath, prompt_file: promptFile,
    created_at: new Date().toISOString(),
  });

  logEvent("info", isUpdate ? "cron_updated" : "cron_created", {
    id, schedule, description, session_id: sessionId.slice(0, 8), project_path: projectPath, total_active: entries.length,
  });
}

// ── Handle CronDelete ──────────────────────────────────────────────────────
else if (tool_name === "CronDelete") {
  const jobId = (tool_input?.id ?? tool_input?.job_id ?? "") as string;
  const found = entries.some((e) => e.id === jobId);
  // Remove prompt file on delete
  try { unlinkSync(join(PROMPTS_DIR, `${jobId}.md`)); } catch { /* already gone */ }
  entries = entries.filter((e) => e.id !== jobId);
  logEvent(found ? "info" : "warn", found ? "cron_deleted" : "cron_delete_not_found", {
    id: jobId, total_active: entries.length,
  });
}

// ── Handle CronList — authoritative reconciliation ─────────────────────────
// toolUseResult.jobs = [{id, cron, humanSchedule, prompt}] — the live in-memory state.
// Overwrites our shadow state with what Claude Code actually has scheduled.
else if (tool_name === "CronList") {
  const resp = tool_response as { jobs?: Array<{id: string; cron: string; humanSchedule: string; prompt: string}> };
  const jobs = resp?.jobs ?? [];

  if (jobs.length === 0) {
    // No active jobs — clear state and prompt files
    for (const e of entries) {
      try { unlinkSync(join(PROMPTS_DIR, `${e.id}.md`)); } catch { /* ok */ }
    }
    entries = [];
    logEvent("info", "cronlist_reconciled_empty", { previous_count: entries.length });
  } else {
    const liveIds = new Set(jobs.map(j => j.id));

    // Remove entries no longer in Claude Code's memory
    for (const e of entries) {
      if (!liveIds.has(e.id)) {
        try { unlinkSync(join(PROMPTS_DIR, `${e.id}.md`)); } catch { /* ok */ }
      }
    }
    entries = entries.filter(e => liveIds.has(e.id));

    // Upsert each live job with authoritative prompt
    mkdirSync(PROMPTS_DIR, { recursive: true });
    for (const job of jobs) {
      const existing = entries.find(e => e.id === job.id);
      const { promptFile } = savePromptVersion(job.id, job.cron, job.humanSchedule, job.prompt, sessionId, projectPath, "CronList");

      if (!existing) {
        entries.push({
          id: job.id, schedule: job.cron,
          description: job.prompt.slice(0, 80),
          session_id: sessionId, project_path: projectPath,
          prompt_file: promptFile, created_at: new Date().toISOString(),
        });
      } else {
        existing.schedule = job.cron;
        existing.description = job.prompt.slice(0, 80);
        existing.prompt_file = promptFile;
      }
    }
    logEvent("info", "cronlist_reconciled", { live_count: jobs.length, total_active: entries.length });
  }
}

// ── Persist ────────────────────────────────────────────────────────────────
try {
  mkdirSync(join(HOME, ".claude", "state"), { recursive: true });
  writeFileSync(STATE_FILE, JSON.stringify(entries, null, 2));
} catch (e) {
  logEvent("error", "state_write_failed", { error: String(e) });
}

process.exit(0);
