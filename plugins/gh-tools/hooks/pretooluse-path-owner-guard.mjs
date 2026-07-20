#!/usr/bin/env bun
// pretooluse-path-owner-guard.mjs — block repo creation / remote changes / pushes
// that would send a repo to the WRONG GitHub owner for its local path.
//
// Incident: 2026-07-18 — ~/vj/cpc/scanners was created under personal `terrylica`
// instead of `vanjobbers` because `gh repo create … --source=. --push` ran with no
// `--owner` (gh defaulted to the token account) and no guard knew ~/vj → vanjobbers.
//
// This is a SIBLING to gh-repo-identity-guard.mjs (left untouched): that one guards
// gh issue/pr/label writes to EXISTING repos by host-alias; this one enforces the
// local-path → owner policy (SSoT: ~/.claude/path-owner-registry.toml) for the
// creation / remote-setup / push surface.
//
// Safety: no `gh`, no network — reads the registry file + local git only. FAIL-OPEN
// when the path is unmapped or the registry is unreadable. Escape hatch:
// ALLOW_OWNER_MISMATCH=1 <command>. Blocks via stdout permissionDecision:"deny".

import { execSync } from "child_process";
import { ownerFromGitUrl, resolveExpectedOwner } from "./lib/path-owner-registry.mjs";

const input = await Bun.stdin.text();
if (!input.trim()) process.exit(0);

let data;
try {
  data = JSON.parse(input);
} catch {
  process.exit(0);
}

if ((data.tool_name ?? "") !== "Bash") process.exit(0);
const command = data.tool_input?.command ?? "";
if (!command) process.exit(0);

// Deliberate escape hatch. The prefix form (`ALLOW_OWNER_MISMATCH=1 <command>`) lives INSIDE the
// command string — the hook process never inherits it — so detect it textually as well.
// (Bug found on first live fire, 2026-07-19: env-only check made the documented override a no-op.)
if (process.env.ALLOW_OWNER_MISMATCH === "1" || /\bALLOW_OWNER_MISMATCH=1\b/.test(command)) {
  process.exit(0);
}

const isRepoCreate = /\bgh\s+repo\s+create\b/.test(command);
const isRemoteSet = /\bgit\s+remote\s+(?:add|set-url)\b/.test(command);
const isPush = /\bgit\s+push\b/.test(command);
if (!isRepoCreate && !isRemoteSet && !isPush) process.exit(0);

const cwd = data.cwd || process.cwd();
const expected = resolveExpectedOwner(cwd);
if (!expected) process.exit(0); // unmapped path — fail-open

function ownerOk(actual) {
  if (!actual) return false;
  if (actual === expected.owner) return true;
  return expected.allowOrgs.includes(actual);
}

function deny(reason) {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason,
      },
    }),
  );
  process.exit(0);
}

const policyLine = `Policy: ${expected.matchedPrefix} → "${expected.owner}"${
  expected.allowOrgs.length ? ` (orgs also allowed: ${expected.allowOrgs.join(", ")})` : ""
} — SSoT ~/.claude/path-owner-registry.toml.
Deliberate override: prefix the command with ALLOW_OWNER_MISMATCH=1`;

// ─── gh repo create ─────────────────────────────────────────────────────────
if (isRepoCreate) {
  let actualOwner = null;
  let explicit = false;
  const ownerFlag = command.match(/--owner[=\s]+([A-Za-z0-9_.-]+)/);
  if (ownerFlag) {
    actualOwner = ownerFlag[1];
    explicit = true;
  } else {
    const after = command.split(/\bgh\s+repo\s+create\b/)[1] ?? "";
    for (const token of after.trim().split(/\s+/)) {
      if (!token || token.startsWith("-")) continue;
      if (token.includes("/")) {
        actualOwner = token.split("/")[0];
        explicit = true;
      }
      break; // first positional decides
    }
  }

  if (!explicit) {
    deny(`[path-owner-guard] BLOCKED: \`gh repo create\` in ${cwd} has no explicit owner, so it would
default to your authenticated token account — exactly the mistake that put a ~/vj repo on the wrong
account. Name the owner instead:
  gh repo create ${expected.owner}/<name> …
${policyLine}`);
  }
  if (!ownerOk(actualOwner)) {
    deny(`[path-owner-guard] BLOCKED: \`gh repo create\` targets owner "${actualOwner}", but ${cwd}
must use "${expected.owner}".
  Fix: gh repo create ${expected.owner}/<name> …
${policyLine}`);
  }
  process.exit(0);
}

// ─── git remote add|set-url ─────────────────────────────────────────────────
if (isRemoteSet) {
  const urlToken = command.match(/((?:git@|ssh:\/\/|https?:\/\/)[^\s]+)/);
  const actualOwner = urlToken ? ownerFromGitUrl(urlToken[1]) : null;
  if (actualOwner && !ownerOk(actualOwner)) {
    deny(`[path-owner-guard] BLOCKED: this remote points at owner "${actualOwner}", but ${cwd} must
use "${expected.owner}".
  Fix: git remote set-url origin git@github.com-${expected.owner}:${expected.owner}/<repo>.git
${policyLine}`);
  }
  process.exit(0);
}

// ─── git push ───────────────────────────────────────────────────────────────
if (isPush) {
  let target = "origin";
  const after = command.split(/\bgit\s+push\b/)[1] ?? "";
  for (const token of after.trim().split(/\s+/)) {
    if (!token || token.startsWith("-")) continue;
    target = token;
    break;
  }

  let actualOwner = null;
  if (/^(?:git@|ssh:\/\/|https?:\/\/)/.test(target)) {
    actualOwner = ownerFromGitUrl(target);
  } else {
    try {
      const url = execSync(`git remote get-url ${target} 2>/dev/null`, {
        encoding: "utf-8",
        timeout: 3000,
        cwd,
      }).trim();
      actualOwner = ownerFromGitUrl(url);
    } catch {
      // no such remote — fail-open
    }
  }

  if (actualOwner && !ownerOk(actualOwner)) {
    deny(`[path-owner-guard] BLOCKED: this push would go to owner "${actualOwner}", but ${cwd} must
use "${expected.owner}".
  Fix the remote: git remote set-url ${target} git@github.com-${expected.owner}:${expected.owner}/<repo>.git
${policyLine}`);
  }
  process.exit(0);
}
