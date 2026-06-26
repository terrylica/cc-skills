// identity.mjs — resolve WHICH GitHub account a token operation targets, reusing
// the host-alias SSoT (ADR 2026-06-21) so autonomous web-auth is multi-account.
//
// Resolution order: explicit --account → repo origin host-alias
// (git@github.com-<account>:…) → spec owner → null (caller uses logged-in).
//
// A tiny plaintext registry (logins only — NOT secret) records which accounts
// have autonomous web-auth provisioned, so `pat agent`/`register` can list them.

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const REGISTRY_PATH =
  process.env.GH_PAT_REGISTRY ?? join(homedir(), ".local", "share", "gh-pat-automation", "provisioned-accounts.json");

/** Pure: extract the account from an origin URL host-alias, or null. */
export function accountFromOriginUrl(url) {
  const m = /^git@github\.com-([A-Za-z0-9_-]+):/.exec(url ?? "");
  return m ? m[1] : null;
}

/** The single gated vault item holding an account's web credential blob. */
export const vaultItemName = (account) => `github-web-${account}`;

function originUrl(cwd) {
  try {
    return execFileSync("git", ["-C", cwd ?? process.cwd(), "remote", "get-url", "origin"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

/**
 * Resolve the target account. Returns { account, source }. account is null when
 * only the logged-in profile applies (caller falls back to whoever is signed in).
 */
export function resolveAccount({ account, owner, cwd } = {}) {
  if (account) return { account, source: "flag" };
  const alias = accountFromOriginUrl(originUrl(cwd));
  if (alias) return { account: alias, source: "host-alias" };
  if (owner) return { account: owner, source: "spec-owner" };
  return { account: null, source: "logged-in" };
}

// ---- provisioned-account registry (logins only, no secrets) -----------------
export function listProvisioned() {
  if (!existsSync(REGISTRY_PATH)) return [];
  try {
    const j = JSON.parse(readFileSync(REGISTRY_PATH, "utf8"));
    return Array.isArray(j.accounts) ? j.accounts : [];
  } catch {
    return [];
  }
}

export const isProvisioned = (account) => listProvisioned().includes(account);

export function addProvisioned(account) {
  const accounts = [...new Set([...listProvisioned(), account])].toSorted();
  mkdirSync(join(REGISTRY_PATH, ".."), { recursive: true });
  writeFileSync(REGISTRY_PATH, `${JSON.stringify({ accounts }, null, 2)}\n`, { mode: 0o600 });
  return accounts;
}
