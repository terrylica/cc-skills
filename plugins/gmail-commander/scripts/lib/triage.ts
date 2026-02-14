/**
 * Email Triage Parsing
 *
 * Parses Claude's structured triage response into typed items.
 * Three-category system: SYSTEM & SECURITY / WORK / PERSONAL & FAMILY.
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

export type Category = "SYSTEM" | "WORK" | "PERSONAL";
export type Urgency = "CRITICAL" | "HIGH" | "MEDIUM" | "LOW";

export interface TriageItem {
  category: Category;
  urgency: Urgency;
  sender: string;
  subject: string;
  action: string;
}

const CATEGORY_PATTERNS: Record<string, Category> = {
  system: "SYSTEM",
  security: "SYSTEM",
  work: "WORK",
  professional: "WORK",
  personal: "PERSONAL",
  family: "PERSONAL",
  errands: "PERSONAL",
};

const URGENCY_PATTERNS: Record<string, Urgency> = {
  critical: "CRITICAL",
  high: "HIGH",
  medium: "MEDIUM",
  low: "LOW",
};

export function parseTriageResponse(text: string): TriageItem[] {
  if (text.includes("NO_SIGNIFICANT_EMAILS")) return [];

  const items: TriageItem[] = [];
  const lines = text.split("\n").filter((l) => l.trim());

  let currentCategory: Category = "WORK";
  let currentUrgency: Urgency = "MEDIUM";

  for (const line of lines) {
    const lineLower = line.toLowerCase();

    // Detect category headers like "SYSTEM & SECURITY" or "[SYSTEM]"
    const catMatch = Object.entries(CATEGORY_PATTERNS).find(
      ([key]) => lineLower.includes(key) && !/[•]|sender|subject/i.test(line)
    );
    if (catMatch && !line.match(/^[•\-*]/)) {
      currentCategory = catMatch[1];
      // Also check if urgency is on same line (e.g. "SYSTEM — CRITICAL")
      const urgOnLine = Object.entries(URGENCY_PATTERNS).find(
        ([key]) => lineLower.includes(key)
      );
      if (urgOnLine) currentUrgency = urgOnLine[1];
      continue;
    }

    // Detect standalone urgency headers like "CRITICAL" or "HIGH"
    const urgMatch = Object.entries(URGENCY_PATTERNS).find(
      ([key]) => lineLower.includes(key) && !/[•]|sender|subject/i.test(line)
    );
    if (urgMatch && !line.match(/^[•\-*]/)) {
      currentUrgency = urgMatch[1];
      continue;
    }

    // Match item lines: "• Sender — Subject" or "- Sender: Subject"
    const match = line.match(
      /^[•\-*]\s*(?:\*\*)?(.+?)(?:\*\*)?\s*[—–\-:]\s*(.+)/
    );
    if (match) {
      const sender = match[1]!.trim();
      const rest = match[2]!.trim();

      items.push({
        category: currentCategory,
        urgency: currentUrgency,
        sender,
        subject: rest,
        action: rest,
      });
    }
  }

  return items;
}

/** Format email list for triage prompt input */
export function formatEmailsForTriage(
  emails: { from: string; subject: string; date: string; snippet: string }[]
): string {
  return emails
    .map(
      (e, i) =>
        `[${i + 1}] From: ${e.from}\n    Subject: ${e.subject}\n    Date: ${e.date}\n    Snippet: ${e.snippet}`
    )
    .join("\n\n");
}

/**
 * Skill contamination detection.
 * Reused from claude-telegram-sync/src/claude-sync/summarizer.ts
 */
const SKILL_CONTAMINATION_PATTERNS = [
  "skills are available",
  "skill tool",
  "keybindings help",
  "keyboard shortcuts",
  "rebind keys",
  "chord bindings",
  "<skill name=",
];

export function isSkillContaminated(text: string): boolean {
  const lower = text.toLowerCase();
  const matches = SKILL_CONTAMINATION_PATTERNS.filter((p) => lower.includes(p));
  return matches.length >= 2;
}
