#!/usr/bin/env node
/**
 * gh-issue-no-anchors.mjs
 *
 * PreToolUse hook that BLOCKS gh issue create/edit when the body contains
 * in-page anchor links like [text](#heading). These don't work in GitHub
 * Issues (Chrome confirmed 2026-03-26).
 *
 * Allowed: [text](https://...), [text](./path), #123 issue refs, etc.
 * Blocked: [text](#anchor-name) — in-page fragment links only.
 */

import { readFileSync } from "fs";

let input;
try {
  input = JSON.parse(readFileSync(0, "utf-8"));
} catch {
  process.exit(0);
}

const { tool_name, tool_input } = input;

if (tool_name !== "Bash") {
  process.exit(0);
}

const command = tool_input?.command || "";

// Only check gh issue create/edit commands
const isIssueWrite = /gh\s+issue\s+(create|edit)/.test(command);
if (!isIssueWrite) {
  process.exit(0);
}

// Look for anchor link pattern: [any text](#any-anchor)
// This catches: [Link Text](#section-name)
// Does NOT catch: [Link](#123) — but that's not a valid pattern anyway
// Does NOT catch: standalone #anchor or bare (#anchor)
const anchorPattern = /\[[^\]]+\]\(#[^)]+\)/;
const match = command.match(anchorPattern);

if (match) {
  const reason = `[gh-tools] Anchor links do not work in GitHub Issues.

Found: ${match[0]}

GitHub Issues do not generate clickable heading anchors in Chrome.
Remove all [text](#anchor) links and use plain text references instead.
Example: "see Hardware Assumptions section below" (no link).`;

  console.log(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: reason } }));
  process.exit(0);
}

// Also check body-file if used
const bodyFileMatch = command.match(/--body-file\s+(\S+)/);
if (bodyFileMatch) {
  try {
    const bodyContent = readFileSync(bodyFileMatch[1], "utf-8");
    const fileMatch = bodyContent.match(anchorPattern);
    if (fileMatch) {
      const reason = `[gh-tools] Anchor links do not work in GitHub Issues.

Found in body file: ${fileMatch[0]}

GitHub Issues do not generate clickable heading anchors in Chrome.
Remove all [text](#anchor) links and use plain text references instead.`;

      console.log(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: reason } }));
      process.exit(0);
    }
  } catch {
    // Can't read file, skip check
  }
}

process.exit(0);
