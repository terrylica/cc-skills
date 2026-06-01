/**
 * Library exports
 *
 * The Gmail surface area is split across three sibling modules — see each
 * file's docstring for the seam rationale (task #27, v1.7 polish):
 *   - gmail.ts          → read API (list / search / read / export)
 *   - gmail-images.ts   → inline image download to disk
 *   - gmail-drafts.ts   → draft CRUD + multipart/mixed MIME builder
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
} from "./gmail.ts";
export {
  readEmailWithImages,
  saveInlineImages,
  saveAttachments,
} from "./gmail-images.ts";
export {
  createDraft,
  listDrafts,
  deleteDraft,
  updateDraft,
} from "./gmail-drafts.ts";
export type { DraftOptions, DraftResult, DraftSummary } from "./gmail-drafts.ts";
export { getImageDir } from "./config.ts";
export * from "./output.ts";
