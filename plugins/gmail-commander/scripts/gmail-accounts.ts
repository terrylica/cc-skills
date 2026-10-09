#!/usr/bin/env bun
/**
 * gmail-accounts — read-only report on the cached Gmail OAuth tokens: which mailbox each token
 * actually owns, which send-as aliases it may use (and which one is the DEFAULT), and when the
 * access token expires. Never prints a token.
 *
 * This is the sanctioned way to look inside ~/.claude/tools/gmail-tokens/. gmail-send-guard denies
 * cat/jq/python reads of that directory, because the files are bearer credentials for whole mailboxes.
 *
 * Why the DEFAULT alias matters: Gmail fills in the From line of any message sent without one from
 * the account's default send-as identity. On 2026-10-08 a raw send went out under the wrong identity
 * on two accounts for exactly that reason. Check the default before staging anything, and pass
 * --from to gmail-draft.ts whenever the default is not the identity you mean.
 *
 * Usage:
 *   bun gmail-accounts.ts                  # every cached account
 *   bun gmail-accounts.ts --account <id>   # one account (token base name)
 *   bun gmail-accounts.ts --json           # machine-readable
 *
 * It does not refresh tokens. An expired access token is reported as such; run any gmail CLI
 * command for that account (or wait for the hourly refresher) and re-run.
 */

import { readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const TOKENS_DIR = join(homedir(), ".claude", "tools", "gmail-tokens");
const API = "https://gmail.googleapis.com/gmail/v1/users/me";

interface SavedToken {
  access_token?: string;
  scope?: string;
  expiry_date?: number;
}
interface SendAs {
  sendAsEmail: string;
  displayName?: string;
  isDefault?: boolean;
  verificationStatus?: string;
}
interface AccountReport {
  account: string;
  status: "ok" | "expired" | "unreadable" | "error";
  mailbox?: string;
  expiresInMinutes?: number;
  scopes?: string[];
  sendAs?: {
    email: string;
    displayName: string;
    isDefault: boolean;
    verification: string;
  }[];
  error?: string;
}

function parseArgs(argv: string[]): { account?: string; json: boolean } {
  const out: { account?: string; json: boolean } = { json: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--json") out.json = true;
    else if (a === "--account") out.account = argv[++i];
    else if (a === "-h" || a === "--help") {
      console.log("usage: gmail-accounts.ts [--account <id>] [--json]");
      process.exit(0);
    } else {
      console.error(`unknown argument: ${a}`);
      process.exit(2);
    }
  }
  return out;
}

/** Token base names: <id>.json, excluding app credentials and backups. */
function listAccounts(): string[] {
  let names: string[];
  try {
    names = readdirSync(TOKENS_DIR);
  } catch {
    return [];
  }
  return names
    .filter((n) => n.endsWith(".json") && !n.endsWith(".app-credentials.json"))
    .map((n) => n.slice(0, -".json".length))
    .toSorted();
}

async function getJson<T>(url: string, token: string): Promise<T> {
  const r = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(15_000),
  });
  if (!r.ok) throw new Error(`HTTP ${r.status} from ${url.replace(API, "")}`);
  return (await r.json()) as T;
}

async function report(account: string): Promise<AccountReport> {
  let tok: SavedToken;
  try {
    tok = JSON.parse(
      readFileSync(join(TOKENS_DIR, `${account}.json`), "utf8"),
    ) as SavedToken;
  } catch (e) {
    return { account, status: "unreadable", error: (e as Error).message };
  }
  const scopes = (tok.scope ?? "")
    .split(/\s+/)
    .filter(Boolean)
    .map((s) => s.replace("https://www.googleapis.com/auth/", ""));
  const expiresInMinutes = tok.expiry_date
    ? Math.round((tok.expiry_date - Date.now()) / 60_000)
    : undefined;
  if (
    !tok.access_token ||
    (expiresInMinutes !== undefined && expiresInMinutes <= 0)
  ) {
    return { account, status: "expired", scopes, expiresInMinutes };
  }
  try {
    const profile = await getJson<{ emailAddress: string }>(
      `${API}/profile`,
      tok.access_token,
    );
    const base: AccountReport = {
      account,
      status: "ok",
      mailbox: profile.emailAddress,
      scopes,
      expiresInMinutes,
    };
    try {
      const sa = await getJson<{ sendAs?: SendAs[] }>(
        `${API}/settings/sendAs`,
        tok.access_token,
      );
      base.sendAs = (sa.sendAs ?? []).map((s) => ({
        email: s.sendAsEmail,
        displayName: s.displayName ?? "",
        isDefault: Boolean(s.isDefault),
        verification:
          s.verificationStatus ??
          (s.sendAsEmail === profile.emailAddress ? "primary" : "unknown"),
      }));
    } catch (e) {
      base.error = `send-as list unavailable: ${(e as Error).message}`;
    }
    return base;
  } catch (e) {
    return {
      account,
      status: "error",
      scopes,
      expiresInMinutes,
      error: (e as Error).message,
    };
  }
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const accounts = args.account ? [args.account] : listAccounts();
  if (accounts.length === 0) {
    console.error(`no cached Gmail tokens in ${TOKENS_DIR}`);
    process.exit(1);
  }
  const reports = await Promise.all(accounts.map(report));
  if (args.json) {
    console.log(JSON.stringify(reports, null, 2));
    return;
  }
  for (const r of reports) {
    const exp =
      r.expiresInMinutes === undefined
        ? ""
        : ` (access token ${r.expiresInMinutes > 0 ? `expires in ${r.expiresInMinutes} min` : "expired"})`;
    console.log(`${r.account} → ${r.mailbox ?? r.status}${exp}`);
    if (r.scopes?.length) console.log(`  scopes: ${r.scopes.join(", ")}`);
    for (const s of r.sendAs ?? []) {
      const name = s.displayName ? `"${s.displayName}" ` : "";
      console.log(
        `  send-as: ${name}<${s.email}>  ${s.verification}${s.isDefault ? "  DEFAULT (used when no From line is set)" : ""}`,
      );
    }
    if (r.error) console.log(`  note: ${r.error}`);
  }
}

await main();
