#!/usr/bin/env bun
/**
 * Session Debrief — Focused session analysis via MiniMax 2.5 highspeed.
 *
 * Three expert modes (--goal 1|2|3):
 * 1. Handoff Document      — exhaustive context extraction for the next developer/session
 * 2. Error Forensics       — complete inventory of warnings/errors Claude ignored or deferred
 * 3. Chronological Summary — dense technical timeline with key outcomes
 *
 * Key design principles:
 * 1. ADAPTIVE extraction: preserve max signal within MiniMax's ~951K char context ceiling
 * 2. TIME-BASED discovery: scans all sessions in the current project within a time window
 * 3. Session chain tracing: recursive parents + sibling discovery for max lookback
 * 4. Budget-aware chunking: Goal 1 splits by session when content exceeds budget
 *
 * Usage:
 *   bun run session-debrief.ts --goal 1 --since 48
 *   bun run session-debrief.ts --goal 2 --since 168
 *   bun run session-debrief.ts --goal 3 --since 720
 *
 * MiniMax API key: ~/.claude/.secrets/ccterrybot-telegram (MINIMAX_API_KEY=...)
 */

import { readFileSync, readdirSync, statSync, existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";

// ── Config ─────────────────────────────────────────────────────────────────────

const MINIMAX_API_URL = "https://api.minimax.io/anthropic/v1/messages";
const MINIMAX_MODEL = "MiniMax-M2.5-highspeed";
const MAX_OUTPUT_TOKENS = 16384;

// MiniMax M2.5 empirical context ceiling: ~951K content chars (260K tokens)
// Official docs claim 204,800 tokens but 260K works in practice.
// Budget: 260K total - 16K output - 0.5K system/framing = ~243K tokens ≈ 890K chars
const MAX_STRUCTURED_LOG_CHARS = 890_000;

// ── Focused Goal System Prompts ────────────────────────────────────────────────

const GOAL1_HANDOFF_SYSTEM = `You are preparing a comprehensive HANDOFF DOCUMENT for the next developer or AI assistant continuing this work — they have zero prior context.

Extract EVERYTHING of value from this session transcript so they can immediately understand and continue without asking questions.

## WHAT WAS ACCOMPLISHED
List every completed task, feature, fix, refactor, and decision — be exhaustive. Include exact file names, function names, and commands. Do not skip minor items.

## CURRENT STATE
What is working right now? What files were modified? What services, configs, or environments changed? Exact versions, flags, and values that matter.

## INCOMPLETE / BROKEN
Anything started but unfinished. Errors not fully resolved. Tests not passing. Items explicitly deferred. TODOs that remain. Be specific about what was left in what state.

## KEY DECISIONS & RATIONALE
Why were things done the specific way they were? What alternatives were rejected and why? What constraints shaped the approach? Future sessions must not undo these unknowingly.

## CRITICAL GOTCHAS & CONTEXT
Non-obvious facts. Things that caused friction or confusion. Workarounds in place. Environment specifics. Dependencies between components. Anything the next person MUST know.

## NEXT STEPS (PRIORITY ORDER)
Concrete tasks to start the next session with. What is the most important thing to do first? What is blocked on what?

Rules:
- Be EXHAUSTIVE — if in doubt, include it
- Technical precision matters: exact paths, exact commands, exact error messages
- Do NOT summarize away important details — the next person needs specifics
- If content spans multiple time periods, note when things happened for chronological orientation`;

const GOAL2_ERRORS_SYSTEM = `You are an ERROR FORENSICS ANALYST. Your SOLE job: catalog every warning, error, deprecation notice, unexpected output, failed command, and anomaly that appeared in this session transcript — especially ones that were NOT fully resolved.

For each finding, use EXACTLY this format:

### [ERROR|WARNING|DEPRECATION|ANOMALY] Brief descriptive title
- **Turn**: T<number>
- **Trigger**: <exact command, tool call, or file operation that caused this>
- **File/Path**: <file path or command involved, if any>
- **Full Text**: <complete error/warning text verbatim — do NOT truncate or paraphrase>
- **Resolution**: UNRESOLVED | PARTIAL (<what was attempted>) | RESOLVED (<how it was fixed>)
- **Claude's Response**: <did Claude acknowledge it? ignore it? say "we'll fix later"? skip it?>

Rules:
- Include EVERY instance — tool errors, bash command failures (non-zero exit), file-not-found, permission denied, type errors, lint warnings, deprecation notices, test failures, unexpected output
- Include cases where Claude explicitly said "ignore this", "we can fix that later", or simply moved on without addressing it
- Order strictly by turn number (chronological)
- Do NOT filter, curate, or judge severity — include everything
- Do NOT skip "minor" warnings — the user specifically wants to see what was missed
- Your job is a COMPLETE inventory, not a curated top-10`;

const GOAL3_SUMMARY_SYSTEM = `You are a TECHNICAL HISTORIAN creating a dense chronological timeline of this Claude Code session period.

Format: one bullet per significant event, strict chronological order by turn number.

• T<N> — <what happened> [<file or command if relevant>]

Group into phases with a ## Phase: <name> header when clear phases emerge (e.g., "## Phase: Initial Investigation", "## Phase: Implementing Feature X", "## Phase: Debugging", "## Phase: Testing & Release").

Rules:
- Start from the earliest turn, strict chronological order
- Maximum conciseness: 1-2 lines per event, but preserve all technical specifics (file names, function names, commands, values)
- Do NOT omit significant events — errors, decisions, discoveries, blockers, solutions all matter
- Mark unresolved errors with ⚠ at the start of the bullet
- For decisions: capture the choice AND rationale if stated
- Skip trivial tool calls (reading a file with no finding) — include only events that changed something, revealed something, or decided something
- Aim for maximum COVERAGE — a month of work should produce a dense timeline

End with:
## Key Outcomes
- [3-7 most important results of this entire session period — what was built, what was decided, what remains broken]`;

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

// ── Session Chain Tracing ──────────────────────────────────────────────────────

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
// Recursive parent tracing — follows parentSessionId and continuation
// references up to MAX_CHAIN_DEPTH levels deep (grandparent, great-grandparent…)

const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g;
const MAX_CHAIN_DEPTH = 10;

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

// ── Time-Based Session Discovery ──────────────────────────────────────────────

/** Convert current working directory to the Claude Code project dir path.
 *  Claude maps /a/b/c → ~/.claude/projects/-a-b-c/
 */
function cwdToProjectDir(cwdOverride?: string): string | null {
  const cwd = cwdOverride || process.cwd();
  const key = cwd.replace(/\//g, "-");
  const projectDir = join(homedir(), ".claude/projects", key);
  if (existsSync(projectDir)) return projectDir;
  return null;
}

/** Find all session JSONL files in a project dir modified within the last sinceHours. */
function discoverSessionsByTimeWindow(
  projectDir: string,
  sinceHours: number,
  verbose: boolean,
): string[] {
  const cutoffMs = Date.now() - sinceHours * 3600 * 1000;
  const sessions: { path: string; mtime: number }[] = [];

  try {
    for (const file of readdirSync(projectDir)) {
      if (!file.endsWith(".jsonl")) continue;
      if (file.startsWith("agent-")) continue;
      const fullPath = join(projectDir, file);
      try {
        const st = statSync(fullPath);
        if (!st.isFile() || st.size < 1000) continue;
        if (st.mtimeMs >= cutoffMs) {
          sessions.push({ path: fullPath, mtime: st.mtimeMs });
          if (verbose) {
            console.error(`[discover] ${file} (${new Date(st.mtimeMs).toLocaleString()})`);
          }
        }
      } catch { continue; }
    }
  } catch {
    return [];
  }

  sessions.sort((a, b) => a.mtime - b.mtime);
  return sessions.map((s) => s.path);
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

// ── Focused Goal Handlers ──────────────────────────────────────────────────────

function buildGoalUserMessage(
  sessionSummary: string,
  structuredLog: string,
  chunkNum?: number,
  totalChunks?: number,
): string {
  const chunkNote = chunkNum && totalChunks && totalChunks > 1
    ? `\nNote: This is part ${chunkNum} of ${totalChunks} — analyze this portion fully and independently.\n`
    : "";
  return `${chunkNote}${sessionSummary}

===BEGIN TRANSCRIPT===
${structuredLog}
===END TRANSCRIPT===

Now produce your analysis. Be exhaustive and technically precise.`;
}

/** Goal 1: Handoff document — chunked across sessions to maximize coverage. */
async function runGoal1Handoff(
  apiKey: string,
  turns: RawTurn[],
  chainInfo: string,
  verbose: boolean,
): Promise<void> {
  // Compute true L0 size by using 10x budget (guarantees no trimming)
  // Avoids string-matching on "middle trimmed" which can appear in session content.
  const l0Log = buildStructuredLogAdaptive(turns, MAX_STRUCTURED_LOG_CHARS * 10, false);
  const fitsInBudget = l0Log.length <= MAX_STRUCTURED_LOG_CHARS;

  if (fitsInBudget) {
    // Fits in one call — use the adaptive log for the real budget
    const structuredLog = buildStructuredLogAdaptive(turns, MAX_STRUCTURED_LOG_CHARS, verbose);
    console.error(`[goal1] Single call — ${structuredLog.length} chars, ${turns.length} turns`);
    const sessionSummary = buildSessionSummary(turns, chainInfo);
    const userMsg = buildGoalUserMessage(sessionSummary, structuredLog);
    const result = await callMiniMax(apiKey, GOAL1_HANDOFF_SYSTEM, userMsg, MAX_OUTPUT_TOKENS);
    console.log(result);
    return;
  }

  // Content too large — chunk by session groupings
  console.error(`[goal1] Content exceeds budget — chunking into session batches`);

  // Group turns by session label (preserves session boundaries)
  const sessionOrder: string[] = [];
  const sessionGroups = new Map<string, RawTurn[]>();
  for (const turn of turns) {
    if (!sessionGroups.has(turn.session)) {
      sessionGroups.set(turn.session, []);
      sessionOrder.push(turn.session);
    }
    sessionGroups.get(turn.session)!.push(turn);
  }

  // Pack sessions into chunks where each chunk fits under budget at L0 fidelity
  const chunks: RawTurn[][] = [];
  let currentChunk: RawTurn[] = [];

  for (const sessionLabel of sessionOrder) {
    const sessionTurns = sessionGroups.get(sessionLabel)!;
    const testChunk = [...currentChunk, ...sessionTurns];
    // Use 10x budget to get true L0 size without false "middle trimmed" matches from content
    const testSize = buildStructuredLogAdaptive(testChunk, MAX_STRUCTURED_LOG_CHARS * 10, false).length;
    if (testSize > MAX_STRUCTURED_LOG_CHARS && currentChunk.length > 0) {
      chunks.push([...currentChunk]);
      currentChunk = [...sessionTurns];
    } else {
      currentChunk = testChunk;
    }
  }
  if (currentChunk.length > 0) chunks.push(currentChunk);

  console.error(`[goal1] Processing ${chunks.length} chunk(s) sequentially for maximum coverage`);
  const chunkResults: string[] = [];

  for (let i = 0; i < chunks.length; i++) {
    const chunk = chunks[i];
    const chunkLog = buildStructuredLogAdaptive(chunk, MAX_STRUCTURED_LOG_CHARS, verbose);
    const chunkSummary = buildSessionSummary(chunk, `${chainInfo} — part ${i + 1}/${chunks.length}`);
    console.error(`[goal1] Chunk ${i + 1}/${chunks.length}: ${chunkLog.length} chars, ${chunk.length} turns`);
    const userMsg = buildGoalUserMessage(chunkSummary, chunkLog, i + 1, chunks.length);
    const result = await callMiniMax(apiKey, GOAL1_HANDOFF_SYSTEM, userMsg, MAX_OUTPUT_TOKENS);
    chunkResults.push(result);
  }

  if (chunkResults.length === 1) {
    console.log(chunkResults[0]);
  } else {
    for (let i = 0; i < chunkResults.length; i++) {
      console.log(`\n${"═".repeat(70)}`);
      console.log(`  HANDOFF PART ${i + 1} OF ${chunkResults.length}`);
      console.log(`${"═".repeat(70)}\n`);
      console.log(chunkResults[i]);
    }
  }
}

/** Goal 2: Error & warning forensics — single pass, full detail. */
async function runGoal2Errors(
  apiKey: string,
  turns: RawTurn[],
  chainInfo: string,
  verbose: boolean,
): Promise<void> {
  const structuredLog = buildStructuredLogAdaptive(turns, MAX_STRUCTURED_LOG_CHARS, verbose);
  const sessionSummary = buildSessionSummary(turns, chainInfo);
  console.error(`[goal2] Error forensics — ${structuredLog.length} chars, ${turns.length} turns`);
  const userMsg = buildGoalUserMessage(sessionSummary, structuredLog);
  const result = await callMiniMax(apiKey, GOAL2_ERRORS_SYSTEM, userMsg, MAX_OUTPUT_TOKENS);
  console.log(result);
}

/** Goal 3: Chronological technical summary — dense timeline. */
async function runGoal3Summary(
  apiKey: string,
  turns: RawTurn[],
  chainInfo: string,
  verbose: boolean,
): Promise<void> {
  const structuredLog = buildStructuredLogAdaptive(turns, MAX_STRUCTURED_LOG_CHARS, verbose);
  const sessionSummary = buildSessionSummary(turns, chainInfo);
  console.error(`[goal3] Chronological summary — ${structuredLog.length} chars, ${turns.length} turns`);
  const userMsg = buildGoalUserMessage(sessionSummary, structuredLog);
  const result = await callMiniMax(apiKey, GOAL3_SUMMARY_SYSTEM, userMsg, MAX_OUTPUT_TOKENS);
  console.log(result);
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const flags = new Set(args.filter((a) => a.startsWith("--")));
  const positional = args.filter((a) => !a.startsWith("--"));

  const dryRun = flags.has("--dry");
  const verbose = flags.has("--verbose");
  const noChain = flags.has("--no-chain");

  // Focused goal mode flags
  const goalIdx = args.indexOf("--goal");
  const goal = goalIdx !== -1 ? parseInt(args[goalIdx + 1], 10) : 0;

  const sinceIdx = args.indexOf("--since");
  const sinceHours = sinceIdx !== -1 ? parseFloat(args[sinceIdx + 1]) : 48;

  const projectDirIdx = args.indexOf("--project-dir");
  const projectDirOverride = projectDirIdx !== -1 ? args[projectDirIdx + 1] : undefined;

  // ── FOCUSED GOAL MODE (--goal 1|2|3) ─────────────────────────────────────────
  if (goal >= 1 && goal <= 3) {
    const goalNames = ["", "Handoff Document", "Error Forensics", "Chronological Summary"];
    console.error(`[session-debrief] Goal ${goal}: ${goalNames[goal]} | Last ${sinceHours}h`);

    const projectDir = projectDirOverride || cwdToProjectDir();
    if (!projectDir) {
      console.error(`[session-debrief] Cannot determine project dir from cwd: ${process.cwd()}`);
      console.error(`  Use --project-dir <path> to specify explicitly`);
      console.error(`  Expected: ~/.claude/projects/${process.cwd().replace(/\//g, "-")}/`);
      process.exit(1);
    }
    console.error(`[session-debrief] Project dir: ${projectDir}`);

    // Discover all sessions within time window
    const primarySessions = discoverSessionsByTimeWindow(projectDir, sinceHours, verbose);
    if (primarySessions.length === 0) {
      console.log(`No sessions found in the last ${sinceHours} hours in ${projectDir}`);
      console.log(`Try increasing --since (e.g., --since 168 for 1 week)`);
      process.exit(0);
    }
    console.error(`[session-debrief] Found ${primarySessions.length} session(s) in time window`);

    // Expand each session with its parent chain, de-duplicating
    const visited = new Set<string>();
    const allSessionPaths: string[] = [];

    for (const s of primarySessions) {
      if (visited.has(s)) continue;
      visited.add(s);

      if (!noChain) {
        const ancestors = traceParentsRecursive(s, visited, verbose);
        for (const a of ancestors) {
          if (!visited.has(a)) {
            visited.add(a);
            allSessionPaths.push(a);
          }
        }
      }
      allSessionPaths.push(s);
    }

    // Sort chronologically (oldest first)
    allSessionPaths.sort((a, b) => statSync(a).mtimeMs - statSync(b).mtimeMs);
    console.error(`[session-debrief] Total sessions (including ancestors): ${allSessionPaths.length}`);

    // Parse all turns
    const allTurns: RawTurn[] = [];
    let turnOffset = 0;
    for (const spath of allSessionPaths) {
      const sid = spath.replace(/^.*\//, "").replace(/\.jsonl$/, "").slice(0, 8);
      const mtime = new Date(statSync(spath).mtimeMs);
      const label = `${sid}… (${mtime.toLocaleDateString()})`;
      const turns = parseSessionRaw(spath, label, turnOffset, verbose);
      allTurns.push(...turns);
      turnOffset = allTurns.length;
    }

    const chainInfo = `${allSessionPaths.length} sessions over last ${sinceHours}h — ${allTurns.length} total turns`;
    console.error(`[session-debrief] Payload: ${allTurns.length} turns across ${allSessionPaths.length} sessions`);

    if (dryRun) {
      const structuredLog = buildStructuredLogAdaptive(allTurns, MAX_STRUCTURED_LOG_CHARS, verbose);
      console.log(buildSessionSummary(allTurns, chainInfo));
      console.log("\n---\n");
      console.log(structuredLog);
      return;
    }

    const apiKey = getApiKey();

    console.log("");
    console.log("=".repeat(70));
    console.log(`  SESSION ANALYSIS — Goal ${goal}: ${goalNames[goal]}`);
    console.log(`  ${chainInfo}`);
    console.log("=".repeat(70));
    console.log("");

    if (goal === 1) {
      await runGoal1Handoff(apiKey, allTurns, chainInfo, verbose);
    } else if (goal === 2) {
      await runGoal2Errors(apiKey, allTurns, chainInfo, verbose);
    } else {
      await runGoal3Summary(apiKey, allTurns, chainInfo, verbose);
    }

    console.log("");
    console.log("=".repeat(70));
    return;
  }

  console.error("Usage: session-debrief.ts --goal <1|2|3> --since <hours> [options]");
  console.error("");
  console.error("  --goal 1            Handoff document (exhaustive context for next session)");
  console.error("  --goal 2            Error forensics (all warnings/errors Claude ignored)");
  console.error("  --goal 3            Chronological summary (technical timeline)");
  console.error("  --since N           Hours to look back (default: 48)");
  console.error("  --project-dir PATH  Override project dir (default: auto-detect from cwd)");
  console.error("  --dry               Parse and show structured log, skip MiniMax calls");
  console.error("  --verbose           Show fidelity levels and timing");
  console.error("  --no-chain          Skip parent chain tracing");
  process.exit(1);
}

main().catch((err) => {
  console.error(`[session-debrief] Fatal: ${err.message}`);
  process.exit(1);
});
