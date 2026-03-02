/**
 * Output formatting utilities
 */

import type { Email, SavedImage } from "./types.ts";

/**
 * Format byte count to human-readable string
 */
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * Print emails in human-readable format
 * Optional savedImagesMap provides download results keyed by email ID
 */
export function printEmails(
  emails: Email[],
  savedImagesMap?: Map<string, SavedImage[]>
): void {
  for (const email of emails) {
    console.log("─".repeat(60));
    console.log(`ID: ${email.id}`);
    console.log(`From: ${email.from}`);
    console.log(`To: ${email.to}`);
    if (email.cc) console.log(`Cc: ${email.cc}`);
    console.log(`Subject: ${email.subject}`);
    console.log(`Date: ${email.date}`);
    console.log(`Labels: ${email.labels.join(", ")}`);
    console.log(`Snippet: ${email.snippet}`);
    if (email.body) {
      console.log("\n--- Body ---");
      console.log(email.body);
    }

    // Inline image metadata
    if (email.inlineImages && email.inlineImages.length > 0) {
      console.log(`\n--- Inline Images (${email.inlineImages.length}) ---`);
      for (const img of email.inlineImages) {
        console.log(`  ${img.filename}  ${img.mimeType}  ${formatBytes(img.size)}`);
      }
    }

    // Saved image paths and markdown references
    const saved = savedImagesMap?.get(email.id);
    if (saved && saved.length > 0) {
      console.log(`\n--- Saved to Disk ---`);
      for (const s of saved) {
        console.log(`  ${s.savedPath}  (${formatBytes(s.bytesWritten)})`);
      }
      console.log(`\n--- Markdown References ---`);
      for (const s of saved) {
        console.log(s.markdownRef);
      }
    }
  }
  console.log("─".repeat(60));
}

/**
 * Print data as JSON
 */
export function printJson(data: unknown): void {
  console.log(JSON.stringify(data, null, 2));
}

/**
 * Print progress indicator
 */
export function printProgress(current: number, total: number): void {
  const percent = Math.round((current / total) * 100);
  process.stderr.write(`\rFetching emails: ${current}/${total} (${percent}%)`);
  if (current === total) {
    process.stderr.write("\n");
  }
}
