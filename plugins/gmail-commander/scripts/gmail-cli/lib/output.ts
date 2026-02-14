/**
 * Output formatting utilities
 */

import type { Email } from "./types.ts";

/**
 * Print emails in human-readable format
 */
export function printEmails(emails: Email[]): void {
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
