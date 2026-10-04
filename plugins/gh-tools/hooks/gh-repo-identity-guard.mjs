#!/usr/bin/env bun
// gh-repo-identity-guard.mjs - Block gh CLI writes based on permission level
//
// Incident: 2026-02-09 — Issue #6 posted to work/example-job-board
// by terrylica (wrong account). Root cause: GH_TOKEN set to wrong account via
// global mise config; project-specific mise config had a parse error.
//
// This PreToolUse hook enforces two permission tiers:
// - "Public-safe" ops (issue create/comment): allowed on any public repo
// - "Push-required" ops (edit, close, merge, label): require push access
//
// Safety:
// - No `gh` CLI calls (avoids credential helper recursion / process storms)
// - Uses curl with Authorization header directly
// - Fail-open: if API fails or token missing, allows through
// - Cache prevents repeated API calls per session

import { readFileSync, writeFileSync, existsSync } from "fs";
import { execSync } from "child_process";
import { homedir } from "os";
import { join } from "path";
import { accountForOwner } from "./lib/path-owner-registry.mjs";

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
// "Public-safe" commands: any authenticated user can do these on public repos
// (gh issue create/comment, gh pr comment). Only require owner/push for
// privileged operations (edit, close, delete, merge, label management).
const GH_PUBLIC_SAFE_PATTERNS = [
  /\bgh\s+issue\s+(create|comment)\b/,
  /\bgh\s+pr\s+comment\b/,
];

const GH_PUSH_REQUIRED_PATTERNS = [
  /\bgh\s+issue\s+(edit|close|delete|label)\b/,
  /\bgh\s+label\s+(create|edit|delete)\b/,
  /\bgh\s+pr\s+(create|edit|close|merge|review)\b/,
  /\bgh\s+api\b.*(?:-X|--method)\s+(POST|PUT|PATCH|DELETE)\b/,
];

const isPublicSafe = GH_PUBLIC_SAFE_PATTERNS.some((pat) => pat.test(command));
const isPushRequired = GH_PUSH_REQUIRED_PATTERNS.some((pat) =>
  pat.test(command)
);

if (!isPublicSafe && !isPushRequired) {
  process.exit(0); // Not a write command — allow
}

// ─── Extract target repo ────────────────────────────────────────────────────

function storedOrigin() {
  try {
    return execSync("git config --get remote.origin.url 2>/dev/null", { encoding: "utf-8", timeout: 3000 }).trim();
  } catch {
    return "";
  }
}

// `git config gh.account` is set by ~/.config/git/accounts/<account>.gitconfig for repos under
// ~/gh/<org>/ — the folder, not the URL, chooses the account there (path-owner-registry.toml).
function configAccount() {
  try {
    return execSync("git config --get gh.account 2>/dev/null", { encoding: "utf-8", timeout: 3000 }).trim() || null;
  } catch {
    return null;
  }
}

function extractRepo(cmd) {
  // --repo owner/repo or -R owner/repo
  const repoFlag = cmd.match(/(?:--repo|-R)\s+([^\s]+)/);
  if (repoFlag) return repoFlag[1];

  // gh api repos/owner/repo/...
  const apiPath = cmd.match(/\bgh\s+api\s+repos\/([^/]+\/[^/]+)/);
  if (apiPath) return apiPath[1];

  // Fallback: the origin remote. Read the STORED url (`git config`), not `git remote get-url`:
  // under ~/gh/<org>/ a url.<alias>.insteadOf rewrite turns git@github.com:org/repo into
  // git@github.com-<account>:org/repo, which the old `github.com[:/]` pattern never matched — so the
  // guard found no target and allowed every write there (GitHub migration 2026-10-04). Alias hosts
  // are accepted too, for repos whose stored url still names one.
  const sshMatch = storedOrigin().match(/github\.com(?:-[A-Za-z0-9_-]+)?[:/]([^/]+\/[^/\s]+?)(?:\.git)?$/);
  if (sshMatch) return sshMatch[1];

  return null;
}

const targetRepo = extractRepo(command);
if (!targetRepo) {
  // Can't determine target repo — allow through (can't guard what we can't identify)
  process.exit(0);
}

const [repoOwner] = targetRepo.split("/");

// ─── Fail-CLOSED for owners the registry knows (2026-10-04) ──────────────────
// A call on an organization repo ran as the operator's personal account because the account was chosen from
// the caller's folder. Account routing now lives in ONE place, the `gh` shim on PATH
// (~/.local/bin/gh), which maps the TARGET repo's owner to its account through the same registry. So
// for a registry-known owner the write is safe exactly when it will go through that shim and the
// account's profile exists. Anything else is denied, deterministically, with no network and no `gh`:
//   · the shim is missing, or the command execs a real gh binary by absolute path (bypasses it);
//   · ~/.config/gh-<account> does not exist (the shim would fall back to the folder's account).
{
  const required = accountForOwner(repoOwner);
  if (required) {
    const profile = join(homedir(), ".config", `gh-${required.toLowerCase().replace(/-/g, "")}`);
    const shim = join(homedir(), ".local", "bin", "gh");
    const absoluteBinary = /(^|[\s;&|(])\/(?:opt\/homebrew|usr\/local|usr)\/bin\/gh\b/.test(command);
    const problems = [];
    if (!existsSync(shim)) problems.push(`the account-routing shim ${shim} is missing`);
    if (absoluteBinary) problems.push("the command runs a gh binary by absolute path, which bypasses the routing shim");
    if (!existsSync(profile)) problems.push(`the profile ${profile} for account "${required}" does not exist`);
    if (problems.length === 0) process.exit(0); // routed to the right account by construction
    if (process.env.ALLOW_OWNER_MISMATCH !== "1") {
      console.log(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: `[gh-repo-identity-guard] ${targetRepo} must be written as "${required}" (SSoT ~/.claude/path-owner-registry.toml), but ${problems.join("; ")}. Run plain \`gh\` (the shim on PATH picks the account from the target repo), or create the profile with: GH_CONFIG_DIR=${profile} gh auth login. Deliberate override: prefix ALLOW_OWNER_MISMATCH=1.`,
        },
      }));
      process.exit(0);
    }
  }
}

// ─── Resolve the local account from the origin host-alias (SSoT) ─────────────
// ADR 2026-06-21 host-alias doctrine: a repo's origin remote
// (git@github.com-<account>:owner/repo) names its account. GH_ACCOUNT env,
// ~/.claude/.secrets/gh-token-* files, and mise [env] token injection are all
// retired. The alias is parsed from git alone — no `gh`, no network — so it
// honours the process-storm rule (no gh-CLI calls inside hooks).
function aliasAccount() {
  try {
    const remote = execSync("git remote get-url origin 2>/dev/null", {
      encoding: "utf-8",
      timeout: 3000,
    }).trim();
    const m = remote.match(/github\.com-([A-Za-z0-9_-]+):/);
    return m ? m[1] : null;
  } catch {
    return null;
  }
}

const localAccount = configAccount() ?? aliasAccount();

// Fast-path (~/gh/<org>/ layout): the folder chose the account (gh.account is set) and the target is
// this repo's own organization, read from its stored canonical remote. The account is that org's
// mapped admin, so this is the "writing to your own repo" case. Zero API calls. Not taken when a
// GH_TOKEN is exported: gh then uses THAT token instead of gh.configdir, which is exactly the
// wrong-account incident this hook exists for, so the token's own push access is checked below.
{
  const own = storedOrigin().match(/github\.com(?:-[A-Za-z0-9_-]+)?[:/]([^/]+)\//);
  if (!process.env.GH_TOKEN && configAccount() && own && own[1] === repoOwner) process.exit(0);
}

// Fast-path: the host-alias account owns the target repo → allow.
// Zero API calls, zero `gh`, and crucially no ambient token required — this
// clears the common "writing to your own repo" case under the new model.
if (localAccount && localAccount === repoOwner) {
  process.exit(0);
}

// Fast-path: GH_ORGS env var (comma-separated org names the user belongs to)
// e.g. GH_ORGS="Eon-Labs,my-other-org"
const ghOrgs = process.env.GH_ORGS;
if (ghOrgs?.split(",").map(s => s.trim()).includes(repoOwner)) {
  process.exit(0); // Org match — allow immediately (zero API calls)
}

// Cross-account write attempt. Verify against an already-exported GH_TOKEN if
// present. Per the process-storm rule the hook never runs `gh` itself, so it
// cannot mint a token — if none is exported we cannot verify and fail open
// (the alias fast-path above already cleared the safe owner case). To enable
// the check, run: export GH_TOKEN=$(~/.claude/tools/bin/gh-token-for-repo)
const ghToken = process.env.GH_TOKEN || "";
if (!ghToken) {
  process.exit(0);
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

// If the origin host-alias named an account that didn't match the owner, note it
if (localAccount) {
  source = `origin alias github.com-${localAccount}`;
}

// ─── Check: authenticated user === repo owner → allow ───────────────────────
if (authenticatedUser === repoOwner) {
  process.exit(0);
}

// ─── Check repo visibility and permissions ──────────────────────────────────
let hasPush = false;
let isPublicRepo = false;
try {
  const repoResult = execSync(
    `curl -sf --max-time 5 -H "Authorization: token ${ghToken}" https://api.github.com/repos/${targetRepo}`,
    { encoding: "utf-8", timeout: 8000 }
  );
  const repoData = JSON.parse(repoResult);
  hasPush = repoData.permissions?.push === true;
  isPublicRepo = repoData.private === false;
} catch {
  // API failed — fail-open (gh CLI will fail itself if no access)
  process.exit(0);
}

if (hasPush) {
  process.exit(0); // Has push access — allow all operations
}

// Public-safe operations on public repos: any authenticated user can do these
if (isPublicSafe && isPublicRepo) {
  process.exit(0);
}

// ─── DENY ───────────────────────────────────────────────────────────────────
const action = isPushRequired ? "Push permission" : "Repo access";
const reason = `[gh-identity-guard] BLOCKED: Wrong GitHub account for ${targetRepo}

Authenticated as: ${authenticatedUser} (via ${source})
Target repository: ${targetRepo}
${action}: DENIED

Fix (ADR 2026-06-21 host-alias model):
  1. Check the origin alias names the right account:
       git remote get-url origin   # expect git@github.com-<account>:owner/repo
  2. If the alias is wrong, repoint it:
       git remote set-url origin git@github.com-${repoOwner}:${targetRepo}.git
  3. Export the matching token for this repo, then retry:
       export GH_TOKEN=$(~/.claude/tools/bin/gh-token-for-repo)`;

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
