#!/usr/bin/env bun
/**
 * PostToolUse hook: Memory Efficiency Reminder
 *
 * Fires once per session after the first Write/Edit of a code file to remind
 * Claude about zero-copy, pre-allocation, cache locality, and lazy evaluation
 * patterns. Prevents the common anti-pattern of building Python lists then
 * converting to Arrow/Polars, or making unnecessary copies in hot paths.
 *
 * Gate: fires once per session via /tmp sentinel file.
 * Scope: .py, .rs, .ts, .go, .java, .kt, .rb, .cpp, .c, .zig files only.
 * Skips: test files, config files, documentation.
 */

interface PostToolUseInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    content?: string;
    new_string?: string;
    [key: string]: unknown;
  };
  session_id?: string;
}

const CODE_EXTENSIONS = new Set([
  ".py", ".rs", ".ts", ".tsx", ".js", ".go",
  ".java", ".kt", ".rb", ".cpp", ".c", ".h", ".zig",
]);

const TEST_PATTERNS = /(?:^|\/)(?:test_|tests\/|__tests__\/|_test\.|_spec\.|\.test\.|\.spec\.)/;

const SENTINEL_DIR = "/tmp/.claude-memory-efficiency";

function getFileExtension(path: string): string {
  const dot = path.lastIndexOf(".");
  return dot >= 0 ? path.slice(dot) : "";
}

async function main(): Promise<void> {
  const stdin = await Bun.stdin.text();
  if (!stdin.trim()) return;

  let input: PostToolUseInput;
  try {
    input = JSON.parse(stdin);
  } catch {
    return;
  }

  // Only Write/Edit
  if (input.tool_name !== "Write" && input.tool_name !== "Edit") return;

  const filePath = input.tool_input?.file_path || "";
  if (!filePath) return;

  // Only code files
  const ext = getFileExtension(filePath);
  if (!CODE_EXTENSIONS.has(ext)) return;

  // Skip test files
  if (TEST_PATTERNS.test(filePath)) return;

  // Once per session gate
  const sessionId = input.session_id || process.env.CLAUDE_SESSION_ID || String(process.ppid);
  const sentinelPath = `${SENTINEL_DIR}/${sessionId}.memory-efficiency`;

  const { existsSync, mkdirSync, writeFileSync } = await import("fs");
  if (existsSync(sentinelPath)) return;

  try {
    mkdirSync(SENTINEL_DIR, { recursive: true });
    writeFileSync(sentinelPath, new Date().toISOString());
  } catch {
    return; // Fail silently
  }

  // Emit reminder as context message
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      context: `[MEMORY-EFFICIENCY] When writing data-path code, prefer these patterns:

┌──────────────────┬─────────────────────────────────────┐
│ AVOID COPIES     │ zero-copy, view, slice, borrow,     │
│                  │ pass-by-reference, move semantics   │
├──────────────────┼─────────────────────────────────────┤
│ AVOID ALLOCATION │ pre-allocate, buffer reuse, arena,  │
│                  │ stack allocation, object pool       │
├──────────────────┼─────────────────────────────────────┤
│ CACHE EFFICIENCY │ contiguous, data locality, SoA,     │
│                  │ cache-friendly, cache-oblivious     │
├──────────────────┼─────────────────────────────────────┤
│ LAZY EVALUATION  │ streaming, iterator, generator,     │
│                  │ predicate pushdown, lazy frame      │
└──────────────────┴─────────────────────────────────────┘

Anti-patterns: Python list → Arrow (copy!), df.to_dict() in loops, .values() materializing lazy frames, repeated pd.concat instead of pre-sized buffer.`,
    },
  }));
}

void main();
