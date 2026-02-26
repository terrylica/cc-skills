/**
 * TypeScript interfaces for Google Drive access
 */

export interface DriveFile {
  id: string;
  name: string;
  mimeType: string;
  size?: string;
  modifiedTime?: string;
  createdTime?: string;
  parents?: string[];
  webViewLink?: string;
  webContentLink?: string;
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
  folderId: string;
  maxResults?: number;
  verbose?: boolean;
}

export interface SearchOptions {
  query: string;
  maxResults?: number;
}

export interface DownloadOptions {
  fileId: string;
  outputPath: string;
}

export interface SyncOptions {
  folderId: string;
  outputDir: string;
  recursive?: boolean;
  maxResults?: number;
}
