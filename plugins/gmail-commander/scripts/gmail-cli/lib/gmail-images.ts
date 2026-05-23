/**
 * Gmail inline-image extraction + download to disk.
 *
 * Split out of gmail.ts because the "fetch attachment bytes from the API
 * + write them to a user-configurable directory" subsystem is bulky and
 * conceptually distinct from the rest of the read API. It's a separate
 * call path triggered only when callers pass `--save-images` / `--image-
 * dir`; the regular read/list/search flow doesn't touch any of this.
 *
 * The lightweight `extractInlineImages` + `mimeToExt` helpers stay in
 * gmail.ts because they're called from `formatMessage` on every read
 * (to populate the `inlineImages` summary field). This module owns the
 * heavyweight download-to-disk path.
 */

import type { gmail_v1 } from "@googleapis/gmail";
import { mkdir, writeFile } from "node:fs/promises";
import { join, basename } from "node:path";

import { readEmail } from "./gmail.ts";
import { getImageDir } from "./config.ts";
import type { Email, SavedImage, ReadOptions } from "./types.ts";

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
