// PROCESS-STORM-OK
/**
 * Telegram HTML Formatting
 *
 * HTML formatting, markdown conversion, and digest rendering for Telegram.
 * Merged from amonic/src/lib/telegram.ts + claude-telegram-sync/src/telegram/format.ts.
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

import type { Category, Urgency, TriageItem } from "./triage.js";

// --- Category & Urgency Display ---

export const CATEGORY_CONFIG: Record<Category, { emoji: string; label: string }> = {
  SYSTEM: { emoji: "\u{1F512}", label: "System & Security" },
  WORK: { emoji: "\u{1F4BC}", label: "Work" },
  PERSONAL: { emoji: "\u{1F464}", label: "Personal & Family" },
};

export const URGENCY_EMOJI: Record<Urgency, string> = {
  CRITICAL: "\u{1F534}",
  HIGH: "\u{1F7E0}",
  MEDIUM: "\u{1F7E1}",
  LOW: "\u26AA",
};

// --- HTML Escaping ---

export function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

export function escapeHtmlAttr(text: string): string {
  return escapeHtml(text).replace(/"/g, "&quot;");
}

// --- Markdown to HTML ---

export function markdownToTelegramHtml(markdown: string): string {
  if (!markdown) return "";

  let html = markdown;

  // Code blocks — must come before inline code
  html = html.replace(/```(\w*)\n([\s\S]*?)```/g, (_, lang, code) => {
    const escapedCode = escapeHtml(code.trim());
    if (lang) {
      return `<pre><code class="language-${escapeHtmlAttr(lang)}">${escapedCode}</code></pre>`;
    }
    return `<pre><code>${escapedCode}</code></pre>`;
  });

  // Inline code
  html = html.replace(/`([^`]+)`/g, (_, code) => {
    return `<code>${escapeHtml(code)}</code>`;
  });

  // Bold
  html = html.replace(/\*\*(.+?)\*\*/g, "<b>$1</b>");
  html = html.replace(/__(.+?)__/g, "<b>$1</b>");

  // Italic
  html = html.replace(/\*(.+?)\*/g, "<i>$1</i>");
  html = html.replace(/_(.+?)_/g, "<i>$1</i>");

  // Links
  html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, text, url) => {
    return `<a href="${escapeHtmlAttr(url)}">${escapeHtml(text)}</a>`;
  });

  return html;
}

export function formatForTelegram(text: string): string {
  if (!text) return "";
  const hasMarkdown = /[*_`\[]/.test(text);
  if (hasMarkdown) return markdownToTelegramHtml(text);
  return escapeHtml(text);
}

// --- Digest Formatting ---

export function formatDigestHtml(items: TriageItem[], totalEmails: number): string {
  let html = `<b>\u{1F4EC} Gmail Digest</b> (6h window)\n`;

  for (const cat of ["SYSTEM", "WORK", "PERSONAL"] as Category[]) {
    const catItems = items.filter((i) => i.category === cat);
    if (catItems.length === 0) continue;

    const { emoji, label } = CATEGORY_CONFIG[cat];
    html += `\n<b>${emoji} ${label}</b>\n`;

    for (const item of catItems) {
      const uEmoji = URGENCY_EMOJI[item.urgency];
      html += `${uEmoji} <b>${escapeHtml(item.sender)}</b> \u2014 ${escapeHtml(item.subject)}\n`;
      html += `  <i>${escapeHtml(item.action)}</i>\n`;
    }
  }

  html += `\n<i>${items.length} significant / ${totalEmails} total emails</i>`;
  return html;
}

// --- Email Card Formatting (for bot /inbox, /search results) ---

export function formatEmailCard(email: {
  id: string;
  from: string;
  subject: string;
  date: string;
  snippet: string;
}, index: number): string {
  return (
    `<b>${index}.</b> ${escapeHtml(email.from)}\n` +
    `   <b>${escapeHtml(email.subject)}</b>\n` +
    `   <i>${escapeHtml(email.date)}</i>\n` +
    `   ${escapeHtml(email.snippet.slice(0, 100))}${email.snippet.length > 100 ? "..." : ""}`
  );
}

export function formatEmailList(
  emails: { id: string; from: string; subject: string; date: string; snippet: string }[]
): string {
  if (emails.length === 0) return "<i>No emails found.</i>";
  return emails.map((e, i) => formatEmailCard(e, i + 1)).join("\n\n");
}

// --- Email Read View (structured from raw gmail-cli output) ---

export function formatEmailReadView(raw: string): string {
  // Parse header block (before "--- Body ---") and body (after)
  const bodyMarker = raw.indexOf("--- Body ---");
  const headerSection = bodyMarker >= 0 ? raw.slice(0, bodyMarker) : raw;
  const bodySection = bodyMarker >= 0 ? raw.slice(bodyMarker + 12).trim() : "";

  // Extract header fields
  const headers: Record<string, string> = {};
  for (const line of headerSection.split("\n")) {
    const match = line.match(/^(From|To|Subject|Date|Labels|Cc|Bcc):\s*(.+)/);
    if (match) headers[match[1]!] = match[2]!.trim();
  }

  // Build header display
  let html = "";
  if (headers.Subject) html += `<b>${escapeHtml(headers.Subject)}</b>\n`;
  if (headers.From) html += `<b>From:</b> ${escapeHtml(headers.From)}\n`;
  if (headers.To) html += `<b>To:</b> ${escapeHtml(headers.To)}\n`;
  if (headers.Cc) html += `<b>Cc:</b> ${escapeHtml(headers.Cc)}\n`;
  if (headers.Date) html += `<i>${escapeHtml(headers.Date)}</i>\n`;
  if (headers.Labels && headers.Labels !== "INBOX") {
    html += `<code>${escapeHtml(headers.Labels)}</code>\n`;
  }

  if (!bodySection) return html || escapeHtml(raw);

  html += "\n";

  // Process body: separate main content from quoted thread
  const bodyLines = bodySection.split("\n");
  const mainLines: string[] = [];
  const quotedLines: string[] = [];
  let inQuote = false;
  let hitSignature = false;

  for (const line of bodyLines) {
    // Detect signature markers
    if (!hitSignature && /^--\s*$/.test(line)) {
      hitSignature = true;
      continue;
    }
    // Detect quoted reply start
    if (!inQuote && /^On .+ wrote:$/.test(line.trim())) {
      inQuote = true;
      quotedLines.push(line);
      continue;
    }
    // Lines starting with > are quoted
    if (line.startsWith(">")) {
      inQuote = true;
      quotedLines.push(line);
      continue;
    }

    if (inQuote) {
      quotedLines.push(line);
    } else if (hitSignature) {
      // Skip signature content
      continue;
    } else {
      mainLines.push(line);
    }
  }

  // Format main body — clean up blank lines, strip tracking URLs
  const mainText = mainLines
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")                           // Collapse excess blank lines
    .replace(/https?:\/\/\S{100,}/g, "[tracking link]")   // Strip long tracking URLs
    .replace(/\[image:\s*photo\]/gi, "[image]")            // Clean image refs
    .trim();

  if (mainText) {
    html += escapeHtml(mainText) + "\n";
  }

  // Format quoted thread — truncated, in blockquote
  if (quotedLines.length > 0) {
    const cleaned = quotedLines
      .map(l => l.replace(/^>\s?/, ""))         // Strip > prefix
      .join("\n")
      .replace(/\n{3,}/g, "\n\n")
      .replace(/https?:\/\/\S{100,}/g, "")     // Strip tracking URLs entirely
      .replace(/\[image:\s*photo\]/gi, "")
      .trim();

    if (cleaned) {
      // Truncate quoted thread to ~500 chars
      const truncated = cleaned.length > 500
        ? cleaned.slice(0, 500).replace(/\n[^\n]*$/, "") + "\n..."
        : cleaned;
      html += `\n<blockquote>${escapeHtml(truncated)}</blockquote>`;
    }
  }

  return html;
}

// --- Send Helpers (raw fetch, used by digest — bot uses grammY) ---

export async function sendTelegramMessage(chatId: string, html: string): Promise<boolean> {
  const token = Bun.env.TELEGRAM_BOT_TOKEN;
  if (!token) throw new Error("TELEGRAM_BOT_TOKEN not set");

  const resp = await fetch(
    `https://api.telegram.org/bot${token}/sendMessage`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        text: html,
        parse_mode: "HTML",
        disable_web_page_preview: true,
      }),
    }
  );

  const result = await resp.json() as { ok: boolean; description?: string };
  return result.ok === true;
}

export async function sendDigest(items: TriageItem[], totalEmails: number): Promise<boolean> {
  const chatId = Bun.env.TELEGRAM_CHAT_ID;
  if (!chatId) throw new Error("TELEGRAM_CHAT_ID not set");

  const html = formatDigestHtml(items, totalEmails);
  return sendTelegramMessage(chatId, html);
}
