#!/usr/bin/env node
/**
 * gh-issue-title-reminder.mjs
 *
 * PostToolUse hook that reminds to optimize GitHub issue titles when:
 * 1. A comment is added to an issue
 * 2. The current user owns the issue (author check)
 * 3. The current title has room for improvement (< 200 chars)
 *
 * This hook is NON-BLOCKING (always exits 0) - it only provides reminders.
 *
 * User detection priority:
 * 1. GH_ACCOUNT environment variable (set by mise per-directory)
 * 2. Fallback: scan ~/.claude/.secrets/gh-token-* files
 */

import { readFileSync, readdirSync } from "fs";
import { execSync } from "child_process";
import { homedir } from "os";
import { join } from "path";

// Read hook input from stdin
let input;
try {
  input = JSON.parse(readFileSync(0, "utf-8"));
} catch {
  process.exit(0); // Silent exit if no input
}

const { tool_name, tool_input, tool_output } = input;

// Only trigger on Bash commands
if (tool_name !== "Bash") {
  process.exit(0);
}

const command = tool_input?.command || "";

// Detect GitHub issue comment commands
const isIssueComment = /gh\s+issue\s+comment/.test(command);
const isApiComment = /gh\s+api\s+.*\/issues\/\d+\/comments/.test(command);
const isIssueCreate = /gh\s+issue\s+create/.test(command);

if (!isIssueComment && !isApiComment && !isIssueCreate) {
  process.exit(0);
}

// Extract issue number and repo from command
let issueNumber = null;
let repo = null;

// Pattern: gh issue comment 123 --repo owner/repo
const commentMatch = command.match(/gh\s+issue\s+comment\s+(\d+)(?:.*--repo\s+([^\s]+))?/);
if (commentMatch) {
  issueNumber = commentMatch[1];
  repo = commentMatch[2];
}

// Pattern: gh api repos/owner/repo/issues/123/comments
const apiMatch = command.match(/gh\s+api\s+repos\/([^\/]+\/[^\/]+)\/issues\/(\d+)\/comments/);
if (apiMatch) {
  repo = apiMatch[1];
  issueNumber = apiMatch[2];
}

// For issue create, we skip - can't check ownership of a new issue
if (isIssueCreate) {
  // Remind to maximize title for new issues
  console.error(`
[gh-tools] GitHub Issue Created

Title Optimization Reminder:
   GitHub allows 256 characters for issue titles.
   Maximize this limit to create informative, searchable titles.

   Check current length: gh issue view <number> --json title --jq '.title | length'
`);
  process.exit(0);
}

// If no issue number found, skip
if (!issueNumber) {
  process.exit(0);
}

// Get current user - priority: GH_ACCOUNT env var, then token filename fallback
function getCurrentUser() {
  // Priority 1: GH_ACCOUNT set by mise per-directory config
  const ghAccount = process.env.GH_ACCOUNT;
  if (ghAccount) {
    return ghAccount;
  }

  // Priority 2: Fallback to token filename pattern
  // Look for exact match first (gh-token-username), skip suffixed ones (gh-token-username-classic)
  const secretsDir = join(homedir(), ".claude", ".secrets");
  try {
    const files = readdirSync(secretsDir);
    // Filter to only base token files (no suffix like -classic, -finegrained)
    const baseTokenFiles = files.filter(f => {
      if (!f.startsWith("gh-token-")) return false;
      const username = f.replace("gh-token-", "");
      // Skip if username contains hyphen (likely a suffix variant)
      return !username.includes("-");
    });
    if (baseTokenFiles.length === 1) {
      return baseTokenFiles[0].replace("gh-token-", "");
    }
    // If multiple or none, try symlinks (they point to the active one)
    const symlinkToken = files.find(f => {
      const fullPath = join(secretsDir, f);
      try {
        const stats = require("fs").lstatSync(fullPath);
        return stats.isSymbolicLink() && f.startsWith("gh-token-");
      } catch { return false; }
    });
    if (symlinkToken) {
      const username = symlinkToken.replace("gh-token-", "");
      return username.includes("-") ? null : username;
    }
  } catch {
    // Fall back or skip
  }
  return null;
}

// Get issue details (author and title)
function getIssueDetails(issueNum, repoArg) {
  try {
    const repoFlag = repoArg ? `--repo ${repoArg}` : "";
    const result = execSync(
      `gh issue view ${issueNum} ${repoFlag} --json author,title 2>/dev/null`,
      { encoding: "utf-8", timeout: 10000 }
    );
    return JSON.parse(result);
  } catch {
    return null;
  }
}

const currentUser = getCurrentUser();
if (!currentUser) {
  // Can't determine current user, skip reminder
  process.exit(0);
}

const issueDetails = getIssueDetails(issueNumber, repo);
if (!issueDetails) {
  process.exit(0);
}

const { author, title } = issueDetails;
const issueOwner = author?.login;

// Only remind if current user owns the issue
if (issueOwner !== currentUser) {
  process.exit(0);
}

// Check if title has room for improvement
const titleLength = title?.length || 0;
const MAX_TITLE_LENGTH = 256;
const OPTIMIZATION_THRESHOLD = 200;

if (titleLength >= OPTIMIZATION_THRESHOLD) {
  // Title is already well-optimized
  process.exit(0);
}

// Show reminder
const repoDisplay = repo || "(current repo)";
console.error(`
[gh-tools] Issue Title Optimization Reminder

Issue: #${issueNumber} in ${repoDisplay}
Current title (${titleLength}/${MAX_TITLE_LENGTH} chars):
  "${title}"

Consider updating the title to:
   - Reflect new findings from this comment
   - Maximize the 256-character limit
   - Capture the full journey/context of the issue

Commands:
  gh issue view ${issueNumber} --json title --jq '.title | length'
  gh issue edit ${issueNumber} --title "..."
`);

process.exit(0);
