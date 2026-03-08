#!/usr/bin/env bun
/**
 * PreToolUse reminder for academic paper/research URLs.
 *
 * Detects WebFetch/WebSearch targeting academic papers (arXiv, IEEE, ACM, etc.)
 * and reminds Claude to use /devops-tools:firecrawl-research-patterns instead.
 * Firecrawl handles JS-rendered pages, PDF extraction, and proper routing.
 *
 * This is a soft block (decision: "block" with exit 0) — Claude sees the
 * reminder but the operation proceeds normally.
 */

import { readFileSync } from "fs";

// --- Types ---

interface HookInput {
  tool_name: string;
  tool_input: {
    url?: string;
    prompt?: string;
    query?: string;  // WebSearch query
  };
}

// --- Academic domain patterns ---

const ACADEMIC_DOMAINS = [
  "arxiv.org",
  "doi.org",
  "springer.com",
  "sciencedirect.com",
  "ieee.org",
  "ieeexplore.ieee.org",
  "dl.acm.org",
  "acm.org",
  "scholar.google.com",
  "semanticscholar.org",
  "openreview.net",
  "proceedings.neurips.cc",
  "proceedings.mlr.press",
  "aclanthology.org",
  "biorxiv.org",
  "medrxiv.org",
  "ssrn.com",
  "researchgate.net",
  "pubmed.ncbi.nlm.nih.gov",
  "ncbi.nlm.nih.gov",
  "nature.com",
  "science.org",
  "jstor.org",
  "wiley.com",
  "tandfonline.com",
  "citeseerx.ist.psu.edu",
  "physionet.org",
  "mpra.ub.uni-muenchen.de",
  "papers.ssrn.com",
];

// Search query patterns that indicate academic research
const RESEARCH_QUERY_PATTERNS = [
  /\barxiv\b/i,
  /\bpaper\b.*\b(20[12]\d)\b/i,   // "paper 2024"
  /\b(20[12]\d)\b.*\bpaper\b/i,   // "2024 paper"
  /\bresearch\s+paper\b/i,
  /\bacademic\s+paper\b/i,
  /\bpeer[- ]reviewed\b/i,
  /\bjournal\s+(article|paper)\b/i,
  /\bconference\s+paper\b/i,
  /\bpublication\b/i,
  /\bdoi:\s*10\./i,
  /\bpreprint\b/i,
];

// --- Main ---

function main(): void {
  let rawInput: string;
  try {
    rawInput = readFileSync("/dev/stdin", "utf-8").trim();
  } catch {
    console.log("{}");
    return;
  }

  if (!rawInput) {
    console.log("{}");
    return;
  }

  // Fast path: check raw input for any academic keyword before parsing JSON
  const hasAcademicSignal = ACADEMIC_DOMAINS.some(d => rawInput.includes(d))
    || /arxiv|doi\.org|preprint|research\s+paper|\bpaper\b.*20[12]\d|20[12]\d.*\bpaper\b|peer.reviewed|conference\s+paper|\bpublication\b/i.test(rawInput);

  if (!hasAcademicSignal) {
    console.log("{}");
    return;
  }

  let input: HookInput;
  try {
    input = JSON.parse(rawInput);
  } catch {
    console.log("{}");
    return;
  }

  const toolName = input.tool_name;
  const url = input.tool_input?.url ?? "";
  const query = input.tool_input?.query ?? input.tool_input?.prompt ?? "";

  let isAcademic = false;
  let matchedSignal = "";

  // Check URL against academic domains
  if (url) {
    for (const domain of ACADEMIC_DOMAINS) {
      if (url.includes(domain)) {
        isAcademic = true;
        matchedSignal = domain;
        break;
      }
    }
    // Check for PDF URLs (common for papers)
    if (!isAcademic && /\.pdf$/i.test(url)) {
      // PDF from any domain could be a paper — check if query/prompt mentions research
      if (RESEARCH_QUERY_PATTERNS.some(p => p.test(query))) {
        isAcademic = true;
        matchedSignal = "PDF + research context";
      }
    }
  }

  // Check search queries for research patterns
  if (!isAcademic && query) {
    for (const pattern of RESEARCH_QUERY_PATTERNS) {
      if (pattern.test(query)) {
        isAcademic = true;
        matchedSignal = `query: "${query.slice(0, 60)}"`;
        break;
      }
    }
  }

  if (!isAcademic) {
    console.log("{}");
    return;
  }

  const reason = `[FIRECRAWL-RESEARCH] Academic paper detected (${matchedSignal})

Use /devops-tools:firecrawl-research-patterns instead of ${toolName}.

WHY:
- WebFetch fails on PDFs (returns binary), JS-heavy sites (IEEE, ACM), and paywalls
- Firecrawl routes papers optimally: arxiv → direct HTML, Semantic Scholar → API, others → JS-rendered scrape
- Persists raw corpus with academic frontmatter for re-analysis
- Self-hosted on littleblack (ZeroTier) — no rate limits

QUICK FIX for arxiv:
  Use /html/ instead of /abs/ or /pdf/:
  https://arxiv.org/html/<ID>  ← full paper as readable HTML`;

  // Soft reminder: allow the operation but show the reason to Claude
  console.log(JSON.stringify({
    hookSpecificOutput: {
      permissionDecision: "allow",
      permissionDecisionReason: reason
    }
  }));
}

main();
