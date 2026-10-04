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
import { ownerFromGitUrl, reservedNames, resolveExpectedOwner } from "./lib/path-owner-registry.mjs";

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

/** The owner/name a `gh repo create` targets, from --owner or the first positional `owner/name`. */
function repoCreateTarget() {
  const after = command.split(/\bgh\s+repo\s+create\b/)[1] ?? "";
  let owner = null;
  let name = null;
  for (const token of after.trim().split(/\s+/)) {
    if (!token || token.startsWith("-")) continue;
    if (token.includes("/")) [owner, name] = token.split("/");
    else name = token;
    break; // first positional decides
  }
  const ownerFlag = command.match(/--owner[=\s]+([A-Za-z0-9_.-]+)/);
  if (ownerFlag) owner = ownerFlag[1];
  return { owner, name, explicit: Boolean(owner) };
}

// Reserved names apply wherever the command runs: a repo named like one that moved away from a
// renamed account would break GitHub's redirect for the moved repo (registry [reserved]).
if (isRepoCreate) {
  const { owner, name } = repoCreateTarget();
  if (owner && name && reservedNames()[owner]?.has(name)) {
    deny(`[path-owner-guard] BLOCKED: "${owner}/${name}" is a reserved name. A repository with that name
used to live under the account now called "${owner}" and moved away; GitHub redirects the old URL only
while no repository of the same name exists there. Creating one would break that redirect.
Pick another name or owner. SSoT: ~/.claude/path-owner-registry.toml [reserved].
Deliberate override: prefix the command with ALLOW_OWNER_MISMATCH=1`);
  }
}

const cwd = data.cwd || process.cwd();
const expected = resolveExpectedOwner(cwd);
if (!expected) process.exit(0); // unmapped path — fail-open

// A read-only path (a third-party clone kept for reference) is never pushed or re-pointed.
if (expected.mode === "read-only" && (isPush || isRemoteSet)) {
  deny(`[path-owner-guard] BLOCKED: ${cwd} is registered read-only (${expected.matchedPrefix}, owner
"${expected.owner}"): it is a reference clone, never pushed or re-pointed.
SSoT: ~/.claude/path-owner-registry.toml. Deliberate override: prefix the command with ALLOW_OWNER_MISMATCH=1`);
}

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
  const { owner: actualOwner, explicit } = repoCreateTarget();

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
