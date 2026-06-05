/**
 * Google Drive API client wrapper
 *
 * Uses @googleapis/drive for lighter dependency footprint
 */

import { createReadStream, createWriteStream } from "node:fs";
import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import type { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { drive, type drive_v3 } from "@googleapis/drive";
import { getAuthClient } from "./auth.ts";
import type {
	DownloadOptions,
	DriveFile,
	ListOptions,
	SearchOptions,
	SyncOptions,
} from "./types.ts";

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
 * Retry a Drive API call with exponential backoff + jitter on transient rate-limit errors.
 *
 * Per Google's official guidance (developers.google.com/workspace/drive/api/guides/handle-errors):
 * retry on HTTP 429 and on 403 with reason rateLimitExceeded / userRateLimitExceeded, waiting
 * min(2^n * 1000 + random_ms, maxBackoffMs) between attempts with a finite retry ceiling. Any
 * non-rate-limit error rethrows immediately so real failures stay loud.
 */
export async function withBackoff<T>(
	fn: () => Promise<T>,
	opts: { maxRetries?: number; maxBackoffMs?: number; label?: string } = {},
): Promise<T> {
	const maxRetries = opts.maxRetries ?? 6;
	const maxBackoffMs = opts.maxBackoffMs ?? 64_000;
	let attempt = 0;
	for (;;) {
		try {
			return await fn();
		} catch (err: unknown) {
			const e = err as {
				code?: number;
				status?: number;
				message?: string;
				errors?: Array<{ reason?: string }>;
				response?: {
					status?: number;
					data?: { error?: { errors?: Array<{ reason?: string }> } };
				};
			};
			const status = e.code ?? e.status ?? e.response?.status;
			const reason =
				e.errors?.[0]?.reason ??
				e.response?.data?.error?.errors?.[0]?.reason ??
				"";
			const isRateLimit =
				status === 429 ||
				(status === 403 &&
					/rateLimitExceeded|userRateLimitExceeded/i.test(reason)) ||
				/rate limit/i.test(e.message ?? "");
			if (!isRateLimit || attempt >= maxRetries) throw err;
			const waitMs = Math.min(
				2 ** attempt * 1000 + Math.floor(Math.random() * 1000),
				maxBackoffMs,
			);
			console.error(
				`[gdrive] ${opts.label ?? "request"}: rate-limited (${status}${reason ? ` ${reason}` : ""}); retry ${attempt + 1}/${maxRetries} in ${Math.round(waitMs / 1000)}s`,
			);
			await new Promise((resolve) => setTimeout(resolve, waitMs));
			attempt++;
		}
	}
}

export interface CreateDocOptions {
	htmlPath: string;
	name: string;
	parentId?: string;
	sourceMimeType?: string;
	targetMimeType?: string;
	updateId?: string;
}

/**
 * Create a NATIVE Google Workspace file (default: a Google Doc) by converting a local source file.
 *
 * Uses the recommended Drive pattern: files.create with the TARGET mimeType in the metadata
 * (application/vnd.google-apps.document) and the SOURCE bytes as media (default text/html). Drive
 * converts on upload via a multipart upload — a *simple* upload silently skips conversion. HTML is
 * the highest-fidelity importable source for Docs (headings, bold, lists, tables). Pass updateId to
 * replace an existing Doc's contents in place (keeps the same id / link / comments).
 */
export async function createDoc(
	client: drive_v3.Drive,
	options: CreateDocOptions,
): Promise<DriveFile> {
	const sourceMimeType = options.sourceMimeType ?? "text/html";
	const targetMimeType =
		options.targetMimeType ?? "application/vnd.google-apps.document";
	const fields = "id, name, mimeType, webViewLink, parents";
	const media = {
		mimeType: sourceMimeType,
		body: createReadStream(options.htmlPath),
	};

	const updateId = options.updateId;
	if (updateId) {
		const res = await withBackoff(
			() =>
				client.files.update({
					fileId: updateId,
					media,
					fields,
					supportsAllDrives: true,
					requestBody: { mimeType: targetMimeType },
				}),
			{ label: "create-doc(update)" },
		);
		return formatFile(res.data);
	}

	const requestBody: drive_v3.Schema$File = {
		name: options.name,
		mimeType: targetMimeType,
	};
	if (options.parentId) requestBody.parents = [options.parentId];
	const res = await withBackoff(
		() =>
			client.files.create({
				requestBody,
				media,
				fields,
				supportsAllDrives: true,
			}),
		{ label: "create-doc" },
	);
	return formatFile(res.data);
}

/**
 * List files in a folder
 */
export async function listFiles(
	client: drive_v3.Drive,
	options: ListOptions,
): Promise<DriveFile[]> {
	const { folderId, maxResults = 100 } = options;

	const query = `'${folderId}' in parents and trashed = false`;

	const res = await withBackoff(
		() =>
			client.files.list({
				q: query,
				pageSize: maxResults,
				fields:
					"files(id, name, mimeType, size, modifiedTime, createdTime, parents, webViewLink, webContentLink)",
				orderBy: "name",
			}),
		{ label: "list" },
	);

	return (res.data.files ?? []).map(formatFile);
}

/**
 * Search files across Drive
 */
export async function searchFiles(
	client: drive_v3.Drive,
	options: SearchOptions,
): Promise<DriveFile[]> {
	const { query, maxResults = 100 } = options;

	const res = await withBackoff(
		() =>
			client.files.list({
				q: `${query} and trashed = false`,
				pageSize: maxResults,
				fields:
					"files(id, name, mimeType, size, modifiedTime, createdTime, parents, webViewLink, webContentLink)",
				orderBy: "modifiedTime desc",
			}),
		{ label: "search" },
	);

	return (res.data.files ?? []).map(formatFile);
}

/**
 * Get file metadata
 */
export async function getFile(
	client: drive_v3.Drive,
	fileId: string,
): Promise<DriveFile | null> {
	try {
		const res = await withBackoff(
			() =>
				client.files.get({
					fileId,
					fields:
						"id, name, mimeType, size, modifiedTime, createdTime, parents, webViewLink, webContentLink",
				}),
			{ label: "info" },
		);
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
	onProgress?: (bytes: number, total: number) => void,
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
			{ responseType: "stream" },
		);

		const stream = res.data as unknown as Readable;
		const writeStream = createWriteStream(outputPath);
		await pipeline(stream, writeStream);
	} else {
		// Regular file download
		const res = await client.files.get(
			{ fileId, alt: "media" },
			{ responseType: "stream" },
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
		"application/vnd.google-apps.document":
			"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
		"application/vnd.google-apps.spreadsheet":
			"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
		"application/vnd.google-apps.presentation":
			"application/vnd.openxmlformats-officedocument.presentationml.presentation",
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
	onProgress?: (current: number, total: number, fileName: string) => void,
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
					onProgress,
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
			const size = file.size
				? `${Math.round(parseInt(file.size, 10) / 1024)}KB`
				: "-";
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
export function printProgress(
	current: number,
	total: number,
	fileName?: string,
): void {
	if (fileName) {
		console.error(`[${current}/${total}] ${fileName}`);
	} else {
		console.error(`Progress: ${current}/${total}`);
	}
}
