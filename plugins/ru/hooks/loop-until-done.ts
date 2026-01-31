#!/usr/bin/env bun
/**
 * Ralph Universal Stop Hook - TypeScript/Bun implementation
 *
 * Autonomous improvement engine for ANY project.
 * Implements an eternal loop with recursive self-improvement behavior.
 *
 * ADR: 2025-12-20-ralph-rssi-eternal-loop
 * Issue #12: https://github.com/terrylica/cc-skills/issues/12
 *
 * Migration: Incremental from Python. Python modules called via subprocess
 * until fully migrated to TypeScript.
 *
 * Ralph Behavior:
 * - Task completion → pivot to exploration (not stop)
 * - Adapter convergence → pivot to exploration (not stop)
 * - Loop detection (99% threshold) → continue with exploration
 * - User-controlled stops → /ru:stop, kill switch, max limits
 *
 * Schema per Claude Code docs:
 * - To ALLOW stop: return {} (empty object)
 * - To CONTINUE (prevent stop): return {"decision": "block", "reason": "..."}
 * - To HARD STOP: return {"continue": false} - overrides everything
 */

import { existsSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { join, dirname } from "path";
import { execSync, spawnSync } from "child_process";
import { homedir } from "os";

// --- Types ---

interface HookInput {
  session_id?: string;
  stop_hook_active?: boolean;
  transcript_path?: string;
}

interface LoopConfig {
  min_hours: number;
  max_hours: number;
  min_iterations: number;
  max_iterations: number;
  no_focus?: boolean;
  target_file?: string;
  discovered_file?: string;
  discovery_method?: string;
}

interface LoopState {
  iteration: number;
  project_path: string;
  started_at: string;
  recent_outputs: string[];
  plan_file: string | null;
  discovered_file: string | null;
  discovery_method: string;
  candidate_files: string[];
  completion_signals: string[];
  last_completion_confidence: number;
  opportunities_discovered: string[];
  validation_round: number;
  validation_iteration: number;
  validation_findings: Record<string, unknown>;
  validation_score: number;
  validation_exhausted: boolean;
  previous_finding_count: number;
  agent_results: unknown[];
  adapter_name: string;
  adapter_convergence: AdapterConvergence | null;
  accumulated_runtime_seconds: number;
  last_hook_timestamp: number;
  force_exploration?: boolean;
  idle_iteration_count?: number;
  last_iteration_time?: number;
  idle_iterations?: number;
}

interface AdapterConvergence {
  should_continue: boolean;
  reason: string;
  confidence: number;
  converged: boolean;
  metrics_count: number;
  metrics_history: unknown[];
}

interface Guidance {
  forbidden: string[];
  encouraged: string[];
  timestamp?: string;
}

// --- Constants ---

const STATE_DIR = join(homedir(), ".claude/hooks/state");
const CONFIG_DIR = join(homedir(), ".claude");
const CONFIG_FILE = join(CONFIG_DIR, "loop_config.json");

const DEFAULT_CONFIG: LoopConfig = {
  min_hours: 1.0,
  max_hours: 9.0,
  min_iterations: 50,
  max_iterations: 99,
};

const TIME_WARNING_THRESHOLD_HOURS = 0.5;
const ITERATIONS_WARNING_THRESHOLD = 10;
const BACKOFF_BASE_INTERVAL = 30;
const BACKOFF_MULTIPLIER = 2;
const BACKOFF_MAX_INTERVAL = 300;
const BACKOFF_JITTER = 5;
const MAX_IDLE_BEFORE_EXPLORE = 3;
const WINDOW_SIZE = 10;

// --- Observability ---

let startTime = Date.now();

function resetTimer(): void {
  startTime = Date.now();
}

function emit(category: string, message: string, target: "stderr" | "terminal" = "stderr"): void {
  const elapsed = ((Date.now() - startTime) / 1000).toFixed(2);
  const output = `[ralph] [${elapsed}s] ${category}: ${message}`;
  if (target === "stderr") {
    console.error(output);
  }
}

// --- Output Functions ---

function hardStop(reason: string): void {
  emit("Hard stop", reason);
  console.log(JSON.stringify({ continue: false }));
}

function allowStop(reason: string): void {
  emit("Allow stop", reason);
  console.log(JSON.stringify({}));
}

function continueSession(reason: string): void {
  emit("Template", `Rendering ralph-unified.md (${reason.includes("EXPLORATION") ? "EXPLORATION" : "IMPLEMENTATION"}): ${reason.split("\n")[0].substring(0, 50)}...`);
  console.log(JSON.stringify({ decision: "block", reason }));
}

// --- Utility Functions ---

function getPathHash(projectDir: string): string {
  // Simple hash for path-based state isolation
  let hash = 0;
  for (let i = 0; i < projectDir.length; i++) {
    const char = projectDir.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return Math.abs(hash).toString(16).substring(0, 8);
}

function buildStateFilePath(stateDir: string, sessionId: string, projectDir: string): string {
  const pathHash = getPathHash(projectDir);
  return join(stateDir, `${sessionId}_${pathHash}.json`);
}

function loadState(stateFile: string, defaultState: LoopState): LoopState {
  try {
    if (existsSync(stateFile)) {
      const data = JSON.parse(readFileSync(stateFile, "utf-8"));
      return { ...defaultState, ...data };
    }
  } catch (e) {
    emit("State", `Failed to load state: ${e}`);
  }
  return defaultState;
}

function saveState(stateFile: string, state: LoopState): void {
  try {
    mkdirSync(dirname(stateFile), { recursive: true });
    writeFileSync(stateFile, JSON.stringify(state, null, 2));
  } catch (e) {
    emit("State", `Failed to save state: ${e}`);
  }
}

function loadProjectState(projectDir: string): "RUNNING" | "STOPPED" | "DRAINING" {
  const stateFile = join(projectDir, ".claude/loop-state");
  try {
    if (existsSync(stateFile)) {
      const content = readFileSync(stateFile, "utf-8").trim().toUpperCase();
      if (content === "STOPPED" || content === "DRAINING" || content === "RUNNING") {
        return content as "RUNNING" | "STOPPED" | "DRAINING";
      }
    }
  } catch {
    // Ignore errors
  }
  return "RUNNING";
}

function saveProjectState(projectDir: string, state: "RUNNING" | "STOPPED" | "DRAINING"): void {
  const stateFile = join(projectDir, ".claude/loop-state");
  try {
    mkdirSync(dirname(stateFile), { recursive: true });
    writeFileSync(stateFile, state);
  } catch {
    // Ignore errors
  }
}

function loadConfig(projectDir: string | null): LoopConfig {
  let config = { ...DEFAULT_CONFIG };

  // Global config
  try {
    if (existsSync(CONFIG_FILE)) {
      const data = JSON.parse(readFileSync(CONFIG_FILE, "utf-8"));
      config = { ...config, ...data };
    }
  } catch {
    // Ignore errors
  }

  // Environment overrides
  if (process.env.LOOP_MIN_HOURS) config.min_hours = parseFloat(process.env.LOOP_MIN_HOURS);
  if (process.env.LOOP_MAX_HOURS) config.max_hours = parseFloat(process.env.LOOP_MAX_HOURS);
  if (process.env.LOOP_MIN_ITERATIONS) config.min_iterations = parseInt(process.env.LOOP_MIN_ITERATIONS);
  if (process.env.LOOP_MAX_ITERATIONS) config.max_iterations = parseInt(process.env.LOOP_MAX_ITERATIONS);

  // Project config
  if (projectDir) {
    const projectConfig = join(projectDir, ".claude/loop-config.json");
    try {
      if (existsSync(projectConfig)) {
        const data = JSON.parse(readFileSync(projectConfig, "utf-8"));
        config = { ...config, ...data };
      }
    } catch {
      // Ignore errors
    }
  }

  return config;
}

function loadGuidance(projectDir: string): Guidance {
  const configFile = join(projectDir, ".claude/ru-config.json");
  try {
    if (existsSync(configFile)) {
      const data = JSON.parse(readFileSync(configFile, "utf-8"));
      return data.guidance || { forbidden: [], encouraged: [] };
    }
  } catch (e) {
    emit("Config", `Failed to load ru-config.json: ${e}`);
  }
  return { forbidden: [], encouraged: [] };
}

function getRuntimeHours(state: LoopState): number {
  return state.accumulated_runtime_seconds / 3600;
}

function getWallClockHours(sessionId: string, projectDir: string): number {
  // Try to get wall clock from started_at
  const startFile = join(projectDir, ".claude/loop-start-timestamp");
  try {
    if (existsSync(startFile)) {
      const startTs = parseInt(readFileSync(startFile, "utf-8").trim());
      const now = Math.floor(Date.now() / 1000);
      return (now - startTs) / 3600;
    }
  } catch {
    // Ignore
  }
  return 0;
}

function updateRuntime(state: LoopState, now: number, gapThreshold: number = 300): void {
  const lastTs = state.last_hook_timestamp || 0;
  if (lastTs > 0) {
    const gap = now - lastTs;
    // Only count time if gap is less than threshold (CLI was active)
    if (gap < gapThreshold) {
      state.accumulated_runtime_seconds += gap;
    }
  }
  state.last_hook_timestamp = now;
}

function detectLoop(currentOutput: string, recentOutputs: string[]): boolean {
  if (!currentOutput || recentOutputs.length < 2) return false;

  // Simple similarity check - if 99% similar to any recent output
  for (const recent of recentOutputs.slice(-3)) {
    const similarity = stringSimilarity(currentOutput, recent);
    if (similarity > 0.99) return true;
  }
  return false;
}

function stringSimilarity(a: string, b: string): number {
  if (a === b) return 1;
  if (a.length === 0 || b.length === 0) return 0;

  // Simple character-based similarity
  const longer = a.length > b.length ? a : b;
  const shorter = a.length > b.length ? b : a;

  let matches = 0;
  for (let i = 0; i < shorter.length; i++) {
    if (shorter[i] === longer[i]) matches++;
  }
  return matches / longer.length;
}

// --- Template Rendering (calls Python until migrated) ---

function renderTemplate(
  taskComplete: boolean,
  iteration: number,
  guidance: Guidance,
  projectDir: string,
  adapterName: string,
): string {
  // Call Python template_loader until migrated
  const hooksDir = dirname(new URL(import.meta.url).pathname);
  const pythonScript = `
import sys
sys.path.insert(0, '${hooksDir}')
from template_loader import get_loader
from ralph_evolution import get_learned_patterns, get_disabled_checks, get_prioritized_checks

loader = get_loader()
ralph_context = {
    "iteration": ${iteration},
    "guidance": ${JSON.stringify(guidance)},
    "project_dir": "${projectDir}",
    "accumulated_patterns": list(get_learned_patterns().keys()),
    "disabled_checks": get_disabled_checks(),
    "effective_checks": get_prioritized_checks(),
    "feature_ideas": [],
    "web_insights": [],
    "missing_tools": [],
    "quality_gate": [],
    "web_queries": [],
}
prompt = loader.render_unified(
    task_complete=${taskComplete ? "True" : "False"},
    ralph_context=ralph_context,
    adapter_name="${adapterName}",
    metrics_history=[],
    opportunities=[],
)
print(prompt)
`;

  try {
    const result = spawnSync("python3", ["-c", pythonScript], {
      encoding: "utf-8",
      timeout: 10000,
      cwd: hooksDir,
    });
    if (result.status === 0) {
      return result.stdout.trim();
    }
    emit("Template", `Python render failed: ${result.stderr}`);
  } catch (e) {
    emit("Template", `Template render error: ${e}`);
  }

  // Fallback minimal template
  return `**Ralph — ${taskComplete ? "EXPLORATION" : "IMPLEMENTATION"}** | Iteration ${iteration}

Execute tasks from the Task system. Use TaskList to find available work.`;
}

// --- Task Completion Check (calls Python until migrated) ---

function checkTaskComplete(planFile: string | null): { complete: boolean; reason: string; confidence: number } {
  if (!planFile) return { complete: false, reason: "", confidence: 0 };

  const hooksDir = dirname(new URL(import.meta.url).pathname);
  const pythonScript = `
import sys
sys.path.insert(0, '${hooksDir}')
from completion import check_task_complete_ralph
complete, reason, confidence = check_task_complete_ralph("${planFile}")
import json
print(json.dumps({"complete": complete, "reason": reason, "confidence": confidence}))
`;

  try {
    const result = spawnSync("python3", ["-c", pythonScript], {
      encoding: "utf-8",
      timeout: 10000,
      cwd: hooksDir,
    });
    if (result.status === 0) {
      return JSON.parse(result.stdout.trim());
    }
  } catch {
    // Ignore
  }
  return { complete: false, reason: "", confidence: 0 };
}

// --- File Discovery (calls Python until migrated) ---

function discoverTargetFile(
  transcriptPath: string | undefined,
  projectDir: string
): { file: string | null; method: string; candidates: string[] } {
  const hooksDir = dirname(new URL(import.meta.url).pathname);
  const pythonScript = `
import sys
sys.path.insert(0, '${hooksDir}')
from discovery import discover_target_file
import json
file, method, candidates = discover_target_file(${transcriptPath ? `"${transcriptPath}"` : "None"}, "${projectDir}")
print(json.dumps({"file": file, "method": method, "candidates": candidates}))
`;

  try {
    const result = spawnSync("python3", ["-c", pythonScript], {
      encoding: "utf-8",
      timeout: 10000,
      cwd: hooksDir,
    });
    if (result.status === 0) {
      return JSON.parse(result.stdout.trim());
    }
  } catch {
    // Ignore
  }
  return { file: null, method: "", candidates: [] };
}

// --- Main ---

async function main(): Promise<void> {
  resetTimer();

  // Read hook input from stdin
  let hookInput: HookInput = {};
  try {
    let inputText = "";
    for await (const chunk of Bun.stdin.stream()) {
      inputText += new TextDecoder().decode(chunk);
    }
    if (inputText.trim()) {
      hookInput = JSON.parse(inputText);
    }
  } catch {
    // Empty or invalid input
  }

  const sessionId = hookInput.session_id || "unknown";
  const transcriptPath = hookInput.transcript_path;
  const projectDir = process.env.CLAUDE_PROJECT_DIR || "";

  emit("State", `Session: ${sessionId}, project: ${projectDir.split("/").pop()}`);

  // --- Early Exit Checks ---

  // Global stop signal
  const globalStop = join(homedir(), ".claude/ralph-global-stop.json");
  if (existsSync(globalStop)) {
    try {
      const globalData = JSON.parse(readFileSync(globalStop, "utf-8"));
      if (globalData.state === "stopped") {
        const tsStr = globalData.timestamp || "";
        let isFresh = true;
        if (tsStr) {
          try {
            const signalTime = new Date(tsStr).getTime();
            const ageSeconds = (Date.now() - signalTime) / 1000;
            isFresh = ageSeconds < 300;
            if (!isFresh) {
              // Stale - clean up
              try { require("fs").unlinkSync(globalStop); } catch {}
              emit("Global stop", `Cleaned up stale signal (${ageSeconds.toFixed(0)}s old)`);
            }
          } catch {
            isFresh = true;
          }
        }
        if (isFresh) {
          if (projectDir) saveProjectState(projectDir, "STOPPED");
          hardStop("Loop stopped via global stop signal");
          return;
        }
      }
    } catch {
      // Ignore
    }
  }

  // Check state machine
  if (projectDir) {
    const currentState = loadProjectState(projectDir);
    if (currentState === "STOPPED") {
      allowStop("Loop state is STOPPED");
      return;
    }
    if (currentState === "DRAINING") {
      saveProjectState(projectDir, "STOPPED");
      const killSwitch = join(projectDir, ".claude/STOP_LOOP");
      try { require("fs").unlinkSync(killSwitch); } catch {}
      hardStop("Loop stopped via state transition (DRAINING → STOPPED)");
      return;
    }
  }

  // Kill switch
  if (projectDir) {
    const killSwitch = join(projectDir, ".claude/STOP_LOOP");
    if (existsSync(killSwitch)) {
      try { require("fs").unlinkSync(killSwitch); } catch {}
      saveProjectState(projectDir, "STOPPED");
      hardStop("Loop stopped via kill switch (.claude/STOP_LOOP)");
      return;
    }
  }

  // --- Load State ---
  const stateFile = buildStateFilePath(STATE_DIR, sessionId, projectDir);
  const defaultState: LoopState = {
    iteration: 0,
    project_path: "",
    started_at: "",
    recent_outputs: [],
    plan_file: null,
    discovered_file: null,
    discovery_method: "",
    candidate_files: [],
    completion_signals: [],
    last_completion_confidence: 0,
    opportunities_discovered: [],
    validation_round: 0,
    validation_iteration: 0,
    validation_findings: {},
    validation_score: 0,
    validation_exhausted: false,
    previous_finding_count: 0,
    agent_results: [],
    adapter_name: "",
    adapter_convergence: null,
    accumulated_runtime_seconds: 0,
    last_hook_timestamp: 0,
  };

  const state = loadState(stateFile, defaultState);
  emit("State", `Loaded session state: iteration ${state.iteration}, runtime ${state.accumulated_runtime_seconds.toFixed(0)}s`);

  // Persist project path
  if (!state.project_path && projectDir) {
    state.project_path = projectDir;
  }

  // Set started_at on first iteration
  if (!state.started_at) {
    state.started_at = new Date().toISOString();
  }

  // --- Load Config ---
  const config = loadConfig(projectDir);

  // --- File Discovery ---
  let planFile = state.discovered_file;
  let discoveryMethod = state.discovery_method;
  let candidateFiles = state.candidate_files;
  const noFocus = config.no_focus || false;

  if (noFocus) {
    planFile = null;
    discoveryMethod = "no_focus";
    candidateFiles = [];
  } else if (config.target_file) {
    planFile = config.target_file;
    discoveryMethod = "explicit (-f flag)";
  } else if (!planFile) {
    const discovery = discoverTargetFile(transcriptPath, projectDir);
    planFile = discovery.file;
    discoveryMethod = discovery.method;
    candidateFiles = discovery.candidates;
  }

  state.discovered_file = planFile;
  state.discovery_method = discoveryMethod;
  state.candidate_files = candidateFiles;
  state.plan_file = planFile;

  if (planFile) {
    emit("Discovery", `Found ${planFile} via ${discoveryMethod}`);
  } else if (noFocus) {
    emit("Discovery", "No-focus mode active (autonomous exploration)");
  } else {
    emit("Discovery", `No target file found (${candidateFiles.length} candidates)`);
  }

  // --- Runtime Tracking ---
  const now = Date.now() / 1000;
  updateRuntime(state, now, 300);
  const runtimeHours = getRuntimeHours(state);
  const wallHours = getWallClockHours(sessionId, projectDir);

  const iteration = state.iteration + 1;

  // --- Completion Checks ---
  if (runtimeHours >= config.max_hours) {
    allowStop(`Maximum runtime (${config.max_hours}h) reached`);
    return;
  }

  if (iteration >= config.max_iterations) {
    allowStop(`Maximum iterations (${config.max_iterations}) reached`);
    return;
  }

  // Check task completion
  const { complete: taskComplete, reason: completionReason, confidence: completionConfidence } = checkTaskComplete(planFile);
  state.last_completion_confidence = completionConfidence;
  if (taskComplete) {
    state.completion_signals.push(completionReason);
  }

  // --- Load Guidance ---
  const guidance = projectDir ? loadGuidance(projectDir) : { forbidden: [], encouraged: [] };

  // Issue #18 fix: Trust guidance without timestamp
  if (guidance.forbidden.length || guidance.encouraged.length) {
    emit("Config", `Guidance merged: ${guidance.forbidden.length} forbidden, ${guidance.encouraged.length} encouraged`);
  } else {
    emit("Config", "No guidance configured (using defaults)");
  }

  // --- Build Continuation Prompt ---
  const effectiveTaskComplete = taskComplete || state.force_exploration || noFocus;

  const timeToMax = Math.max(0, config.max_hours - runtimeHours);
  const itersToMax = Math.max(0, config.max_iterations - iteration);
  const remainingHours = Math.max(0, config.min_hours - runtimeHours);
  const remainingIters = Math.max(0, config.min_iterations - iteration);

  let warning = "";
  if (timeToMax < TIME_WARNING_THRESHOLD_HOURS || itersToMax < ITERATIONS_WARNING_THRESHOLD) {
    warning = " | **ENDING SOON**";
  }

  const mode = effectiveTaskComplete ? "EXPLORATION" : "IMPLEMENTATION";
  const header = `**Ralph — ${mode}** | Iteration ${iteration}/${config.max_iterations} | Runtime: ${runtimeHours.toFixed(1)}h/${config.max_hours}h | Wall: ${wallHours.toFixed(1)}h | ${remainingHours.toFixed(1)}h / ${remainingIters} iters to min${warning}`;

  let focusSuffix = "";
  if (planFile && !noFocus) {
    focusSuffix = discoveryMethod
      ? `\n\n**Focus file** (via ${discoveryMethod}): ${planFile}`
      : `\n\n**Focus file**: ${planFile}`;
  }

  // Render template
  const templatePrompt = renderTemplate(
    effectiveTaskComplete,
    iteration,
    guidance,
    projectDir,
    state.adapter_name,
  );

  const reason = `${header}${focusSuffix}\n\n${templatePrompt}`;

  // --- Update State ---
  state.iteration = iteration;
  saveState(stateFile, state);

  continueSession(reason);
}

main().catch((err) => {
  console.error(`[ralph] Fatal error: ${err}`);
  // On error, allow stop to prevent infinite loop
  console.log(JSON.stringify({}));
});
