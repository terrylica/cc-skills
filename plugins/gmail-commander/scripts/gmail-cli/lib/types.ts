/**
 * TypeScript interfaces for Gmail access
 */

export interface Email {
  id: string;
  threadId: string;
  snippet: string;
  from: string;
  to: string;
  cc: string;
  subject: string;
  date: string;
  labels: string[];
  body?: string;
  inlineImages?: InlineImage[];
  attachments?: Attachment[];
}

export interface InlineImage {
  attachmentId: string;
  mimeType: string;
  filename: string;
  contentId: string;
  size: number;
  partId: string;
}

/**
 * A real file attachment (application/pdf, document, etc.) — a MIME part
 * with a non-empty filename + attachmentId that is NOT an inline image.
 * Inline images (image/* parts) are surfaced via `inlineImages` instead,
 * so the two lists never overlap.
 */
export interface Attachment {
  attachmentId: string;
  mimeType: string;
  filename: string;
  size: number;
  partId: string;
}

export interface SavedImage {
  image: InlineImage;
  savedPath: string;
  bytesWritten: number;
  markdownRef: string;
}

export interface SavedAttachment {
  attachment: Attachment;
  savedPath: string;
  bytesWritten: number;
}

export interface ReadOptions {
  saveImages?: boolean;
  outputDir?: string;
}

export interface OAuthCredentials {
  installed: {
    client_id: string;
    client_secret: string;
    redirect_uris: string[];
    auth_uri: string;
    token_uri: string;
  };
}

export interface SavedToken {
  access_token: string;
  refresh_token?: string;
  scope: string;
  token_type: string;
  expiry_date?: number;
}

export interface ListOptions {
  maxResults: number;
  labelIds?: string[];
}

export interface SearchOptions {
  query: string;
  maxResults: number;
}

export interface ExportOptions {
  query: string;
  outputPath: string;
  maxResults: number;
}
