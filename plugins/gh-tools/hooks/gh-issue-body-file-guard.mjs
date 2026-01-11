#!/usr/bin/env bun
// ADR: /docs/adr/2026-01-11-gh-issue-body-file-guard.md
// gh-issue-body-file-guard.mjs - Block gh issue create with inline --body
//
// Problem: gh issue create --body "$(cat <<'EOF'...)" silently fails for long content.
// Solution: Require --body-file for reliability.

// Read stdin
const input = await Bun.stdin.text();

// Handle empty input (e.g., when testing with --help)
if (!input.trim()) {
  process.exit(0);
}

const data = JSON.parse(input);

const toolName = data.tool_name ?? "";
const command = data.tool_input?.command ?? "";

// Only intercept Bash tool
if (toolName !== "Bash") {
  process.exit(0);
}

// Check if this is a gh issue create command
if (!/\bgh\s+issue\s+create\b/.test(command)) {
  process.exit(0);
}

// Check if it uses --body-file (ALLOWED)
if (/--body-file/.test(command)) {
  process.exit(0);
}

// Check if it uses inline --body (BLOCKED)
if (/--body\s/.test(command)) {
  const reason = `[gh-issue-guard] BLOCKED: gh issue create with inline --body

Inline --body with heredocs is unreliable for long issue bodies.
Issues may appear created but not actually exist.

Required pattern:
  1. Write content to temp file:
     echo "..." > /tmp/issue-body.md

  2. Use --body-file:
     gh issue create --title "..." --body-file /tmp/issue-body.md

  3. Clean up:
     rm /tmp/issue-body.md

Reference: /docs/adr/2026-01-11-gh-issue-body-file-guard.md`;

  console.log(JSON.stringify({
    permissionDecision: "deny",
    reason: reason
  }));
  process.exit(0);
}

// Allow (no --body flag at all - interactive mode)
process.exit(0);
