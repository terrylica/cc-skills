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
  readEmail,
  exportEmails,
  createDraft,
  printEmails,
  printJson,
  printProgress,
} from "./lib/index.ts";

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

OPTIONS:
  -n, --number      Number of emails to fetch (default: 10)
  -l, --label       Filter by label (can be used multiple times)
  -q, --query       Search query (for export command)
  -o, --output      Output file path (for export command)
  --json            Output as JSON
  --to              Recipient email (for draft command)
  --from            Sender email alias (for draft command, auto-detected from original if replying)
  --subject         Email subject (for draft command)
  --body            Email body (for draft command)
  --reply-to        Message ID to reply to (for draft command)

ENVIRONMENT:
  GMAIL_OP_UUID     1Password item UUID for OAuth credentials (required)
  GMAIL_OP_VAULT    1Password vault (default: Employee)

EXAMPLES:
  gmail list -n 10
  gmail list -l INBOX -l UNREAD --json
  gmail search "from:someone@example.com"
  gmail search "subject:job application after:2026/01/01"
  gmail read 18abc123def
  gmail export -q "label:inbox" -o emails.json -n 100
  gmail draft --to "user@example.com" --subject "Hello" --body "Message body"
  gmail draft --to "user@example.com" --subject "Re: Hello" --body "Reply" --reply-to 18abc123def

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
      help: { type: "boolean", short: "h" },
      to: { type: "string" },
      from: { type: "string" },
      subject: { type: "string" },
      body: { type: "string" },
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
        const email = await readEmail(client, messageId);
        if (!email) {
          console.error("Error: Email not found");
          process.exit(1);
        }
        if (asJson) {
          printJson(email);
        } else {
          printEmails([email]);
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
        const body = values.body;
        const replyTo = values["reply-to"];

        if (!to || !subject || !body) {
          console.error("Error: --to, --subject, and --body are required for draft command");
          process.exit(1);
        }

        const result = await createDraft(client, {
          to,
          from,
          subject,
          body,
          replyToMessageId: replyTo,
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
