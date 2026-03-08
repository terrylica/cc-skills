/**
 * Auto-Continue Stop Hook — TypeScript Evaluation Engine
 *
 * Evaluates whether a plan-driven session has completed all work
 * using MiniMax M2.5-highspeed. If work remains, blocks the stop
 * with "Continue as planned". When done, optionally injects a sweep prompt.
 *
 * Dependencies resolved at runtime from ~/.claude/automation/claude-telegram-sync/src/:
 *   - parseTranscript(), extractSessionSummary() from transcript-parser.ts
 *   - querySummaryModel() from summary-model.ts
 *   - escapeHtml() from format.ts
 *
 * Secrets: sourced by auto-continue-wrapper.sh from ~/.claude/.secrets/ccterrybot-telegram
 * (MINIMAX_API_KEY, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID). Never hardcoded here.
 */

import { readFileSync, writeFileSync, appendFileSync, existsSync, mkdirSync } from "fs";
import { join, basename } from "path";
import { homedir } from "os";

// --- Dynamic imports from claude-telegram-sync automation package ---
// These resolve at runtime against the installed automation directory.
// The cc-skills repo (public) contains this file as SSoT; the automation
// directory contains the package with transcript parsing and model clients.
const SYNC_ROOT = join(homedir(), ".claude", "automation", "claude-telegram-sync", "src");

const { parseTranscript, extractSessionSummary } = await import(
  join(SYNC_ROOT, "claude-sync", "transcript-parser.js")
);
const { querySummaryModel } = await import(
  join(SYNC_ROOT, "claude-sync", "summary-model.js")
);
const { escapeHtml } = await import(
  join(SYNC_ROOT, "telegram", "format.js")
);

// Local type definition (mirrors transcript-parser.ts ConversationTurn)
interface ConversationTurn {
  prompt: string;
  response: string;
  toolSummary?: string;
  toolResults?: string;
}

// --- Constants ---

const MAX_ITERATIONS = Number(Bun.env.AUTO_CONTINUE_MAX_ITERATIONS ?? "10");
const MAX_RUNTIME_MIN = Number(Bun.env.AUTO_CONTINUE_MAX_RUNTIME_MIN ?? "180");
const TRANSCRIPT_BUDGET = Number(Bun.env.AUTO_CONTINUE_TRANSCRIPT_BUDGET ?? "102400");
const STATE_DIR = join(homedir(), ".claude", "hooks", "state");
const LOG_FILE = "/tmp/auto-continue-hook.log";

// Ensure MiniMax env defaults (wrapper also sets these, but TS must be self-contained)
Bun.env.SUMMARY_MODEL ??= "MiniMax-M2.5-highspeed";
Bun.env.SUMMARY_BASE_URL ??= "https://api.minimax.io/anthropic";

const SYSTEM_PROMPT = `You are an autonomous session evaluator. You receive a session transcript and optionally a plan file. Your job: determine the single best next action.

RESPOND WITH EXACTLY ONE LINE in the format:
DECISION|<your crafted instruction or summary>

Where DECISION is one of:

CONTINUE — Work remains. Your instruction text becomes the user's next message to Claude, so make it specific and actionable. Reference exact deliverables, files, or steps that are unfinished.

SWEEP — Primary work appears done but needs a final multi-agent review pass. Use when the main deliverables are complete but the session hasn't verified quality, updated documentation/memory, or cross-checked against the original request.

REDIRECT — Claude drifted from the original request. Your instruction should re-anchor Claude to what the user actually asked for. Reference the original request and explain what went off track.

DONE — (LAST RESORT) Return ONLY when you are absolutely certain no value-adding work remains. Simple Q&A with a complete answer, user said thanks, or conversation is trivially finished. If there is ANY possibility of improvement, documentation, testing, memory updates, or follow-up — choose a different decision.

PRIORITY ORDER (highest to lowest):
  CONTINUE > REDIRECT > SWEEP > DONE

Your job is to maximize Claude's output. The deterministic safety boundaries (max iterations, max runtime) handle the "stop eventually" concern — your job is to find reasons to keep working, not reasons to stop.

EVALUATION RULES:
1. Read the ENTIRE transcript to understand what was requested and what was delivered.
2. If a plan file is provided, use it as the authority for what needs to be done.
3. If no plan file exists (marked "NO_PLAN"), infer deliverables from the user's messages in the transcript. Look for numbered lists, checkboxes, "Output:" sections, multi-step prompts, or explicit requests.
4. For multi-deliverable prompts (e.g., "Output: updated plan, updated memory, completed deliverables"), check EACH deliverable individually. If any is missing → CONTINUE.
5. ACTIVELY LOOK for reasons to continue. Check for: incomplete deliverables, code that lacks tests, missing documentation updates, memory files that should be updated, GitHub issues that could be commented on or closed, error handling gaps, edge cases, opportunities to improve code quality.
6. Even if the primary task appears done, look for adjacent value: Did Claude update project memory? Did Claude commit the changes? Are there GitHub issues to update? Could the solution be more robust?
7. SWEEP when coding work is done but quality verification, documentation, or cross-checking hasn't happened yet.
8. REDIRECT when the last few turns show Claude working on something unrelated to the original request.
9. DONE requires absolute certainty. Ask yourself: "If I were the user, would I be satisfied that every aspect of my request — explicit and implied — has been addressed?" If there is any doubt, choose CONTINUE.
10. Your instruction text is critical — Claude will receive it verbatim as a user message. Write it as a direct, imperative instruction.`;

const SWEEP_PROMPT = `Spawn multiple agents with multiple perspectives to review our plan, to search ~/fork-tools and to search the online Internet web for SOTA well-maintained FOSS(s) that can help us avoid hand-rolled solution(s). Review relevant GitHub Issues and our memory and then infer what's left unsaid and undone. Fork (not clone) FOSS(s) to our ~/fork-tools and deep dive them to be inspired. Adpot certain ideations from the FOSS if the FOSS is too heavy. Be expansive and thorough--I don't mind scope creeps, but keep changes aligned with the plan's goals. Identify gaps/incomplete work and finish what's necessary. Output: updated plan, updated memory, update relevant GitHub Issues, completed deliverables, and a concise list of what you changed and why.`;

// --- Types ---

interface AutoContinueState {
  iteration: number;
  total_iterations: number;  // Lifetime counter — never resets
  sweep_done: boolean;
  sweep_notified: boolean;   // Prevents duplicate "Sweep complete" Telegram spam
  started_at: string;
}

interface HookInput {
  session_id?: string;
  sessionId?: string;
  cwd?: string;
  transcript_path?: string;
  stop_hook_active?: boolean;
}

// --- Logging ---

function hookLog(msg: string): void {
  try {
    appendFileSync(LOG_FILE, `${new Date().toISOString()} [auto-continue] ${msg}\n`);
  } catch {
    // fail-open
  }
}

// --- State Management ---

function stateFilePath(sessionId: string): string {
  return join(STATE_DIR, `auto-continue-${sessionId}.json`);
}

function loadState(sessionId: string): AutoContinueState {
  const path = stateFilePath(sessionId);
  try {
    if (existsSync(path)) {
      const raw = readFileSync(path, "utf-8");
      const parsed = JSON.parse(raw);
      return {
        iteration: parsed.iteration ?? 0,
        total_iterations: parsed.total_iterations ?? parsed.iteration ?? 0,
        sweep_done: parsed.sweep_done ?? false,
        sweep_notified: parsed.sweep_notified ?? false,
        started_at: parsed.started_at ?? new Date().toISOString(),
      };
    }
  } catch {
    // Corrupted state file — reset
    hookLog(`State file corrupted for ${sessionId}, resetting`);
  }
  return { iteration: 0, total_iterations: 0, sweep_done: false, sweep_notified: false, started_at: new Date().toISOString() };
}

function saveState(sessionId: string, state: AutoContinueState): void {
  try {
    if (!existsSync(STATE_DIR)) {
      mkdirSync(STATE_DIR, { recursive: true });
    }
    writeFileSync(stateFilePath(sessionId), JSON.stringify(state, null, 2));
  } catch (e) {
    hookLog(`Failed to save state: ${e}`);
  }
}

// --- Plan Discovery ---

/** Discover plan file by scanning raw transcript content (structure-agnostic). */
function discoverPlanFromTranscript(transcriptPath: string): string | null {
  const planRegex = /\.claude\/plans\/([a-zA-Z0-9_.-]+\.md)/g;

  // Search current transcript first
  try {
    const raw = readFileSync(transcriptPath, "utf-8");
    let match: RegExpExecArray | null;
    while ((match = planRegex.exec(raw)) !== null) {
      const planPath = join(homedir(), ".claude", "plans", match[1]!);
      if (existsSync(planPath)) return planPath;
    }
  } catch {
    // fall through
  }

  // Fallback: find THE LAST plan from sibling sessions in the same project directory.
  // Walk most-recent-first. The first sibling with a plan IS the last plan — either:
  //   - sweep_done=true → plan is finished, return null (don't dig deeper into older plans)
  //   - sweep_done=false / no state → adopt it, MiniMax evaluates relevance to current work
  try {
    const dir = require("path").dirname(transcriptPath);
    const currentFile = basename(transcriptPath);
    const siblings = require("fs").readdirSync(dir) as string[];
    const jsonlFiles = siblings
      .filter((f: string) => f.endsWith(".jsonl") && f !== currentFile)
      .map((f: string) => ({ name: f, mtime: require("fs").statSync(join(dir, f)).mtimeMs }))
      .sort((a: { mtime: number }, b: { mtime: number }) => b.mtime - a.mtime);

    for (const { name } of jsonlFiles) {
      let planPath: string | null = null;
      try {
        const raw = readFileSync(join(dir, name), "utf-8");
        let match: RegExpExecArray | null;
        planRegex.lastIndex = 0;
        // Prefer main plan (no -agent- suffix) over agent sub-plans
        const candidates: string[] = [];
        while ((match = planRegex.exec(raw)) !== null) {
          const p = join(homedir(), ".claude", "plans", match[1]!);
          if (existsSync(p)) candidates.push(p);
        }
        if (candidates.length === 0) continue; // no plan in this sibling, check older
        planPath = candidates.find(p => !basename(p).includes("-agent-")) ?? candidates[0]!;
      } catch {
        continue;
      }

      // This is THE LAST plan. Check if it's finished.
      const siblingSessionId = name.replace(/\.jsonl$/, "");
      const siblingStateFile = stateFilePath(siblingSessionId);
      if (existsSync(siblingStateFile)) {
        const siblingState = loadState(siblingSessionId);
        if (siblingState.sweep_done) {
          hookLog(`Last plan found in sibling ${name.slice(0, 8)} but sweep_done — plan finished`);
          return null; // definitive: last plan is done, no active plan
        }
      }

      hookLog(`Last plan discovered in sibling ${name.slice(0, 8)}: ${basename(planPath)}`);
      return planPath;
    }
  } catch {
    // fall through
  }

  return null;
}

// --- Transcript Building ---

function buildTranscriptText(turns: ConversationTurn[], budget: number): string {
  const maxPromptChars = 2000;
  const maxResponseChars = 4000;
  const maxToolResultChars = 1500;

  const turnTexts = turns.map((t, i) => {
    const p = t.prompt.length > maxPromptChars
      ? t.prompt.slice(0, maxPromptChars) + " [truncated]"
      : t.prompt;
    const r = t.response.length > maxResponseChars
      ? t.response.slice(0, maxResponseChars) + " [truncated]"
      : t.response || "[no text response]";
    const tools = t.toolSummary ? `\nTools used: ${t.toolSummary}` : "";
    const results = t.toolResults && t.toolResults.length > 0
      ? `\nKey tool outputs:\n${t.toolResults.length > maxToolResultChars ? t.toolResults.slice(0, maxToolResultChars) + " [truncated]" : t.toolResults}`
      : "";
    return `=== Turn ${i + 1} ===\nUser request:\n${p}\n\nOutcome:\n${r}${tools}${results}`;
  });

  let transcript = "";
  for (const t of turnTexts) {
    if (transcript.length + t.length > budget) {
      transcript += "\n\n[remaining turns omitted for length]";
      break;
    }
    transcript += (transcript ? "\n\n" : "") + t;
  }
  return transcript;
}

// --- MiniMax Evaluation ---

interface EvalResult {
  decision: "CONTINUE" | "DONE" | "SWEEP" | "REDIRECT";
  reason: string;
  minimaxId?: string;
}

async function evaluateCompletion(transcript: string, planContent: string): Promise<EvalResult> {
  const hasPlan = planContent && planContent.trim() !== "NO_PLAN" && planContent.trim().length > 0;
  const truncatedPlan = hasPlan
    ? (planContent.length > 15000 ? planContent.slice(0, 15000) + "\n[plan truncated]" : planContent)
    : null;

  const planSection = truncatedPlan
    ? `## Plan (authoritative task list)\n"""\n${truncatedPlan}\n"""\n\n`
    : `## Plan\nNO PLAN FILE. Infer deliverables from the user's messages in the transcript below. Look for numbered lists, checkboxes, "Output:" sections, multi-step prompts, or explicit multi-deliverable requests.\n\n`;

  const prompt = `${planSection}## Session Transcript
"""
${transcript}
"""

Evaluate the session. What is the best next action?`;

  const result = await querySummaryModel({
    prompt,
    systemPrompt: SYSTEM_PROMPT,
    maxTokens: 2048,
  });

  const parsed = parseDecision(result.text);
  parsed.minimaxId = result.messageId;
  return parsed;
}

function parseDecision(text: string): EvalResult {
  if (!text.trim()) {
    hookLog("WARN: empty model response, defaulting to DONE (fail-open)");
    return { decision: "DONE", reason: "empty model response" };
  }

  // Helper: check if a string starts with a known decision keyword
  const matchDecision = (s: string): EvalResult["decision"] | null => {
    const u = s.trim().toUpperCase();
    if (u.startsWith("CONT")) return "CONTINUE";
    if (u.startsWith("SWEEP")) return "SWEEP";
    if (u.startsWith("REDIR")) return "REDIRECT";
    if (u.startsWith("DONE")) return "DONE";
    return null;
  };

  for (const line of text.trim().split("\n")) {
    const reason = line.includes("|") ? line.split("|").slice(1).join("|").trim() : "";

    // Direct match: line starts with decision keyword (e.g., "CONTINUE|do X")
    const direct = matchDecision(line);
    if (direct) return { decision: direct, reason };

    // Indirect match: MiniMax echoed format literally (e.g., "DECISION|DONE — ...")
    // Check each pipe-delimited field for a decision keyword
    if (line.includes("|")) {
      for (const field of line.split("|")) {
        const found = matchDecision(field);
        if (found) {
          // Reason is everything after this field
          const idx = line.indexOf(field) + field.length;
          const rest = line.slice(idx).replace(/^\|/, "").trim();
          return { decision: found, reason: rest || reason };
        }
      }
    }
  }
  hookLog(`WARN: no decision found in response, defaulting to DONE: ${text.slice(0, 100)}`);
  return { decision: "DONE", reason: "no decision line found" };
}

// --- Sweep Detection ---

function detectSweepNeeded(planContent: string): boolean {
  if (!planContent || planContent === "NO_PLAN") return false;

  const hasUnchecked = /\[ \]/.test(planContent);
  const hasChecked = /\[x\]/i.test(planContent);

  // Checkbox-based plans: sweep if all checked, none unchecked
  if (hasChecked && !hasUnchecked) {
    const hasSweepSection = /##\s*(final review|sweep|review|post-implementation)/i.test(planContent);
    return !hasSweepSection;
  }

  // Non-checkbox plans: always sweep on first DONE
  if (!hasChecked && !hasUnchecked) {
    return true;
  }

  return false; // Has unchecked items — MiniMax should have said CONTINUE
}

// --- Telegram Notification ---

const TG_TIMEOUT_MS = 5000;

interface NotificationParams {
  decision: "CONTINUE" | "DONE" | "SWEEP" | "REDIRECT";
  reason: string;
  planPath: string;
  planContent: string;
  iteration: number;
  maxIterations: number;
  elapsedMin: number;
  maxRuntimeMin: number;
  turnCount: number;
  sessionId: string;
  cwd: string;
  gitBranch: string;
  toolCalls: number;
  toolBreakdown: string;
  errors: number;
  minimaxId?: string;
}

function extractPlanTitle(planContent: string): string {
  const match = planContent.match(/^#\s+(.+)$/m);
  return match?.[1]?.replace(/^Plan:\s*/i, "").trim() ?? "Untitled Plan";
}

function progressBar(done: number, total: number, width = 10): string {
  if (total === 0) return "";
  const filled = Math.round((done / total) * width);
  return "\u2588".repeat(filled) + "\u2591".repeat(width - filled);
}

function checkboxCounts(planContent: string): { checked: number; total: number } {
  const checked = (planContent.match(/\[x\]/gi) || []).length;
  const unchecked = (planContent.match(/\[ \]/g) || []).length;
  return { checked, total: checked + unchecked };
}

function formatDecisionMessage(params: NotificationParams): string {
  const {
    decision, reason, planPath, planContent,
    iteration, maxIterations, elapsedMin, maxRuntimeMin,
    turnCount, sessionId, cwd, gitBranch, toolCalls, toolBreakdown, errors, minimaxId,
  } = params;

  const icons = { CONTINUE: "\uD83D\uDD04", SWEEP: "\uD83E\uDDF9", REDIRECT: "\u21A9\uFE0F", DONE: "\u2705" } as const;
  const icon = icons[decision];
  const planFile = escapeHtml(basename(planPath) || "unknown");
  const planTitle = escapeHtml(extractPlanTitle(planContent));
  const shortSession = escapeHtml(sessionId.slice(0, 8));
  const shortCwd = escapeHtml(cwd.replace(homedir(), "~"));
  const separator = "\u2501".repeat(24);

  const displayReason = reason.slice(0, 200);

  // Checkbox progress (only if plan uses checkboxes)
  const { checked, total } = checkboxCounts(planContent);
  const hasCheckboxes = total > 0;
  const progressLine = hasCheckboxes
    ? `${progressBar(checked, total)} <code>${checked}/${total} tasks</code>\n`
    : "";

  const timestamp = new Date().toLocaleString("en-CA", {
    timeZone: "America/Vancouver",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hour12: false,
  });

  const lines = [
    `<b>${icon} Auto-Continue: ${decision}</b>`,
    separator,
    ``,
    `<i>${escapeHtml(displayReason) || "No reason provided"}</i>`,
  ];

  if (decision === "SWEEP") {
    lines.push(`\u26A1 <b>Action</b>: Sweep prompt injected for final review`);
  }

  lines.push(
    ``,
    `<b>\uD83D\uDCCB Plan</b>: ${planTitle}`,
    `${progressLine}<code>${planFile}</code>`,
    ``,
    `<b>\uD83D\uDCCA Session</b>`,
    `\u2022 Iteration: <code>${iteration} / ${maxIterations}</code>`,
    `\u2022 Runtime: <code>${elapsedMin.toFixed(1)} / ${maxRuntimeMin} min</code>`,
    `\u2022 <code>${turnCount}T ${toolBreakdown || `${toolCalls}\u2699`}${errors > 0 ? ` ${errors}\u2717` : ""}</code>`,
  );

  if (gitBranch) {
    lines.push(`\u2022 Branch: <code>${escapeHtml(gitBranch)}</code>`);
  }

  lines.push(
    `\u2022 Project: <code>${shortCwd}</code>`,
    `\u2022 Claude session uuid jsonl ~/.claude/projects: <code>${shortSession}</code>`,
  );

  if (minimaxId) {
    lines.push(`\u2022 MiniMax 2.5 highspeed uuid: <code>${escapeHtml(minimaxId.slice(0, 12))}</code>`);
  }

  lines.push(
    ``,
    separator,
    `<i>${timestamp}</i>`,
  );

  let message = lines.join("\n");
  if (message.length > 4096) {
    message = message.replace(/\u2588[\u2588\u2591]*\s*<code>\d+\/\d+ tasks<\/code>\n/, "");
    if (message.length > 4096) {
      let cutPoint = message.lastIndexOf("\n", 4080);
      if (cutPoint < 2000) cutPoint = 4080;
      message = message.slice(0, cutPoint)
        .replace(/&[^;]*$/, "")  // strip broken HTML entities at cut point
        .replace(/<[^>]*$/, "")  // strip broken HTML tags at cut point
        + "\n\u2026";
    }
  }

  return message;
}

async function sendTelegramNotification(params: NotificationParams): Promise<void> {
  const token = Bun.env.TELEGRAM_BOT_TOKEN;
  const chatId = Bun.env.TELEGRAM_CHAT_ID;
  if (!token || !chatId) {
    hookLog("Telegram credentials missing, skipping notification");
    return;
  }

  const message = formatDecisionMessage(params);

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TG_TIMEOUT_MS);
    const t0 = Date.now();

    const response = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        text: message,
        parse_mode: "HTML",
        disable_notification: true,
        link_preview_options: { is_disabled: true },
      }),
      signal: controller.signal,
    });

    clearTimeout(timer);
    const durationMs = Date.now() - t0;

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      hookLog(`Telegram API error ${response.status} (${durationMs}ms): ${body.slice(0, 200)}`);
    } else {
      hookLog(`Telegram notification sent: ${params.decision} (${durationMs}ms)`);
    }
  } catch (e) {
    const isTimeout = e instanceof DOMException && e.name === "AbortError";
    hookLog(`Telegram notification ${isTimeout ? "timed out" : "failed"} (non-fatal): ${e}`);
  }
}

/** Lightweight notification for early exits (no plan/MiniMax context). */
async function sendExitNotification(
  exitReason: string,
  sessionId: string,
  cwd: string,
  state?: AutoContinueState,
): Promise<void> {
  const token = Bun.env.TELEGRAM_BOT_TOKEN;
  const chatId = Bun.env.TELEGRAM_CHAT_ID;
  if (!token || !chatId) return;

  const shortSession = escapeHtml(sessionId.slice(0, 8));
  const shortCwd = escapeHtml(cwd.replace(homedir(), "~"));
  const separator = "\u2501".repeat(24);
  const timestamp = new Date().toLocaleString("en-CA", {
    timeZone: "America/Vancouver",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hour12: false,
  });

  const stateInfo = state
    ? `\n\u2022 Iteration: <code>${state.total_iterations} / ${MAX_ITERATIONS}</code>`
    : "";
  const elapsedInfo = state
    ? `\n\u2022 Runtime: <code>${((Date.now() - new Date(state.started_at).getTime()) / 60000).toFixed(1)} / ${MAX_RUNTIME_MIN} min</code>`
    : "";

  const message = [
    `<b>\u23F9 Auto-Continue: STOP</b>`,
    separator,
    ``,
    `<i>${escapeHtml(exitReason)}</i>`,
    ``,
    `<b>\uD83D\uDCCA Session</b>${stateInfo}${elapsedInfo}`,
    `\u2022 Project: <code>${shortCwd}</code>`,
    `\u2022 Claude session uuid jsonl ~/.claude/projects: <code>${shortSession}</code>`,
    ``,
    separator,
    `<i>${timestamp}</i>`,
  ].join("\n");

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TG_TIMEOUT_MS);
    await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId, text: message, parse_mode: "HTML",
        disable_notification: true, link_preview_options: { is_disabled: true },
      }),
      signal: controller.signal,
    });
    clearTimeout(timer);
    hookLog(`Telegram exit notification sent: ${exitReason}`);
  } catch {
    // non-fatal
  }
}

// --- Output Helpers ---

function allowStop(): void {
  console.log("{}");
}

function blockStop(reason: string): void {
  console.log(JSON.stringify({ decision: "block", reason }));
}

// --- Main ---

async function main(): Promise<void> {
  // Parse stdin
  const reader = Bun.stdin.stream().getReader();
  let inputText = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    inputText += new TextDecoder().decode(value);
  }

  let input: HookInput;
  try {
    input = JSON.parse(inputText);
  } catch {
    hookLog("Failed to parse stdin JSON");
    allowStop();
    return;
  }

  const sessionId = input.session_id || input.sessionId || "";
  const transcriptPath = input.transcript_path || "";

  if (!sessionId || !transcriptPath) {
    allowStop();
    return;
  }

  // Diagnostic: log env var state for debugging config issues
  const envState = [
    Bun.env.MINIMAX_API_KEY ? "KEY\u2713" : "KEY\u2717",
    Bun.env.SUMMARY_MODEL ? "MODEL\u2713" : "MODEL\u2717",
    Bun.env.SUMMARY_BASE_URL ? "URL\u2713" : "URL\u2717",
    Bun.env.TELEGRAM_BOT_TOKEN ? "TG\u2713" : "TG\u2717",
  ].join(" ");
  hookLog(`session=${sessionId.slice(0, 8)} env=[${envState}]`);

  // Load state
  const state = loadState(sessionId);
  const cwd = input.cwd || "";

  if (input.stop_hook_active) {
    // Circuit breaker: use total_iterations (lifetime, never resets) to catch
    // loops that survive across streak resets. The streak counter (iteration)
    // resets on manual intervention, but total_iterations never does.
    if (state.total_iterations >= 2) {
      hookLog(`Breaking loop: stop_hook_active with total_iterations=${state.total_iterations} >= 2`);
      allowStop();
      await sendExitNotification("Loop breaker: consecutive stop_hook_active", sessionId, cwd, state);
      return;
    }
    hookLog(`stop_hook_active=true for ${sessionId} (iteration=${state.iteration}, total=${state.total_iterations}), proceeding with evaluation`);
  } else {
    // Manual intervention — reset auto-iteration streak.
    // Only uninterrupted auto-iterations count toward limits.
    // total_iterations is preserved for notification accuracy.
    if (state.iteration > 0 || state.sweep_done) {
      hookLog(`Manual intervention detected (iteration=${state.iteration}\u21920, sweep_done=${state.sweep_done}\u2192false), resetting streak (total=${state.total_iterations})`);
    }
    state.iteration = 0;
    state.sweep_done = false;
    state.sweep_notified = false;
    state.started_at = new Date().toISOString();
    saveState(sessionId, state);
  }

  // Check limits
  if (state.iteration >= MAX_ITERATIONS) {
    hookLog(`Max iterations (${MAX_ITERATIONS}) reached for ${sessionId}`);
    allowStop();
    await sendExitNotification(`Max iterations (${MAX_ITERATIONS}) reached`, sessionId, cwd, state);
    return;
  }

  const elapsedMin = (Date.now() - new Date(state.started_at).getTime()) / 60000;
  if (state.iteration > 0 && elapsedMin >= MAX_RUNTIME_MIN) {
    hookLog(`Max runtime (${MAX_RUNTIME_MIN}min) reached for ${sessionId}`);
    allowStop();
    await sendExitNotification(`Max runtime (${MAX_RUNTIME_MIN}min) reached`, sessionId, cwd, state);
    return;
  }

  if (state.sweep_done) {
    hookLog(`sweep_done=true for ${sessionId.slice(0, 8)}, allowing stop`);
    allowStop();
    if (!state.sweep_notified) {
      state.sweep_notified = true;
      saveState(sessionId, state);
      await sendExitNotification("Sweep complete \u2014 session finished", sessionId, cwd, state);
    }
    return;
  }

  // Parse transcript first (single file read), then discover plan from events
  let transcript: string;
  let turnCount: number;
  let planContent: string;
  let planPath: string = "";
  let gitBranch: string = "";
  let toolCalls: number = 0;
  let toolBreakdown: string = "";
  let sessionErrors: number = 0;
  try {
    // Discover plan file — optional. MiniMax evaluates with or without a plan.
    const discovered = discoverPlanFromTranscript(transcriptPath);
    if (discovered) {
      planPath = discovered;
      try {
        planContent = readFileSync(planPath, "utf-8");
        if (!planContent.trim()) planContent = "NO_PLAN";
      } catch {
        hookLog(`Failed to read plan file: ${planPath}, continuing without plan`);
        planContent = "NO_PLAN";
      }
    } else {
      hookLog("No plan file found \u2014 MiniMax will infer deliverables from transcript");
      planContent = "NO_PLAN";
      planPath = "";
    }

    const events = parseTranscript(transcriptPath);
    const summary = extractSessionSummary(events);
    turnCount = summary.turns.length;
    gitBranch = summary.gitBranch ?? "";

    // Aggregate tool counts across all turns for compact breakdown
    // Exclude subagent orchestration tools — report main session's direct work only
    const SUBAGENT_TOOLS = new Set(["Agent", "Task", "TaskCreate", "TaskGet", "TaskList", "TaskOutput", "TaskUpdate", "TaskStop"]);
    const toolAgg = new Map<string, number>();
    for (const turn of summary.turns) {
      if (!turn.toolSummary) continue;
      for (const part of turn.toolSummary.split(", ")) {
        const m = part.match(/^(\w+)(?:\s+x(\d+))?$/);
        if (m?.[1] && !SUBAGENT_TOOLS.has(m[1])) {
          toolAgg.set(m[1], (toolAgg.get(m[1]) ?? 0) + Number(m[2] ?? 1));
        }
      }
    }
    // Sort by count descending, format as "Bash61 Edit54 Read55"
    toolBreakdown = [...toolAgg.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 6) // top 6 to keep it concise
      .map(([name, count]) => `${name}${count}`)
      .join(" ");
    toolCalls = [...toolAgg.values()].reduce((a, b) => a + b, 0);
    sessionErrors = summary.errors ?? 0;

    if (turnCount === 0) {
      // Before bailing on empty transcript, check if a sibling plan was never swept.
      // This handles the case where a previous session implemented a plan but was
      // interrupted before Stop hooks fired — the sweep never ran. When the user
      // opens a continuation session (0 turns), we inject the sweep as the first action.
      if (planPath && planContent !== "NO_PLAN" && !state.sweep_done) {
        hookLog(`0-turn session with un-swept sibling plan: ${basename(planPath)} \u2014 injecting sweep`);
        state.sweep_done = true;
        state.total_iterations++;
        saveState(sessionId, state);
        blockStop(SWEEP_PROMPT);
        await sendTelegramNotification({
          decision: "SWEEP",
          reason: "Sibling session implemented plan but sweep never fired \u2014 injecting final audit",
          planPath, planContent,
          iteration: state.total_iterations,
          maxIterations: MAX_ITERATIONS,
          elapsedMin: 0, maxRuntimeMin: MAX_RUNTIME_MIN,
          turnCount: 0, sessionId, cwd,
          gitBranch, toolCalls: 0, toolBreakdown: "", errors: 0,
        });
        return;
      }
      hookLog("No turns found in transcript");
      allowStop();
      await sendExitNotification("No turns in transcript", sessionId, cwd, state);
      return;
    }

    transcript = buildTranscriptText(summary.turns, TRANSCRIPT_BUDGET);
  } catch (e) {
    hookLog(`Failed to parse transcript: ${e}`);
    allowStop();
    await sendExitNotification("Transcript parse failed", sessionId, cwd, state);
    return;
  }

  // MiniMax evaluation
  let evalResult: EvalResult;
  try {
    evalResult = await evaluateCompletion(transcript, planContent);
    hookLog(`MiniMax decision: ${evalResult.decision} (iteration=${state.iteration}, turns=${turnCount}, id=${evalResult.minimaxId ?? "none"})`);
  } catch (e) {
    hookLog(`MiniMax evaluation failed: ${e}`);
    allowStop();
    await sendExitNotification(`MiniMax failed: ${String(e).slice(0, 100)}`, sessionId, cwd, state);
    return;
  }

  // MiniMax now determines the full decision — CONTINUE, SWEEP, REDIRECT, or DONE.
  // Deterministic sweep detection is kept as a fallback for DONE when MiniMax doesn't suggest SWEEP.
  let effectiveDecision = evalResult.decision;
  if (effectiveDecision === "DONE" && detectSweepNeeded(planContent) && !state.sweep_done) {
    effectiveDecision = "SWEEP";
    evalResult.reason = "Deterministic sweep: all checkboxes done, no review section";
  }

  // Act on decision (emit stdout FIRST — this is what Claude Code reads)
  switch (effectiveDecision) {
    case "CONTINUE":
    case "REDIRECT":
      state.iteration++;
      state.total_iterations++;
      saveState(sessionId, state);
      // MiniMax crafted the continuation instruction — use it directly
      blockStop(evalResult.reason || "Continue as planned");
      break;
    case "SWEEP":
      state.sweep_done = true;
      saveState(sessionId, state);
      blockStop(SWEEP_PROMPT);
      break;
    case "DONE":
      allowStop();
      break;
  }

  // Send Telegram notification AFTER decision output (awaited to keep process alive)
  await sendTelegramNotification({
    decision: effectiveDecision,
    reason: evalResult.reason,
    planPath, planContent,
    iteration: state.total_iterations,
    maxIterations: MAX_ITERATIONS,
    elapsedMin, maxRuntimeMin: MAX_RUNTIME_MIN,
    turnCount, sessionId,
    cwd,
    gitBranch, toolCalls, toolBreakdown, errors: sessionErrors,
    minimaxId: evalResult.minimaxId,
  });
}

// Fail-open wrapper
main().catch((e) => {
  hookLog(`Uncaught error: ${e}`);
  allowStop();
});
