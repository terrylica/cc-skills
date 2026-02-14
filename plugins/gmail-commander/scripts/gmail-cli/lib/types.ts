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
