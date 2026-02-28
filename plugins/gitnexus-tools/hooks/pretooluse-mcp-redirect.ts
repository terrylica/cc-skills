#!/usr/bin/env bun
/**
 * PreToolUse hook: GitNexus MCP → CLI redirect
 *
 * Intercepts attempts to use GitNexus via MCP (readMcpResource, useMcpTool)
 * and denies them with CLI guidance. GitNexus is CLI-only by design — MCP
 * schemas (~3,500 tokens for 7 tools) waste context window on every turn.
 *
 * Also intercepts generic exploration tools (Task with Explore subagent)
 * when the user has asked about GitNexus, reminding Claude to use the CLI.
 *
 * Fail-open: parse errors → allow.
 */

// --- Types ---

interface HookInput {
  tool_name: string;
  tool_input: {
    command?: string;
    prompt?: string;
    server_name?: string;
    uri?: string;
    name?: string;
    subagent_type?: string;
    [key: string]: unknown;
  };
  tool_use_id?: string;
}

// --- Output helpers (inline — no cross-plugin imports) ---

function allow(): void {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
      },
    })
  );
}

function deny(reason: string): void {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason,
      },
    })
  );
}

// --- Detection ---

const GITNEXUS_RE = /\bgitnexus\b/i;

// --- Main ---

async function main(): Promise<void> {
  let inputText = "";
  for await (const chunk of Bun.stdin.stream()) {
    inputText += new TextDecoder().decode(chunk);
  }

  let input: HookInput;
  try {
    input = JSON.parse(inputText);
  } catch {
    allow();
    return;
  }

  const { tool_name, tool_input = {} } = input;

  // Case 1: MCP resource read targeting gitnexus
  if (tool_name === "readMcpResource" || tool_name === "useMcpTool") {
    const serverName = tool_input.server_name || "";
    const uri = tool_input.uri || "";
    const name = tool_input.name || "";

    if (
      GITNEXUS_RE.test(serverName) ||
      GITNEXUS_RE.test(uri) ||
      GITNEXUS_RE.test(name)
    ) {
      deny(
        `[GITNEXUS] No MCP server — GitNexus is CLI-only by design (saves ~3,500 tokens/turn).

Use the CLI directly:
  npx gitnexus@latest query "<concept>" --limit 5    # Explore flows
  npx gitnexus@latest context "<symbol>" --content    # 360° view
  npx gitnexus@latest impact "<symbol>" --depth 3     # Blast radius
  npx gitnexus@latest status                          # Check freshness
  npx gitnexus@latest analyze                         # Re-index

Or invoke skills:
  /gitnexus-tools:explore   — Trace execution flows
  /gitnexus-tools:impact    — Blast radius analysis
  /gitnexus-tools:dead-code — Find orphan functions
  /gitnexus-tools:reindex   — Re-index repository`
      );
      return;
    }
  }

  allow();
}

main().catch(() => {
  allow();
});
