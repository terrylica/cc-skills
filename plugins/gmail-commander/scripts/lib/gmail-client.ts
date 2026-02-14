// PROCESS-STORM-OK — Gmail CLI subprocess wrapper (intentional Bun.spawn)
/**
 * Gmail CLI Wrapper
 *
 * Thin wrapper around the gmail-cli binary (absorbed from gmail-tools).
 * Fetches emails via subprocess, returns typed objects.
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

import { auditLog } from "./audit.js";
import { join } from "path";

/** Resolve the gmail CLI binary path relative to this plugin */
function getGmailCli(): string {
  const pluginPath = join(
    process.env.HOME || "~",
    ".claude", "plugins", "marketplaces", "cc-skills",
    "plugins", "gmail-commander", "scripts", "gmail-cli", "gmail"
  );
  return pluginPath;
}

export interface Email {
  id: string;
  from: string;
  to: string;
  subject: string;
  date: string;
  labels: string[];
  snippet: string;
}

export interface DraftOptions {
  to: string;
  subject: string;
  body: string;
  from?: string;
  replyTo?: string;
}

async function runGmailCli(args: string[]): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  const opUuid = Bun.env.GMAIL_OP_UUID;
  if (!opUuid) throw new Error("GMAIL_OP_UUID not set");

  const proc = Bun.spawn([getGmailCli(), ...args], {
    env: { ...process.env, GMAIL_OP_UUID: opUuid },
    stdout: "pipe",
    stderr: "pipe",
  });

  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const exitCode = await proc.exited;
  return { stdout, stderr, exitCode };
}

function parseEmailJson(stdout: string): Email[] {
  try {
    const emails = JSON.parse(stdout);
    return Array.isArray(emails) ? emails : [];
  } catch {
    return [];
  }
}

export async function fetchRecentEmails(hours: number): Promise<Email[]> {
  const { stdout, stderr, exitCode } = await runGmailCli(
    ["search", `newer_than:${hours}h`, "-n", "50", "--json"]
  );
  if (exitCode !== 0) {
    auditLog("gmail.error", { exitCode, stderr: stderr.slice(0, 500) });
    throw new Error(`Gmail CLI failed (exit ${exitCode}): ${stderr.slice(0, 200)}`);
  }
  return parseEmailJson(stdout);
}

export async function readEmail(messageId: string): Promise<string> {
  const { stdout } = await runGmailCli(["read", messageId]);
  return stdout;
}

export async function searchEmails(query: string, count: number = 10): Promise<Email[]> {
  const { stdout, stderr, exitCode } = await runGmailCli(
    ["search", query, "-n", String(count), "--json"]
  );
  if (exitCode !== 0) {
    auditLog("gmail.search_error", { exitCode, stderr: stderr.slice(0, 500) });
    throw new Error(`Gmail search failed (exit ${exitCode}): ${stderr.slice(0, 200)}`);
  }
  return parseEmailJson(stdout);
}

export async function listInboxEmails(count: number = 10): Promise<Email[]> {
  const { stdout, stderr, exitCode } = await runGmailCli(
    ["list", "-n", String(count), "--json"]
  );
  if (exitCode !== 0) {
    auditLog("gmail.list_error", { exitCode, stderr: stderr.slice(0, 500) });
    throw new Error(`Gmail list failed (exit ${exitCode}): ${stderr.slice(0, 200)}`);
  }
  return parseEmailJson(stdout);
}

export async function listDrafts(count: number = 10): Promise<Email[]> {
  return searchEmails("in:drafts", count);
}

export async function createDraft(opts: DraftOptions): Promise<string> {
  const args = ["draft", "--to", opts.to, "--subject", opts.subject, "--body", opts.body];
  if (opts.from) args.push("--from", opts.from);
  if (opts.replyTo) args.push("--reply-to", opts.replyTo);

  const { stdout, stderr, exitCode } = await runGmailCli(args);
  if (exitCode !== 0) {
    auditLog("gmail.draft_error", { exitCode, stderr: stderr.slice(0, 500) });
    throw new Error(`Gmail draft failed (exit ${exitCode}): ${stderr.slice(0, 200)}`);
  }
  return stdout;
}
