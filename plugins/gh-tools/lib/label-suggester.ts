#!/usr/bin/env bun
/**
 * label-suggester.ts - AI-powered label suggestion with taxonomy awareness
 *
 * Uses gpt-4.1 via gh-models to suggest labels from existing repository taxonomy.
 * Falls back to keyword matching when gh-models is unavailable.
 *
 * Key principle: Only suggest labels that exist in the repository.
 */

import { execSync } from "node:child_process";
import { logger } from "./logger";
import { getLabels, type Label } from "./label-cache";
import { isGhModelsAvailable, type ContentType } from "./content-detector";

/**
 * Keyword patterns for fallback label matching
 */
const KEYWORD_LABEL_MAP: Record<string, string[]> = {
  bug: ["bug", "error", "crash", "broken", "fail", "exception", "defect"],
  enhancement: ["feature", "add", "implement", "improve", "enhancement", "request"],
  documentation: ["docs", "documentation", "readme", "typo", "example", "guide"],
  question: ["question", "help", "how", "support", "confused"],
  "good first issue": ["simple", "easy", "beginner", "first", "starter"],
  priority: ["urgent", "critical", "blocker", "important", "asap"],
  "help wanted": ["help", "wanted", "contribution", "volunteer"],
};

/**
 * Suggest labels using AI (gpt-4.1 via gh-models)
 */
function aiSuggestLabels(taxonomy: Label[], title: string, body: string): string[] {
  const startTime = Date.now();

  // Build label list for prompt
  const labelList = taxonomy.map((l) => `- ${l.name}: ${l.description || "No description"}`).join("\n");

  const prompt = `Suggest 2-4 labels from the EXISTING taxonomy only for this GitHub issue.
Never suggest labels that don't exist in the list below.
Return ONLY a JSON array of label names, nothing else.

AVAILABLE LABELS:
${labelList}

ISSUE TITLE: ${title}
ISSUE BODY:
${body.slice(0, 1500)}

Return format: ["label1", "label2"]`;

  const result = execSync(
    `gh models run openai/gpt-4.1 "${prompt.replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`,
    {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
      timeout: 30000,
    }
  ).trim();

  const duration = Date.now() - startTime;

  // Parse JSON response
  const jsonMatch = result.match(/\[.*\]/s);
  if (!jsonMatch) {
    logger.warn("AI label suggestion failed to parse", {
      event: "labels_parse_failed",
      ctx: { ai_model: "openai/gpt-4.1", raw_response: result.slice(0, 100) },
    });
    return [];
  }

  const suggestions = JSON.parse(jsonMatch[0]) as string[];

  // Validate all suggested labels exist in taxonomy
  const validLabels = suggestions.filter((label) =>
    taxonomy.some((t) => t.name.toLowerCase() === label.toLowerCase())
  );

  logger.info("AI label suggestion", {
    event: "labels_suggested",
    duration_ms: duration,
    ctx: { ai_model: "openai/gpt-4.1", labels_count: validLabels.length, suggested: validLabels, filtered_out: suggestions.length - validLabels.length },
  });

  return validLabels;
}

/**
 * Suggest labels using keyword matching (fallback)
 */
function keywordMatchLabels(taxonomy: Label[], title: string, body: string): string[] {
  const content = `${title} ${body}`.toLowerCase();
  const suggestions: string[] = [];

  // Check each label in taxonomy against keyword patterns
  for (const label of taxonomy) {
    const labelName = label.name.toLowerCase();

    // Check if content matches keywords for this label
    for (const [keywordLabel, keywords] of Object.entries(KEYWORD_LABEL_MAP)) {
      if (labelName.includes(keywordLabel) || keywordLabel.includes(labelName)) {
        const hasMatch = keywords.some((kw) => content.includes(kw));
        if (hasMatch && !suggestions.includes(label.name)) {
          suggestions.push(label.name);
        }
      }
    }

    // Also check if label name appears in content
    if (content.includes(labelName) && !suggestions.includes(label.name)) {
      suggestions.push(label.name);
    }
  }

  // Limit to 4 labels
  const limited = suggestions.slice(0, 4);

  logger.info("Keyword label matching", {
    event: "labels_suggested",
    ctx: { labels_count: limited.length, fallback_used: true, suggested: limited },
  });

  return limited;
}

/**
 * Suggest labels for an issue based on content
 *
 * @param repo - Repository in "owner/repo" format
 * @param title - Issue title
 * @param body - Issue body
 * @returns Array of suggested label names
 */
export function suggestLabels(repo: string, title: string, body: string): string[] {
  // Get repository's label taxonomy
  const taxonomy = getLabels(repo);

  if (taxonomy.length === 0) {
    logger.warn("No labels in repository", { event: "no_labels", ctx: { repo } });
    return [];
  }

  // Try AI suggestion if available
  if (isGhModelsAvailable()) {
    return aiSuggestLabels(taxonomy, title, body);
  }

  // Fallback to keyword matching
  return keywordMatchLabels(taxonomy, title, body);
}

/**
 * Get common labels that map to content types
 */
export function getLabelsForContentType(
  taxonomy: Label[],
  contentType: ContentType
): string[] {
  const typeToLabels: Record<ContentType, string[]> = {
    bug: ["bug", "defect", "error", "issue"],
    feature: ["enhancement", "feature", "feature-request", "improvement"],
    question: ["question", "help wanted", "support"],
    documentation: ["documentation", "docs", "readme"],
    unknown: [],
  };

  const targetLabels = typeToLabels[contentType];
  const matches = taxonomy.filter((label) =>
    targetLabels.some((target) => label.name.toLowerCase().includes(target))
  );

  return matches.map((l) => l.name);
}

/**
 * Check if gh-models extension needs to be installed
 */
export function checkGhModelsInstallation(): { available: boolean; installCommand?: string } {
  if (isGhModelsAvailable()) {
    return { available: true };
  }

  return {
    available: false,
    installCommand: "gh extension install github/gh-models",
  };
}
