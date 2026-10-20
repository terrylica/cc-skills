// The Google Workspace Admin console recipe family (admin.google.com). Skill: skills/admin-console/SKILL.md.
//
// Google asks an administrator for a FRESH password on accounts.google.com before admin pages, every so often; the
// shared gate (lib/gate.ts) handles it with this classifier.
import type { Family, PageKind } from "../../lib/gate.ts";

/** Pure: classify a page by its URL and visible text. */
export function classifyPage(url: string, text: string): PageKind {
  let host = "";
  try {
    host = new URL(url).hostname;
  } catch {
    return "other";
  }
  if (host === "accounts.google.com") {
    if (/verify it'?s you|verify it’s you|enter your password|confirm it'?s you|to continue, first verify/i.test(text)) return "reauth";
    return "signin";
  }
  if (host === "admin.google.com") return "ready";
  return "other";
}

export const GOOGLE_ADMIN: Family = { name: "google-admin", console: "Google Admin console", classify: classifyPage };
