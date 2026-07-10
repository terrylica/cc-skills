/**
 * Gmail draft create / list / update / delete + MIME builder.
 *
 * Split out of gmail.ts (which was 690 LOC). All write-side functionality
 * lives here, including the multipart/mixed MIME builder that takes
 * attachment files. The read-side API (list/search/read/export) stays in
 * gmail.ts; image-download specifically lives in gmail-images.ts.
 *
 * Why this seam: the MIME builder is private to draft creation and
 * nothing on the read side touches it. Keeping them together means a
 * future change to the multipart shape only has to be reasoned about
 * inside one file.
 */

import type { gmail_v1 } from "@googleapis/gmail";
import { basename } from "node:path";

// ─────────────────────────────────────────────────────────────────────────────
// MIME builder (private helpers used by createDraft / updateDraft)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Guess a MIME type from a file extension.
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
 * RFC 2047 "encoded-word" for a mail header value containing non-ASCII.
 *
 * Mail headers are ASCII-only (RFC 5322). Putting raw UTF-8 bytes (e.g. an
 * em-dash "—" = E2 80 94) straight into `Subject:` makes clients decode them
 * as Latin-1 → the classic "â€"" mojibake. RFC 2047 fixes this by base64-
 * encoding the UTF-8 bytes inside `=?UTF-8?B?…?=`.
 *
 * Pure-ASCII values pass through untouched. Non-ASCII values are split into
 * encoded-words on CODE-POINT boundaries (never mid-codepoint) so each word's
 * total length stays within RFC 2047's 75-char cap, folded with CRLF+SP.
 */
export function encodeMimeHeader(value: string): string {
  // Printable ASCII only → safe to emit verbatim.
  if (/^[\x20-\x7E]*$/.test(value)) return value;

  const prefix = "=?UTF-8?B?";
  const suffix = "?=";
  // Each encoded-word ≤ 75 chars. base64 is 4 chars per 3 bytes, so budget the
  // raw UTF-8 byte count that keeps prefix+base64+suffix under the cap.
  const maxB64 = 75 - prefix.length - suffix.length;
  const maxBytes = Math.floor(maxB64 / 4) * 3;

  const words: string[] = [];
  let buf: number[] = [];
  for (const ch of value) {
    const chBytes = [...Buffer.from(ch, "utf-8")];
    if (buf.length > 0 && buf.length + chBytes.length > maxBytes) {
      words.push(prefix + Buffer.from(buf).toString("base64") + suffix);
      buf = [];
    }
    buf.push(...chBytes);
  }
  if (buf.length > 0) {
    words.push(prefix + Buffer.from(buf).toString("base64") + suffix);
  }
  // Fold adjacent encoded-words with CRLF + a single space (RFC 5322 folding).
  return words.join("\r\n ");
}

/**
 * Encode a `From`/`To`-style address whose display name may contain non-ASCII.
 *
 * Only the display-name portion is RFC 2047-encoded; the `<addr@host>` is left
 * untouched. A bare `addr@host` (no display name) passes straight through.
 */
export function encodeAddressHeader(value: string): string {
  const m = value.match(/^\s*(.*?)\s*(<[^>]+>)\s*$/);
  if (!m) return encodeMimeHeader(value);
  const [, display, addr] = m;
  if (!display) return addr;
  return `${encodeMimeHeader(display)} ${addr}`;
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
/**
 * Convert a plain-text body into RFC 3676 `format=flowed` so recipient mail
 * clients REFLOW paragraphs to the reader's window width instead of hard-wrapping
 * long author lines at a fixed column (the "premature wrapping" symptom).
 *
 * Rules (RFC 3676):
 *   - A soft line break (paragraph continues, client may reflow) is a line that
 *     ENDS WITH A SPACE before CRLF. We word-wrap each paragraph at 72 cols and
 *     end every wrapped line except the last with a trailing space.
 *   - A hard line break (a real break the author intended — list items, sign-off
 *     lines, blank lines) is a line with NO trailing space. The LAST line of each
 *     source line stays hard, so intentional breaks (numbered lists, "Best,\nRicky")
 *     are preserved exactly.
 *   - Space-stuffing: lines beginning with a space, ">", or "From " get one leading
 *     space so they aren't misread as quote/soft markers; the reader's client strips it.
 */
/** RFC 3676 space-stuffing: a line starting with space, ">" or "From " gets a leading space. */
function stuffFlowed(line: string): string {
  return /^( |>|From )/.test(line) ? " " + line : line;
}

function toFormatFlowed(body: string, wrap = 72): string {
  const out: string[] = [];
  // Normalize newlines; each source line is a hard unit whose long content we soft-wrap.
  for (const srcLine of body.replace(/\r\n/g, "\n").split("\n")) {
    if (srcLine === "") {
      out.push(""); // preserved blank line = hard paragraph separator
      continue;
    }
    if (srcLine.length <= wrap) {
      out.push(stuffFlowed(srcLine)); // short line: emit as a hard line (no trailing space)
      continue;
    }
    const words = srcLine.split(" ");
    let cur = "";
    for (const w of words) {
      if (cur === "") cur = w;
      else if ((cur + " " + w).length <= wrap) cur += " " + w;
      else {
        out.push(stuffFlowed(cur) + " "); // soft break: trailing space → client reflows
        cur = w;
      }
    }
    out.push(stuffFlowed(cur)); // last chunk of this source line = hard break
  }
  return out.join("\r\n");
}

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

  if (from) headers.push(`From: ${encodeAddressHeader(from)}`);
  headers.push(`To: ${encodeAddressHeader(to)}`);
  headers.push(`Subject: ${encodeMimeHeader(subject)}`);
  headers.push("MIME-Version: 1.0");

  if (inReplyTo) {
    headers.push(`In-Reply-To: ${inReplyTo}`);
    // Prefer the explicit References chain (built by createDraft to
    // include the parent's full ancestor chain). Fall back to
    // In-Reply-To only when the caller doesn't pass a chain — that's
    // the direct-reply degenerate case where there's no deeper context.
    headers.push(`References: ${references ?? inReplyTo}`);
  }

  // RFC 3676 format=flowed so recipients' clients REFLOW paragraphs to their window
  // width instead of hard-wrapping the author's long lines at a fixed column.
  const flowedBody = toFormatFlowed(body);

  let mimeBody: string;
  if (attachments && attachments.length > 0) {
    // multipart/mixed: text body + N attachment parts
    const boundary = `=_gmail_cli_${Math.random().toString(36).slice(2)}_${Date.now().toString(36)}`;
    headers.push(`Content-Type: multipart/mixed; boundary="${boundary}"`);

    const bodyPart = [
      "Content-Type: text/plain; charset=utf-8; format=flowed",
      "Content-Transfer-Encoding: 8bit",
      "",
      flowedBody,
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
    headers.push("Content-Type: text/plain; charset=utf-8; format=flowed");
    headers.push("Content-Transfer-Encoding: 8bit");
    mimeBody = flowedBody;
  }

  // Encode the whole message as UTF-8 bytes (Buffer.from defaults to utf-8), so the
  // 8-bit body and any encoded-word headers transmit their bytes intact.
  const email = headers.join("\r\n") + "\r\n\r\n" + mimeBody;
  return Buffer.from(email, "utf-8").toString("base64url");
}

// ─────────────────────────────────────────────────────────────────────────────
// Public draft types + API
// ─────────────────────────────────────────────────────────────────────────────

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
