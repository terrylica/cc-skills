/**
 * Google Drive API client wrapper
 *
 * Uses @googleapis/drive for lighter dependency footprint
 */

import { drive, type drive_v3 } from "@googleapis/drive";
import { createWriteStream } from "node:fs";
import { mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { pipeline } from "node:stream/promises";
import { Readable } from "node:stream";
import { getAuthClient } from "./auth.ts";
import type { DriveFile, ListOptions, SearchOptions, DownloadOptions, SyncOptions } from "./types.ts";

/**
 * Create authenticated Google Drive API service
 */
export async function createDriveClient(): Promise<drive_v3.Drive> {
  const auth = await getAuthClient();
  return drive({ version: "v3", auth });
}

/**
 * Transform Drive API file to DriveFile type
 */
function formatFile(file: drive_v3.Schema$File): DriveFile {
  return {
    id: file.id ?? "",
    name: file.name ?? "",
    mimeType: file.mimeType ?? "",
    size: file.size ?? undefined,
    modifiedTime: file.modifiedTime ?? undefined,
    createdTime: file.createdTime ?? undefined,
    parents: file.parents ?? undefined,
    webViewLink: file.webViewLink ?? undefined,
    webContentLink: file.webContentLink ?? undefined,
  };
}

/**
 * List files in a folder
 */
export async function listFiles(
  client: drive_v3.Drive,
  options: ListOptions
): Promise<DriveFile[]> {
  const { folderId, maxResults = 100 } = options;

  const query = `'${folderId}' in parents and trashed = false`;

  const res = await client.files.list({
    q: query,
    pageSize: maxResults,
    fields: "files(id, name, mimeType, size, modifiedTime, createdTime, parents, webViewLink, webContentLink)",
    orderBy: "name",
  });

  return (res.data.files ?? []).map(formatFile);
}

/**
 * Search files across Drive
 */
export async function searchFiles(
  client: drive_v3.Drive,
  options: SearchOptions
): Promise<DriveFile[]> {
  const { query, maxResults = 100 } = options;

  const res = await client.files.list({
    q: `${query} and trashed = false`,
    pageSize: maxResults,
    fields: "files(id, name, mimeType, size, modifiedTime, createdTime, parents, webViewLink, webContentLink)",
    orderBy: "modifiedTime desc",
  });

  return (res.data.files ?? []).map(formatFile);
}

/**
 * Get file metadata
 */
export async function getFile(
  client: drive_v3.Drive,
  fileId: string
): Promise<DriveFile | null> {
  try {
    const res = await client.files.get({
      fileId,
      fields: "id, name, mimeType, size, modifiedTime, createdTime, parents, webViewLink, webContentLink",
    });
    return formatFile(res.data);
  } catch (err) {
    console.error("Error getting file:", err);
    return null;
  }
}

/**
 * Download a file to local path
 */
export async function downloadFile(
  client: drive_v3.Drive,
  options: DownloadOptions,
  onProgress?: (bytes: number, total: number) => void
): Promise<void> {
  const { fileId, outputPath } = options;

  // Get file metadata first for size info
  const meta = await client.files.get({
    fileId,
    fields: "id, name, mimeType, size",
  });

  const mimeType = meta.data.mimeType ?? "";
  const totalSize = parseInt(meta.data.size ?? "0", 10);

  // Ensure output directory exists
  await mkdir(dirname(outputPath), { recursive: true });

  // Handle Google Docs export vs regular download
  if (mimeType.startsWith("application/vnd.google-apps.")) {
    // Google Docs need to be exported
    const exportMimeType = getExportMimeType(mimeType);
    const res = await client.files.export(
      { fileId, mimeType: exportMimeType },
      { responseType: "stream" }
    );

    const stream = res.data as unknown as Readable;
    const writeStream = createWriteStream(outputPath);
    await pipeline(stream, writeStream);
  } else {
    // Regular file download
    const res = await client.files.get(
      { fileId, alt: "media" },
      { responseType: "stream" }
    );

    const stream = res.data as unknown as Readable;
    const writeStream = createWriteStream(outputPath);

    let downloaded = 0;
    stream.on("data", (chunk: Buffer) => {
      downloaded += chunk.length;
      onProgress?.(downloaded, totalSize);
    });

    await pipeline(stream, writeStream);
  }
}

/**
 * Get export MIME type for Google Docs
 */
function getExportMimeType(googleMimeType: string): string {
  const exportMap: Record<string, string> = {
    "application/vnd.google-apps.document": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.google-apps.spreadsheet": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.google-apps.presentation": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "application/vnd.google-apps.drawing": "image/png",
  };
  return exportMap[googleMimeType] ?? "application/pdf";
}

/**
 * Get file extension for export
 */
function getExportExtension(googleMimeType: string): string {
  const extMap: Record<string, string> = {
    "application/vnd.google-apps.document": ".docx",
    "application/vnd.google-apps.spreadsheet": ".xlsx",
    "application/vnd.google-apps.presentation": ".pptx",
    "application/vnd.google-apps.drawing": ".png",
  };
  return extMap[googleMimeType] ?? ".pdf";
}

/**
 * Sync (download) all files from a folder
 */
export async function syncFolder(
  client: drive_v3.Drive,
  options: SyncOptions,
  onProgress?: (current: number, total: number, fileName: string) => void
): Promise<DriveFile[]> {
  const { folderId, outputDir, recursive = false, maxResults = 1000 } = options;

  // Ensure output directory exists
  await mkdir(outputDir, { recursive: true });

  // List all files in folder
  const files = await listFiles(client, { folderId, maxResults });
  const downloaded: DriveFile[] = [];

  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    onProgress?.(i + 1, files.length, file.name);

    if (file.mimeType === "application/vnd.google-apps.folder") {
      // Handle subfolders if recursive
      if (recursive) {
        const subDir = join(outputDir, file.name);
        const subFiles = await syncFolder(
          client,
          { folderId: file.id, outputDir: subDir, recursive, maxResults },
          onProgress
        );
        downloaded.push(...subFiles);
      }
    } else {
      // Download file
      let outputPath = join(outputDir, file.name);

      // Add extension for Google Docs exports
      if (file.mimeType.startsWith("application/vnd.google-apps.")) {
        outputPath += getExportExtension(file.mimeType);
      }

      try {
        await downloadFile(client, { fileId: file.id, outputPath });
        downloaded.push(file);
      } catch (err) {
        console.error(`Failed to download ${file.name}:`, err);
      }
    }
  }

  return downloaded;
}

/**
 * Print file list in human-readable format
 */
export function printFiles(files: DriveFile[], verbose = false): void {
  if (files.length === 0) {
    console.log("No files found.");
    return;
  }

  for (const file of files) {
    if (verbose) {
      const size = file.size ? `${Math.round(parseInt(file.size) / 1024)}KB` : "-";
      const modified = file.modifiedTime
        ? new Date(file.modifiedTime).toLocaleDateString()
        : "-";
      console.log(`${file.id}\t${size}\t${modified}\t${file.name}`);
    } else {
      console.log(`${file.id}\t${file.name}`);
    }
  }
}

/**
 * Print JSON output
 */
export function printJson(data: unknown): void {
  console.log(JSON.stringify(data, null, 2));
}

/**
 * Print progress
 */
export function printProgress(current: number, total: number, fileName?: string): void {
  if (fileName) {
    console.error(`[${current}/${total}] ${fileName}`);
  } else {
    console.error(`Progress: ${current}/${total}`);
  }
}
