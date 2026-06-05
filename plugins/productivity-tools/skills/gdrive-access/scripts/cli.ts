#!/usr/bin/env bun
/**
 * Google Drive CLI - Access Google Drive via command line
 *
 * Configuration via mise environment variables:
 * - GDRIVE_OP_UUID: 1Password item UUID for OAuth credentials
 * - GDRIVE_OP_VAULT: 1Password vault (optional, default: Employee)
 */

import { parseArgs } from "node:util";
import {
	createDoc,
	createDriveClient,
	downloadFile,
	getFile,
	listFiles,
	printFiles,
	printJson,
	printProgress,
	searchFiles,
	syncFolder,
} from "./lib/index.ts";

const USAGE = `
Google Drive CLI - Access Google Drive via command line

USAGE:
  gdrive <command> [options]

COMMANDS:
  list <folder_id>      List files in a folder
  search <query>        Search files using Drive query syntax
  info <file_id>        Get file metadata
  download <file_id>    Download a single file
  sync <folder_id>      Download all files from a folder
  create-doc <file>     Create a NATIVE Google Doc from an HTML (or .docx) source

OPTIONS:
  -n, --number        Number of files to fetch (default: 100)
  -o, --output        Output path for download/sync
  -r, --recursive     Include subfolders in sync
  -v, --verbose       Show detailed file information
  --json              Output as JSON
  --name <title>      Doc title           (create-doc, on create)
  --parent <id>       Destination folder   (create-doc, on create)
  --update <file_id>  Replace an existing Doc's contents in place (create-doc)

ENVIRONMENT:
  GDRIVE_OP_UUID      1Password item UUID for OAuth credentials (required)
  GDRIVE_OP_VAULT     1Password vault (default: Employee)

EXAMPLES:
  gdrive list 1wqqqvBmeUFYuwOOEQhzoChC7KzAk-mAS
  gdrive list 1wqqqvBmeUFYuwOOEQhzoChC7KzAk-mAS --verbose
  gdrive search "name contains 'training'"
  gdrive info 1abc123def456
  gdrive download 1abc123def456 -o ./file.pdf
  gdrive sync 1wqqqvBmeUFYuwOOEQhzoChC7KzAk-mAS -o ./output -r
  gdrive create-doc ./report.html --name "Q1 Report" --parent 1wqqqv...
  gdrive create-doc ./report.html --update 1abc123def456   # overwrite an existing Doc

  # Markdown -> native Google Doc (HTML is the highest-fidelity import source):
  pandoc notes.md -o /tmp/notes.html --standalone && gdrive create-doc /tmp/notes.html --name "Notes" --parent <folder_id>

DRIVE SEARCH SYNTAX:
  name contains 'keyword'           Name contains keyword
  name = 'exact name'               Exact name match
  mimeType = 'application/pdf'      By file type
  modifiedTime > '2026-01-01'       Modified after date
  trashed = false                   Not in trash
  'folderId' in parents             In specific folder

FOLDER ID:
  Extract from Google Drive URL:
  https://drive.google.com/drive/folders/1wqqqvBmeUFYuwOOEQhzoChC7KzAk-mAS
                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                    This is the folder ID
`;

async function main() {
	const { values, positionals } = parseArgs({
		allowPositionals: true,
		options: {
			number: { type: "string", short: "n", default: "100" },
			output: { type: "string", short: "o" },
			recursive: { type: "boolean", short: "r", default: false },
			verbose: { type: "boolean", short: "v", default: false },
			json: { type: "boolean", default: false },
			name: { type: "string" },
			parent: { type: "string" },
			update: { type: "string" },
			help: { type: "boolean", short: "h" },
		},
	});

	if (values.help || positionals.length === 0) {
		console.log(USAGE);
		process.exit(0);
	}

	const [command, ...args] = positionals;
	const maxResults = parseInt(values.number!, 10);
	const asJson = values.json;
	const verbose = values.verbose;

	try {
		const client = await createDriveClient();

		switch (command) {
			case "list": {
				const folderId = args[0];
				if (!folderId) {
					console.error("Error: Folder ID required");
					console.error("Usage: gdrive list <folder_id>");
					process.exit(1);
				}
				const files = await listFiles(client, {
					folderId,
					maxResults,
					verbose,
				});
				if (asJson) {
					printJson(files);
				} else {
					printFiles(files, verbose);
				}
				break;
			}

			case "search": {
				const query = args.join(" ");
				if (!query) {
					console.error("Error: Search query required");
					console.error("Usage: gdrive search <query>");
					process.exit(1);
				}
				const files = await searchFiles(client, { query, maxResults });
				if (asJson) {
					printJson(files);
				} else {
					printFiles(files, verbose);
				}
				break;
			}

			case "info": {
				const fileId = args[0];
				if (!fileId) {
					console.error("Error: File ID required");
					console.error("Usage: gdrive info <file_id>");
					process.exit(1);
				}
				const file = await getFile(client, fileId);
				if (!file) {
					console.error("Error: File not found");
					process.exit(1);
				}
				if (asJson) {
					printJson(file);
				} else {
					console.log(`ID:       ${file.id}`);
					console.log(`Name:     ${file.name}`);
					console.log(`Type:     ${file.mimeType}`);
					if (file.size)
						console.log(
							`Size:     ${Math.round(parseInt(file.size, 10) / 1024)}KB`,
						);
					if (file.modifiedTime) console.log(`Modified: ${file.modifiedTime}`);
					if (file.webViewLink) console.log(`Link:     ${file.webViewLink}`);
				}
				break;
			}

			case "download": {
				const fileId = args[0];
				if (!fileId) {
					console.error("Error: File ID required");
					console.error("Usage: gdrive download <file_id> -o <output_path>");
					process.exit(1);
				}

				// Get file info first for default output name
				const file = await getFile(client, fileId);
				if (!file) {
					console.error("Error: File not found");
					process.exit(1);
				}

				const outputPath = values.output ?? file.name;
				console.error(`Downloading: ${file.name}`);

				await downloadFile(client, { fileId, outputPath }, (bytes, total) => {
					if (total > 0) {
						const pct = Math.round((bytes / total) * 100);
						process.stderr.write(
							`\r${pct}% (${Math.round(bytes / 1024)}KB / ${Math.round(total / 1024)}KB)`,
						);
					}
				});
				console.error(`\nSaved to: ${outputPath}`);
				break;
			}

			case "sync": {
				const folderId = args[0];
				if (!folderId) {
					console.error("Error: Folder ID required");
					console.error("Usage: gdrive sync <folder_id> -o <output_dir>");
					process.exit(1);
				}

				const outputDir = values.output ?? "./gdrive-sync";
				const recursive = values.recursive;

				console.error(`Syncing folder to: ${outputDir}`);
				if (recursive) console.error("(including subfolders)");

				const files = await syncFolder(
					client,
					{ folderId, outputDir, recursive, maxResults },
					printProgress,
				);

				console.error(`\nSynced ${files.length} files to ${outputDir}`);

				if (asJson) {
					printJson(files);
				}
				break;
			}

			case "create-doc": {
				const htmlPath = args[0];
				if (!htmlPath) {
					console.error("Error: source file required");
					console.error(
						'Usage: gdrive create-doc <file.html> --name "Title" --parent <folder_id>',
					);
					console.error(
						"       gdrive create-doc <file.html> --update <existing_doc_id>",
					);
					process.exit(1);
				}
				if (!values.update && (!values.name || !values.parent)) {
					console.error(
						"Error: --name and --parent are required when creating a new Doc",
					);
					console.error(
						"       (or pass --update <doc_id> to overwrite an existing Doc)",
					);
					process.exit(1);
				}
				const file = await createDoc(client, {
					htmlPath,
					name: values.name ?? "",
					parentId: values.parent,
					updateId: values.update,
				});
				if (asJson) {
					printJson(file);
				} else {
					console.log(
						values.update
							? "Updated native Google Doc:"
							: "Created native Google Doc:",
					);
					console.log(`  ID:   ${file.id}`);
					console.log(`  Name: ${file.name}`);
					console.log(`  Type: ${file.mimeType}`);
					if (file.webViewLink) console.log(`  Link: ${file.webViewLink}`);
				}
				break;
			}

			default:
				console.error(`Unknown command: ${command}`);
				console.log(USAGE);
				process.exit(1);
		}
	} catch (error) {
		console.error("Error:", error instanceof Error ? error.message : error);
		process.exit(1);
	}
}

main();
