#!/usr/bin/env bun
/**
 * content-detector.ts - Content type detection for GitHub issues
 *
 * Detects issue type (bug, feature, question, documentation) using:
 * 1. AI via gh-models (gpt-4.1) if available
 * 2. Keyword-based fallback
 *
 * Returns content type for template selection and label suggestions.
 */

import { execSync } from "node:child_process";
import { logger } from "./logger";

export type ContentType = "bug" | "feature" | "question" | "documentation" | "unknown";

/**
 * Keyword patterns for fallback detection
 */
const KEYWORD_PATTERNS: Record<ContentType, RegExp[]> = {
  bug: [
    /\b(bug|error|crash|broken|fail|exception|stacktrace|stack trace)\b/i,
    /\b(not working|doesn't work|won't work|can't|cannot)\b/i,
    /\b(issue|problem|defect|regression)\b/i,
    /TypeError|ReferenceError|SyntaxError|Error:/i,
  ],
  feature: [
    /\b(feature|enhancement|add|implement|support|would be nice|request)\b/i,
    /\b(improve|suggestion|propose|idea|wish|want)\b/i,
    /\b(new|additional|capability|functionality)\b/i,
  ],
  question: [
    /\b(how|what|why|when|where|which|who)\b.*\?/i,
    /\b(question|help|confused|understand|explain|clarify)\b/i,
    /\b(wondering|curious|asking|ask)\b/i,
  ],
  documentation: [
    /\b(docs?|documentation|readme|typo|spelling|grammar)\b/i,
    /\b(example|tutorial|guide|instructions|clarify)\b/i,
    /\b(outdated|update|incorrect|wrong)\b.*\b(doc|readme|guide)\b/i,
  ],
  unknown: [],
};

/**
 * Check if gh-models extension is available
 */
export function isGhModelsAvailable(): boolean {
  const result = execSync("gh extension list 2>/dev/null || true", {
    encoding: "utf-8",
    stdio: ["pipe", "pipe", "pipe"],
  });
  return result.includes("gh-models") || result.includes("github/gh-models");
}

/**
 * Detect content type using AI (gpt-4.1 via gh-models)
 */
function aiDetectType(content: string): ContentType {
  const startTime = Date.now();

  const prompt = `Classify this GitHub issue content into exactly one category.
Categories: bug, feature, question, documentation
Return ONLY the category name, nothing else.

Content:
${content.slice(0, 2000)}`;

  const result = execSync(
    `gh models run openai/gpt-4.1 "${prompt.replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`,
    {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
      timeout: 30000,
    }
  ).trim().toLowerCase();

  const duration = Date.now() - startTime;

  // Validate response is one of our types
  const validTypes: ContentType[] = ["bug", "feature", "question", "documentation"];
  const detectedType = validTypes.find((t) => result.includes(t)) || "unknown";

  logger.info("AI content type detection", {
    event: "type_detected",
    duration_ms: duration,
    ctx: { ai_model: "openai/gpt-4.1", detected_type: detectedType, raw_response: result.slice(0, 50) },
  });

  return detectedType;
}

/**
 * Detect content type using keyword patterns (fallback)
 */
function keywordDetectType(content: string): ContentType {
  const scores: Record<ContentType, number> = {
    bug: 0,
    feature: 0,
    question: 0,
    documentation: 0,
    unknown: 0,
  };

  // Score each type based on pattern matches
  for (const [type, patterns] of Object.entries(KEYWORD_PATTERNS)) {
    for (const pattern of patterns) {
      const matches = content.match(pattern);
      if (matches) {
        scores[type as ContentType] += matches.length;
      }
    }
  }

  // Find highest scoring type
  let maxScore = 0;
  let detectedType: ContentType = "unknown";

  for (const [type, score] of Object.entries(scores)) {
    if (score > maxScore) {
      maxScore = score;
      detectedType = type as ContentType;
    }
  }

  logger.info("Keyword content type detection", {
    event: "type_detected",
    ctx: { fallback_used: true, detected_type: detectedType, score: maxScore },
  });

  return detectedType;
}

/**
 * Detect content type from issue title and body
 *
 * Uses AI if available, falls back to keyword matching.
 *
 * @param title - Issue title
 * @param body - Issue body
 * @returns Detected content type
 */
export function detectContentType(title: string, body: string): ContentType {
  const content = `${title}\n\n${body}`;

  // Try AI detection if gh-models is available
  if (isGhModelsAvailable()) {
    return aiDetectType(content);
  }

  // Fallback to keyword detection
  return keywordDetectType(content);
}

/**
 * Get content type display name
 */
export function getContentTypeDisplayName(type: ContentType): string {
  const names: Record<ContentType, string> = {
    bug: "Bug Report",
    feature: "Feature Request",
    question: "Question",
    documentation: "Documentation",
    unknown: "General",
  };
  return names[type];
}

/**
 * Get suggested prefix for issue title based on content type
 */
export function getTitlePrefix(type: ContentType): string {
  const prefixes: Record<ContentType, string> = {
    bug: "Bug:",
    feature: "Feature:",
    question: "Question:",
    documentation: "Docs:",
    unknown: "",
  };
  return prefixes[type];
}
