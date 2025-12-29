/**
 * Markdown parsing utilities using marked + gray-matter
 *
 * Provides frontmatter extraction, link extraction, and code block extraction
 * using AST-based parsing for accuracy.
 */

import { Marked, type Token, type Tokens } from "marked";
import matter from "gray-matter";
import type {
  SkillFrontmatter,
  ParsedMarkdown,
  ExtractedLink,
  CodeBlock,
} from "./types.js";

// ============================================================================
// Markdown Parsing
// ============================================================================

/**
 * Parse markdown content with frontmatter extraction
 */
export function parseMarkdown(content: string): ParsedMarkdown {
  let frontmatter: SkillFrontmatter | null = null;
  let frontmatterError = "";
  let markdownContent = content;

  // Check for frontmatter delimiter
  if (!content.startsWith("---")) {
    return {
      frontmatter: null,
      frontmatterError: "No YAML frontmatter found (must start with ---)",
      content,
    };
  }

  // Parse frontmatter with gray-matter
  try {
    const parsed = matter(content);
    frontmatter = parsed.data as SkillFrontmatter;
    markdownContent = parsed.content;

    // Check if frontmatter was actually found (not just empty)
    if (Object.keys(frontmatter).length === 0) {
      // Check if there's a closing delimiter
      const hasClosingDelimiter = content.indexOf("\n---", 4) !== -1;
      if (!hasClosingDelimiter) {
        return {
          frontmatter: null,
          frontmatterError: "Invalid YAML frontmatter (missing closing ---)",
          content,
        };
      }
    }
  } catch (err) {
    frontmatterError = `Invalid YAML syntax: ${err instanceof Error ? err.message : String(err)}`;
  }

  return {
    frontmatter,
    frontmatterError,
    content: markdownContent,
  };
}

// ============================================================================
// Link Extraction
// ============================================================================

/**
 * Extract all links from markdown content using marked AST
 */
export function extractLinks(content: string): ExtractedLink[] {
  const links: ExtractedLink[] = [];
  const marked = new Marked();

  try {
    const tokens = marked.lexer(content);
    walkTokensForLinks(tokens, links, content);
  } catch (err) {
    // If AST parsing fails, return empty (caller should handle)
    console.error(`Link extraction failed: ${err}`);
  }

  return links;
}

/**
 * Recursively walk tokens to find links
 */
function walkTokensForLinks(
  tokens: Token[],
  links: ExtractedLink[],
  originalContent: string
): void {
  for (const token of tokens) {
    if (token.type === "link") {
      const linkToken = token as Tokens.Link;
      // Calculate line number from raw position
      const lineNumber = findLineNumber(originalContent, linkToken.raw);
      links.push({
        text: extractLinkText(linkToken),
        href: linkToken.href,
        lineNumber,
        column: 1, // marked doesn't provide column info
      });
    }

    // Recurse into nested tokens
    if ("tokens" in token && Array.isArray(token.tokens)) {
      walkTokensForLinks(token.tokens, links, originalContent);
    }

    // Handle list items
    if ("items" in token && Array.isArray(token.items)) {
      for (const item of token.items) {
        if ("tokens" in item && Array.isArray(item.tokens)) {
          walkTokensForLinks(item.tokens, links, originalContent);
        }
      }
    }
  }
}

/**
 * Extract display text from link token
 */
function extractLinkText(token: Tokens.Link): string {
  if (!token.tokens) return token.text || "";

  return token.tokens
    .map((t) => {
      if ("text" in t) return t.text;
      if ("raw" in t) return t.raw;
      return "";
    })
    .join("");
}

/**
 * Find line number of a substring in content
 */
function findLineNumber(content: string, substring: string): number {
  const index = content.indexOf(substring);
  if (index === -1) return 1;
  return content.slice(0, index).split("\n").length;
}

// ============================================================================
// Code Block Extraction
// ============================================================================

/**
 * Extract all code blocks from markdown content
 */
export function extractCodeBlocks(content: string): CodeBlock[] {
  const blocks: CodeBlock[] = [];
  const marked = new Marked();

  try {
    const tokens = marked.lexer(content);

    for (const token of tokens) {
      if (token.type === "code") {
        const codeToken = token as Tokens.Code;
        blocks.push({
          lang: codeToken.lang,
          text: codeToken.text,
          lineNumber: findLineNumber(content, token.raw),
        });
      }
    }
  } catch (err) {
    console.error(`Code block extraction failed: ${err}`);
  }

  return blocks;
}

/**
 * Extract only bash code blocks from markdown content
 */
export function extractBashBlocks(content: string): CodeBlock[] {
  return extractCodeBlocks(content).filter(
    (block) => block.lang === "bash" || block.lang === "sh"
  );
}

// ============================================================================
// Content Stripping (for regex-based fallback)
// ============================================================================

/**
 * Strip fenced code blocks from content
 */
export function stripFencedCodeBlocks(content: string): string {
  return content.replace(/```[\s\S]*?```/g, "");
}

/**
 * Strip inline code from content
 */
export function stripInlineCode(content: string): string {
  return content.replace(/`[^`]+`/g, "");
}

/**
 * Strip all code from content (both fenced and inline)
 */
export function stripAllCode(content: string): string {
  return stripInlineCode(stripFencedCodeBlocks(content));
}

// ============================================================================
// Line Counting
// ============================================================================

/**
 * Count lines in content (for S1 compliance checking)
 */
export function countLines(content: string): number {
  return content.split("\n").length;
}

/**
 * Count non-empty lines in content
 */
export function countNonEmptyLines(content: string): number {
  return content.split("\n").filter((line) => line.trim().length > 0).length;
}
