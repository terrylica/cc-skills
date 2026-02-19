#!/usr/bin/env bun
// gh-repo-identity-guard.mjs - Block gh CLI writes when user lacks push access
//
// Incident: 2026-02-09 — Issue #6 posted to 459ecs/dental-career-opportunities
// by terrylica (wrong account). Root cause: GH_TOKEN set to wrong account via
// global mise config; project-specific mise config had a parse error.
//
// This PreToolUse hook prevents gh CLI write operations when the authenticated
// user does not have push access to the target repository.
//
// Safety:
// - No `gh` CLI calls (avoids credential helper recursion / process storms)
// - Uses curl with Authorization header directly
// - Fail-open: if API fails or token missing, allows through
// - Cache prevents repeated API calls per session

import { readFileSync, writeFileSync, existsSync } from "fs";
import { execSync } from "child_process";

// ─── Read stdin ─────────────────────────────────────────────────────────────
const input = await Bun.stdin.text();

if (!input.trim()) {
  process.exit(0);
}

let data;
try {
  data = JSON.parse(input);
} catch {
  process.exit(0);
}

const toolName = data.tool_name ?? "";
const command = data.tool_input?.command ?? "";

// Only intercept Bash tool
if (toolName !== "Bash") {
  process.exit(0);
}

// ─── Match gh write commands ────────────────────────────────────────────────
const GH_WRITE_PATTERNS = [
  /\bgh\s+issue\s+(create|comment|edit|close|delete|label)\b/,
  /\bgh\s+label\s+(create|edit|delete)\b/,
  /\bgh\s+pr\s+(create|comment|review|edit|close|merge)\b/,
  /\bgh\s+api\b.*(?:-X|--method)\s+(POST|PUT|PATCH|DELETE)\b/,
];

const isWriteCommand = GH_WRITE_PATTERNS.some((pat) => pat.test(command));
if (!isWriteCommand) {
  process.exit(0);
}

// ─── Extract target repo ────────────────────────────────────────────────────

function extractRepo(cmd) {
  // --repo owner/repo or -R owner/repo
  const repoFlag = cmd.match(/(?:--repo|-R)\s+([^\s]+)/);
  if (repoFlag) return repoFlag[1];

  // gh api repos/owner/repo/...
  const apiPath = cmd.match(/\bgh\s+api\s+repos\/([^\/]+\/[^\/]+)/);
  if (apiPath) return apiPath[1];

  // Fallback: git remote
  try {
    const remote = execSync("git remote get-url origin 2>/dev/null", {
      encoding: "utf-8",
      timeout: 3000,
    }).trim();
    // Parse git@github.com:owner/repo.git or https://github.com/owner/repo.git
    const sshMatch = remote.match(/github\.com[:/]([^/]+\/[^/.]+)/);
    if (sshMatch) return sshMatch[1];
  } catch {
    // No git remote available
  }

  return null;
}

const targetRepo = extractRepo(command);
if (!targetRepo) {
  // Can't determine target repo — allow through (can't guard what we can't identify)
  process.exit(0);
}

const [repoOwner] = targetRepo.split("/");

// ─── Resolve authenticated user ─────────────────────────────────────────────

const ghToken = process.env.GH_TOKEN || "";
if (!ghToken) {
  // No token set — allow through (gh CLI will fail itself)
  process.exit(0);
}

// Fast-path: GH_ACCOUNT env var
const ghAccount = process.env.GH_ACCOUNT;
if (ghAccount && ghAccount === repoOwner) {
  process.exit(0); // Owner match — allow immediately (zero API calls)
}

// Cache: /tmp/.gh-identity-cache-{uid}.json
// Keyed on first 4 + last 4 chars of token for privacy
const uid = process.getuid?.() ?? "unknown";
const cacheFile = `/tmp/.gh-identity-cache-${uid}.json`;
const tokenKey = `${ghToken.slice(0, 4)}...${ghToken.slice(-4)}`;

function readCache() {
  try {
    if (!existsSync(cacheFile)) return null;
    const cache = JSON.parse(readFileSync(cacheFile, "utf-8"));
    const entry = cache[tokenKey];
    if (!entry) return null;
    // 5-minute TTL
    if (Date.now() - entry.timestamp > 5 * 60 * 1000) return null;
    return entry;
  } catch {
    return null;
  }
}

function writeCache(username, permissions) {
  try {
    let cache = {};
    if (existsSync(cacheFile)) {
      try {
        cache = JSON.parse(readFileSync(cacheFile, "utf-8"));
      } catch {
        cache = {};
      }
    }
    cache[tokenKey] = { username, permissions, timestamp: Date.now() };
    writeFileSync(cacheFile, JSON.stringify(cache, null, 2));
  } catch {
    // Cache write failure is non-critical
  }
}

// Try cache first
let authenticatedUser = null;
let source = "";
const cached = readCache();

if (cached) {
  authenticatedUser = cached.username;
  source = "cache";
} else {
  // API: curl to resolve user (no gh CLI — prevents process storm)
  try {
    const result = execSync(
      `curl -sf --max-time 5 -H "Authorization: token ${ghToken}" https://api.github.com/user`,
      { encoding: "utf-8", timeout: 8000 }
    );
    const userData = JSON.parse(result);
    authenticatedUser = userData.login;
    source = "API /user";
    writeCache(authenticatedUser, {});
  } catch {
    // API failed — fail-open
    process.exit(0);
  }
}

if (!authenticatedUser) {
  process.exit(0); // Can't resolve user — fail-open
}

// If GH_ACCOUNT was set but didn't match owner, note that
if (ghAccount) {
  source = `GH_ACCOUNT=${ghAccount}`;
}

// ─── Check: authenticated user === repo owner → allow ───────────────────────
if (authenticatedUser === repoOwner) {
  process.exit(0);
}

// ─── Check push permission ──────────────────────────────────────────────────
let hasPush = false;
try {
  const repoResult = execSync(
    `curl -sf --max-time 5 -H "Authorization: token ${ghToken}" https://api.github.com/repos/${targetRepo}`,
    { encoding: "utf-8", timeout: 8000 }
  );
  const repoData = JSON.parse(repoResult);
  hasPush = repoData.permissions?.push === true;
} catch {
  // API failed — fail-open (gh CLI will fail itself if no access)
  process.exit(0);
}

if (hasPush) {
  process.exit(0); // Has push access — allow
}

// ─── DENY ───────────────────────────────────────────────────────────────────
const reason = `[gh-identity-guard] BLOCKED: Wrong GitHub account for ${targetRepo}

Authenticated as: ${authenticatedUser} (via ${source})
Target repository: ${targetRepo}
Push permission: DENIED

Fix:
  1. Check mise config: mise env | grep GH_TOKEN
  2. Verify GH_ACCOUNT: echo $GH_ACCOUNT
  3. If mise parse error: mise doctor
  4. Set correct token: export GH_TOKEN=$(cat ~/.claude/.secrets/gh-token-${repoOwner})`;

console.log(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  })
);
process.exit(0);
