#!/usr/bin/env bun
/**
 * Session Blind Spots — Diverse-perspective consensus analysis of Claude Code sessions.
 *
 * Key design principles:
 * 1. ADAPTIVE extraction: preserve max signal within MiniMax's ~951K char context ceiling
 * 2. DIVERSE perspectives: 50 distinct reviewer lenses (not copies of same prompt)
 * 3. Session chain tracing: recursive parents + sibling discovery for max lookback
 * 4. Budget-aware inclusion: drop oldest ancestors first, not middle-trim everything
 * 5. Consensus distillation: N diverse reviews → one ranked synthesis
 *
 * Usage:
 *   bun run session-blind-spots.ts <session-id-or-path> [--dry] [--verbose] [--shots N] [--no-chain]
 *
 * MiniMax API key: ~/.claude/.secrets/ccterrybot-telegram (MINIMAX_API_KEY=...)
 */

import { readFileSync, readdirSync, statSync, existsSync } from "fs";
import { homedir } from "os";
import { join, resolve } from "path";

// ── Config ─────────────────────────────────────────────────────────────────────

const MINIMAX_API_URL = "https://api.minimax.io/anthropic/v1/messages";
const MINIMAX_MODEL = "MiniMax-M2.5-highspeed";
const MAX_OUTPUT_TOKENS = 16384;
const DISTILL_MAX_OUTPUT_TOKENS = 16384;

// MiniMax M2.5 empirical context ceiling: ~951K content chars (260K tokens)
// Official docs claim 204,800 tokens but 260K works in practice.
// Budget: 260K total - 16K output - 0.5K system/framing = ~243K tokens ≈ 890K chars
const MAX_STRUCTURED_LOG_CHARS = 890_000;

// Default: all 50 perspectives (MiniMax is cheap and fast enough)
const DEFAULT_SHOTS = 50;

// ── API Key ────────────────────────────────────────────────────────────────────

function getApiKey(): string {
  const secretsPath = join(homedir(), ".claude/.secrets/ccterrybot-telegram");
  if (!existsSync(secretsPath)) {
    throw new Error(`Secrets file not found: ${secretsPath}`);
  }
  const content = readFileSync(secretsPath, "utf-8");
  for (const line of content.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.startsWith("MINIMAX_API_KEY=")) {
      return trimmed.slice("MINIMAX_API_KEY=".length).replace(/^["']|["']$/g, "");
    }
  }
  throw new Error("MINIMAX_API_KEY not found in secrets file");
}

// ── Session Resolution ─────────────────────────────────────────────────────────

function resolveSessionPath(input: string): string {
  if (input.endsWith(".jsonl") || input.includes("/")) {
    const resolved = resolve(input);
    if (existsSync(resolved)) return resolved;
    const expanded = input.replace(/^~/, homedir());
    if (existsSync(expanded)) return expanded;
    throw new Error(`Session file not found: ${input}`);
  }

  const projectsDir = join(homedir(), ".claude/projects");
  if (!existsSync(projectsDir)) {
    throw new Error(`Projects directory not found: ${projectsDir}`);
  }

  const uuid = input.trim();
  const matches: { path: string; mtime: number }[] = [];

  for (const projectDir of readdirSync(projectsDir)) {
    const fullDir = join(projectsDir, projectDir);
    try {
      if (!statSync(fullDir).isDirectory()) continue;
    } catch {
      continue;
    }

    const candidate = join(fullDir, `${uuid}.jsonl`);
    if (existsSync(candidate)) {
      matches.push({ path: candidate, mtime: statSync(candidate).mtimeMs });
    }
  }

  if (matches.length === 0) {
    throw new Error(`No session JSONL found for UUID: ${uuid}`);
  }

  matches.sort((a, b) => b.mtime - a.mtime);
  return matches[0].path;
}

function findSessionByUuid(uuid: string): string | null {
  const projectsDir = join(homedir(), ".claude/projects");
  if (!existsSync(projectsDir)) return null;

  for (const projectDir of readdirSync(projectsDir)) {
    const fullDir = join(projectsDir, projectDir);
    try {
      if (!statSync(fullDir).isDirectory()) continue;
    } catch {
      continue;
    }
    const candidate = join(fullDir, `${uuid}.jsonl`);
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

// ── Session Chain Tracing ──────────────────────────────────────────────────────
//
// Maximizes historical lookback within the MiniMax budget:
//   1. Recursive parent tracing — follows parentSessionId and continuation
//      references up to MAX_CHAIN_DEPTH levels deep (grandparent, great-grandparent…)
//   2. Same-project sibling discovery — finds sessions in the same project dir
//      modified within SIBLING_WINDOW_HOURS of the primary session
//   3. Budget-aware assembly — sessions ordered chronologically (oldest first) for
//      the MiniMax payload. When total exceeds budget, oldest ancestors are dropped
//      first (not middle-trimmed), preserving the most recent context.

const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g;
const MAX_CHAIN_DEPTH = 10;
const SIBLING_WINDOW_HOURS = 24;

/** Extract parent/continuation UUIDs from a session JSONL.
 *
 * Scans the FULL file because context compaction inserts "This session is
 * being continued" markers deep in the JSONL (e.g. line 1310+), not just
 * the first few lines.
 *
 * CRITICAL: Only searches user-role message TEXT blocks for continuation
 * markers — never raw JSON lines. Raw line matching causes self-referential
 * poisoning when the session contains tool calls that write/read code with
 * continuation marker strings and arbitrary UUIDs as file paths.
 */
function extractParentUuids(path: string, ownUuid: string): Set<string> {
  const raw = readFileSync(path, "utf-8");
  const uuids = new Set<string>();

  // Check parentSessionId in first JSON line
  const firstNewline = raw.indexOf("\n");
  const firstLine = firstNewline > 0 ? raw.slice(0, firstNewline) : raw;
  try {
    const firstObj = JSON.parse(firstLine);
    if (firstObj.parentSessionId && firstObj.parentSessionId !== ownUuid) {
      uuids.add(firstObj.parentSessionId);
    }
  } catch { /* ignore */ }

  const CONTINUATION_MARKERS = [
    "continued from",
    "summary below",
    "prior session",
    "previous conversation",
    "This session is being continued",
  ];

  // Parse each line as JSON, then check ONLY user message text for markers.
  // This prevents false positives from code/tool I/O that incidentally
  // contains marker strings and unrelated UUIDs.
  let pos = 0;
  while (pos < raw.length) {
    const nextNewline = raw.indexOf("\n", pos);
    const lineEnd = nextNewline === -1 ? raw.length : nextNewline;
    const line = raw.slice(pos, lineEnd);
    pos = lineEnd + 1;

    // Quick pre-filter: skip lines that can't possibly contain markers
    let hasMarker = false;
    for (const marker of CONTINUATION_MARKERS) {
      if (line.includes(marker)) {
        hasMarker = true;
        break;
      }
    }
    if (!hasMarker) continue;

    // Parse JSON and extract only user text blocks
    let obj: any;
    try {
      obj = JSON.parse(line);
    } catch { continue; }

    const msg = obj.message;
    if (!msg || msg.role !== "user") continue;

    // Extract text from content (string or text blocks only — not tool_use/tool_result)
    const content = msg.content;
    let textParts: string[] = [];
    if (typeof content === "string") {
      textParts.push(content);
    } else if (Array.isArray(content)) {
      for (const block of content) {
        if (block?.type === "text" && typeof block.text === "string") {
          textParts.push(block.text);
        }
      }
    }

    for (const text of textParts) {
      let textHasMarker = false;
      for (const marker of CONTINUATION_MARKERS) {
        if (text.includes(marker)) {
          textHasMarker = true;
          break;
        }
      }
      if (textHasMarker) {
        const matches = text.match(UUID_RE) || [];
        for (const uuid of matches) {
          if (uuid !== ownUuid) uuids.add(uuid);
        }
      }
    }
  }

  return uuids;
}

/** Recursively trace parent chain up to MAX_CHAIN_DEPTH. Returns paths oldest-first. */
function traceParentsRecursive(
  startPath: string,
  visited: Set<string>,
  verbose: boolean,
  depth = 0,
): string[] {
  if (depth >= MAX_CHAIN_DEPTH) return [];

  const ownUuid = startPath.match(/([0-9a-f-]{36})\.jsonl$/)?.[1] || "";
  const parentUuids = extractParentUuids(startPath, ownUuid);
  const ancestors: string[] = [];

  for (const uuid of parentUuids) {
    const parentPath = findSessionByUuid(uuid);
    if (!parentPath || visited.has(parentPath)) continue;

    visited.add(parentPath);

    // Recurse deeper first (grandparent before parent)
    const olderAncestors = traceParentsRecursive(parentPath, visited, verbose, depth + 1);
    ancestors.push(...olderAncestors);
    ancestors.push(parentPath);

    if (verbose) {
      const size = statSync(parentPath).size;
      console.error(`[chain] Found ancestor (depth ${depth + 1}): ${uuid.slice(0, 8)}… (${(size / 1048576).toFixed(1)}MB)`);
    }
  }

  return ancestors;
}

/** Find sibling sessions in the same project dir within a time window.
 *  Only searches the immediate project dir (not subagent subdirectories).
 *  Subagent sessions (agent-* files in subagents/) are excluded — they
 *  contain tool-level execution, not user-facing conversation.
 */
function findSiblings(
  primaryPath: string,
  visited: Set<string>,
  verbose: boolean,
): string[] {
  // Use the project dir (not a subagents/ subdir)
  const rawDir = primaryPath.replace(/\/[^/]+$/, "");
  const dir = rawDir.replace(/\/subagents$/, "").replace(/\/[0-9a-f-]{36}\/subagents$/, "").replace(/\/[0-9a-f-]{36}$/, "");
  const primaryMtime = statSync(primaryPath).mtimeMs;
  const windowMs = SIBLING_WINDOW_HOURS * 3600 * 1000;

  const siblings: { path: string; mtime: number }[] = [];

  try {
    for (const file of readdirSync(dir)) {
      if (!file.endsWith(".jsonl")) continue;
      // Skip agent subagent files that ended up in the project dir
      if (file.startsWith("agent-")) continue;
      const fullPath = join(dir, file);
      if (visited.has(fullPath)) continue;

      try {
        const st = statSync(fullPath);
        if (!st.isFile()) continue;
        const timeDiff = Math.abs(st.mtimeMs - primaryMtime);
        if (timeDiff <= windowMs && st.size > 1000) { // Skip tiny sessions (<1KB)
          siblings.push({ path: fullPath, mtime: st.mtimeMs });
        }
      } catch { continue; }
    }
  } catch { return []; }

  // Sort by mtime ascending (oldest first) for chronological order
  siblings.sort((a, b) => a.mtime - b.mtime);

  if (verbose && siblings.length > 0) {
    console.error(`[chain] Found ${siblings.length} sibling(s) within ${SIBLING_WINDOW_HOURS}h window`);
  }

  return siblings.map((s) => s.path);
}

function traceSessionChain(primaryPath: string, verbose: boolean): string[] {
  const visited = new Set<string>([primaryPath]);

  // 1. Recursive parent chain (oldest first)
  const ancestors = traceParentsRecursive(primaryPath, visited, verbose);

  // 2. Sibling discovery (same project dir, within time window)
  const siblings = findSiblings(primaryPath, visited, verbose);
  for (const s of siblings) visited.add(s);

  // 3. Assemble chronologically: ancestors → siblings → primary
  // Siblings that are older than primary go before it; newer ones after (but primary is last for review focus)
  const primaryMtime = statSync(primaryPath).mtimeMs;
  const olderSiblings = siblings.filter((s) => statSync(s).mtimeMs < primaryMtime);
  const newerSiblings = siblings.filter((s) => statSync(s).mtimeMs >= primaryMtime);

  const chain = [...ancestors, ...olderSiblings, primaryPath, ...newerSiblings];

  if (verbose && chain.length > 1) {
    console.error(`[chain] Full chain: ${chain.length} sessions (${ancestors.length} ancestor(s), ${siblings.length} sibling(s))`);
  }

  return chain;
}

// ── JSONL Parsing — Adaptive Fidelity ──────────────────────────────────────────

interface RawTurn {
  n: number;
  session: string;
  role: "user" | "assistant";
  userText: string;      // full user/assistant text (pre-truncation)
  toolCalls: string[];   // tool name + full input
  toolResults: string[]; // full tool result text
  files: string[];
  errors: string[];
  timestamp?: string;
}

const STRIP_PATTERNS = [
  /<system-reminder>[\s\S]*?<\/system-reminder>/g,
  /<available-deferred-tools>[\s\S]*?<\/available-deferred-tools>/g,
  /data:[^;]+;base64,[A-Za-z0-9+/=]{100,}/g,
  // Claude Code injects plan file contents as system reminders — already caught above
  // Hook output noise
  /<user-prompt-submit-hook>[\s\S]*?<\/user-prompt-submit-hook>/g,
];

const SKILL_LISTING_RE = /^- [\w-]+:[\w-]+: .+$/gm;

function stripNoise(text: string): string {
  let result = text;
  for (const pat of STRIP_PATTERNS) {
    result = result.replace(pat, "");
  }

  const skillMatches = result.match(SKILL_LISTING_RE);
  if (skillMatches && skillMatches.length > 15) {
    result = result.replace(SKILL_LISTING_RE, "");
    result = result.replace(/\n{3,}/g, "\n\n");
  }

  return result.trim();
}

function truncate(text: string, maxLen: number): string {
  if (text.length <= maxLen) return text;
  const half = Math.floor(maxLen / 2) - 20;
  return text.slice(0, half) + `\n[…${text.length - maxLen} chars cut…]\n` + text.slice(-half);
}

function extractFilePath(input: unknown): string | null {
  if (!input || typeof input !== "object") return null;
  const obj = input as Record<string, unknown>;
  if (typeof obj.file_path === "string") {
    const fp = obj.file_path;
    if (fp.startsWith("/") || fp.startsWith("~/")) return fp;
  }
  return null;
}

function extractError(toolName: string, resultText: string): string | null {
  if (!resultText) return null;
  const lower = resultText.toLowerCase();
  if (lower.includes("error") || lower.includes("failed") || lower.includes("exception") ||
      lower.includes("permission denied") || lower.includes("not found") ||
      lower.includes("rejected") || lower.includes("denied")) {
    return `${toolName}: ${resultText.slice(0, 300)}`;
  }
  return null;
}

function extractRawContent(content: unknown): {
  text: string;
  toolCalls: string[];
  toolResults: string[];
  files: string[];
  errors: string[];
} {
  const toolCalls: string[] = [];
  const toolResults: string[] = [];
  const files: string[] = [];
  const errors: string[] = [];
  let text = "";

  if (typeof content === "string") {
    text = content;
  } else if (Array.isArray(content)) {
    for (const block of content) {
      if (!block || typeof block !== "object") continue;

      if (block.type === "text" && block.text) {
        text += block.text + "\n";
      } else if (block.type === "tool_use") {
        const inputStr = typeof block.input === "string"
          ? block.input
          : JSON.stringify(block.input);
        toolCalls.push(`${block.name}(${inputStr})`);

        const fp = extractFilePath(block.input);
        if (fp) files.push(fp);
      } else if (block.type === "tool_result") {
        const resultText = typeof block.content === "string"
          ? block.content
          : Array.isArray(block.content)
            ? block.content.map((b: any) => b.text || "").join("")
            : JSON.stringify(block.content);

        toolResults.push(resultText);

        if (block.is_error || (resultText && resultText.toLowerCase().includes("error"))) {
          const err = extractError(block.tool_use_id || "tool", resultText);
          if (err) errors.push(err);
        }
      } else if (block.type === "image") {
        // Note the image without including the base64 data
        const media = block.source?.media_type || "unknown";
        const dataLen = block.source?.data?.length || 0;
        text += `[image: ${media}, ${Math.round(dataLen / 1024)}KB]\n`;
      }
    }
  }

  return { text: stripNoise(text), toolCalls, toolResults, files, errors };
}

function parseSessionRaw(path: string, sessionLabel: string, startTurn: number, verbose: boolean): RawTurn[] {
  const raw = readFileSync(path, "utf-8");
  const turns: RawTurn[] = [];
  let skipped = 0;
  let turnNum = startTurn;
  let lineCount = 0;

  // Line-by-line iteration without creating a massive string array
  // (a 96MB JSONL split into 28K strings wastes memory on array overhead)
  let pos = 0;
  while (pos < raw.length) {
    const nextNewline = raw.indexOf("\n", pos);
    const lineEnd = nextNewline === -1 ? raw.length : nextNewline;
    const line = raw.slice(pos, lineEnd);
    pos = lineEnd + 1;

    if (!line) continue;
    lineCount++;
    let obj: any;
    try {
      obj = JSON.parse(line);
    } catch {
      skipped++;
      continue;
    }

    if (obj.type === "file-history-snapshot" || obj.type === "progress" || obj.type === "summary") {
      skipped++;
      continue;
    }

    // Extract queued user messages — these capture user intent that may not
    // appear in a regular user turn (typed while assistant was busy)
    if (obj.type === "queue-operation" && obj.operation === "enqueue" && obj.content) {
      const content = typeof obj.content === "string" ? obj.content : "";
      // Skip task-notification noise
      if (content && !content.startsWith("<task-notification>") && content.length > 10) {
        turnNum++;
        turns.push({
          n: turnNum,
          session: sessionLabel,
          role: "user",
          userText: `[queued message] ${stripNoise(content)}`,
          toolCalls: [],
          toolResults: [],
          files: [],
          errors: [],
          timestamp: obj.timestamp,
        });
      } else {
        skipped++;
      }
      continue;
    }

    // last-prompt captures the final user prompt before session ended
    if (obj.type === "last-prompt" && obj.lastPrompt) {
      turnNum++;
      turns.push({
        n: turnNum,
        session: sessionLabel,
        role: "user",
        userText: `[last prompt before session end] ${obj.lastPrompt}`,
        toolCalls: [],
        toolResults: [],
        files: [],
        errors: [],
      });
      continue;
    }

    const msg = obj.message;
    if (!msg) {
      skipped++;
      continue;
    }

    const role = msg.role as string;
    if (role !== "user" && role !== "assistant") {
      skipped++;
      continue;
    }

    const { text, toolCalls, toolResults, files, errors } = extractRawContent(msg.content);

    if (!text && toolCalls.length === 0) {
      skipped++;
      continue;
    }

    turnNum++;

    turns.push({
      n: turnNum,
      session: sessionLabel,
      role: role as RawTurn["role"],
      userText: text,
      toolCalls,
      toolResults,
      files: files.length > 0 ? [...new Set(files)] : [],
      errors,
      timestamp: obj.timestamp,
    });
  }

  if (verbose) {
    console.error(`[parse] ${sessionLabel}: ${lineCount} lines → ${turns.length} turns (${skipped} skipped)`);
  }

  return turns;
}

// ── Adaptive Structured Log Builder ────────────────────────────────────────────
//
// Strategy: First build at full fidelity. If over budget, progressively reduce:
//   Level 0: Full fidelity (no truncation)
//   Level 1: Truncate tool results to 2000 chars
//   Level 2: Truncate tool results to 600 chars, tool inputs to 300 chars
//   Level 3: Truncate tool results to 200 chars, tool inputs to 150 chars, assistant text to 2000 chars
//   Level 4: Trim middle of log (beginning + end preserved)

function buildTurnText(turn: RawTurn, toolInputLimit: number, toolResultLimit: number, textLimit: number): string {
  const label = turn.role === "user" ? "USER" : "CLAUDE";
  const ts = turn.timestamp ? ` ${turn.timestamp.slice(11, 19)}` : "";
  let section = `[T${turn.n}] ${label}${ts}\n`;

  const text = turn.role === "user"
    ? truncate(turn.userText, Math.max(textLimit, 4000)) // User text: never below 4000
    : truncate(turn.userText, textLimit);

  if (text) section += text + "\n";

  if (turn.toolCalls.length > 0) {
    const truncatedCalls = turn.toolCalls.map((tc) => {
      const parenIdx = tc.indexOf("(");
      if (parenIdx === -1) return tc;
      const name = tc.slice(0, parenIdx);
      const input = tc.slice(parenIdx + 1, -1);
      return `${name}(${truncate(input, toolInputLimit)})`;
    });
    section += `→ Tools: ${truncatedCalls.join(" | ")}\n`;
  }

  if (turn.toolResults.length > 0 && toolResultLimit > 0) {
    for (const result of turn.toolResults) {
      const truncResult = truncate(result, toolResultLimit);
      if (truncResult.length > 10) {
        section += `→ Result: ${truncResult}\n`;
      }
    }
  }

  if (turn.files.length > 0) {
    section += `→ Files: ${turn.files.join(", ")}\n`;
  }
  if (turn.errors.length > 0) {
    section += `→ ERRORS: ${turn.errors.join(" | ")}\n`;
  }

  return section;
}

function buildStructuredLogAdaptive(turns: RawTurn[], budget: number, verbose: boolean): string {
  // Fidelity levels: [toolInputLimit, toolResultLimit, assistantTextLimit]
  const levels: [number, number, number][] = [
    [Infinity, Infinity, Infinity],  // L0: full fidelity
    [2000, 2000, Infinity],          // L1: trim tool I/O
    [600,  800,  Infinity],          // L2: more aggressive tool trim
    [300,  400,  3000],              // L3: also trim assistant text
    [150,  200,  1500],              // L4: aggressive all-around
  ];

  let bestLog = "";
  let usedLevel = 0;

  for (let li = 0; li < levels.length; li++) {
    const [tiLimit, trLimit, txtLimit] = levels[li];
    const sections: string[] = [];
    let currentSession = "";

    for (const turn of turns) {
      if (turn.session !== currentSession) {
        currentSession = turn.session;
        sections.push(`\n══ SESSION: ${currentSession} ══\n`);
      }
      sections.push(buildTurnText(turn, tiLimit, trLimit, txtLimit));
    }

    const log = sections.join("\n");
    bestLog = log;
    usedLevel = li;

    if (log.length <= budget) {
      if (verbose) {
        console.error(`[adaptive] Level ${li} fits: ${log.length} chars (budget: ${budget})`);
      }
      return log;
    }

    if (verbose) {
      console.error(`[adaptive] Level ${li} too large: ${log.length} chars (budget: ${budget}), trying next level`);
    }
  }

  // Still over budget after all levels — trim middle
  if (verbose) {
    console.error(`[adaptive] All levels exceeded budget, trimming middle`);
  }

  const keepEach = Math.floor(budget * 0.45);
  const beginning = bestLog.slice(0, keepEach);
  const end = bestLog.slice(-keepEach);
  const droppedChars = bestLog.length - keepEach * 2;
  return beginning +
    `\n\n=== [${droppedChars} chars / ~${Math.round(droppedChars / 4)} tokens of middle trimmed — beginning and end preserved] ===\n\n` +
    end;
}

// ── Summary stats ──────────────────────────────────────────────────────────────

function buildSessionSummary(turns: RawTurn[], chainInfo: string): string {
  const allFiles = new Set<string>();
  const allErrors: string[] = [];
  const toolCounts = new Map<string, number>();
  let userTurns = 0;
  let assistantTurns = 0;

  for (const turn of turns) {
    if (turn.role === "user") userTurns++;
    else assistantTurns++;

    for (const f of turn.files) allFiles.add(f);
    allErrors.push(...turn.errors);

    for (const tc of turn.toolCalls) {
      const name = tc.split("(")[0];
      toolCounts.set(name, (toolCounts.get(name) || 0) + 1);
    }
  }

  const topTools = [...toolCounts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([name, count]) => `${name}(${count})`)
    .join(", ");

  const lines = [
    `SESSION METADATA`,
    chainInfo,
    `Total turns: ${turns.length} (${userTurns} user, ${assistantTurns} claude)`,
    `Files touched: ${allFiles.size}`,
    `Top tools: ${topTools}`,
    `Errors encountered: ${allErrors.length}`,
  ];

  if (allFiles.size > 0 && allFiles.size <= 60) {
    lines.push(`\nFILES MODIFIED:`);
    for (const f of allFiles) {
      lines.push(`  ${f}`);
    }
  }

  if (allErrors.length > 0) {
    lines.push(`\nERRORS DURING SESSION:`);
    for (const e of allErrors.slice(0, 25)) {
      lines.push(`  ⚠ ${e.slice(0, 200)}`);
    }
  }

  return lines.join("\n");
}

// ── 10 Diverse Reviewer Perspectives ───────────────────────────────────────────

const REVIEW_PREAMBLE = `IMPORTANT: You are NOT Claude Code. You are a SEPARATE reviewer. Do NOT continue the session. Do NOT reproduce the transcript. Do NOT write code. Your ONLY job is to write a structured review.

For each finding, use this exact format:

### [CRITICAL|WARNING|INFO] Short title
- Category: <your perspective name>
- Turn: T<number>
- Evidence: "<quote from transcript>"
- Risk: <what goes wrong>
- Fix: <specific command or file edit for Claude Code to execute>

Rules:
- Cite specific turn numbers with evidence from the transcript
- Every Fix must be a concrete command or file path + change
- Do NOT report things completed successfully. Only report problems.
- Do NOT invent problems — evidence must exist in the transcript
- Maximum 8 findings from your perspective. Quality over quantity.

End with:
## Top 3 Actions
1-3: most impactful fixes with exact commands`;

const PERSPECTIVES: { name: string; prompt: string }[] = [
  {
    name: "Completeness Tracker",
    prompt: `You are a COMPLETENESS TRACKER reviewing a Claude Code session transcript.

Your SOLE focus: Did the user get what they asked for?

Look for:
- User requests that were acknowledged but never fulfilled
- Tasks started then abandoned mid-way when context shifted
- User questions that were answered with "I'll do that" but never done
- Partial implementations where the user asked for A, B, C but only A and B were delivered
- TODOs, FIXMEs, or "we'll handle that later" that were never revisited
- Items the user explicitly asked to commit/release/push that weren't

Ignore everything else — security, architecture, style. ONLY completeness.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Security Auditor",
    prompt: `You are a SECURITY AUDITOR reviewing a Claude Code session transcript.

Your SOLE focus: Security vulnerabilities introduced or exposed during this session.

Look for:
- Credentials, API keys, tokens written to files or logged to stdout
- Secrets in environment variables that get committed to git
- File permissions that are too open (world-readable secrets)
- Command injection vectors in shell commands or hook scripts
- Path traversal possibilities in user-controlled input
- HTTP endpoints without authentication or input validation
- Hardcoded passwords or tokens in source code
- .env files or secrets files not in .gitignore

Ignore everything else — completeness, architecture, style. ONLY security.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Verification Engineer",
    prompt: `You are a VERIFICATION ENGINEER reviewing a Claude Code session transcript.

Your SOLE focus: What was changed but never verified to actually work?

Look for:
- Code written or modified but never executed, tested, or run
- Configuration files changed but the service never restarted/reloaded to pick up changes
- Shell scripts created but never tested with actual input
- API integrations coded but never called with real credentials
- File paths referenced that were never checked to exist
- Assumptions about system state ("this file should have X") never validated with a read/ls
- Regex patterns written but never tested against sample input
- "It should work" statements without evidence it was tried

Ignore everything else. ONLY verification gaps.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Side-Effect Hunter",
    prompt: `You are a SIDE-EFFECT HUNTER reviewing a Claude Code session transcript.

Your SOLE focus: Unintended consequences of changes made in this session.

Look for:
- Files created or modified that may break other systems not visible in this session
- Processes started but never stopped (orphaned daemons, backgrounded jobs)
- Temporary files created in /tmp that were never cleaned up
- Lock files created but never released
- Services reloaded in wrong order causing dependency issues
- Git state left dirty (uncommitted files, unstaged changes)
- Package installations that modified lockfiles as side effect
- Environment variables exported that affect other tools
- Symlinks created that may conflict with existing paths

Ignore everything else. ONLY side effects.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Architecture Critic",
    prompt: `You are an ARCHITECTURE CRITIC reviewing a Claude Code session transcript.

Your SOLE focus: Structural and design problems in the changes made.

Look for:
- Over-engineering: abstractions, configs, or layers added for a simple task
- Under-engineering: quick hacks that will be hard to maintain or extend
- Wrong level of abstraction: solving at app level what should be infra, or vice versa
- Coupling: changes that tightly bind components that should be independent
- Single point of failure: critical paths with no redundancy or fallback
- Reinventing the wheel: custom code for something a library/tool already handles
- Config sprawl: settings scattered across multiple files instead of one SSoT
- Wrong tool for the job: bash where TypeScript was needed, or vice versa

Ignore security, completeness, testing. ONLY architecture and design.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Error Flow Analyst",
    prompt: `You are an ERROR FLOW ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: How errors are handled (or not) in code written during this session.

Look for:
- try/catch blocks that swallow errors silently (catch with empty body or just console.log)
- Error conditions checked but with wrong fallback behavior
- Missing error handling on network calls, file I/O, or subprocess execution
- Race conditions between concurrent operations (parallel promises, file locks)
- Timeout values that are too short or missing entirely
- Retry logic without backoff or with unlimited retries
- Error messages that hide the root cause (generic "something went wrong")
- Exit codes that don't distinguish between different failure modes

Ignore completeness, security, architecture. ONLY error handling.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "User Intent Decoder",
    prompt: `You are a USER INTENT DECODER reviewing a Claude Code session transcript.

Your SOLE focus: Was the user's TRUE intent understood and served?

Look for:
- User said X but Claude Code interpreted it as Y (misunderstanding)
- User's implicit expectations that were not addressed (they said "fix it" but meant "fix it AND test it")
- User frustration signals ("no", "that's not what I meant", "again", repeating themselves)
- Cases where Claude Code did the letter of the request but missed the spirit
- User asked a question but got a different answer than what they needed
- User preferences stated earlier in session that were forgotten/ignored later
- User explicitly corrected Claude Code but the correction wasn't fully applied

Ignore technical correctness. ONLY user intent alignment.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Regression Hunter",
    prompt: `You are a REGRESSION HUNTER reviewing a Claude Code session transcript.

Your SOLE focus: Did any fix or change break something that was working before?

Look for:
- Bug fixes that introduced new bugs (fix one thing, break another)
- Refactoring that changed behavior, not just structure
- File deletions that might break imports/requires in other files
- Config changes that affect other services sharing the same config
- Hook/script modifications that change behavior for ALL users, not just the current task
- Version bumps that might break downstream consumers
- Path changes where old paths are still referenced elsewhere
- API contract changes (function signatures, return types) without updating callers

Ignore everything else. ONLY regressions.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Process Auditor",
    prompt: `You are a PROCESS AUDITOR reviewing a Claude Code session transcript.

Your SOLE focus: Development workflow and process issues.

Look for:
- Changes made to wrong branch or wrong copy (marketplace vs source repo)
- Commits that should have been made but weren't
- Release steps skipped or done out of order
- Pre-commit hooks bypassed (--no-verify)
- Changes to production without going through staging/testing
- Multiple small commits that should have been batched
- Force pushes or destructive git operations without good reason
- Files committed that shouldn't be (secrets, build artifacts, lockfiles)
- Missing changelog entries for user-facing changes

Ignore code quality, architecture, security. ONLY process and workflow.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Documentation Staleness Detector",
    prompt: `You are a DOCUMENTATION STALENESS DETECTOR reviewing a Claude Code session transcript.

Your SOLE focus: Documentation that became stale or misleading due to changes in this session.

Look for:
- Code changed but comments/docstrings not updated to match
- README/CLAUDE.md files that reference old paths, old behavior, or removed features
- SKILL.md files with outdated usage examples or configuration references
- Inline comments that describe logic that was changed or removed
- Architecture docs that no longer match the actual architecture
- Variable/function names that no longer reflect their purpose after refactoring
- Example commands in docs that won't work after the changes made
- Version numbers or dates in docs that are now wrong

Ignore code bugs, security, process. ONLY documentation accuracy.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Concurrency & Timing Analyst",
    prompt: `You are a CONCURRENCY & TIMING ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: Race conditions, timing bugs, and parallel execution issues.

Look for:
- Multiple processes reading/writing the same file without locking
- Promise.all or parallel operations where order matters but isn't guaranteed
- Lock files acquired but never released on error paths
- Timeouts that are too short for real-world conditions (network latency, cold starts)
- File operations assumed to be atomic when they aren't (read-modify-write without lock)
- Services started/stopped in wrong order creating timing windows
- Heartbeat/health checks with intervals that miss transient failures
- Signal handlers (SIGTERM, SIGINT) that don't clean up concurrent state

Ignore everything else. ONLY concurrency and timing.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Dependency Chain Auditor",
    prompt: `You are a DEPENDENCY CHAIN AUDITOR reviewing a Claude Code session transcript.

Your SOLE focus: Dependency issues — missing, broken, circular, or phantom dependencies.

Look for:
- Imports/requires of modules that don't exist or weren't installed
- Package.json/pyproject.toml dependencies added but lockfile not updated
- Circular dependencies between files or modules
- Dependency on specific version that wasn't pinned
- Using a global tool (bun, npm, uv) that may not be available on other machines
- Shared libraries modified without checking all consumers
- Runtime dependencies confused with dev dependencies
- Missing peer dependencies that will fail at runtime

Ignore everything else. ONLY dependency correctness.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Performance & Resource Analyst",
    prompt: `You are a PERFORMANCE & RESOURCE ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: Performance problems and resource waste in code written this session.

Look for:
- Reading entire large files into memory when streaming would work
- O(n²) or worse algorithms in data processing paths
- Unbounded growth (arrays/maps/logs that grow without limit)
- Spawning subprocesses in loops without concurrency limits
- Large JSON.stringify/parse operations on data that could be streamed
- Disk I/O in hot paths (writing to disk on every request)
- Missing pagination or limits on database/API queries
- Memory leaks from unclosed file handles, sockets, or event listeners

Ignore correctness, security, documentation. ONLY performance and resources.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Cross-System Impact Analyst",
    prompt: `You are a CROSS-SYSTEM IMPACT ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: How changes in this session affect OTHER systems not visible in the transcript.

Look for:
- Config changes that are shared by multiple services (mise.toml, .env, plist files)
- Hook modifications that fire for ALL projects, not just the current one
- Shell profile changes (.zshenv, .zshrc) that affect every terminal session
- PATH modifications or symlink changes that affect other tools
- launchd service changes that affect system-wide behavior
- Changes to shared libraries used by multiple projects
- API contract changes that other clients depend on
- Git hooks or CI/CD changes that affect all developers on the repo

Ignore in-session completeness. ONLY cross-system ripple effects.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Idempotency Checker",
    prompt: `You are an IDEMPOTENCY CHECKER reviewing a Claude Code session transcript.

Your SOLE focus: Operations that are NOT safe to run twice, or that have non-deterministic outcomes.

Look for:
- Scripts that append to files without checking if content already exists (duplicate entries)
- Database/API operations without upsert logic (double-creates, duplicate records)
- File creation that fails if file already exists (no idempotent overwrite)
- PlistBuddy/sed commands that apply the same transformation repeatedly
- Git operations that assume clean state (commit when nothing to commit, push when up to date)
- Setup scripts that fail on second run (mkdir without -p, ln without -f)
- Service restarts that don't check if already running in desired state
- Cron/timer jobs that can overlap with previous still-running instances

Ignore security, architecture, documentation. ONLY idempotency and repeatability.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Configuration Drift Detector",
    prompt: `You are a CONFIGURATION DRIFT DETECTOR reviewing a Claude Code session transcript.

Your SOLE focus: Configuration that has diverged from its single source of truth (SSoT).

Look for:
- Same setting defined in multiple places with different values
- Environment variables set in .zshenv AND mise.toml AND plist files (which one wins?)
- File paths hardcoded in scripts that should reference a config variable
- Magic numbers or hardcoded values that should be in config
- Config files modified directly when they should be generated from a template
- Chezmoi-tracked files modified locally without updating the source template
- Settings in comments ("was 5, now 10") that no longer match actual values
- Default values in code that don't match defaults documented in config reference

Ignore code logic, security, testing. ONLY configuration consistency.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Rollback Feasibility Analyst",
    prompt: `You are a ROLLBACK FEASIBILITY ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: Can the changes in this session be safely undone if something goes wrong?

Look for:
- Destructive operations (rm -rf, git reset --hard, DROP TABLE) with no backup
- Data migrations that are not reversible (lossy transformations)
- Files deleted that weren't committed to git first
- Service config changes that can't be easily reverted (plist modifications)
- Database schema changes without down migration
- Published releases that can't be unpublished (npm, PyPI, crates.io)
- State file modifications where the old state is lost
- Symlink chains where the original target was deleted

Ignore code quality, documentation, process. ONLY rollback safety.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Platform Portability Reviewer",
    prompt: `You are a PLATFORM PORTABILITY REVIEWER reviewing a Claude Code session transcript.

Your SOLE focus: Platform-specific assumptions that will break on other systems.

Look for:
- Hardcoded /Users/username paths that only work on one machine
- macOS-specific commands (PlistBuddy, launchctl, say, afplay) used without platform checks
- Shell syntax that works in zsh but not bash (or vice versa)
- Assumptions about tool availability (bun, mise, fd, rg) without fallback
- File system case sensitivity assumptions (macOS is case-insensitive by default)
- Signal handling differences between macOS and Linux (SIGSTOP behavior)
- Homebrew paths (/opt/homebrew, /usr/local) hardcoded without detection
- Apple Silicon (arm64) specific code without x86 fallback

Ignore correctness, security, completeness. ONLY portability.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Technical Debt Accountant",
    prompt: `You are a TECHNICAL DEBT ACCOUNTANT reviewing a Claude Code session transcript.

Your SOLE focus: Workarounds and shortcuts that will accumulate as technical debt.

Look for:
- "Quick fix" or "temporary" solutions that have no follow-up plan
- Copy-pasted code that should be a shared function/module
- Workarounds for upstream bugs that should be reported/fixed properly
- Feature flags or conditional logic for "old" vs "new" behavior that will never be cleaned up
- TODO/FIXME/HACK comments added without corresponding issue tracking
- Shell scripts doing what should be proper TypeScript/Python code
- Hardcoded timeouts/retries as substitutes for proper error recovery
- Manual steps documented in comments that should be automated

Ignore immediate bugs, security, documentation. ONLY future debt accumulation.

${REVIEW_PREAMBLE}`,
  },
  // ── Perspectives 20-50 ──────────────────────────────────────────────────────
  {
    name: "Data Integrity Analyst",
    prompt: `You are a DATA INTEGRITY ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: Data loss, corruption, truncation, or encoding issues introduced in this session.

Look for:
- File reads/writes without encoding specification (defaulting to wrong encoding)
- String truncation that loses meaningful data (substring, slice without bounds check)
- JSON parsing without validation that could silently drop fields
- Data transformations that lose precision (float rounding, date timezone stripping)
- Writes to files that overwrite existing data instead of appending/merging
- Missing null/undefined checks before accessing nested data
- Streaming data processed with fixed-size buffers that can overflow
- Character encoding mismatches (UTF-8 vs Latin-1, BOM handling)

Ignore architecture, performance, process. ONLY data integrity.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "API Contract Reviewer",
    prompt: `You are an API CONTRACT REVIEWER reviewing a Claude Code session transcript.

Your SOLE focus: API contracts — breaking changes, missing versioning, undocumented behavior.

Look for:
- Function signatures changed without updating all callers
- Return types modified (was string, now object) without migration
- New required parameters added to existing functions
- HTTP endpoints changed without backward compatibility
- Event/hook schemas modified without version bump
- Removed fields from JSON responses that consumers depend on
- Changed error codes or error response shapes
- Implicit contracts (ordering, timing) broken by refactoring

Ignore security, completeness, performance. ONLY API contract stability.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Observability Gap Detector",
    prompt: `You are an OBSERVABILITY GAP DETECTOR reviewing a Claude Code session transcript.

Your SOLE focus: Missing logging, metrics, alerting, or tracing in code written this session.

Look for:
- Error paths with no logging (silent failures that can't be debugged)
- New features without any telemetry or audit trail
- catch blocks that don't log the error before handling it
- Background processes with no health check or heartbeat
- API calls without request/response logging for debugging
- State transitions with no observable output (how do you know it happened?)
- Missing structured logging fields (timestamp, component, request_id)
- Console.log used where structured logging (NDJSON, audit-log) should be

Ignore correctness, architecture, testing. ONLY observability and debuggability.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Failure Mode Analyst",
    prompt: `You are a FAILURE MODE ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: What happens when things go wrong? Is graceful degradation implemented?

Look for:
- Network calls without timeout or retry that will hang forever on failure
- Services that crash entirely instead of degrading (one bad request kills all)
- Missing circuit breakers for external dependencies
- No fallback behavior when a dependency is unavailable
- Error cascades where one failure causes multiple downstream failures
- Critical paths with no redundancy (single API, single server, single file)
- Recovery logic that itself can fail (retry loop that exhausts resources)
- Missing health checks that would detect failures before users do

Ignore code style, documentation, completeness. ONLY failure resilience.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Input Validation Sentinel",
    prompt: `You are an INPUT VALIDATION SENTINEL reviewing a Claude Code session transcript.

Your SOLE focus: Missing or inadequate input validation at system boundaries.

Look for:
- User input passed directly to shell commands (command injection)
- File paths from user input not sanitized (path traversal)
- Numeric inputs not checked for NaN, Infinity, negative, or overflow
- String inputs not checked for length, format, or dangerous characters
- JSON/YAML parsed without schema validation
- Environment variables used without checking they exist or are valid
- CLI arguments parsed but edge cases not handled (empty, missing, malformed)
- URLs constructed from user input without encoding

Ignore architecture, performance, documentation. ONLY input validation.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Resource Cleanup Inspector",
    prompt: `You are a RESOURCE CLEANUP INSPECTOR reviewing a Claude Code session transcript.

Your SOLE focus: Resources acquired but never properly released or cleaned up.

Look for:
- File handles opened but never closed (especially in error paths)
- Database connections or HTTP clients created but never disposed
- Event listeners added but never removed (memory leak)
- setInterval/setTimeout created without corresponding clear
- Temporary directories created but never removed after use
- Child processes spawned but never killed on parent exit
- Subscriptions (WebSocket, SSE, pub/sub) never unsubscribed
- Mutex/semaphore acquired but not released in finally blocks

Ignore correctness, documentation, process. ONLY resource lifecycle.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Naming & Semantics Reviewer",
    prompt: `You are a NAMING & SEMANTICS REVIEWER reviewing a Claude Code session transcript.

Your SOLE focus: Misleading names, inconsistent terminology, and semantic confusion.

Look for:
- Variables/functions whose names no longer match their behavior after changes
- Inconsistent naming across the same concept (userId vs user_id vs uid)
- Boolean variables with confusing polarity (isDisabled vs isEnabled)
- Generic names that obscure purpose (data, result, tmp, handler, process)
- File names that don't reflect their content after refactoring
- Constants named in a way that contradicts their value
- Same word used for different concepts in different parts of the code
- Abbreviations that are ambiguous (res = response or result?)

Ignore bugs, security, performance. ONLY naming clarity and consistency.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Permission & Scope Auditor",
    prompt: `You are a PERMISSION & SCOPE AUDITOR reviewing a Claude Code session transcript.

Your SOLE focus: Over-permissioned access and unnecessarily broad scopes.

Look for:
- API tokens with full admin scope when read-only would suffice
- File permissions set to 777 or 666 when 600/700 would work
- Service accounts with access to all vaults/projects when one is needed
- OAuth scopes requested that are broader than required
- sudo/root usage when user-level permissions would work
- Environment variables exposing secrets to all child processes unnecessarily
- File operations on directories when specific files should be targeted
- GitHub PATs with repo/admin scope when just read is needed

Ignore code logic, architecture, testing. ONLY principle of least privilege.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Caching Correctness Analyst",
    prompt: `You are a CACHING CORRECTNESS ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: Caching bugs — stale data, invalidation failures, key collisions.

Look for:
- Cached values that are never invalidated when the source changes
- Cache keys that don't include all relevant parameters (cache pollution)
- In-memory caches that grow without bounds or TTL
- File-based caches that survive across deployments when they shouldn't
- Memoization of functions with side effects (cached result hides mutation)
- Stale reads where code uses cached data but the source was updated mid-session
- DNS or HTTP caching interfering with real-time behavior
- Prompt caching assumptions that may not hold across API providers

Ignore security, completeness, documentation. ONLY caching correctness.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Test Coverage Gap Finder",
    prompt: `You are a TEST COVERAGE GAP FINDER reviewing a Claude Code session transcript.

Your SOLE focus: Code paths that have no test and edge cases left untested.

Look for:
- New functions/features written without corresponding test cases
- Error branches (catch, else, default) never exercised by tests
- Boundary conditions not tested (empty arrays, zero, max values, unicode)
- Configuration combinations that were never validated together
- Integration points (API calls, DB queries) tested with mocks but not real services
- Shell scripts written with no test harness at all
- Regex patterns without test cases for edge inputs
- Changes to existing code without updating or adding regression tests

Ignore architecture, security, documentation. ONLY test coverage gaps.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Logging Hygiene Auditor",
    prompt: `You are a LOGGING HYGIENE AUDITOR reviewing a Claude Code session transcript.

Your SOLE focus: Logging quality — PII leaks, missing context, log level misuse.

Look for:
- Sensitive data logged (API keys, passwords, tokens, email addresses, IP addresses)
- Log messages at wrong level (errors logged as info, debug noise in production)
- Missing correlation IDs that make it impossible to trace requests across services
- Log messages without enough context to diagnose the issue (just "error" or "failed")
- Console.log/console.error used in production code instead of structured logging
- Log files that grow unbounded without rotation
- Timestamps missing or in inconsistent formats across components
- Stack traces logged for expected/handled errors (noise)

Ignore code logic, architecture, performance. ONLY logging quality.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Encoding & Serialization Analyst",
    prompt: `You are an ENCODING & SERIALIZATION ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: Encoding mismatches, serialization bugs, and data format issues.

Look for:
- UTF-8 vs ASCII assumptions when handling international text or emoji
- JSON.stringify on objects with circular references (will throw)
- Date serialization without timezone (ISO 8601 vs locale-dependent)
- Binary data treated as string (base64 encoding missing or double-encoded)
- YAML parsing without safe loader (code execution risk)
- JSONL files with inconsistent line endings (\\r\\n vs \\n)
- URL encoding/decoding mismatches (double-encoding, missing encoding)
- Shell argument escaping failures (spaces in paths, special characters)

Ignore security policy, architecture, completeness. ONLY encoding and serialization.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Rate Limit & Quota Tracker",
    prompt: `You are a RATE LIMIT & QUOTA TRACKER reviewing a Claude Code session transcript.

Your SOLE focus: API rate limits, quota exhaustion, and backpressure issues.

Look for:
- API calls in loops without rate limiting or throttling
- Missing retry-after header handling on 429 responses
- Parallel requests that exceed provider concurrency limits
- No backoff strategy when hitting rate limits (just retry immediately)
- Batch operations that could exceed API payload size limits
- Token/credit consumption not tracked or estimated before expensive operations
- Missing pagination leading to unbounded result sets
- Queue depth or concurrency limits not configured for background workers

Ignore code style, documentation, testing. ONLY rate limits and quotas.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Authentication Flow Auditor",
    prompt: `You are an AUTHENTICATION FLOW AUDITOR reviewing a Claude Code session transcript.

Your SOLE focus: Authentication and token lifecycle issues.

Look for:
- Tokens stored in plaintext files without restrictive permissions
- Missing token refresh logic (tokens will expire and break silently)
- OAuth flows without PKCE or state parameter validation
- Hardcoded bearer tokens that should be rotated
- Session/token expiry not checked before making API calls
- Multiple auth mechanisms configured that might conflict
- Fallback auth paths that bypass the primary auth check
- Token scope escalation (using a narrow token to get a broader one)

Ignore code architecture, performance, completeness. ONLY authentication lifecycle.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Network Resilience Analyst",
    prompt: `You are a NETWORK RESILIENCE ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: Network failure handling — timeouts, DNS, connection pooling, retries.

Look for:
- HTTP calls without explicit timeout (will hang indefinitely)
- No retry logic for transient network errors (ECONNRESET, ETIMEDOUT)
- DNS resolution assumed to always succeed (no fallback)
- Connection pools not configured (creating new connection per request)
- Missing keep-alive or connection reuse for repeated API calls
- WebSocket/SSE connections without reconnect-on-drop logic
- fetch() calls without AbortSignal for cancellation
- Hardcoded hostnames/IPs instead of DNS-resolvable names

Ignore security policy, code style, documentation. ONLY network resilience.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Git History Hygiene Auditor",
    prompt: `You are a GIT HISTORY HYGIENE AUDITOR reviewing a Claude Code session transcript.

Your SOLE focus: Git history quality and safety.

Look for:
- Large binary files committed to git (should use LFS or .gitignore)
- Secrets accidentally committed (even if later removed — still in history)
- Merge conflicts resolved by deleting one side entirely
- Commit messages that don't describe the actual change
- Commits mixing unrelated changes (fix + feature + refactor in one commit)
- Amended commits that destroyed previous work
- Force pushes to shared branches
- .gitignore patterns that are too broad (ignoring needed files) or too narrow (missing build artifacts)

Ignore code quality, architecture, testing. ONLY git history cleanliness.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Boundary Condition Analyst",
    prompt: `You are a BOUNDARY CONDITION ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: Edge cases at boundaries — empty inputs, zero, max values, off-by-one.

Look for:
- Array operations without empty array check (.length === 0, [0] on empty)
- String operations without empty/null string check
- Numeric operations at boundaries (division by zero, integer overflow, NaN propagation)
- Off-by-one errors in loops, slicing, indexing (< vs <=, .slice(0, n) vs .slice(0, n+1))
- File operations on empty files or missing files without guard
- Map/Set operations on empty collections
- Date arithmetic crossing DST boundaries or month-end
- Regex on empty strings or strings with only whitespace

Ignore architecture, security, documentation. ONLY boundary conditions.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Async Lifecycle Manager",
    prompt: `You are an ASYNC LIFECYCLE MANAGER reviewing a Claude Code session transcript.

Your SOLE focus: Async operations — unresolved promises, dangling callbacks, event loop issues.

Look for:
- Promises created but never awaited (fire-and-forget with no error handling)
- async functions called without await (missing return value, unhandled rejection)
- Promise.all used where Promise.allSettled should be (one failure kills all)
- Event emitters with listeners that throw but no error handler registered
- Callbacks nested deeply instead of using async/await (callback hell)
- process.exit() called while async operations are still pending
- Unhandled promise rejections that will crash in newer Node.js
- Top-level await in modules that blocks import

Ignore security, documentation, naming. ONLY async operation lifecycle.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Environment Assumptions Detector",
    prompt: `You are an ENVIRONMENT ASSUMPTIONS DETECTOR reviewing a Claude Code session transcript.

Your SOLE focus: Implicit assumptions about the runtime environment.

Look for:
- Code that assumes specific environment variables exist without defaults
- Scripts that assume specific tools are installed (bun, mise, fd, jq, rg)
- Paths that assume a specific OS user or home directory structure
- Code that assumes network access (will fail in air-gapped environments)
- Scripts that assume specific shell (zsh features in bash, bash features in sh)
- Assumed directory structure (node_modules exists, .git exists, tmp writable)
- Hardware assumptions (arm64, GPU available, minimum memory)
- Locale/timezone assumptions (C locale, UTC, US date format)

Ignore code quality, security, architecture. ONLY environment assumptions.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Cost & Billing Analyst",
    prompt: `You are a COST & BILLING ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: Unnecessary costs — expensive API calls, wasted compute, unbounded spending.

Look for:
- LLM API calls with unnecessarily large context (sending more than needed)
- Expensive model used where a cheaper one would suffice (Opus where Haiku works)
- API calls in loops without caching (paying for the same data repeatedly)
- Cloud resources provisioned but never cleaned up (running services, storage)
- Unbounded parallel API calls that could spike bills
- Missing cost estimation before expensive operations
- Full file reads when only headers/metadata were needed
- Premium API tiers used when free tiers have sufficient quota

Ignore code correctness, security, documentation. ONLY cost efficiency.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Semantic Versioning Compliance",
    prompt: `You are a SEMANTIC VERSIONING COMPLIANCE reviewer reviewing a Claude Code session transcript.

Your SOLE focus: Version management — breaking changes, changelogs, compatibility.

Look for:
- Breaking API changes released as patch or minor version (should be major)
- New features released as patch (should be minor)
- Missing CHANGELOG entries for user-visible changes
- Version strings hardcoded in multiple files that could drift
- Pre-release versions (alpha, beta, rc) mixed with stable releases
- Package published without version bump (overwriting previous)
- Dependency version constraints too loose (^, ~, *) or too strict (pinned exact)
- Git tags not matching package.json/pyproject.toml version

Ignore code quality, architecture, testing. ONLY versioning correctness.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "State Machine Validator",
    prompt: `You are a STATE MACHINE VALIDATOR reviewing a Claude Code session transcript.

Your SOLE focus: Invalid state transitions, missing states, and state corruption.

Look for:
- Status fields that can reach impossible combinations (running + stopped)
- State transitions without validation (jumping from A to C, skipping B)
- Missing terminal states (process starts but has no defined end condition)
- State persisted to disk but not atomically (partial writes on crash)
- Concurrent state updates without synchronization (last-write-wins corruption)
- Boolean flags used instead of proper state enums (is_running, is_paused, is_errored)
- Recovery from error state not implemented (stuck in error forever)
- State spread across multiple files/variables that can become inconsistent

Ignore security, documentation, performance. ONLY state management correctness.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Deprecation Tracker",
    prompt: `You are a DEPRECATION TRACKER reviewing a Claude Code session transcript.

Your SOLE focus: Usage of deprecated APIs, libraries, patterns, or features.

Look for:
- Node.js/Bun APIs marked as deprecated in recent versions
- npm/pip packages that are unmaintained or have known deprecation notices
- Deprecated CLI flags or command syntax used in shell scripts
- Deprecated language features (var instead of let/const, old class syntax)
- GitHub API endpoints marked for removal
- Deprecated HTTP headers or protocols (HTTP/1.0, non-secure cookies)
- Deprecated macOS APIs or system calls
- Libraries with "archived" or "moved to" GitHub status

Ignore code style, architecture, completeness. ONLY deprecated usage.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Filesystem Safety Reviewer",
    prompt: `You are a FILESYSTEM SAFETY REVIEWER reviewing a Claude Code session transcript.

Your SOLE focus: Dangerous filesystem operations and disk space issues.

Look for:
- rm -rf with variables that could expand to / or ~ (catastrophic deletion)
- Writing to disk without checking available space
- Symlink following that could escape intended directory (symlink attacks)
- File operations on paths with spaces or special characters not properly quoted
- Temp files created in predictable locations (symlink race attacks)
- Log files or data files that grow without rotation or size limit
- Hard links that create unexpected data sharing between files
- Atomic file writes not used for critical data (write to temp then rename)

Ignore code logic, naming, documentation. ONLY filesystem safety.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Migration Safety Reviewer",
    prompt: `You are a MIGRATION SAFETY REVIEWER reviewing a Claude Code session transcript.

Your SOLE focus: Data and schema migration risks.

Look for:
- Schema changes without migration scripts (manual ALTER TABLE)
- Data format changes without backward compatibility period
- File format changes that break existing consumers
- Config file format changes without migration tooling
- Database column renames/removes without checking all queries
- API version bumps without deprecation period for old version
- Environment variable renames without updating all consumers
- Path structure changes without redirect/symlink for old paths

Ignore performance, architecture, completeness. ONLY migration safety.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Internationalization Blind Spot",
    prompt: `You are an INTERNATIONALIZATION BLIND SPOT reviewer reviewing a Claude Code session transcript.

Your SOLE focus: Locale, language, and character set assumptions that will fail internationally.

Look for:
- Hardcoded English strings in user-facing output
- Date formatting that assumes US format (MM/DD/YYYY)
- Currency or number formatting without locale awareness
- String sorting that doesn't handle non-ASCII characters (CJK, accented)
- Hardcoded character width assumptions (CJK characters are double-width)
- Regex patterns that only match ASCII ([a-zA-Z] misses accented characters)
- Text length calculations using .length instead of grapheme count (emoji, combining marks)
- Locale-dependent APIs used without specifying locale explicitly

Ignore security, performance, architecture. ONLY internationalization.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "License & Compliance Auditor",
    prompt: `You are a LICENSE & COMPLIANCE AUDITOR reviewing a Claude Code session transcript.

Your SOLE focus: License compatibility and compliance issues.

Look for:
- GPL-licensed dependencies added to non-GPL projects (viral licensing)
- Code copied from Stack Overflow or GitHub without checking license
- Third-party APIs used without agreeing to their terms of service
- Missing LICENSE file in new packages or repositories
- Copyleft code mixed with proprietary code
- Data scraped from websites without checking robots.txt or ToS
- API keys shared or committed that violate provider terms
- Open source libraries used beyond their license scope (AGPL network clause)

Ignore code quality, testing, performance. ONLY licensing and compliance.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Signal & Shutdown Handler",
    prompt: `You are a SIGNAL & SHUTDOWN HANDLER reviewer reviewing a Claude Code session transcript.

Your SOLE focus: Process lifecycle — startup, shutdown, signals, and cleanup on exit.

Look for:
- Missing SIGTERM/SIGINT handlers in long-running processes
- Cleanup logic not in finally blocks (skipped on unexpected exit)
- Graceful shutdown not implemented (connections dropped, data lost)
- PID files not cleaned up on process exit
- Child processes not killed when parent exits (zombie processes)
- Lock files not released on SIGKILL (unrecoverable without manual intervention)
- atexit/beforeExit handlers that do async work (may not complete)
- Services that don't drain in-flight requests before shutting down

Ignore code logic, security, documentation. ONLY process lifecycle safety.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Secrets Rotation Analyst",
    prompt: `You are a SECRETS ROTATION ANALYST reviewing a Claude Code session transcript.

Your SOLE focus: Secret lifecycle — rotation, expiry, scope, and revocation.

Look for:
- API keys with no expiry date or rotation schedule
- Tokens created without documenting their scope or where they're used
- Old secrets not revoked after new ones are generated
- Secrets shared across environments (dev/staging/prod using same key)
- Service account tokens with no audit trail of who created them
- Passwords or tokens stored without encryption at rest
- Secret rotation that requires manual restarts of dependent services
- Missing secret inventory (which secrets exist, where they're used, when they expire)

Ignore code architecture, testing, performance. ONLY secret lifecycle management.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "UX Consistency Reviewer",
    prompt: `You are a UX CONSISTENCY REVIEWER reviewing a Claude Code session transcript.

Your SOLE focus: User experience consistency in CLI tools, scripts, and outputs.

Look for:
- Inconsistent CLI flag naming (--dry vs --dry-run, --verbose vs -v vs --debug)
- Error messages with different formats across the same tool
- Missing --help or usage information in new scripts
- Progress indicators inconsistent (some show %, some show spinner, some nothing)
- Exit codes inconsistent (some use 0/1, some use custom codes)
- Output format inconsistent (some JSON, some plain text, some markdown)
- Color usage inconsistent (some use ANSI colors, some don't)
- Confirmation prompts for destructive actions missing or inconsistent

Ignore code internals, security, performance. ONLY user-facing consistency.

${REVIEW_PREAMBLE}`,
  },
  {
    name: "Dependency Freshness Auditor",
    prompt: `You are a DEPENDENCY FRESHNESS AUDITOR reviewing a Claude Code session transcript.

Your SOLE focus: Outdated or vulnerable dependencies.

Look for:
- Dependencies pinned to old versions when newer versions fix known bugs
- Security advisories for packages used in this session
- Major version updates available that could improve performance/features
- Packages with no releases in 2+ years (possibly abandoned)
- Transitive dependencies with known vulnerabilities
- Build tools or linters using outdated versions (missing new rules/features)
- Lockfiles that haven't been regenerated after dependency changes
- Using polyfills or workarounds for features available in current runtime

Ignore code style, architecture, completeness. ONLY dependency freshness.

${REVIEW_PREAMBLE}`,
  },
];

// ── MiniMax API ────────────────────────────────────────────────────────────────

async function callMiniMax(
  apiKey: string,
  system: string,
  userContent: string,
  maxTokens: number,
  timeoutMs: number = 180_000,
): Promise<string> {
  const res = await fetch(MINIMAX_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MINIMAX_MODEL,
      max_tokens: maxTokens,
      system,
      messages: [{ role: "user", content: userContent }],
    }),
    signal: AbortSignal.timeout(timeoutMs),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`MiniMax API ${res.status}: ${body.slice(0, 500)}`);
  }

  const result: any = await res.json();

  if (result.content && Array.isArray(result.content)) {
    return result.content.map((b: any) => b.text || "").join("");
  }

  return JSON.stringify(result, null, 2);
}

// ── Distillation Prompt ────────────────────────────────────────────────────────

const DISTILL_SYSTEM_PROMPT = `You are a senior engineering lead. You will receive reviews from multiple specialist reviewers, each analyzing the same coding session from a DIFFERENT perspective (security, completeness, verification, side-effects, architecture, error handling, user intent, regressions, process, documentation).

Your job: synthesize these diverse reviews into ONE definitive action plan by:

1. MERGING overlapping findings (same root issue seen from different angles = higher confidence)
2. REMOVING false positives (findings contradicted by other reviewers' evidence)
3. RANKING by impact: what causes the most damage if not fixed?
4. KEEPING the best evidence quotes and fix commands from across all reviews
5. NOTING the perspective diversity: "seen by Security + Verification" is more credible than one perspective alone

## Output format

For each finding:

### [CRITICAL|WARNING|INFO] Short title
- Perspectives: <which reviewers reported this, e.g. "Completeness + Verification + Process">
- Confidence: <N>/<total> perspectives flagged this
- Turn: T<number>
- Evidence: "<best evidence quote from any reviewer>"
- Risk: <concrete consequence if not fixed>
- Fix: <exact command or file edit Claude Code should execute>

Rules:
- Include findings from 2+ perspectives, OR single-perspective CRITICAL findings with strong evidence
- Maximum 12 findings, ranked by (confidence × severity)
- Every Fix must be a concrete command, file path, or code change
- If reviewers DISAGREE on a finding, note the disagreement and your judgment

End with:

## Priority Action Plan
1. <highest impact action with exact command — note which perspectives support it>
2. <second>
3. <third>
4. <fourth — if warranted>
5. <fifth — if warranted>`;

// ── Multi-Perspective Consensus ────────────────────────────────────────────────

async function diversePerspectiveConsensus(
  apiKey: string,
  sessionSummary: string,
  structuredLog: string,
  shots: number,
  verbose: boolean,
): Promise<string> {
  const userMessage = `Review this Claude Code session transcript from your assigned perspective. Output ONLY your structured review — do NOT continue the session or reproduce the transcript.

${sessionSummary}

===BEGIN TRANSCRIPT===
${structuredLog}
===END TRANSCRIPT===

Now write your review. Remember: ONLY findings from your specific perspective. Do NOT reproduce transcript content.`;

  // Select which perspectives to use (rotate through all 10 if shots > 10)
  const selectedPerspectives: typeof PERSPECTIVES[number][] = [];
  for (let i = 0; i < shots; i++) {
    selectedPerspectives.push(PERSPECTIVES[i % PERSPECTIVES.length]);
  }

  // Phase 1: Fire N parallel diverse review calls
  const perspectiveNames = selectedPerspectives.map((p) => p.name);
  console.error(`[consensus] Firing ${shots} diverse perspective calls:`);
  for (const name of perspectiveNames) {
    console.error(`  → ${name}`);
  }

  const startTime = Date.now();

  const promises = selectedPerspectives.map((perspective, i) =>
    callMiniMax(apiKey, perspective.prompt, userMessage, MAX_OUTPUT_TOKENS)
      .then((result) => {
        if (verbose) {
          const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
          console.error(`[consensus] ${perspective.name} complete (${elapsed}s)`);
        }
        return { index: i, name: perspective.name, result, error: null as string | null };
      })
      .catch((err) => {
        console.error(`[consensus] ${perspective.name} failed: ${err.message}`);
        return { index: i, name: perspective.name, result: "", error: err.message };
      })
  );

  const results = await Promise.all(promises);
  const successful = results.filter((r) => !r.error);
  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);

  console.error(`[consensus] ${successful.length}/${shots} perspectives succeeded in ${elapsed}s`);

  if (successful.length === 0) {
    throw new Error("All perspective calls failed");
  }

  if (successful.length === 1) {
    return `[Single perspective: ${successful[0].name}]\n\n${successful[0].result}`;
  }

  // Phase 2: Distill all diverse reviews into one consensus
  console.error(`[consensus] Distilling ${successful.length} diverse perspectives...`);

  const distillInput = successful
    .map((r) => `═══ ${r.name.toUpperCase()} ═══\n\n${r.result}`)
    .join("\n\n");

  const distillMessage = `Below are ${successful.length} reviews of the same Claude Code session, each from a DIFFERENT specialist perspective. Synthesize them into one definitive action plan.

${distillInput}

Now write the synthesized consensus report. Merge overlapping findings, rank by impact, note which perspectives support each finding.`;

  const consensus = await callMiniMax(
    apiKey,
    DISTILL_SYSTEM_PROMPT,
    distillMessage,
    DISTILL_MAX_OUTPUT_TOKENS,
    240_000,
  );

  return consensus;
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const flags = new Set(args.filter((a) => a.startsWith("--")));
  const positional = args.filter((a) => !a.startsWith("--"));

  const dryRun = flags.has("--dry");
  const verbose = flags.has("--verbose");
  const noChain = flags.has("--no-chain");

  let shots = DEFAULT_SHOTS;
  const shotsIdx = args.indexOf("--shots");
  if (shotsIdx !== -1 && args[shotsIdx + 1]) {
    shots = parseInt(args[shotsIdx + 1], 10);
    if (isNaN(shots) || shots < 1) shots = DEFAULT_SHOTS;
    if (shots > 50) shots = 50;
  }

  if (positional.length === 0) {
    console.error("Usage: session-blind-spots.ts <session-id-or-path> [options]");
    console.error("");
    console.error("  session-id-or-path  UUID or full .jsonl path");
    console.error("  --dry               Parse and show structured log, skip MiniMax calls");
    console.error("  --verbose           Show adaptive fidelity levels and per-shot timing");
    console.error("  --shots N           Number of diverse perspectives (default: 50, max: 50)");
    console.error("  --no-chain          Skip session chain tracing (single session only)");
    console.error("");
    console.error("Perspectives (rotated across shots):");
    for (const p of PERSPECTIVES) {
      console.error(`  ${p.name}`);
    }
    process.exit(1);
  }

  const input = positional[0];
  console.error(`[blind-spots] Resolving session: ${input}`);

  const sessionPath = resolveSessionPath(input);
  const fileSize = statSync(sessionPath).size;
  console.error(`[blind-spots] File: ${sessionPath} (${(fileSize / 1048576).toFixed(1)}MB)`);

  // Trace session chain (recursive parents + siblings)
  let sessionChain: string[];
  if (noChain) {
    sessionChain = [sessionPath];
  } else {
    sessionChain = traceSessionChain(sessionPath, verbose);
    if (sessionChain.length > 1) {
      const pMtime = statSync(sessionPath).mtimeMs;
      let ancestorCount = 0;
      let siblingCount = 0;
      for (const s of sessionChain) {
        if (s === sessionPath) continue;
        // Ancestors were traced via parent chain; siblings via time proximity in same dir
        const sMtime = statSync(s).mtimeMs;
        if (sMtime < pMtime) ancestorCount++; // older = could be ancestor or older sibling
        else siblingCount++; // newer = sibling
      }
      console.error(`[blind-spots] Session chain: ${sessionChain.length} sessions (${ancestorCount} older, ${siblingCount} newer sibling(s))`);
    }
  }

  // Parse all sessions and build labels
  const allTurns: RawTurn[] = [];
  let turnOffset = 0;
  const chainLabels: string[] = [];
  // Track per-session turn ranges for budget-aware dropping
  const sessionTurnRanges: { path: string; label: string; startIdx: number; endIdx: number }[] = [];

  for (const spath of sessionChain) {
    // Handle both UUID filenames (abc123-...) and agent filenames (agent-abc123...)
    const sid = spath.match(/([0-9a-f-]{36})\.jsonl$/)?.[1]
             || spath.match(/(agent-[0-9a-f]{12,})\.jsonl$/)?.[1]
             || spath.replace(/^.*\//, "").replace(/\.jsonl$/, "");
    let label: string;
    if (spath === sessionPath) {
      label = `${sid.slice(0, 8)}… (primary)`;
    } else {
      const sMtime = statSync(spath).mtimeMs;
      const pMtime = statSync(sessionPath).mtimeMs;
      const relation = sMtime < pMtime ? "ancestor" : "sibling";
      label = `${sid.slice(0, 8)}… (${relation})`;
    }
    chainLabels.push(label);

    const startIdx = allTurns.length;
    const turns = parseSessionRaw(spath, label, turnOffset, verbose);
    allTurns.push(...turns);
    turnOffset = allTurns.length;
    sessionTurnRanges.push({ path: spath, label, startIdx, endIdx: allTurns.length });
  }

  console.error(`[blind-spots] Total: ${allTurns.length} turns across ${sessionChain.length} session(s)`);

  // Budget-aware session inclusion: if full chain exceeds budget even at L4,
  // progressively drop non-primary sessions until it fits without middle-trim.
  //
  // Drop order: oldest sessions first, but within the same age tier, drop
  // sessions with fewer turns first (tiny/empty sessions waste budget on
  // session headers without contributing content).
  let turnsForPayload = allTurns;
  let droppedSessions = 0;

  if (sessionChain.length > 1) {
    const testLog = buildStructuredLogAdaptive(allTurns, MAX_STRUCTURED_LOG_CHARS, false);
    if (testLog.includes("middle trimmed")) {
      // Middle-trim was triggered — try dropping sessions instead
      const droppable = sessionTurnRanges
        .filter((r) => r.path !== sessionPath)
        .map((r) => ({ ...r, turnCount: r.endIdx - r.startIdx }))
        // Sort: oldest first, then fewest turns first (drop least valuable first)
        .sort((a, b) => {
          const aMtime = statSync(a.path).mtimeMs;
          const bMtime = statSync(b.path).mtimeMs;
          // Primary sort: oldest first
          if (Math.abs(aMtime - bMtime) > 3600_000) return aMtime - bMtime;
          // Secondary sort: fewest turns first (drop empty sessions before rich ones)
          return a.turnCount - b.turnCount;
        });

      for (let dropCount = 1; dropCount <= droppable.length; dropCount++) {
        const toDrop = new Set(droppable.slice(0, dropCount).flatMap((r) =>
          Array.from({ length: r.endIdx - r.startIdx }, (_, i) => r.startIdx + i)
        ));
        const reducedTurns = allTurns.filter((_, i) => !toDrop.has(i));
        const reducedLog = buildStructuredLogAdaptive(reducedTurns, MAX_STRUCTURED_LOG_CHARS, false);

        if (!reducedLog.includes("middle trimmed")) {
          turnsForPayload = reducedTurns;
          droppedSessions = dropCount;
          if (verbose) {
            const droppedLabels = droppable.slice(0, dropCount).map((r) => `${r.label} (${r.turnCount} turns)`);
            console.error(`[budget] Dropped ${dropCount} session(s) to avoid middle-trim: ${droppedLabels.join(", ")}`);
          }
          break;
        }
      }

      if (droppedSessions === 0 && verbose) {
        console.error(`[budget] Middle-trim unavoidable — primary session alone exceeds budget`);
      }
    }
  }

  const chainInfo = sessionChain.length > 1
    ? `Session chain: ${chainLabels.join(" → ")}${droppedSessions > 0 ? ` (${droppedSessions} oldest dropped for budget)` : ""}`
    : `Single session: ${chainLabels[0]}`;

  const sessionSummary = buildSessionSummary(turnsForPayload, chainInfo);
  const structuredLog = buildStructuredLogAdaptive(turnsForPayload, MAX_STRUCTURED_LOG_CHARS, verbose);
  const totalInput = sessionSummary.length + structuredLog.length;
  const estimatedTokens = Math.round(totalInput / 4);
  console.error(`[blind-spots] Payload: ${structuredLog.length} chars log + ${sessionSummary.length} chars summary (~${estimatedTokens} tokens)`);

  if (dryRun) {
    console.log(sessionSummary);
    console.log("\n---\n");
    console.log(structuredLog);
    return;
  }

  const apiKey = getApiKey();

  console.error(`[blind-spots] Diverse perspectives: ${shots} shots → distillation`);
  const analysis = await diversePerspectiveConsensus(apiKey, sessionSummary, structuredLog, shots, verbose);

  console.log("");
  console.log("=".repeat(70));
  console.log("  SESSION BLIND SPOT ANALYSIS — MiniMax 2.5 Highspeed");
  console.log(`  Session: ${input}`);
  console.log(`  Chain: ${sessionChain.length} session(s)${droppedSessions > 0 ? ` (${droppedSessions} dropped for budget)` : ""} | Turns: ${turnsForPayload.length} | Perspectives: ${shots}`);
  console.log("=".repeat(70));
  console.log("");
  console.log(analysis);
  console.log("");
  console.log("=".repeat(70));
}

main().catch((err) => {
  console.error(`[blind-spots] Fatal: ${err.message}`);
  process.exit(1);
});
