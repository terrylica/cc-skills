// FILE-SIZE-OK: this file is the single Gmail API surface for the CLI —
// list/search/read/export + draft create/list/update/delete + MIME builder
// + image-attachment download. Splitting along those seams (e.g. into
// gmail-read.ts / gmail-draft.ts / gmail-mime.ts) is a tracked follow-up;
// for now we keep it monolithic so the public surface stays in one place
// and the type imports don't fan out across files. Re-evaluate split when
// this file approaches the 1000-line hard cap.

/**
 * Gmail API client wrapper
 *
 * Uses @googleapis/gmail for lighter dependency footprint
 */

import { gmail, type gmail_v1 } from "@googleapis/gmail";
import { getAuthClient } from "./auth.ts";
import type { Email, InlineImage, SavedImage, ReadOptions, ListOptions, SearchOptions, ExportOptions } from "./types.ts";
import { getImageDir } from "./config.ts";
import { mkdir, writeFile } from "node:fs/promises";
import { join, basename } from "node:path";

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
 * Recursively extract inline image metadata from MIME payload
 * Collects image/* parts that have an attachmentId (Gmail stores large inline images as attachments)
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
 * Fetch attachment data from Gmail API
 */
async function fetchAttachmentData(
  client: gmail_v1.Gmail,
  messageId: string,
  attachmentId: string
): Promise<Buffer> {
  const res = await client.users.messages.attachments.get({
    userId: "me",
    messageId,
    id: attachmentId,
  });
  return Buffer.from(res.data.data!, "base64url");
}

/**
 * Sanitize filename with zero-padded index to avoid collisions
 * Copy-pasted images often share the same generic name (e.g. "image.png")
 */
function sanitizeFilename(filename: string, index: number): string {
  const safe = basename(filename).replace(/[^a-zA-Z0-9._-]/g, "_");
  const pad = String(index + 1).padStart(2, "0");
  return `${pad}_${safe}`;
}

/**
 * Download all inline images from an email to disk
 * Returns SavedImage[] with file paths and ready-to-paste markdown references
 */
export async function saveInlineImages(
  client: gmail_v1.Gmail,
  email: Email,
  outputDir?: string,
  onProgress?: (current: number, total: number) => void
): Promise<SavedImage[]> {
  const images = email.inlineImages;
  if (!images || images.length === 0) return [];

  const dir = outputDir ?? getImageDir(email.id);
  await mkdir(dir, { recursive: true });

  const saved: SavedImage[] = [];
  for (let i = 0; i < images.length; i++) {
    const img = images[i];
    const filename = sanitizeFilename(img.filename, i);
    const filePath = join(dir, filename);
    const data = await fetchAttachmentData(client, email.id, img.attachmentId);
    await writeFile(filePath, data);
    saved.push({
      image: img,
      savedPath: filePath,
      bytesWritten: data.length,
      markdownRef: `![${filename}](${filePath})`,
    });
    onProgress?.(i + 1, images.length);
  }

  return saved;
}

/**
 * Read email with optional inline image download
 * Convenience wrapper combining readEmail + saveInlineImages
 */
export async function readEmailWithImages(
  client: gmail_v1.Gmail,
  messageId: string,
  options?: ReadOptions
): Promise<{ email: Email; savedImages: SavedImage[] } | null> {
  const email = await readEmail(client, messageId);
  if (!email) return null;

  let savedImages: SavedImage[] = [];
  if (options?.saveImages) {
    savedImages = await saveInlineImages(client, email, options.outputDir);
  }
  return { email, savedImages };
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
 * Guess MIME type from filename extension.
 *
 * Used by the attachment builder when callers don't specify a type
 * explicitly. The lookup table covers the file types we expect to see in
 * day-to-day clinical / engineering communication (PDFs, screenshots,
 * spreadsheets, archives). Everything else falls back to the safe
 * default `application/octet-stream`, which Gmail renders as a generic
 * download attachment with no preview.
 */
function guessMimeType(filename: string): string {
  const ext = filename.toLowerCase().split(".").pop() ?? "";
  const map: Record<string, string> = {
    pdf: "application/pdf",
    png: "image/png",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    gif: "image/gif",
    webp: "image/webp",
    svg: "image/svg+xml",
    txt: "text/plain",
    md: "text/markdown",
    json: "application/json",
    html: "text/html",
    htm: "text/html",
    csv: "text/csv",
    xml: "application/xml",
    zip: "application/zip",
    gz: "application/gzip",
    tar: "application/x-tar",
    doc: "application/msword",
    docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    xls: "application/vnd.ms-excel",
    xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ppt: "application/vnd.ms-powerpoint",
    pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    mp3: "audio/mpeg",
    mp4: "video/mp4",
    wav: "audio/wav",
  };
  return map[ext] ?? "application/octet-stream";
}

/**
 * Encode a single attachment file as a multipart MIME part.
 *
 * Reads the file via Bun.file, base64-encodes the bytes, and wraps to
 * the 76-character line limit required by RFC 2045 (some Gmail / older
 * mail clients reject longer lines with a "format" error).
 */
async function buildAttachmentPart(filePath: string): Promise<string> {
  const file = Bun.file(filePath);
  if (!(await file.exists())) {
    throw new Error(`Attachment not found: ${filePath}`);
  }
  const filename = basename(filePath);
  const mimeType = guessMimeType(filename);
  const bytes = Buffer.from(await file.arrayBuffer());
  const b64 = bytes.toString("base64");
  // RFC 2045 §6.8: base64 lines MUST be ≤ 76 chars
  const wrapped = b64.match(/.{1,76}/g)?.join("\r\n") ?? b64;

  // Quote the filename in case it contains spaces / commas.
  const safeName = filename.replace(/"/g, '\\"');

  return [
    `Content-Type: ${mimeType}; name="${safeName}"`,
    "Content-Transfer-Encoding: base64",
    `Content-Disposition: attachment; filename="${safeName}"`,
    "",
    wrapped,
  ].join("\r\n");
}

/**
 * Build an RFC 2822 / 5322 formatted email and base64url-encode it for
 * the Gmail API's `raw` field.
 *
 * Two shapes:
 *   - No attachments → simple `text/plain` body, headers + blank line + body
 *   - With attachments → `multipart/mixed` with one text/plain part and one
 *     part per attachment file (base64-encoded)
 *
 * The async signature is required by attachment file reads. The no-
 * attachment fast path still resolves in a single tick.
 *
 * Threading (RFC 5322 §3.6.4):
 *   - `inReplyTo` is the parent message's Message-ID, written as-is.
 *   - `references` is the chain of ancestor Message-IDs, space-separated,
 *     oldest first. Callers (see createDraft) construct this as the
 *     parent's References header + " " + parent's Message-ID.
 *   - If `inReplyTo` is provided but `references` is omitted, falls back
 *     to References = In-Reply-To (the direct-reply degenerate case).
 *     Deep-thread replies should always provide `references` to keep
 *     mail clients' conversation view intact.
 */
async function buildRawMessage(
  to: string,
  subject: string,
  body: string,
  options: {
    inReplyTo?: string;
    references?: string;
    from?: string;
    attachments?: string[];
  } = {}
): Promise<string> {
  const { inReplyTo, references, from, attachments } = options;
  const headers: string[] = [];

  if (from) headers.push(`From: ${from}`);
  headers.push(`To: ${to}`);
  headers.push(`Subject: ${subject}`);
  headers.push("MIME-Version: 1.0");

  if (inReplyTo) {
    headers.push(`In-Reply-To: ${inReplyTo}`);
    // Prefer the explicit References chain (built by createDraft to
    // include the parent's full ancestor chain). Fall back to
    // In-Reply-To only when the caller doesn't pass a chain — that's
    // the direct-reply degenerate case where there's no deeper context.
    headers.push(`References: ${references ?? inReplyTo}`);
  }

  let mimeBody: string;
  if (attachments && attachments.length > 0) {
    // multipart/mixed: text body + N attachment parts
    const boundary = `=_gmail_cli_${Math.random().toString(36).slice(2)}_${Date.now().toString(36)}`;
    headers.push(`Content-Type: multipart/mixed; boundary="${boundary}"`);

    const bodyPart = [
      "Content-Type: text/plain; charset=utf-8",
      "Content-Transfer-Encoding: 8bit",
      "",
      body,
    ].join("\r\n");

    const attachmentParts = await Promise.all(
      attachments.map((path) => buildAttachmentPart(path))
    );

    mimeBody = [
      `--${boundary}`,
      bodyPart,
      ...attachmentParts.flatMap((p) => [`--${boundary}`, p]),
      `--${boundary}--`,
      "",
    ].join("\r\n");
  } else {
    headers.push("Content-Type: text/plain; charset=utf-8");
    mimeBody = body;
  }

  const email = headers.join("\r\n") + "\r\n\r\n" + mimeBody;
  return Buffer.from(email).toString("base64url");
}

export interface DraftOptions {
  to: string;
  subject: string;
  body: string;
  replyToMessageId?: string;
  from?: string;
  /**
   * Filesystem paths to attach to the email. Each becomes a separate
   * MIME part in a multipart/mixed message. Mime type is guessed from
   * the file extension; unknown extensions fall back to
   * application/octet-stream.
   */
  attachments?: string[];
}

export interface DraftResult {
  draftId: string;
  messageId: string;
  threadId?: string;
  fromAddress?: string;
  fromAutoDetected?: boolean;
}

export interface DraftSummary {
  draftId: string;
  messageId: string;
  threadId: string;
  from: string;
  to: string;
  subject: string;
  snippet: string;
  date: string;
}

/**
 * List Gmail drafts with metadata
 *
 * Returns proper draft IDs (required for delete/update) unlike searching "in:drafts"
 * which only returns message IDs.
 */
export async function listDrafts(
  client: gmail_v1.Gmail,
  maxResults: number = 20
): Promise<DraftSummary[]> {
  const res = await client.users.drafts.list({
    userId: "me",
    maxResults,
  });

  const drafts = res.data.drafts ?? [];

  return Promise.all(
    drafts.map(async (d) => {
      const detail = await client.users.drafts.get({
        userId: "me",
        id: d.id!,
        format: "metadata",
      });
      const headers = detail.data.message?.payload?.headers ?? [];
      const getH = (name: string) =>
        headers.find((h) => h.name?.toLowerCase() === name.toLowerCase())?.value ?? "";

      return {
        draftId: d.id!,
        messageId: detail.data.message?.id ?? "",
        threadId: detail.data.message?.threadId ?? "",
        from: getH("From"),
        to: getH("To"),
        subject: getH("Subject"),
        snippet: detail.data.message?.snippet ?? "",
        date: getH("Date"),
      };
    })
  );
}

/**
 * Delete a Gmail draft by draft ID
 *
 * Permanently removes the draft. Use listDrafts to get draft IDs.
 */
export async function deleteDraft(
  client: gmail_v1.Gmail,
  draftId: string
): Promise<void> {
  await client.users.drafts.delete({
    userId: "me",
    id: draftId,
  });
}

/**
 * Update (replace) an existing Gmail draft
 *
 * Deletes the old draft and creates a new one in the same thread.
 * Gmail API's drafts.update replaces the entire message, so this
 * delete-then-create approach is equivalent and simpler.
 */
export async function updateDraft(
  client: gmail_v1.Gmail,
  draftId: string,
  options: DraftOptions
): Promise<DraftResult> {
  // Delete old draft then create replacement
  await client.users.drafts.delete({ userId: "me", id: draftId });
  return createDraft(client, options);
}

/**
 * Create a Gmail draft
 *
 * When replying (replyToMessageId set) and no explicit `from` is provided,
 * auto-detects the correct sender by reading the original email's To/Cc/Delivered-To
 * headers. This ensures replies use the same alias the original was addressed to,
 * which is critical for accounts with multiple Send As addresses configured.
 */
export async function createDraft(
  client: gmail_v1.Gmail,
  options: DraftOptions
): Promise<DraftResult> {
  let threadId: string | undefined;
  let inReplyTo: string | undefined;
  let references: string | undefined;
  let detectedFrom: string | undefined;

  // If replying, get the original message's thread, Message-ID, References,
  // and recipient headers
  if (options.replyToMessageId) {
    const original = await client.users.messages.get({
      userId: "me",
      id: options.replyToMessageId,
      format: "metadata",
      metadataHeaders: ["Message-ID", "References", "To", "Cc", "Delivered-To"],
    });
    threadId = original.data.threadId ?? undefined;
    const msgIdHeader = original.data.payload?.headers?.find(
      (h) => h.name === "Message-ID"
    );
    const refsHeader = original.data.payload?.headers?.find(
      (h) => h.name === "References"
    );
    inReplyTo = msgIdHeader?.value ?? undefined;

    // Build the References chain per RFC 5322 §3.6.4. Two cases:
    //   - parent IS the thread root (no References header itself) →
    //     References = parent's Message-ID only
    //   - parent has a References chain (mid-thread reply) →
    //     References = parent's References + " " + parent's Message-ID
    // Mail clients use this chain to render the conversation tree.
    // Without it, deep replies appear to start a sibling thread in
    // RFC-strict clients (Thunderbird, mutt, mail.app), even when the
    // Gmail-specific threadId glues them together server-side.
    const parentRefs = refsHeader?.value ?? "";
    if (inReplyTo) {
      references = parentRefs ? `${parentRefs} ${inReplyTo}` : inReplyTo;
    }

    // Auto-detect sender: find which of our aliases the original was sent to
    if (!options.from) {
      // Get user's configured Send As aliases
      const profile = await client.users.getProfile({ userId: "me" });
      const primaryEmail = profile.data.emailAddress;

      let sendAsAddresses: string[] = [];
      try {
        const sendAs = await client.users.settings.sendAs.list({ userId: "me" });
        sendAsAddresses = (sendAs.data.sendAs ?? [])
          .map((s) => s.sendAsEmail?.toLowerCase())
          .filter((e): e is string => !!e);
      } catch {
        // Fallback: just use primary email if sendAs API not available
        if (primaryEmail) sendAsAddresses = [primaryEmail.toLowerCase()];
      }

      // Check To, Cc, Delivered-To headers for a matching alias
      const toHeader = original.data.payload?.headers?.find((h) => h.name === "To")?.value ?? "";
      const ccHeader = original.data.payload?.headers?.find((h) => h.name === "Cc")?.value ?? "";
      const deliveredTo = original.data.payload?.headers?.find((h) => h.name === "Delivered-To")?.value ?? "";

      const allRecipients = `${toHeader}, ${ccHeader}, ${deliveredTo}`.toLowerCase();

      for (const alias of sendAsAddresses) {
        if (allRecipients.includes(alias)) {
          detectedFrom = alias;
          break;
        }
      }
    }
  }

  const fromAddress = options.from ?? detectedFrom;
  const raw = await buildRawMessage(options.to, options.subject, options.body, {
    inReplyTo,
    references,
    from: fromAddress,
    attachments: options.attachments,
  });

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
    draftId: res.data.id ?? "",
    messageId: res.data.message?.id ?? "",
    threadId: res.data.message?.threadId ?? undefined,
    fromAddress: fromAddress,
    fromAutoDetected: !options.from && !!detectedFrom,
  };
}
