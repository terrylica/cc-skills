#!/usr/bin/env bun
/**
 * Gmail CLI - Access Gmail via command line
 *
 * Configuration via mise environment variables:
 * - GMAIL_OP_UUID: 1Password item UUID for OAuth credentials
 * - GMAIL_OP_VAULT: 1Password vault (optional, default: Employee)
 */

import { parseArgs } from "node:util";
import {
  createGmailClient,
  listEmails,
  searchEmails,
  readEmailWithImages,
  saveAttachments,
  exportEmails,
  createDraft,
  listDrafts,
  deleteDraft,
  updateDraft,
  printEmails,
  printJson,
  printProgress,
} from "./lib/index.ts";
import type { SavedImage, SavedAttachment } from "./lib/types.ts";

/**
 * Resolve the email body from --body OR --body-file (mutually exclusive).
 *
 * --body wins if both are provided (with a stderr warning) so users who
 * accidentally pass both don't get an opaque "no body" error.
 */
async function resolveBody(
  body: string | undefined,
  bodyFile: string | undefined
): Promise<string | undefined> {
  if (body && bodyFile) {
    console.error("Warning: both --body and --body-file given. Using --body and ignoring --body-file.");
    return body;
  }
  if (body) return body;
  if (bodyFile) {
    const file = Bun.file(bodyFile);
    if (!(await file.exists())) {
      throw new Error(`--body-file path not found: ${bodyFile}`);
    }
    return await file.text();
  }
  return undefined;
}

/**
 * Format an unknown error into something a human can act on.
 *
 * The googleapis library (via gaxios) throws errors whose .message is
 * often empty — particularly for HTTP 5xx responses from a proxy that
 * can't tunnel to the API host. The default `error.message` rendering
 * surfaces an empty "Error:" with no signal. This helper extracts the
 * HTTP status, request URL, response body snippet, and a category-
 * specific hint so users can diagnose without source-spelunking.
 */
function formatError(error: unknown): string {
  if (!(error instanceof Error)) return String(error);

  const e = error as Error & {
    response?: { status?: number; statusText?: string; data?: unknown };
    config?: { url?: string; method?: string };
    code?: string;
  };

  if (e.response?.status) {
    const status = e.response.status;
    const statusText = e.response.statusText ?? "";
    const method = e.config?.method?.toUpperCase() ?? "?";
    const url = e.config?.url ?? "(no url)";
    let dataStr = "";
    if (e.response.data) {
      const raw = typeof e.response.data === "string"
        ? e.response.data
        : JSON.stringify(e.response.data);
      dataStr = raw.slice(0, 400);
    }
    let hint = "";
    if (status === 502 || status === 503 || status === 504) {
      hint = "\n  hint: HTTP 5xx from a gateway often means a proxy can't tunnel to Google. This CLI auto-injects *.googleapis.com into NO_PROXY at startup — if you still see this, check that HTTPS_PROXY is set BEFORE the CLI runs (NO_PROXY is only injected when a proxy is detected).";
    } else if (status === 401) {
      hint = "\n  hint: token expired or revoked. Try `rm ~/.claude/tools/gmail-tokens/$GMAIL_OP_UUID.json` to force re-auth on next run.";
    } else if (status === 403) {
      hint = "\n  hint: OAuth scope insufficient (drafts/attachments need gmail.compose) or 'Send As' alias not configured. Check token scopes with `jq .scope $TOKEN_FILE`.";
    } else if (status === 404) {
      hint = "\n  hint: message / draft ID not found. List existing drafts with `gmail drafts` first.";
    } else if (status === 413) {
      hint = "\n  hint: attachment(s) exceed Gmail's 25 MB per-message limit. Split or use Drive links.";
    }
    return `HTTP ${status} ${statusText} ${method} ${url}${dataStr ? "\n  body: " + dataStr : ""}${hint}`;
  }

  if (e.code) {
    return `${e.code}${e.message ? ": " + e.message : ""}`;
  }

  return e.message || `(empty Error; type=${e.name ?? "unknown"})`;
}

const USAGE = `
Gmail CLI - Access Gmail via command line

USAGE:
  gmail <command> [options]

COMMANDS:
  list              List recent emails
  search <query>    Search emails using Gmail query syntax
  read <id>         Read a specific email with full body
  export            Export emails to JSON file
  draft             Create a draft email
  drafts            List drafts with draft IDs
  draft-delete <id> Delete a draft by draft ID
  draft-update <id> Replace a draft (delete + recreate)

OPTIONS:
  -n, --number      Number of emails to fetch (default: 10)
  -l, --label       Filter by label (can be used multiple times)
  -q, --query       Search query (for export command)
  -o, --output      Output file path (for export command)
  --json            Output as JSON
  --save-images     Download inline images to disk (for read command)
  --image-dir       Custom output directory for images (implies --save-images)
  --save-attachments Download real file attachments (PDF, docx, …) to disk (for read command)
  --attachment-dir  Custom output directory for attachments (implies --save-attachments)
  --to              Recipient email (for draft/draft-update)
  --from            Sender alias (for draft/draft-update, auto-detected if replying)
  --subject         Email subject (for draft/draft-update)
  --body            Email body (for draft/draft-update) — mutually exclusive with --body-file
  --body-file       Read email body from a file (for draft/draft-update). Useful for
                    multi-paragraph bodies that are awkward to pass on the shell.
  --attach          File path to attach (for draft/draft-update). Repeatable for
                    multiple attachments. MIME type guessed from extension.
  --reply-to        Message ID to reply to (for draft/draft-update)

ENVIRONMENT:
  GMAIL_OP_UUID     1Password item UUID for OAuth credentials (required)
  GMAIL_OP_VAULT    1Password vault (default: Employee)
  HTTPS_PROXY       Honored by gaxios for HTTP egress — but this CLI auto-injects
                    *.googleapis.com into NO_PROXY at startup so corporate proxies
                    that can't tunnel to Google don't cause silent HTTP 502s.

EXAMPLES:
  gmail list -n 10
  gmail list -l INBOX -l UNREAD --json
  gmail search "from:someone@example.com"
  gmail search "subject:job application after:2026/01/01"
  gmail read 18abc123def
  gmail read 18abc123def --save-images
  gmail read 18abc123def --save-images --image-dir ./attachments/
  gmail read 18abc123def --save-attachments --attachment-dir ./files/
  gmail export -q "label:inbox" -o emails.json -n 100
  gmail draft --to "user@example.com" --subject "Hello" --body "Message body"
  gmail draft --to "user@example.com" --subject "Re: Hello" --body "Reply" --reply-to 18abc123def
  gmail draft --to "user@example.com" --subject "Report" --body-file ./email.txt \\
              --attach ./report.pdf --attach ./screenshot.png
  gmail drafts --json
  gmail draft-delete r8104335052503336070
  gmail draft-update r8104335052503336070 --to "user@example.com" --subject "Updated" --body "New body"

GMAIL SEARCH SYNTAX:
  from:sender@example.com    From specific sender
  to:recipient@example.com   To specific recipient
  subject:keyword            Subject contains keyword
  after:2026/01/01           After date
  before:2026/02/01          Before date
  label:inbox                Has label
  is:unread                  Unread emails
  has:attachment             Has attachment
`;

async function main() {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      number: { type: "string", short: "n", default: "10" },
      label: { type: "string", short: "l", multiple: true },
      query: { type: "string", short: "q" },
      output: { type: "string", short: "o" },
      json: { type: "boolean", default: false },
      "save-images": { type: "boolean", default: false },
      "image-dir": { type: "string" },
      "save-attachments": { type: "boolean", default: false },
      "attachment-dir": { type: "string" },
      help: { type: "boolean", short: "h" },
      to: { type: "string" },
      from: { type: "string" },
      subject: { type: "string" },
      body: { type: "string" },
      "body-file": { type: "string" },
      attach: { type: "string", multiple: true },
      "reply-to": { type: "string" },
    },
  });

  if (values.help || positionals.length === 0) {
    console.log(USAGE);
    process.exit(0);
  }

  const [command, ...args] = positionals;
  const maxResults = parseInt(values.number!, 10);
  const asJson = values.json;

  try {
    const client = await createGmailClient();

    switch (command) {
      case "list": {
        const emails = await listEmails(client, {
          maxResults,
          labelIds: values.label,
        });
        if (asJson) {
          printJson(emails);
        } else {
          printEmails(emails);
        }
        break;
      }

      case "search": {
        const query = args.join(" ");
        if (!query) {
          console.error("Error: Search query required");
          process.exit(1);
        }
        const emails = await searchEmails(client, { query, maxResults });
        if (asJson) {
          printJson(emails);
        } else {
          printEmails(emails);
        }
        break;
      }

      case "read": {
        const messageId = args[0];
        if (!messageId) {
          console.error("Error: Message ID required");
          process.exit(1);
        }
        const shouldSaveImages = values["save-images"] || !!values["image-dir"];
        const imageDir = values["image-dir"];
        const shouldSaveAttachments = values["save-attachments"] || !!values["attachment-dir"];
        const attachmentDir = values["attachment-dir"];

        const result = await readEmailWithImages(client, messageId, {
          saveImages: shouldSaveImages,
          outputDir: imageDir,
        });
        if (!result) {
          console.error("Error: Email not found");
          process.exit(1);
        }

        let savedAttachments: SavedAttachment[] = [];
        if (shouldSaveAttachments) {
          savedAttachments = await saveAttachments(client, result.email, attachmentDir);
        }

        if (asJson) {
          printJson({
            ...result.email,
            ...(result.savedImages.length > 0 && { savedImages: result.savedImages }),
            ...(savedAttachments.length > 0 && { savedAttachments }),
          });
        } else {
          const savedMap = new Map<string, SavedImage[]>();
          if (result.savedImages.length > 0) {
            savedMap.set(result.email.id, result.savedImages);
          }
          printEmails([result.email], savedMap);
          if (savedAttachments.length > 0) {
            console.log(`\n--- Saved Attachments (${savedAttachments.length}) ---`);
            for (const sa of savedAttachments) {
              console.log(`  ${sa.savedPath}  (${sa.bytesWritten.toLocaleString()} B, ${sa.attachment.mimeType})`);
            }
          }
        }
        break;
      }

      case "export": {
        const query = values.query ?? "label:inbox";
        const outputPath = values.output ?? "emails.json";
        console.error(`Exporting emails matching: ${query}`);
        const emails = await exportEmails(
          client,
          { query, outputPath, maxResults },
          printProgress
        );
        console.error(`Exported ${emails.length} emails to ${outputPath}`);
        break;
      }

      case "draft": {
        const to = values.to;
        const from = values.from;
        const subject = values.subject;
        const body = await resolveBody(values.body, values["body-file"]);
        const replyTo = values["reply-to"];
        const attachments = values.attach;

        if (!to || !subject || !body) {
          console.error("Error: --to, --subject, and (--body OR --body-file) are required for draft command");
          process.exit(1);
        }

        const result = await createDraft(client, {
          to,
          from,
          subject,
          body,
          replyToMessageId: replyTo,
          attachments,
        });

        if (asJson) {
          printJson(result);
        } else {
          console.log("Draft created successfully!");
          console.log(`Draft ID: ${result.draftId}`);
          if (result.threadId) {
            console.log(`Thread ID: ${result.threadId}`);
          }
          if (result.fromAddress) {
            console.log(`From: ${result.fromAddress}${result.fromAutoDetected ? " (auto-detected from original email)" : ""}`);
          }
          console.log(`\nOpen Gmail to review: https://mail.google.com/mail/u/0/#drafts`);
        }
        break;
      }

      case "drafts": {
        const drafts = await listDrafts(client, maxResults);
        if (asJson) {
          printJson(drafts);
        } else {
          for (const d of drafts) {
            console.log("─".repeat(60));
            console.log(`Draft ID: ${d.draftId}`);
            console.log(`Message ID: ${d.messageId}`);
            console.log(`From: ${d.from}`);
            console.log(`To: ${d.to}`);
            console.log(`Subject: ${d.subject}`);
            console.log(`Date: ${d.date}`);
            console.log(`Snippet: ${d.snippet}`);
          }
          console.log("─".repeat(60));
          console.log(`\n${drafts.length} draft(s)`);
        }
        break;
      }

      case "draft-delete": {
        const draftId = args[0];
        if (!draftId) {
          console.error("Error: Draft ID required (use 'drafts --json' to find IDs)");
          process.exit(1);
        }
        await deleteDraft(client, draftId);
        if (asJson) {
          printJson({ deleted: draftId });
        } else {
          console.log(`Deleted draft: ${draftId}`);
        }
        break;
      }

      case "draft-update": {
        const draftId = args[0];
        if (!draftId) {
          console.error("Error: Draft ID required (use 'drafts --json' to find IDs)");
          process.exit(1);
        }
        const to = values.to;
        const from = values.from;
        const subject = values.subject;
        const body = await resolveBody(values.body, values["body-file"]);
        const replyTo = values["reply-to"];
        const attachments = values.attach;

        if (!to || !subject || !body) {
          console.error("Error: --to, --subject, and (--body OR --body-file) are required for draft-update");
          process.exit(1);
        }

        const result = await updateDraft(client, draftId, {
          to,
          from,
          subject,
          body,
          replyToMessageId: replyTo,
          attachments,
        });

        if (asJson) {
          printJson(result);
        } else {
          console.log(`Updated draft (old: ${draftId} → new: ${result.draftId})`);
          if (result.threadId) {
            console.log(`Thread ID: ${result.threadId}`);
          }
          if (result.fromAddress) {
            console.log(`From: ${result.fromAddress}${result.fromAutoDetected ? " (auto-detected)" : ""}`);
          }
          console.log(`\nOpen Gmail to review: https://mail.google.com/mail/u/0/#drafts`);
        }
        break;
      }

      default:
        console.error(`Unknown command: ${command}`);
        console.log(USAGE);
        process.exit(1);
    }
  } catch (error) {
    console.error("Error:", formatError(error));
    process.exit(1);
  }
}

main();
