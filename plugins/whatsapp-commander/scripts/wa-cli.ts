#!/usr/bin/env bun
/**
 * wa-cli.ts — WhatsApp messaging helper for Claude Code.
 *
 * WhatsApp has NO sanctioned personal-account send API (unlike Telegram's
 * MTProto or Gmail's OAuth API), so this CLI exposes the two realistic,
 * Terms-of-Service-safe tiers as enum-keyed handler functions:
 *
 *   Command.Link — Tier 1 (default): build a wa.me click-to-chat deep link with
 *                  the message pre-filled. No credentials; the human taps Send.
 *   Command.Send — Tier 3: send a text via the WhatsApp Business Cloud API,
 *                  reading credentials from the environment (resolve via 1Password).
 *
 * Function-driven + enum-driven by design (see plugin convention).
 */

import { readFile } from "node:fs/promises";
import process from "node:process";

enum Command {
  Link = "link",
  Send = "send",
}

enum ExitCode {
  Ok = 0,
  Failure = 1,
  Usage = 2,
}

enum EnvVar {
  Token = "WHATSAPP_TOKEN",
  PhoneNumberId = "WHATSAPP_PHONE_NUMBER_ID",
  GraphVersion = "WHATSAPP_GRAPH_VERSION",
}

const DEFAULT_GRAPH_VERSION = "v21.0";
const MIN_E164_DIGITS = 8;

interface MessageRequest {
  readonly number: string;
  readonly text: string;
}

interface CloudCreds {
  readonly token: string;
  readonly phoneNumberId: string;
  readonly graphVersion: string;
}

/** Caller-fixable input problem → exit code 2. */
class UsageError extends Error {}

/** Remote API rejected the request → exit code 1. */
class ApiError extends Error {}

/** Strip every non-digit: "+1 (604) 816-8818" → "16048168818" (E.164, no plus). */
function normalizeNumber(raw: string): string {
  const digits = raw.replace(/\D+/g, "");
  if (digits.length < MIN_E164_DIGITS) {
    throw new UsageError(
      `number "${raw}" has too few digits — pass full international format incl. country code`,
    );
  }
  return digits;
}

/** Past this the wa.me landing-page preview scrolls and *looks* truncated — keep bodies concise. */
const MAX_TIER1_CHARS = 700;

/**
 * Codepoints that break a Tier-1 wa.me deep link: astral-plane (> U+FFFF) and emoji
 * selectors/blocks arrive on the recipient's side as U+FFFD (a diamond-`?`), even though
 * the URL is valid UTF-8. BMP text — including all CJK — survives. Returns the distinct
 * offending codepoints (as `U+XXXX`), empty if the body is safe.
 */
function astralOffenders(text: string): readonly string[] {
  const bad = new Set<string>();
  for (const ch of text) {
    const cp = ch.codePointAt(0) ?? 0;
    const isAstral = cp > 0xffff;
    const isEmojiSelector = cp === 0xfe0f || cp === 0x20e3;
    const isEmojiBlock = cp >= 0x1f000 || (cp >= 0x2600 && cp <= 0x27bf);
    if (isAstral || isEmojiSelector || isEmojiBlock) {
      bad.add(`U+${cp.toString(16).toUpperCase().padStart(4, "0")}`);
    }
  }
  return [...bad];
}

/**
 * Non-fatal structural smells that make the wa.me landing-page PREVIEW look truncated
 * (the box is a fixed scrollable preview — the link still carries the whole body). Each is
 * a lesson from a real round-trip: a bare "1" line reads as a cut-off message; a trailing
 * "——" reads as a dangling "-- 1"; over-length bodies scroll out of view.
 */
function bodyWarnings(text: string): readonly string[] {
  const warnings: string[] = [];
  if (text.length > MAX_TIER1_CHARS) {
    warnings.push(
      `body is ${text.length} chars (> ${MAX_TIER1_CHARS}); the wa.me preview scrolls and looks cut off — trim, or inline the list`,
    );
  }
  const lines = text.split("\n");
  for (const [index, line] of lines.entries()) {
    if (/^\s*\d+[.)]?\s*$/.test(line)) {
      warnings.push(
        `line ${index + 1} is a lone list number ("${line.trim()}") — looks truncated in the preview; inline it as (1)/(2)`,
      );
    }
    if (/[—–-]{2,}\s*$/.test(line)) {
      warnings.push(
        `line ${index + 1} ends with a dash run — reads as a dangling "-- 1"; use a colon lead-in instead`,
      );
    }
  }
  return warnings;
}

/** Decode what we just encoded and assert it survived intact — proves link completeness. */
function assertLinkRoundTrips(url: string, source: string): void {
  const marker = "?text=";
  const at = url.indexOf(marker);
  const decoded = at >= 0 ? decodeURIComponent(url.slice(at + marker.length)) : "";
  if (decoded !== source) {
    throw new ApiError(
      `link round-trip mismatch: decoded ${decoded.length} chars vs source ${source.length} — refusing to emit a corrupted link`,
    );
  }
}

/** Tier 1: a wa.me deep link with URL-encoded pre-filled text. Always available. */
function buildWaLink(request: MessageRequest): string {
  const number = normalizeNumber(request.number);
  const offenders = astralOffenders(request.text);
  if (offenders.length > 0) {
    throw new UsageError(
      `body has emoji / astral chars that become "�" on the wa.me path: ${offenders.join(", ")}. ` +
        "Keep Tier-1 bodies BMP-only — headings 【】, bullets -, numbering (1)/(2).",
    );
  }
  const url = `https://wa.me/${number}?text=${encodeURIComponent(request.text)}`;
  assertLinkRoundTrips(url, request.text);
  for (const warning of bodyWarnings(request.text)) {
    process.stderr.write(`warning: ${warning}\n`);
  }
  process.stderr.write(`✓ link carries the full ${request.text.length}-char body (round-trip verified)\n`);
  return url;
}

function resolveCloudCreds(): CloudCreds {
  const token = process.env[EnvVar.Token] ?? "";
  const phoneNumberId = process.env[EnvVar.PhoneNumberId] ?? "";
  const graphVersion = process.env[EnvVar.GraphVersion] ?? DEFAULT_GRAPH_VERSION;
  if (token === "" || phoneNumberId === "") {
    throw new UsageError(
      `Cloud API send needs ${EnvVar.Token} and ${EnvVar.PhoneNumberId} in the environment ` +
        "(resolve via 1Password). Use the `link` command for the no-credential path.",
    );
  }
  return { token, phoneNumberId, graphVersion };
}

/** Tier 3: send a text message via the WhatsApp Business Cloud API. */
async function sendViaCloudApi(request: MessageRequest): Promise<string> {
  const creds = resolveCloudCreds();
  const url = `https://graph.facebook.com/${creds.graphVersion}/${creds.phoneNumberId}/messages`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${creds.token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: normalizeNumber(request.number),
      type: "text",
      text: { preview_url: true, body: request.text },
    }),
  });
  const payload = await response.text();
  if (!response.ok) {
    throw new ApiError(`Cloud API HTTP ${response.status}: ${payload}`);
  }
  return payload;
}

type Handler = (request: MessageRequest) => Promise<string>;

/** Enum-keyed dispatch table — adding a Command forces a handler here. */
const HANDLERS: Record<Command, Handler> = {
  [Command.Link]: (request) => Promise.resolve(buildWaLink(request)),
  [Command.Send]: (request) => sendViaCloudApi(request),
};

interface ParsedArgs {
  readonly command: Command;
  readonly number: string;
  readonly text: string;
}

function parseCommand(value: string | undefined): Command {
  for (const candidate of Object.values(Command)) {
    if (candidate === value) {
      return candidate;
    }
  }
  throw new UsageError(
    `unknown command "${value ?? ""}" — use one of: ${Object.values(Command).join(", ")}`,
  );
}

async function readMessageText(
  positional: string,
  filePath: string | undefined,
): Promise<string> {
  if (filePath !== undefined) {
    return (await readFile(filePath, "utf8")).trimEnd();
  }
  if (positional !== "") {
    return positional;
  }
  throw new UsageError("no message text — pass it as an argument or via --file <path>");
}

async function parseArgs(argv: readonly string[]): Promise<ParsedArgs> {
  const command = parseCommand(argv[0]);
  const number = argv[1] ?? "";
  if (number === "") {
    throw new UsageError("missing recipient number (international format)");
  }
  let filePath: string | undefined;
  const positionals: string[] = [];
  for (let index = 2; index < argv.length; index += 1) {
    const arg = argv[index] ?? "";
    if (arg === "--file" || arg === "--body-file") {
      filePath = argv[index + 1];
      index += 1;
    } else {
      positionals.push(arg);
    }
  }
  const text = await readMessageText(positionals.join(" "), filePath);
  return { command, number, text };
}

const USAGE = `wa-cli.ts — WhatsApp messaging helper

Usage:
  bun wa-cli.ts link <number> <message>        Build a wa.me click-to-chat link (no credentials)
  bun wa-cli.ts link <number> --file <path>    …with the message body read from a file
  bun wa-cli.ts send <number> <message>        Send via WhatsApp Business Cloud API (creds in env)

Numbers accept any format; non-digits are stripped (always include the country code).
`;

async function main(): Promise<ExitCode> {
  const argv = process.argv.slice(2);
  const first = argv[0];
  if (first === undefined || first === "-h" || first === "--help") {
    process.stdout.write(USAGE);
    return ExitCode.Ok;
  }
  const { command, number, text } = await parseArgs(argv);
  const output = await HANDLERS[command]({ number, text });
  process.stdout.write(`${output}\n`);
  return ExitCode.Ok;
}

main()
  .then((code) => process.exit(code))
  .catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${message}\n`);
    process.exit(error instanceof UsageError ? ExitCode.Usage : ExitCode.Failure);
  });
