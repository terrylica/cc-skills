/**
 * Gmail API client wrapper
 *
 * Uses @googleapis/gmail for lighter dependency footprint
 */

import { gmail, type gmail_v1 } from "@googleapis/gmail";
import { getAuthClient } from "./auth.ts";
import type { Email, ListOptions, SearchOptions, ExportOptions } from "./types.ts";

/**
 * Create authenticated Gmail API service
 */
export async function createGmailClient(): Promise<gmail_v1.Gmail> {
  const auth = await getAuthClient();
  return gmail({ version: "v1", auth });
}

/**
 * Extract header value from message headers
 */
function getHeader(headers: gmail_v1.Schema$MessagePartHeader[] | undefined, name: string): string {
  if (!headers) return "";
  const header = headers.find((h) => h.name?.toLowerCase() === name.toLowerCase());
  return header?.value ?? "";
}

/**
 * Recursively parse email body from MIME payload
 */
function parseBody(payload: gmail_v1.Schema$MessagePart | undefined): string {
  if (!payload) return "";

  // Direct body data
  if (payload.body?.data) {
    return Buffer.from(payload.body.data, "base64url").toString("utf-8");
  }

  // Multipart message - prefer text/plain, fallback to text/html
  if (payload.parts) {
    for (const part of payload.parts) {
      if (part.mimeType === "text/plain" && part.body?.data) {
        return Buffer.from(part.body.data, "base64url").toString("utf-8");
      }
    }
    for (const part of payload.parts) {
      if (part.mimeType === "text/html" && part.body?.data) {
        return Buffer.from(part.body.data, "base64url").toString("utf-8");
      }
      if (part.mimeType?.startsWith("multipart/")) {
        const nested = parseBody(part);
        if (nested) return nested;
      }
    }
  }

  return "";
}

/**
 * Transform Gmail API message to Email type
 */
function formatMessage(msg: gmail_v1.Schema$Message, includeBody = false): Email {
  const headers = msg.payload?.headers;

  return {
    id: msg.id ?? "",
    threadId: msg.threadId ?? "",
    snippet: msg.snippet ?? "",
    from: getHeader(headers, "From"),
    to: getHeader(headers, "To"),
    cc: getHeader(headers, "Cc"),
    subject: getHeader(headers, "Subject"),
    date: getHeader(headers, "Date"),
    labels: msg.labelIds ?? [],
    ...(includeBody && { body: parseBody(msg.payload) }),
  };
}

/**
 * Fetch full message details for a list of message IDs (parallel)
 */
async function fetchMessages(
  client: gmail_v1.Gmail,
  messageIds: string[],
  includeBody = false
): Promise<Email[]> {
  return Promise.all(
    messageIds.map(async (id) => {
      const res = await client.users.messages.get({
        userId: "me",
        id,
        format: includeBody ? "full" : "metadata",
        metadataHeaders: ["From", "To", "Cc", "Subject", "Date"],
      });
      return formatMessage(res.data, includeBody);
    })
  );
}

/**
 * List recent emails
 */
export async function listEmails(client: gmail_v1.Gmail, options: ListOptions): Promise<Email[]> {
  const res = await client.users.messages.list({
    userId: "me",
    maxResults: options.maxResults,
    labelIds: options.labelIds,
  });

  const messageIds = res.data.messages?.map((m) => m.id!) ?? [];
  return fetchMessages(client, messageIds);
}

/**
 * Search emails using Gmail query syntax
 */
export async function searchEmails(client: gmail_v1.Gmail, options: SearchOptions): Promise<Email[]> {
  const res = await client.users.messages.list({
    userId: "me",
    q: options.query,
    maxResults: options.maxResults,
  });

  const messageIds = res.data.messages?.map((m) => m.id!) ?? [];
  return fetchMessages(client, messageIds);
}

/**
 * Read single email with full body
 */
export async function readEmail(client: gmail_v1.Gmail, messageId: string): Promise<Email | null> {
  try {
    const res = await client.users.messages.get({
      userId: "me",
      id: messageId,
      format: "full",
    });
    return formatMessage(res.data, true);
  } catch (err) {
    console.error("Error reading email:", err);
    return null;
  }
}

/**
 * Export emails to JSON file
 */
export async function exportEmails(
  client: gmail_v1.Gmail,
  options: ExportOptions,
  onProgress?: (current: number, total: number) => void
): Promise<Email[]> {
  const res = await client.users.messages.list({
    userId: "me",
    q: options.query,
    maxResults: options.maxResults,
  });

  const messageIds = res.data.messages?.map((m) => m.id!) ?? [];
  const total = messageIds.length;

  // Fetch with progress reporting
  const emails: Email[] = [];
  for (let i = 0; i < messageIds.length; i++) {
    const msg = await client.users.messages.get({
      userId: "me",
      id: messageIds[i],
      format: "full",
    });
    emails.push(formatMessage(msg.data, true));
    onProgress?.(i + 1, total);
  }

  await Bun.write(options.outputPath, JSON.stringify(emails, null, 2));
  return emails;
}

/**
 * Create RFC 2822 formatted email for Gmail API
 */
function createRawEmail(
  to: string,
  subject: string,
  body: string,
  inReplyTo?: string
): string {
  const headers = [
    `To: ${to}`,
    `Subject: ${subject}`,
    "Content-Type: text/plain; charset=utf-8",
  ];

  if (inReplyTo) {
    headers.push(`In-Reply-To: ${inReplyTo}`);
    headers.push(`References: ${inReplyTo}`);
  }

  const email = headers.join("\r\n") + "\r\n\r\n" + body;
  return Buffer.from(email).toString("base64url");
}

export interface DraftOptions {
  to: string;
  subject: string;
  body: string;
  replyToMessageId?: string;
}

export interface DraftResult {
  draftId: string;
  messageId: string;
  threadId?: string;
}

/**
 * Create a Gmail draft
 */
export async function createDraft(
  client: gmail_v1.Gmail,
  options: DraftOptions
): Promise<DraftResult> {
  let threadId: string | undefined;
  let inReplyTo: string | undefined;

  // If replying, get the original message's thread and Message-ID header
  if (options.replyToMessageId) {
    const original = await client.users.messages.get({
      userId: "me",
      id: options.replyToMessageId,
      format: "metadata",
      metadataHeaders: ["Message-ID"],
    });
    threadId = original.data.threadId ?? undefined;
    const msgIdHeader = original.data.payload?.headers?.find(
      (h) => h.name === "Message-ID"
    );
    inReplyTo = msgIdHeader?.value ?? undefined;
  }

  const raw = createRawEmail(options.to, options.subject, options.body, inReplyTo);

  const res = await client.users.drafts.create({
    userId: "me",
    requestBody: {
      message: {
        raw,
        threadId,
      },
    },
  });

  return {
    draftId: res.data.id!,
    messageId: res.data.message?.id!,
    threadId: res.data.message?.threadId ?? undefined,
  };
}
