/**
 * Library exports
 */

export * from "./types.ts";
export * from "./config.ts";
export * from "./auth.ts";
export {
  createGmailClient,
  listEmails,
  searchEmails,
  readEmail,
  exportEmails,
  createDraft,
  listDrafts,
  deleteDraft,
  updateDraft,
} from "./gmail.ts";
export type { DraftOptions, DraftResult, DraftSummary } from "./gmail.ts";
export * from "./output.ts";
