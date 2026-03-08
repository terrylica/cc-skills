#!/usr/bin/env bun
/**
 * Session Blind Spots — Diverse-perspective consensus analysis of Claude Code sessions.
 *
 * Key design principles:
 * 1. ADAPTIVE extraction: preserve max signal within MiniMax's ~920K char context ceiling
 * 2. DIVERSE perspectives: 20 distinct reviewer lenses (not copies of same prompt)
 * 3. Session chain tracing: follows parent sessions for full historical context
 * 4. Consensus distillation: N diverse reviews → one ranked synthesis
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

// Default: 10 diverse perspectives (use --shots 20 for all 20)
const DEFAULT_SHOTS = 10;

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

const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g;

function traceSessionChain(primaryPath: string, verbose: boolean): string[] {
  const chain: string[] = [primaryPath];
  const visited = new Set<string>([primaryPath]);
  const primaryUuid = primaryPath.match(/([0-9a-f-]{36})\.jsonl$/)?.[1] || "";

  const raw = readFileSync(primaryPath, "utf-8");
  const lines = raw.split("\n").filter(Boolean).slice(0, 50);

  const referencedUuids = new Set<string>();

  for (const line of lines) {
    if (line.includes("continued from") || line.includes("summary below") ||
        line.includes("prior session") || line.includes("previous conversation")) {
      const matches = line.match(UUID_RE) || [];
      for (const uuid of matches) {
        if (uuid !== primaryUuid) {
          referencedUuids.add(uuid);
        }
      }
    }
  }

  try {
    const firstObj = JSON.parse(lines[0]);
    if (firstObj.parentSessionId && firstObj.parentSessionId !== primaryUuid) {
      referencedUuids.add(firstObj.parentSessionId);
    }
  } catch { /* ignore */ }

  for (const uuid of referencedUuids) {
    const parentPath = findSessionByUuid(uuid);
    if (parentPath && !visited.has(parentPath)) {
      visited.add(parentPath);
      chain.unshift(parentPath);
      if (verbose) {
        const size = statSync(parentPath).size;
        console.error(`[chain] Found parent session: ${uuid} (${(size / 1048576).toFixed(1)}MB)`);
      }
    }
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
      }
    }
  }

  return { text: stripNoise(text), toolCalls, toolResults, files, errors };
}

function parseSessionRaw(path: string, sessionLabel: string, startTurn: number, verbose: boolean): RawTurn[] {
  const raw = readFileSync(path, "utf-8");
  const lines = raw.split("\n").filter(Boolean);
  const turns: RawTurn[] = [];
  let skipped = 0;
  let turnNum = startTurn;

  for (const line of lines) {
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
    console.error(`[parse] ${sessionLabel}: ${lines.length} lines → ${turns.length} turns (${skipped} skipped)`);
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
    if (shots > 20) shots = 20;
  }

  if (positional.length === 0) {
    console.error("Usage: session-blind-spots.ts <session-id-or-path> [options]");
    console.error("");
    console.error("  session-id-or-path  UUID or full .jsonl path");
    console.error("  --dry               Parse and show structured log, skip MiniMax calls");
    console.error("  --verbose           Show adaptive fidelity levels and per-shot timing");
    console.error("  --shots N           Number of diverse perspectives (default: 5, max: 20)");
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

  // Trace session chain
  let sessionChain: string[];
  if (noChain) {
    sessionChain = [sessionPath];
  } else {
    sessionChain = traceSessionChain(sessionPath, verbose);
    if (sessionChain.length > 1) {
      console.error(`[blind-spots] Session chain: ${sessionChain.length} sessions (${sessionChain.length - 1} parent(s))`);
    }
  }

  // Parse all sessions
  const allTurns: RawTurn[] = [];
  let turnOffset = 0;
  const chainLabels: string[] = [];

  for (const spath of sessionChain) {
    const sid = spath.match(/([0-9a-f-]{36})\.jsonl$/)?.[1] || "unknown";
    const label = spath === sessionPath ? `${sid.slice(0, 8)}… (primary)` : `${sid.slice(0, 8)}… (parent)`;
    chainLabels.push(label);

    const turns = parseSessionRaw(spath, label, turnOffset, verbose);
    allTurns.push(...turns);
    turnOffset = allTurns.length;
  }

  console.error(`[blind-spots] Total: ${allTurns.length} turns across ${sessionChain.length} session(s)`);

  const chainInfo = sessionChain.length > 1
    ? `Session chain: ${chainLabels.join(" → ")}`
    : `Single session: ${chainLabels[0]}`;

  const sessionSummary = buildSessionSummary(allTurns, chainInfo);
  const structuredLog = buildStructuredLogAdaptive(allTurns, MAX_STRUCTURED_LOG_CHARS, verbose);
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
  console.log(`  Chain: ${sessionChain.length} session(s) | Turns: ${allTurns.length} | Perspectives: ${shots}`);
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
