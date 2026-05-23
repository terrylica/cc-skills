/**
 * Gmail API client wrapper — read-side core (list / search / read / export).
 *
 * Split history (task #27 v1.7 polish):
 *   - Inline image *download* lives in `gmail-images.ts` (heavyweight
 *     fetch-to-disk path). The light `extractInlineImages` summary helper
 *     stays here because `formatMessage` calls it on every read to
 *     populate `Email.inlineImages`.
 *   - Draft create / list / update / delete + the multipart/mixed MIME
 *     builder live in `gmail-drafts.ts`.
 *
 * Public re-exports of all three modules live in `lib/index.ts`.
 *
 * Uses @googleapis/gmail for lighter dependency footprint.
 */

import { gmail, type gmail_v1 } from "@googleapis/gmail";
import { getAuthClient } from "./auth.ts";
import type { Email, InlineImage, ListOptions, SearchOptions, ExportOptions } from "./types.ts";

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
    const textPart = payload.parts.find((p) => p.mimeType === "text/plain");
    if (textPart) return parseBody(textPart);

    const htmlPart = payload.parts.find((p) => p.mimeType === "text/html");
    if (htmlPart) return parseBody(htmlPart);

    // Recurse into nested multipart
    for (const part of payload.parts) {
      const body = parseBody(part);
      if (body) return body;
    }
  }

  return "";
}

/**
 * Extract inline images from MIME payload.
 *
 * Walks the MIME tree, identifying image/* parts with attachmentId references.
 * Copy-pasted screenshots in compose typically appear as image/png parts
 * with attachmentId set, even though they're not "real" attachments in the
 * UI sense.
 */
function extractInlineImages(payload: gmail_v1.Schema$MessagePart | undefined): InlineImage[] {
  const images: InlineImage[] = [];
  if (!payload) return images;

  function walk(part: gmail_v1.Schema$MessagePart): void {
    if (part.mimeType?.startsWith("image/") && part.body?.attachmentId) {
      images.push({
        attachmentId: part.body.attachmentId,
        mimeType: part.mimeType,
        filename: part.filename || `image.${mimeToExt(part.mimeType)}`,
        contentId: getHeader(part.headers, "Content-Id").replace(/^<|>$/g, ""),
        size: part.body.size ?? 0,
        partId: part.partId ?? "",
      });
    }
    if (part.parts) {
      for (const child of part.parts) {
        walk(child);
      }
    }
  }

  walk(payload);
  return images;
}

/**
 * Map MIME type to file extension
 */
function mimeToExt(mimeType: string): string {
  const map: Record<string, string> = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/gif": "gif",
    "image/webp": "webp",
    "image/bmp": "bmp",
    "image/svg+xml": "svg",
    "image/tiff": "tiff",
  };
  return map[mimeType] ?? "bin";
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
    ...(includeBody && { inlineImages: extractInlineImages(msg.payload) }),
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
 * Read single email with full body.
 *
 * Errors (404 for missing IDs, 401 for expired tokens, network failures)
 * propagate to the CLI's top-level error handler where they're rendered
 * with HTTP status + URL + actionable hint. Previously this function
 * swallowed errors and returned null, which forced the CLI to render
 * a generic "Email not found" regardless of the real cause.
 */
export async function readEmail(client: gmail_v1.Gmail, messageId: string): Promise<Email | null> {
  const res = await client.users.messages.get({
    userId: "me",
    id: messageId,
    format: "full",
  });
  return formatMessage(res.data, true);
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
  const emails: Email[] = [];

  for (let i = 0; i < messageIds.length; i++) {
    const msg = await client.users.messages.get({
      userId: "me",
      id: messageIds[i],
      format: "full",
    });
    emails.push(formatMessage(msg.data, true));
    onProgress?.(i + 1, messageIds.length);
  }

  return emails;
}
