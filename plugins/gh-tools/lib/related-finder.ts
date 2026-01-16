#!/usr/bin/env bun
/**
 * related-finder.ts - Find related issues and detect potential duplicates
 *
 * Searches for related issues to:
 * 1. Auto-link in the issue body
 * 2. Show candidates for user selection
 * 3. Warn about potential duplicates
 */

import { execSync } from "node:child_process";
import { logger } from "./logger";

export interface RelatedIssue {
  number: number;
  title: string;
  state: "open" | "closed";
  url: string;
  similarity: number;
}

export interface RelatedIssuesResult {
  toLink: RelatedIssue[];
  potentialDupes: RelatedIssue[];
  all: RelatedIssue[];
}

/**
 * Extract keywords from text for search
 */
function extractKeywords(text: string): string[] {
  // Remove common stop words and extract meaningful terms
  const stopWords = new Set([
    "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
    "of", "with", "by", "from", "is", "are", "was", "were", "be", "been",
    "have", "has", "had", "do", "does", "did", "will", "would", "could",
    "should", "may", "might", "can", "this", "that", "these", "those",
    "i", "you", "he", "she", "it", "we", "they", "my", "your", "his",
    "her", "its", "our", "their", "what", "which", "who", "when", "where",
    "why", "how", "if", "then", "else", "so", "as", "not", "no", "yes",
  ]);

  // Extract words, filter stop words, dedupe
  const words = text
    .toLowerCase()
    .replace(/[^\w\s]/g, " ")
    .split(/\s+/)
    .filter((word) => word.length > 2 && !stopWords.has(word));

  // Return unique words, limited to most relevant
  return [...new Set(words)].slice(0, 10);
}

/**
 * Calculate similarity score between two strings (simple word overlap)
 */
function calculateSimilarity(text1: string, text2: string): number {
  const words1 = new Set(extractKeywords(text1));
  const words2 = new Set(extractKeywords(text2));

  if (words1.size === 0 || words2.size === 0) {
    return 0;
  }

  // Count overlapping words
  let overlap = 0;
  for (const word of words1) {
    if (words2.has(word)) {
      overlap++;
    }
  }

  // Jaccard similarity
  const union = new Set([...words1, ...words2]).size;
  return overlap / union;
}

/**
 * Search for related issues using gh CLI
 */
function searchIssues(repo: string, query: string, limit: number): RelatedIssue[] {
  const startTime = Date.now();

  const output = execSync(
    `gh search issues "${query}" --repo "${repo}" --limit ${limit} --json number,title,state,url`,
    {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
      timeout: 30000,
    }
  );

  const duration = Date.now() - startTime;
  const results = JSON.parse(output) as Array<{
    number: number;
    title: string;
    state: string;
    url: string;
  }>;

  logger.debug("Issue search completed", {
    event: "issues_searched",
    duration_ms: duration,
    ctx: { repo, query: query.slice(0, 50), results_count: results.length },
  });

  return results.map((r) => ({
    number: r.number,
    title: r.title,
    state: r.state as "open" | "closed",
    url: r.url,
    similarity: 0, // Will be calculated after
  }));
}

/**
 * Find related issues for a new issue
 *
 * @param repo - Repository in "owner/repo" format
 * @param title - New issue title
 * @param body - New issue body
 * @returns Related issues categorized by relevance
 */
export function findRelated(
  repo: string,
  title: string,
  body: string
): RelatedIssuesResult {
  const startTime = Date.now();
  const content = `${title} ${body}`;
  const keywords = extractKeywords(content);

  if (keywords.length === 0) {
    logger.info("No keywords extracted for search", {
      event: "no_keywords",
      ctx: { repo },
    });
    return { toLink: [], potentialDupes: [], all: [] };
  }

  // Build search query from keywords
  const query = keywords.slice(0, 5).join(" ");

  // Search for related issues
  let results: RelatedIssue[];
  results = searchIssues(repo, query, 10);

  // Calculate similarity scores
  for (const issue of results) {
    issue.similarity = calculateSimilarity(content, issue.title);
  }

  // Sort by similarity
  results.sort((a, b) => b.similarity - a.similarity);

  // Categorize results
  const potentialDupes = results.filter((r) => r.similarity >= 0.5);
  const toLink = results.filter((r) => r.similarity >= 0.2 && r.similarity < 0.5).slice(0, 3);

  const duration = Date.now() - startTime;

  logger.info("Related issues found", {
    event: "related_found",
    duration_ms: duration,
    ctx: {
      repo,
      total: results.length,
      potential_dupes: potentialDupes.length,
      to_link: toLink.length,
    },
  });

  return {
    toLink,
    potentialDupes,
    all: results,
  };
}

/**
 * Format related issues as markdown links for inclusion in issue body
 */
export function formatRelatedLinks(issues: RelatedIssue[]): string {
  if (issues.length === 0) {
    return "";
  }

  const lines = ["", "## Related Issues", ""];
  for (const issue of issues) {
    const stateEmoji = issue.state === "open" ? "" : "";
    lines.push(`- ${stateEmoji} #${issue.number}: ${issue.title}`);
  }

  return lines.join("\n");
}

/**
 * Generate duplicate warning message
 */
export function getDuplicateWarning(dupes: RelatedIssue[]): string | null {
  if (dupes.length === 0) {
    return null;
  }

  const issueRefs = dupes.map((d) => `#${d.number}`).join(", ");
  return `Potential duplicate(s) detected: ${issueRefs}. Please review before creating.`;
}
