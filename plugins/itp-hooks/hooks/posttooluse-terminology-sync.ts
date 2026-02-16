#!/usr/bin/env bun
/**
 * PostToolUse hook: Project CLAUDE.md to Global GLOSSARY.md sync with duplicate detection.
 *
 * When a project's CLAUDE.md Terminology section is edited, this hook:
 * 1. Extracts terms from the project's Terminology table
 * 2. Scans ALL known CLAUDE.md files for terminology
 * 3. Detects duplicates/conflicts across projects
 * 4. BLOCKS if conflicts found (requires immediate resolution)
 * 5. Merges new terms into global GLOSSARY.md
 * 6. Triggers Vale vocabulary sync
 *
 * Pattern: Follows lifecycle-reference.md TypeScript template.
 * Trigger: After Edit or Write on project CLAUDE.md files.
 */

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { Glob, $ } from "bun";
import { trackHookError } from "./lib/hook-error-tracker.ts";

// ============================================================================
// CONFIGURATION
// ============================================================================

const HOME = process.env.HOME || "";
const GLOSSARY = join(HOME, ".claude/docs/GLOSSARY.md");
const SYNC_SCRIPT = join(HOME, ".claude/tools/bin/glossary-sync.ts");

// Default scan paths - can be overridden by GLOSSARY.md config
// Supports up to 5 levels deep for nested project structures like:
// ~/eon/alpha-forge/examples/research/models/CLAUDE.md
const DEFAULT_SCAN_PATHS = [
  `${HOME}/eon/*/CLAUDE.md`,
  `${HOME}/eon/*/*/CLAUDE.md`,
  `${HOME}/eon/*/*/*/CLAUDE.md`,
  `${HOME}/eon/*/*/*/*/CLAUDE.md`,
  `${HOME}/eon/*/*/*/*/*/CLAUDE.md`,
  GLOSSARY,
];

// ============================================================================
// TYPES
// ============================================================================

interface PostToolUseInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    [key: string]: unknown;
  };
}

interface Term {
  term: string;
  acronym: string;
  definition: string;
  file: string;
  line: number;
  project: string;
}

interface Conflict {
  type: "definition" | "acronym" | "acronym_collision";
  term: string;
  acronym?: string;
  occurrences: Array<{ file: string; line: number; value: string; project: string }>;
}

interface HookResult {
  exitCode: number;
  stdout?: string;
  stderr?: string;
}

// ============================================================================
// HELPERS
// ============================================================================

async function parseStdin(): Promise<PostToolUseInput | null> {
  try {
    const stdin = await Bun.stdin.text();
    if (!stdin.trim()) return null;
    return JSON.parse(stdin) as PostToolUseInput;
  } catch {
    return null;
  }
}

function createVisibilityOutput(reason: string): string {
  return JSON.stringify({
    decision: "block",
    reason: reason,
  });
}

/**
 * Get scan paths from GLOSSARY.md configuration or use defaults.
 */
function getScanPaths(): string[] {
  if (!existsSync(GLOSSARY)) return DEFAULT_SCAN_PATHS;

  const content = readFileSync(GLOSSARY, "utf8");
  const match = content.match(/<!-- SCAN_PATHS:\n([\s\S]*?)-->/);

  if (!match) return DEFAULT_SCAN_PATHS;

  const paths = match[1]
    .split("\n")
    .map((line) => line.replace(/^- /, "").trim())
    .filter((line) => line && !line.startsWith("#"))
    .map((path) => path.replace("~", HOME));

  return paths.length > 0 ? paths : DEFAULT_SCAN_PATHS;
}

/**
 * Get project name from file path.
 */
function getProjectName(filePath: string): string {
  const dir = dirname(filePath);
  // Try to find project root (directory containing .git or mise.toml)
  let current = dir;
  for (let i = 0; i < 10; i++) {
    if (
      existsSync(join(current, ".git")) ||
      existsSync(join(current, "mise.toml"))
    ) {
      return basename(current);
    }
    current = dirname(current);
  }
  return basename(dir);
}

/**
 * Extract terminology table from CLAUDE.md content.
 */
function extractTerms(content: string, filePath: string): Term[] {
  const terms: Term[] = [];
  const projectName = getProjectName(filePath);

  // Find Terminology section
  const match = content.match(/## Terminology\s*\n([\s\S]*?)(?=\n## |$)/i);
  if (!match) return terms;

  const section = match[1];
  const lines = section.split("\n");
  let lineNumber =
    content.substring(0, content.indexOf(match[0])).split("\n").length;

  for (const line of lines) {
    lineNumber++;
    if (!line.startsWith("|")) continue;

    const cells = line
      .split("|")
      .map((c) => c.trim())
      .filter(Boolean);
    if (
      cells.length < 2 ||
      cells[0].toLowerCase() === "term" ||
      cells[0].startsWith("---")
    )
      continue;

    const term = cells[0].replace(/\*\*/g, "");
    const secondCol = cells[1] || "";
    const thirdCol = cells[2] || "";

    // Detect if second column is acronym (uppercase, short) or definition
    const isAcronym =
      /^[A-Z][A-Z0-9]*$/.test(secondCol) && secondCol.length <= 10;

    terms.push({
      term,
      acronym: isAcronym ? secondCol : "-",
      definition: isAcronym ? thirdCol : secondCol,
      file: filePath,
      line: lineNumber,
      project: projectName,
    });
  }

  return terms;
}

// ============================================================================
// DUPLICATE DETECTION
// ============================================================================

/**
 * Scan all files matching configured paths.
 */
async function scanAllFiles(): Promise<Term[]> {
  const allTerms: Term[] = [];
  const scanPaths = getScanPaths();

  for (const pattern of scanPaths) {
    const glob = new Glob(pattern);
    for await (const filePath of glob.scan({ absolute: true })) {
      if (!existsSync(filePath)) continue;
      const content = readFileSync(filePath, "utf8");
      const terms = extractTerms(content, filePath);
      allTerms.push(...terms);
    }
  }

  return allTerms;
}

/**
 * Detect conflicts across all terms.
 */
function detectConflicts(terms: Term[]): Conflict[] {
  const conflicts: Conflict[] = [];

  // Index by term name (lowercase)
  const termIndex = new Map<string, Term[]>();
  const acronymIndex = new Map<string, Term[]>();

  for (const t of terms) {
    const termKey = t.term.toLowerCase();
    const acronymKey = t.acronym.toUpperCase();

    if (!termIndex.has(termKey)) termIndex.set(termKey, []);
    termIndex.get(termKey)!.push(t);

    if (acronymKey !== "-") {
      if (!acronymIndex.has(acronymKey)) acronymIndex.set(acronymKey, []);
      acronymIndex.get(acronymKey)!.push(t);
    }
  }

  // Check for conflicting definitions of same term
  for (const [term, defs] of termIndex) {
    if (defs.length <= 1) continue;

    const uniqueDefs = new Set(defs.map((d) => d.definition.toLowerCase().trim()));
    if (uniqueDefs.size > 1) {
      conflicts.push({
        type: "definition",
        term,
        occurrences: defs.map((d) => ({
          file: d.file,
          line: d.line,
          value: d.definition,
          project: d.project,
        })),
      });
    }

    // Check if acronyms differ for same term
    const uniqueAcronyms = new Set(defs.map((d) => d.acronym.toUpperCase()));
    uniqueAcronyms.delete("-");
    if (uniqueAcronyms.size > 1) {
      conflicts.push({
        type: "acronym",
        term,
        occurrences: defs.map((d) => ({
          file: d.file,
          line: d.line,
          value: d.acronym,
          project: d.project,
        })),
      });
    }
  }

  // Check for acronym collisions (same acronym, different terms)
  for (const [acronym, usages] of acronymIndex) {
    const uniqueTerms = new Set(usages.map((u) => u.term.toLowerCase()));
    if (uniqueTerms.size > 1) {
      conflicts.push({
        type: "acronym_collision",
        acronym,
        term: [...uniqueTerms].join(", "),
        occurrences: usages.map((u) => ({
          file: u.file,
          line: u.line,
          value: u.term,
          project: u.project,
        })),
      });
    }
  }

  return conflicts;
}

/**
 * Format conflict report for Claude.
 */
function formatConflictReport(conflicts: Conflict[]): string {
  const sections: string[] = [];

  for (const c of conflicts) {
    if (c.type === "definition") {
      sections.push(`### CONFLICTING DEFINITIONS: "${c.term}"

${c.occurrences.map((x) => `- **${x.project}** (${basename(x.file)}:${x.line}): ${x.value}`).join("\n")}

**Action Required**: Consolidate to ONE definition in GLOSSARY.md.`);
    }

    if (c.type === "acronym") {
      sections.push(`### CONFLICTING ACRONYMS: "${c.term}"

${c.occurrences.map((x) => `- **${x.project}** (${basename(x.file)}:${x.line}): ${x.value}`).join("\n")}

**Action Required**: Standardize to ONE acronym in GLOSSARY.md.`);
    }

    if (c.type === "acronym_collision") {
      sections.push(`### ACRONYM COLLISION: "${c.acronym}"

Used for different terms:
${c.occurrences.map((x) => `- **${x.project}** (${basename(x.file)}:${x.line}): ${x.value}`).join("\n")}

**Action Required**: Rename one acronym to avoid ambiguity.`);
    }
  }

  return sections.join("\n\n---\n\n");
}

// ============================================================================
// MERGE NEW TERMS
// ============================================================================

/**
 * Merge new terms into GLOSSARY.md.
 * Returns list of newly added terms.
 */
function mergeIntoGlossary(newTerms: Term[]): string[] {
  if (!existsSync(GLOSSARY)) {
    return [];
  }

  const content = readFileSync(GLOSSARY, "utf8");
  const existingTerms = new Set<string>();
  const existingAcronyms = new Set<string>();

  // Extract existing term names AND acronyms (case-insensitive)
  const pattern = /^\|\s*\*?\*?([^|*]+)\*?\*?\s*\|\s*([^|]+)\s*\|/gm;
  let match;
  while ((match = pattern.exec(content)) !== null) {
    const term = match[1].trim().toLowerCase();
    const acronym = match[2].trim().toUpperCase();
    existingTerms.add(term);
    if (acronym && acronym !== "-") {
      existingAcronyms.add(acronym);
    }
  }

  // Find new terms not in glossary (check both term name AND acronym)
  const toAdd = newTerms.filter((t) => {
    const termLower = t.term.toLowerCase();
    const acronymUpper = t.acronym.toUpperCase();

    // Skip if term already exists
    if (existingTerms.has(termLower)) return false;

    // Skip if this is just an acronym that already exists as a term or acronym
    if (existingAcronyms.has(termLower.toUpperCase())) return false;
    if (existingTerms.has(acronymUpper.toLowerCase())) return false;

    return true;
  });

  if (toAdd.length === 0) return [];

  // Find insertion point (before "## Maintenance" or end of file)
  let insertPos = content.indexOf("## Maintenance");
  if (insertPos === -1) insertPos = content.length;

  // Find the right section to add to (look for Trading Fitness Domain section)
  const domainPos = content.indexOf("## Trading Fitness Domain");
  if (domainPos !== -1) {
    // Find end of table in that section
    const sectionEnd = content.indexOf("\n## ", domainPos + 1);
    if (sectionEnd !== -1) {
      // Find last table row before section end
      const tableLines = content.substring(domainPos, sectionEnd).split("\n");
      let lastTableLine = domainPos;
      for (let i = 0; i < tableLines.length; i++) {
        if (tableLines[i].startsWith("|") && !tableLines[i].includes("---")) {
          lastTableLine = domainPos + tableLines.slice(0, i + 1).join("\n").length;
        }
      }
      insertPos = lastTableLine + 1;
    }
  }

  // Format new rows
  const newRows = toAdd
    .map(
      (t) =>
        `| **${t.term}** | ${t.acronym} | ${t.definition} | - | ${t.project} |`,
    )
    .join("\n");

  // Insert new terms
  const updated =
    content.slice(0, insertPos) + "\n" + newRows + content.slice(insertPos);
  writeFileSync(GLOSSARY, updated);

  return toAdd.map((t) => t.term);
}

// ============================================================================
// MAIN LOGIC
// ============================================================================

async function runHook(): Promise<HookResult> {
  const input = await parseStdin();
  if (!input) {
    return { exitCode: 0 };
  }

  const { tool_name, tool_input } = input;
  const filePath = tool_input?.file_path || "";

  // Only trigger on Edit/Write
  if (tool_name !== "Edit" && tool_name !== "Write") {
    return { exitCode: 0 };
  }

  // Only trigger on CLAUDE.md files
  if (!filePath.endsWith("CLAUDE.md")) {
    return { exitCode: 0 };
  }

  // Skip global GLOSSARY.md (handled by glossary-sync hook)
  if (filePath.includes(".claude/docs/GLOSSARY.md")) {
    return { exitCode: 0 };
  }

  // Check if file exists
  if (!existsSync(filePath)) {
    return { exitCode: 0 };
  }

  // Read CLAUDE.md content
  const content = readFileSync(filePath, "utf8");

  // Check if it has a Terminology section
  if (!/## Terminology/i.test(content)) {
    return { exitCode: 0 };
  }

  // PHASE 1: Scan all projects for terminology
  const allTerms = await scanAllFiles();

  // PHASE 2: Detect conflicts ACROSS ALL PROJECTS
  const conflicts = detectConflicts(allTerms);

  // PHASE 3: If conflicts found, BLOCK and require immediate resolution
  if (conflicts.length > 0) {
    const report = formatConflictReport(conflicts);

    const reason = `[TERMINOLOGY-SYNC] DUPLICATE/CONFLICTING TERMS DETECTED

${conflicts.length} conflict(s) found across project CLAUDE.md files.

${report}

---

**IMMEDIATE ACTION REQUIRED**:
1. Review the conflicting definitions above
2. Update GLOSSARY.md with the canonical definition
3. Update project CLAUDE.md files to use consistent terminology
4. Re-run this edit after conflicts are resolved

Vale cannot proceed until terminology is consistent across all projects.`;

    return {
      exitCode: 0,
      stdout: createVisibilityOutput(reason),
    };
  }

  // PHASE 4: No conflicts - proceed with sync
  const projectName = getProjectName(filePath);
  const terms = extractTerms(content, filePath);

  if (terms.length === 0) {
    return { exitCode: 0 };
  }

  // Merge into global GLOSSARY.md
  const added = mergeIntoGlossary(terms);

  // Trigger glossary sync to update Vale vocabulary
  if (added.length > 0 && existsSync(SYNC_SCRIPT)) {
    try {
      await $`bun ${SYNC_SCRIPT}`.quiet().nothrow();
    } catch {
      // Sync failed, but we still added terms
    }
  }

  if (added.length > 0) {
    const reason = `[TERMINOLOGY-SYNC] Synced ${terms.length} terms from ${projectName}/CLAUDE.md to global glossary.

**Newly added terms**: ${added.join(", ")}

**Actions taken**:
1. Merged new terms into ~/.claude/docs/GLOSSARY.md
2. Synced Vale vocabulary files (accept.txt, Terminology.yml)

Vale will now enforce consistent terminology for these terms across all projects.`;

    return {
      exitCode: 0,
      stdout: createVisibilityOutput(reason),
    };
  }

  // All terms already exist, no sync needed
  return { exitCode: 0 };
}

// ============================================================================
// ENTRY POINT
// ============================================================================

async function main(): Promise<never> {
  let result: HookResult;

  try {
    result = await runHook();
  } catch (err: unknown) {
    trackHookError("posttooluse-terminology-sync", err instanceof Error ? err.message : String(err));
    return process.exit(0);
  }

  if (result.stderr) trackHookError("posttooluse-terminology-sync", result.stderr);
  if (result.stdout) console.log(result.stdout);
  return process.exit(result.exitCode);
}

void main();
