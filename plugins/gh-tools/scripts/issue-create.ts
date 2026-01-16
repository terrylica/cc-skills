#!/usr/bin/env bun
/**
 * issue-create.ts - Main entry point for GitHub issue creation
 *
 * Usage:
 *   bun issue-create.ts --repo OWNER/REPO --body "content"
 *   bun issue-create.ts --body "content"  # Uses current repo from git
 *
 * Options:
 *   --repo, -r      Repository in owner/repo format
 *   --body, -b      Issue body content
 *   --title, -t     Issue title (optional, extracted from body if not provided)
 *   --labels, -l    Comma-separated labels (optional, suggested if not provided)
 *   --dry-run       Preview without creating issue
 *   --no-ai         Disable AI features (use keyword fallback only)
 *   --verbose, -v   Enable verbose output
 *   --help, -h      Show help
 */

import { parseArgs } from "node:util";
import { execSync } from "node:child_process";
import { writeFileSync, unlinkSync, existsSync } from "node:fs";
import { logger, createLogger } from "../lib/logger";
import { detectContentType, getTitlePrefix, getContentTypeDisplayName } from "../lib/content-detector";
import { suggestLabels, checkGhModelsInstallation } from "../lib/label-suggester";
import { findRelated, formatRelatedLinks, getDuplicateWarning } from "../lib/related-finder";

// Content templates by type
const TEMPLATES: Record<string, string> = {
  bug: `## Description
{CONTENT}

## Steps to Reproduce
1.
2.
3.

## Expected Behavior


## Actual Behavior


## Environment
- OS:
- Version:
`,
  feature: `## Summary
{CONTENT}

## Use Case


## Proposed Solution


## Alternatives Considered

`,
  question: `## Question
{CONTENT}

## Context


## What I've Tried

`,
  documentation: `## Description
{CONTENT}

## Location


## Suggested Change

`,
  unknown: `{CONTENT}`,
};

interface ParsedArgs {
  repo?: string;
  body?: string;
  title?: string;
  labels?: string;
  dryRun: boolean;
  noAi: boolean;
  verbose: boolean;
  help: boolean;
}

function parseArguments(): ParsedArgs {
  const { values } = parseArgs({
    options: {
      repo: { type: "string", short: "r" },
      body: { type: "string", short: "b" },
      title: { type: "string", short: "t" },
      labels: { type: "string", short: "l" },
      "dry-run": { type: "boolean", default: false },
      "no-ai": { type: "boolean", default: false },
      verbose: { type: "boolean", short: "v", default: false },
      help: { type: "boolean", short: "h", default: false },
    },
    allowPositionals: true,
  });

  return {
    repo: values.repo as string | undefined,
    body: values.body as string | undefined,
    title: values.title as string | undefined,
    labels: values.labels as string | undefined,
    dryRun: values["dry-run"] as boolean,
    noAi: values["no-ai"] as boolean,
    verbose: values.verbose as boolean,
    help: values.help as boolean,
  };
}

function showHelp(): void {
  console.log(`
GitHub Issue Creator - Create well-formatted issues with AI-powered labeling

Usage:
  bun issue-create.ts --repo OWNER/REPO --body "content"
  bun issue-create.ts --body "content"  # Uses current repo

Options:
  --repo, -r      Repository in owner/repo format
  --body, -b      Issue body content (required)
  --title, -t     Issue title (optional, extracted from body if not provided)
  --labels, -l    Comma-separated labels (optional, suggested if not provided)
  --dry-run       Preview without creating issue
  --no-ai         Disable AI features
  --verbose, -v   Enable verbose output
  --help, -h      Show this help

Examples:
  bun issue-create.ts --repo owner/repo --body "Bug: login fails with error"
  bun issue-create.ts -b "Feature: add dark mode support" --dry-run
`);
}

function getRepoFromGit(): string | null {
  const output = execSync("gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true", {
    encoding: "utf-8",
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();

  return output || null;
}

function getPermissionLevel(repo: string): string {
  const output = execSync(
    `gh repo view "${repo}" --json viewerPermission -q .viewerPermission 2>/dev/null || echo "NONE"`,
    {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }
  ).trim();

  return output || "NONE";
}

function extractTitle(content: string, contentType: string): string {
  // Try to extract first line as title
  const firstLine = content.split("\n")[0].trim();

  // Clean up common prefixes
  let title = firstLine
    .replace(/^#+\s*/, "") // Remove markdown headers
    .replace(/^(bug|feature|question|docs?):\s*/i, "") // Remove type prefixes
    .slice(0, 72); // Limit length

  // Add type prefix if not already present
  const prefix = getTitlePrefix(contentType as any);
  if (prefix && !title.toLowerCase().startsWith(prefix.toLowerCase())) {
    title = `${prefix} ${title}`;
  }

  return title;
}

function formatBody(content: string, contentType: string): string {
  const template = TEMPLATES[contentType] || TEMPLATES.unknown;
  return template.replace("{CONTENT}", content);
}

function showPreview(
  repo: string,
  title: string,
  labels: string[],
  body: string,
  relatedIssues: any[]
): void {
  console.log("\n" + "=".repeat(60));
  console.log("ISSUE PREVIEW");
  console.log("=".repeat(60));
  console.log(`Repository: ${repo}`);
  console.log(`Title:      ${title}`);
  console.log(`Labels:     ${labels.length > 0 ? labels.join(", ") : "(none)"}`);
  if (relatedIssues.length > 0) {
    console.log(`Related:    ${relatedIssues.map((r) => `#${r.number}`).join(", ")}`);
  }
  console.log("-".repeat(60));
  console.log("Body Preview:");
  console.log(body.slice(0, 500) + (body.length > 500 ? "\n..." : ""));
  console.log("=".repeat(60) + "\n");
}

function createIssue(
  repo: string,
  title: string,
  labels: string[],
  body: string
): { number: number; url: string } {
  // Write body to temp file (required by hook)
  const tempFile = `/tmp/gh-issue-${Date.now()}.md`;
  writeFileSync(tempFile, body);

  // Build command
  let cmd = `gh issue create --repo "${repo}" --title "${title.replace(/"/g, '\\"')}" --body-file "${tempFile}"`;

  if (labels.length > 0) {
    cmd += ` --label "${labels.join(",")}"`;
  }

  const output = execSync(cmd, {
    encoding: "utf-8",
    stdio: ["pipe", "pipe", "pipe"],
  });

  // Clean up temp file
  if (existsSync(tempFile)) {
    unlinkSync(tempFile);
  }

  // Parse issue URL from output
  const url = output.trim();
  const numberMatch = url.match(/\/issues\/(\d+)$/);
  const number = numberMatch ? parseInt(numberMatch[1], 10) : 0;

  return { number, url };
}

async function main(): Promise<void> {
  const startTime = Date.now();
  const args = parseArguments();

  if (args.help) {
    showHelp();
    process.exit(0);
  }

  // Validate required args
  if (!args.body) {
    console.error("Error: --body is required");
    showHelp();
    process.exit(1);
  }

  // Step 1: Preflight - detect repo
  let repo = args.repo;
  if (!repo) {
    repo = getRepoFromGit();
    if (!repo) {
      console.error("Error: No repository context. Use --repo or run from a git directory.");
      process.exit(1);
    }
  }

  const log = createLogger({ repo });
  log.info("Issue creation started", { event: "preflight" });

  // Check permissions
  const permission = getPermissionLevel(repo);
  if (args.verbose) {
    console.log(`Permission level: ${permission}`);
  }

  if (permission === "NONE" || permission === "READ") {
    console.log("\nYou don't have write access to this repository.");
    console.log("Here's the formatted issue content for manual creation:\n");
    // Continue to show preview only
    args.dryRun = true;
  }

  // Check gh-models availability
  if (!args.noAi) {
    const ghModels = checkGhModelsInstallation();
    if (!ghModels.available) {
      console.log("\nNote: gh-models not installed. Using keyword-based suggestions.");
      console.log(`Install for AI features: ${ghModels.installCommand}\n`);
    }
  }

  // Step 2-3: Detect content type and extract title
  const contentType = args.noAi
    ? "unknown"
    : detectContentType(args.title || "", args.body);

  if (args.verbose) {
    console.log(`Detected type: ${getContentTypeDisplayName(contentType)}`);
  }

  const title = args.title || extractTitle(args.body, contentType);

  // Step 4: Format body
  let formattedBody = formatBody(args.body, contentType);

  // Step 5: Suggest labels
  let labels: string[] = [];
  if (args.labels) {
    labels = args.labels.split(",").map((l) => l.trim());
  } else if (!args.noAi) {
    labels = suggestLabels(repo, title, args.body);
  }

  // Step 6: Find related issues
  const related = findRelated(repo, title, args.body);

  // Add related links to body
  if (related.toLink.length > 0) {
    formattedBody += formatRelatedLinks(related.toLink);
  }

  // Warn about duplicates
  const dupeWarning = getDuplicateWarning(related.potentialDupes);
  if (dupeWarning) {
    console.log(`\nWarning: ${dupeWarning}`);
  }

  // Step 7: Preview
  showPreview(repo, title, labels, formattedBody, related.toLink);

  if (args.dryRun) {
    console.log("[Dry run - issue not created]");
    log.info("Dry run completed", {
      event: "dry_run",
      duration_ms: Date.now() - startTime,
      ctx: { title, labels_count: labels.length },
    });
    process.exit(0);
  }

  // Create the issue
  console.log("Creating issue...");
  const issue = createIssue(repo, title, labels, formattedBody);

  console.log(`\nIssue created: ${issue.url}`);

  log.info("Issue created successfully", {
    event: "issue_created",
    duration_ms: Date.now() - startTime,
    ctx: { issue_number: issue.number, labels_count: labels.length },
  });
}

main();
