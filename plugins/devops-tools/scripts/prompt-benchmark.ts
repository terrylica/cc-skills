#!/usr/bin/env bun
/**
 * Prompt Benchmark — Scientific evaluation framework for session-debrief prompts.
 *
 * Modes:
 *   --mode freeze    Save current session output as a frozen corpus fixture
 *   --mode matrix    Run all 3 goals against a corpus, report quantitative metrics
 *   --mode ab        A/B compare two prompt variants using MiniMax as judge
 *   --mode variance  Run goal N three times, measure output stability (Jaccard)
 *
 * Usage:
 *   bun run prompt-benchmark.ts --mode freeze --goal 2 --since 8 --name baseline-8h
 *   bun run prompt-benchmark.ts --mode matrix --corpus baseline-8h
 *   bun run prompt-benchmark.ts --mode ab --corpus baseline-8h --goal 2 --variant-a g2-v5 --variant-b g2-v6
 *   bun run prompt-benchmark.ts --mode variance --corpus baseline-8h --goal 2 --runs 3
 *
 * Corpus fixtures: ~/.claude/benchmarks/session-debrief/corpus/<name>/
 *   structured-log.txt  — frozen --dry output (session log fed to MiniMax)
 *   session-summary.txt — frozen session metadata summary
 *   output-g<N>.txt     — reference output for each goal
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync } from "fs";
import { homedir } from "os";
import { join } from "path";

// ── Config ─────────────────────────────────────────────────────────────────────

const MINIMAX_API_URL = "https://api.minimax.io/anthropic/v1/messages";
// MINIMAX_MODEL: single source of truth is ~/.config/mise/config.toml
const MINIMAX_MODEL = process.env.MINIMAX_MODEL ?? "MiniMax-M2.7-highspeed";
const CORPUS_BASE = join(homedir(), ".claude/benchmarks/session-debrief/corpus");

// ── API Key ────────────────────────────────────────────────────────────────────

function getApiKey(): string {
  const secretsPath = join(homedir(), ".claude/.secrets/ccterrybot-telegram");
  const content = readFileSync(secretsPath, "utf-8");
  for (const line of content.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.startsWith("MINIMAX_API_KEY=")) {
      return trimmed.slice("MINIMAX_API_KEY=".length).replace(/^["']|["']$/g, "");
    }
  }
  throw new Error("MINIMAX_API_KEY not found in secrets file");
}

// ── MiniMax API ────────────────────────────────────────────────────────────────

async function callMiniMax(
  apiKey: string,
  system: string,
  userContent: string,
  maxTokens: number = 8192,
): Promise<string> {
  const res = await fetch(MINIMAX_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MINIMAX_MODEL,
      max_tokens: maxTokens,
      system,
      messages: [{ role: "user", content: userContent }],
    }),
    signal: AbortSignal.timeout(300_000),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`MiniMax API ${res.status}: ${body.slice(0, 300)}`);
  }

  const result: any = await res.json();
  if (result.content && Array.isArray(result.content)) {
    return result.content.map((b: any) => b.text || "").join("");
  }
  return JSON.stringify(result, null, 2);
}

// ── Corpus Management ─────────────────────────────────────────────────────────

function corpusDir(name: string): string {
  return join(CORPUS_BASE, name);
}

function loadCorpus(name: string): {
  structuredLog: string;
  sessionSummary: string;
  outputs: Record<number, string>;
} {
  const dir = corpusDir(name);
  if (!existsSync(dir)) {
    throw new Error(`Corpus not found: ${dir}\nCreate it with: --mode freeze --name ${name}`);
  }

  const structuredLog = readFileSync(join(dir, "structured-log.txt"), "utf-8");
  const sessionSummary = readFileSync(join(dir, "session-summary.txt"), "utf-8");

  const outputs: Record<number, string> = {};
  for (const g of [1, 2, 3]) {
    const p = join(dir, `output-g${g}.txt`);
    if (existsSync(p)) outputs[g] = readFileSync(p, "utf-8");
  }

  return { structuredLog, sessionSummary, outputs };
}

function saveCorpus(name: string, structuredLog: string, sessionSummary: string): void {
  const dir = corpusDir(name);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "structured-log.txt"), structuredLog);
  writeFileSync(join(dir, "session-summary.txt"), sessionSummary);
  console.error(`[corpus] Saved to ${dir}`);
}

function saveCorpusOutput(name: string, goal: number, output: string): void {
  const dir = corpusDir(name);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `output-g${goal}.txt`), output);
  console.error(`[corpus] Saved goal ${goal} output to ${dir}/output-g${goal}.txt`);
}

function listCorpora(): string[] {
  if (!existsSync(CORPUS_BASE)) return [];
  return readdirSync(CORPUS_BASE).filter((f) => {
    return existsSync(join(CORPUS_BASE, f, "structured-log.txt"));
  });
}

// ── Metrics ───────────────────────────────────────────────────────────────────

/**
 * Goal 2 ordering score: what fraction of adjacent findings within a session
 * appear with ascending turn numbers.
 * Score = correctPairs / adjacentPairs (1.0 = perfectly ordered)
 */
function goal2OrderingScore(output: string): { score: number; details: string } {
  // Extract T<N> from headings: ### T644 [ERROR] or ### [ERROR] ... - **Turn**: T644
  const headingTurns: number[] = [];

  // Pattern 1: ### T<N> [TYPE] or ### T<N>-T<M> [TYPE] (turn-first headings)
  // Extracts only the FIRST turn number (start of range)
  const headingRe = /^###\s+T(\d+)(?:-T\d+)?\s+\[/gm;
  let m: RegExpExecArray | null;
  while ((m = headingRe.exec(output)) !== null) {
    headingTurns.push(parseInt(m[1], 10));
  }

  // Pattern 2: - **Turn**: T<N> (legacy inline turn field)
  if (headingTurns.length === 0) {
    const turnFieldRe = /\*\*Turn\*\*:\s*T(\d+)/g;
    while ((m = turnFieldRe.exec(output)) !== null) {
      headingTurns.push(parseInt(m[1], 10));
    }
  }

  if (headingTurns.length < 2) {
    return { score: 1.0, details: `only ${headingTurns.length} finding(s) — no pairs to compare` };
  }

  // Split by session headers to compare within-session only
  const sessionBlocks = output.split(/^## Session:/m).slice(1);
  let correctPairs = 0;
  let totalPairs = 0;

  for (const block of sessionBlocks) {
    const blockTurns: number[] = [];
    const hRe = /^###\s+T(\d+)(?:-T\d+)?\s+\[/gm;
    while ((m = hRe.exec(block)) !== null) blockTurns.push(parseInt(m[1], 10));
    if (blockTurns.length === 0) {
      const tRe = /\*\*Turn\*\*:\s*T(\d+)/g;
      while ((m = tRe.exec(block)) !== null) blockTurns.push(parseInt(m[1], 10));
    }
    for (let i = 1; i < blockTurns.length; i++) {
      totalPairs++;
      if (blockTurns[i] >= blockTurns[i - 1]) correctPairs++;
    }
  }

  // Fallback: no session blocks found — treat all as one session
  if (totalPairs === 0 && headingTurns.length >= 2) {
    for (let i = 1; i < headingTurns.length; i++) {
      totalPairs++;
      if (headingTurns[i] >= headingTurns[i - 1]) correctPairs++;
    }
  }

  const score = totalPairs > 0 ? correctPairs / totalPairs : 1.0;
  return {
    score,
    details: `${correctPairs}/${totalPairs} adjacent pairs in order (${headingTurns.length} findings total)`,
  };
}

/**
 * Goal 2 finding count: total number of error/warning/deprecation/anomaly entries.
 * Handles both single-turn (T12) and range (T12-T34) prefixes.
 */
function goal2FindingCount(output: string): number {
  // Matches: ### T12 [ERROR], ### T12-T34 [ERROR], ### [ERROR]
  const matches = output.match(/^###\s+(T\d+(?:-T\d+)?\s+)?\[(ERROR|WARNING|DEPRECATION|ANOMALY)\]/gm);
  return matches ? matches.length : 0;
}

/**
 * Goal 3 phase order score: what fraction of phase transitions go forward in time.
 * Extracts starting turn numbers from phase headers and checks for monotonic increase.
 */
function goal3PhaseOrderScore(output: string): { score: number; details: string } {
  const phaseRe = /^## Phase:.*\(T(\d+)/gm;
  const startTurns: number[] = [];
  let m: RegExpExecArray | null;
  while ((m = phaseRe.exec(output)) !== null) {
    startTurns.push(parseInt(m[1], 10));
  }

  if (startTurns.length < 2) {
    return { score: 1.0, details: `${startTurns.length} phase(s) — no transitions to check` };
  }

  let correct = 0;
  for (let i = 1; i < startTurns.length; i++) {
    if (startTurns[i] >= startTurns[i - 1]) correct++;
  }
  const score = correct / (startTurns.length - 1);
  return {
    score,
    details: `${correct}/${startTurns.length - 1} phase transitions forward (turns: ${startTurns.join(", ")})`,
  };
}

/**
 * Goal 3 bullet count: total timeline bullets.
 */
function goal3BulletCount(output: string): number {
  const matches = output.match(/^•\s+T\d+/gm);
  return matches ? matches.length : 0;
}

/**
 * Goal 1 section coverage: how many of the 6 required sections are present.
 */
function goal1SectionCoverage(output: string): { score: number; missing: string[] } {
  const required = [
    "## WHAT WAS ACCOMPLISHED",
    "## CURRENT STATE",
    "## INCOMPLETE / BROKEN",
    "## KEY DECISIONS",
    "## CRITICAL GOTCHAS",
    "## NEXT STEPS",
  ];
  const missing = required.filter((s) => !output.includes(s));
  return {
    score: (required.length - missing.length) / required.length,
    missing,
  };
}

/**
 * Jaccard similarity between two texts using a term set of:
 * - File paths (anything starting with / or ~/ or containing /)
 * - Turn references (T<N> patterns)
 * - Status words (RESOLVED/UNRESOLVED/PARTIAL/ERROR/WARNING)
 */
function jaccardSimilarity(a: string, b: string): number {
  function extractTerms(text: string): Set<string> {
    const terms = new Set<string>();
    // File paths
    const pathRe = /(?:^|\s)((?:\/|~\/|\.\/)\S+)/gm;
    let m: RegExpExecArray | null;
    while ((m = pathRe.exec(text)) !== null) terms.add(m[1].replace(/[,.)]+$/, ""));
    // Turn refs
    const turnRe = /\bT(\d+)\b/g;
    while ((m = turnRe.exec(text)) !== null) terms.add(`T${m[1]}`);
    // Status words
    const statusRe = /\b(RESOLVED|UNRESOLVED|PARTIAL|ERROR|WARNING|DEPRECATION|ANOMALY|ACKNOWLEDGED|IGNORED|FIXED|DEFERRED)\b/g;
    while ((m = statusRe.exec(text)) !== null) terms.add(m[1]);
    return terms;
  }

  const setA = extractTerms(a);
  const setB = extractTerms(b);
  if (setA.size === 0 && setB.size === 0) return 1.0;

  const intersection = new Set([...setA].filter((t) => setB.has(t)));
  const union = new Set([...setA, ...setB]);
  return intersection.size / union.size;
}

// ── Prompt Loading ─────────────────────────────────────────────────────────────

/**
 * Load system prompt variants. Each variant is a function that returns a system prompt string.
 * Variants are loaded from the current session-debrief.ts prompts.
 * For A/B testing, you can modify these to test different versions.
 */
const PROMPT_VARIANTS: Record<string, Record<number, string>> = {
  // Current prompts are loaded dynamically from session-debrief.ts
  // This map stores overrides for A/B testing
};

function loadCurrentPrompts(): Record<number, string> {
  // Import from session-debrief.ts by reading the file
  const debriefPath = join(import.meta.dir, "session-debrief.ts");
  const content = readFileSync(debriefPath, "utf-8");

  const prompts: Record<number, string> = {};

  const promptNames = ["GOAL1_HANDOFF_SYSTEM", "GOAL2_ERRORS_SYSTEM", "GOAL3_SUMMARY_SYSTEM"];
  for (let i = 0; i < promptNames.length; i++) {
    const name = promptNames[i];
    const startMarker = `const ${name} = \``;
    const startIdx = content.indexOf(startMarker);
    if (startIdx === -1) {
      throw new Error(`Could not find ${name} in session-debrief.ts`);
    }
    // Find closing backtick that's not escaped
    let pos = startIdx + startMarker.length;
    let depth = 1;
    while (pos < content.length && depth > 0) {
      if (content[pos] === "`" && content[pos - 1] !== "\\") depth = 0;
      else pos++;
    }
    prompts[i + 1] = content.slice(startIdx + startMarker.length, pos);
  }
  return prompts;
}

// ── A/B Judge ─────────────────────────────────────────────────────────────────

const AB_JUDGE_SYSTEM = `You are an objective evaluator comparing two AI-generated outputs (A and B) for quality.
Score each output on four dimensions from 1-5:
- completeness: coverage of all relevant items from the source transcript
- accuracy: correctness of facts, paths, turn numbers, error messages
- format: adherence to the required output structure (sections, headings, ordering)
- ordering: chronological correctness (for error/timeline outputs)

Output ONLY this exact format with no other text:
SCORES_A: completeness=N accuracy=N format=N ordering=N
SCORES_B: completeness=N accuracy=N format=N ordering=N
WINNER: A|B|TIE
REASONING: <one sentence>`;

interface JudgeResult {
  scoresA: Record<string, number>;
  scoresB: Record<string, number>;
  winner: "A" | "B" | "TIE";
  reasoning: string;
  totalA: number;
  totalB: number;
}

function parseJudgeOutput(output: string): JudgeResult {
  const scoreRe = /SCORES_([AB]):\s*completeness=(\d)\s+accuracy=(\d)\s+format=(\d)\s+ordering=(\d)/g;
  const scores: Record<string, Record<string, number>> = {};
  let m: RegExpExecArray | null;
  while ((m = scoreRe.exec(output)) !== null) {
    scores[m[1]] = {
      completeness: parseInt(m[2]),
      accuracy: parseInt(m[3]),
      format: parseInt(m[4]),
      ordering: parseInt(m[5]),
    };
  }

  const winnerM = output.match(/WINNER:\s*(A|B|TIE)/);
  const reasonM = output.match(/REASONING:\s*(.+)/);

  const scoresA = scores["A"] || { completeness: 0, accuracy: 0, format: 0, ordering: 0 };
  const scoresB = scores["B"] || { completeness: 0, accuracy: 0, format: 0, ordering: 0 };

  return {
    scoresA,
    scoresB,
    winner: (winnerM?.[1] as "A" | "B" | "TIE") || "TIE",
    reasoning: reasonM?.[1] || "(no reasoning)",
    totalA: Object.values(scoresA).reduce((a, b) => a + b, 0),
    totalB: Object.values(scoresB).reduce((a, b) => a + b, 0),
  };
}

// ── Report Rendering ───────────────────────────────────────────────────────────

function renderMetricsTable(rows: Array<{
  label: string;
  goal: number;
  ordering?: number;
  findings?: number;
  bullets?: number;
  sectionCoverage?: number;
  phaseOrder?: number;
  chars: number;
}>): string {
  const header = [
    "Label".padEnd(25),
    "G".padEnd(3),
    "Order".padEnd(7),
    "Count".padEnd(7),
    "Sect%".padEnd(7),
    "Chars".padEnd(8),
  ].join("  ");
  const separator = "─".repeat(header.length);

  const lines = [separator, header, separator];
  for (const r of rows) {
    const ordering = r.ordering !== undefined ? (r.ordering * 100).toFixed(0) + "%" : r.phaseOrder !== undefined ? (r.phaseOrder * 100).toFixed(0) + "%" : "  —  ";
    const count = r.findings !== undefined ? String(r.findings) : r.bullets !== undefined ? String(r.bullets) : "—";
    const sect = r.sectionCoverage !== undefined ? (r.sectionCoverage * 100).toFixed(0) + "%" : "  —  ";

    lines.push([
      r.label.slice(0, 24).padEnd(25),
      String(r.goal).padEnd(3),
      ordering.padStart(5).padEnd(7),
      count.padStart(5).padEnd(7),
      sect.padStart(5).padEnd(7),
      String(r.chars).padStart(6).padEnd(8),
    ].join("  "));
  }
  lines.push(separator);
  return lines.join("\n");
}

// ── Mode: Freeze ──────────────────────────────────────────────────────────────

async function modeFreeze(args: Args): Promise<void> {
  const { corpusName, goal, since } = args;
  if (!corpusName) throw new Error("--name required for freeze mode");

  console.error(`[freeze] Running --dry for goal ${goal || "all"}, last ${since}h...`);

  // Run session-debrief.ts --dry to get frozen corpus
  const debriefPath = join(import.meta.dir, "session-debrief.ts");

  for (const g of goal ? [goal] : [1, 2, 3]) {
    const proc = Bun.spawn(
      ["bun", "run", debriefPath, "--goal", String(g), "--since", String(since), "--dry"],
      { stdout: "pipe", stderr: "pipe" },
    );
    const output = await new Response(proc.stdout).text();
    await proc.exited;

    const parts = output.split("\n---\n");
    if (parts.length < 2) {
      console.error(`[freeze] Warning: unexpected --dry output format for goal ${g}`);
      continue;
    }

    const sessionSummary = parts[0].trim();
    const structuredLog = parts.slice(1).join("\n---\n").trim();

    // Save corpus only once (same for all goals)
    if (g === (goal || 1)) {
      saveCorpus(corpusName, structuredLog, sessionSummary);
    }

    console.error(`[freeze] Goal ${g}: ${structuredLog.length} chars, ${sessionSummary.length} chars summary`);
  }

  console.log(`Corpus frozen: ${corpusName}`);
  console.log(`Location: ${corpusDir(corpusName)}`);
  console.log(`Run: bun run prompt-benchmark.ts --mode matrix --corpus ${corpusName}`);
}

// ── Mode: Matrix ──────────────────────────────────────────────────────────────

async function modeMatrix(args: Args): Promise<void> {
  const { corpusName } = args;
  if (!corpusName) throw new Error("--corpus required for matrix mode");

  const corpus = loadCorpus(corpusName);
  const apiKey = getApiKey();
  const prompts = loadCurrentPrompts();

  const metricRows: Parameters<typeof renderMetricsTable>[0] = [];

  for (const g of [1, 2, 3]) {
    console.error(`[matrix] Running goal ${g}...`);

    const userMsg = `${corpus.sessionSummary}\n\n===BEGIN TRANSCRIPT===\n${corpus.structuredLog}\n===END TRANSCRIPT===\n\nNow produce your analysis. Be exhaustive and technically precise.`;

    const output = await callMiniMax(apiKey, prompts[g], userMsg, 16384);
    saveCorpusOutput(corpusName, g, output);

    if (g === 1) {
      const { score, missing } = goal1SectionCoverage(output);
      console.error(`  Section coverage: ${(score * 100).toFixed(0)}%${missing.length ? " (missing: " + missing.join(", ") + ")" : ""}`);
      metricRows.push({ label: corpusName, goal: g, sectionCoverage: score, chars: output.length });
    } else if (g === 2) {
      const { score: ord, details: ordDetails } = goal2OrderingScore(output);
      const count = goal2FindingCount(output);
      console.error(`  Ordering: ${(ord * 100).toFixed(0)}% (${ordDetails})`);
      console.error(`  Findings: ${count}`);
      metricRows.push({ label: corpusName, goal: g, ordering: ord, findings: count, chars: output.length });
    } else {
      const { score: phOrd, details: phDetails } = goal3PhaseOrderScore(output);
      const bullets = goal3BulletCount(output);
      console.error(`  Phase order: ${(phOrd * 100).toFixed(0)}% (${phDetails})`);
      console.error(`  Bullets: ${bullets}`);
      metricRows.push({ label: corpusName, goal: g, phaseOrder: phOrd, bullets, chars: output.length });
    }
  }

  console.log("\n" + renderMetricsTable(metricRows));
}

// ── Mode: A/B Compare ─────────────────────────────────────────────────────────

async function modeAB(args: Args): Promise<void> {
  const { corpusName, goal, variantA, variantB } = args;
  if (!corpusName) throw new Error("--corpus required for ab mode");
  if (!goal) throw new Error("--goal required for ab mode");
  if (!variantA || !variantB) throw new Error("--variant-a and --variant-b required for ab mode");

  const corpus = loadCorpus(corpusName);
  const apiKey = getApiKey();
  const prompts = loadCurrentPrompts();

  const userMsg = `${corpus.sessionSummary}\n\n===BEGIN TRANSCRIPT===\n${corpus.structuredLog}\n===END TRANSCRIPT===\n\nNow produce your analysis. Be exhaustive and technically precise.`;

  console.error(`[ab] Running variant A (${variantA}), goal ${goal}...`);
  // For now both variants use the current prompt; in practice you'd swap the prompt
  const outputA = await callMiniMax(apiKey, prompts[goal], userMsg, 16384);

  console.error(`[ab] Running variant B (${variantB}), goal ${goal}...`);
  const outputB = await callMiniMax(apiKey, prompts[goal], userMsg, 16384);

  console.error(`[ab] Calling MiniMax judge...`);
  const judgeMsg = `## Source Transcript (abbreviated)
${corpus.sessionSummary}
...
[${corpus.structuredLog.length} chars of transcript]

## Goal: ${goal === 1 ? "Handoff Document" : goal === 2 ? "Error Forensics" : "Chronological Summary"}

## Output A (variant: ${variantA})
${outputA.slice(0, 8000)}

## Output B (variant: ${variantB})
${outputB.slice(0, 8000)}`;

  const judgeOutput = await callMiniMax(apiKey, AB_JUDGE_SYSTEM, judgeMsg, 512);
  const result = parseJudgeOutput(judgeOutput);

  // Quantitative metrics
  console.log("\n" + "═".repeat(60));
  console.log(`  A/B COMPARISON: Goal ${goal} | ${variantA} vs ${variantB}`);
  console.log("═".repeat(60));
  console.log(`\nJudge scores:`);
  console.log(`  Variant A (${variantA}): completeness=${result.scoresA.completeness} accuracy=${result.scoresA.accuracy} format=${result.scoresA.format} ordering=${result.scoresA.ordering} → total=${result.totalA}`);
  console.log(`  Variant B (${variantB}): completeness=${result.scoresB.completeness} accuracy=${result.scoresB.accuracy} format=${result.scoresB.format} ordering=${result.scoresB.ordering} → total=${result.totalB}`);
  console.log(`  Winner: ${result.winner} | ${result.reasoning}`);

  // Auto-metrics
  if (goal === 2) {
    const { score: ordA } = goal2OrderingScore(outputA);
    const { score: ordB } = goal2OrderingScore(outputB);
    const cntA = goal2FindingCount(outputA);
    const cntB = goal2FindingCount(outputB);
    console.log(`\nAuto-metrics:`);
    console.log(`  Ordering:  A=${(ordA * 100).toFixed(0)}%  B=${(ordB * 100).toFixed(0)}%`);
    console.log(`  Findings:  A=${cntA}  B=${cntB}`);
  } else if (goal === 3) {
    const { score: phA } = goal3PhaseOrderScore(outputA);
    const { score: phB } = goal3PhaseOrderScore(outputB);
    const bulA = goal3BulletCount(outputA);
    const bulB = goal3BulletCount(outputB);
    console.log(`\nAuto-metrics:`);
    console.log(`  Phase order:  A=${(phA * 100).toFixed(0)}%  B=${(phB * 100).toFixed(0)}%`);
    console.log(`  Bullets:  A=${bulA}  B=${bulB}`);
  }

  const jaccard = jaccardSimilarity(outputA, outputB);
  console.log(`\nJaccard similarity (A vs B): ${(jaccard * 100).toFixed(0)}%`);
  console.log("═".repeat(60));
}

// ── Mode: Variance ────────────────────────────────────────────────────────────

async function modeVariance(args: Args): Promise<void> {
  const { corpusName, goal, runs } = args;
  if (!corpusName) throw new Error("--corpus required for variance mode");
  if (!goal) throw new Error("--goal required for variance mode");

  const corpus = loadCorpus(corpusName);
  const apiKey = getApiKey();
  const prompts = loadCurrentPrompts();

  const userMsg = `${corpus.sessionSummary}\n\n===BEGIN TRANSCRIPT===\n${corpus.structuredLog}\n===END TRANSCRIPT===\n\nNow produce your analysis. Be exhaustive and technically precise.`;

  const outputs: string[] = [];
  for (let i = 0; i < runs; i++) {
    console.error(`[variance] Run ${i + 1}/${runs}...`);
    const output = await callMiniMax(apiKey, prompts[goal], userMsg, 16384);
    outputs.push(output);
    console.error(`  ${output.length} chars`);
  }

  // Pairwise Jaccard
  const pairs: [number, number, number][] = [];
  for (let i = 0; i < outputs.length; i++) {
    for (let j = i + 1; j < outputs.length; j++) {
      pairs.push([i, j, jaccardSimilarity(outputs[i], outputs[j])]);
    }
  }
  const avgJaccard = pairs.reduce((s, p) => s + p[2], 0) / pairs.length;

  console.log("\n" + "═".repeat(60));
  console.log(`  VARIANCE TEST: Goal ${goal} | ${runs} runs`);
  console.log("═".repeat(60));
  console.log(`\nPairwise Jaccard similarities:`);
  for (const [i, j, sim] of pairs) {
    console.log(`  Run ${i + 1} vs Run ${j + 1}: ${(sim * 100).toFixed(0)}%`);
  }
  console.log(`\nMean Jaccard: ${(avgJaccard * 100).toFixed(0)}%`);
  console.log(`Interpretation: ${avgJaccard >= 0.7 ? "STABLE (≥70%)" : avgJaccard >= 0.5 ? "MODERATE (50-70%)" : "UNSTABLE (<50%)"}`);

  if (goal === 2) {
    const metrics = outputs.map((o) => ({
      ordering: goal2OrderingScore(o).score,
      findings: goal2FindingCount(o),
    }));
    console.log(`\nPer-run metrics:`);
    metrics.forEach((m, i) => console.log(`  Run ${i + 1}: ordering=${(m.ordering * 100).toFixed(0)}% findings=${m.findings}`));
  } else if (goal === 3) {
    const metrics = outputs.map((o) => ({
      phaseOrder: goal3PhaseOrderScore(o).score,
      bullets: goal3BulletCount(o),
    }));
    console.log(`\nPer-run metrics:`);
    metrics.forEach((m, i) => console.log(`  Run ${i + 1}: phaseOrder=${(m.phaseOrder * 100).toFixed(0)}% bullets=${m.bullets}`));
  }
  console.log("═".repeat(60));
}

// ── Mode: List ─────────────────────────────────────────────────────────────────

async function modeList(): Promise<void> {
  const corpora = listCorpora();
  if (corpora.length === 0) {
    console.log("No corpus fixtures found.");
    console.log(`Create one: bun run prompt-benchmark.ts --mode freeze --name baseline-8h --since 8`);
    return;
  }
  console.log(`Corpus fixtures in ${CORPUS_BASE}:\n`);
  for (const name of corpora) {
    const dir = corpusDir(name);
    const logSize = existsSync(join(dir, "structured-log.txt"))
      ? readFileSync(join(dir, "structured-log.txt")).length
      : 0;
    const outputs = [1, 2, 3].filter((g) => existsSync(join(dir, `output-g${g}.txt`))).map((g) => `g${g}`);
    console.log(`  ${name.padEnd(30)} log=${Math.round(logSize / 1024)}KB  outputs=${outputs.join(",") || "none"}`);
  }
}

// ── Mode: Metrics (score saved outputs without re-running) ────────────────────

async function modeMetrics(args: Args): Promise<void> {
  const { corpusName } = args;
  if (!corpusName) throw new Error("--corpus required for metrics mode");

  const corpus = loadCorpus(corpusName);
  const rows: Parameters<typeof renderMetricsTable>[0] = [];

  for (const g of [1, 2, 3]) {
    if (!corpus.outputs[g]) {
      console.error(`[metrics] No saved output for goal ${g} in corpus ${corpusName}`);
      continue;
    }
    const output = corpus.outputs[g];
    if (g === 1) {
      const { score, missing } = goal1SectionCoverage(output);
      console.error(`  G1 section coverage: ${(score * 100).toFixed(0)}%${missing.length ? " missing: " + missing.join(", ") : ""}`);
      rows.push({ label: corpusName, goal: g, sectionCoverage: score, chars: output.length });
    } else if (g === 2) {
      const { score, details } = goal2OrderingScore(output);
      const count = goal2FindingCount(output);
      console.error(`  G2 ordering: ${(score * 100).toFixed(0)}% (${details})`);
      console.error(`  G2 findings: ${count}`);
      rows.push({ label: corpusName, goal: g, ordering: score, findings: count, chars: output.length });
    } else {
      const { score, details } = goal3PhaseOrderScore(output);
      const bullets = goal3BulletCount(output);
      console.error(`  G3 phase order: ${(score * 100).toFixed(0)}% (${details})`);
      console.error(`  G3 bullets: ${bullets}`);
      rows.push({ label: corpusName, goal: g, phaseOrder: score, bullets, chars: output.length });
    }
  }

  console.log("\n" + renderMetricsTable(rows));
}

// ── Args Parsing ──────────────────────────────────────────────────────────────

interface Args {
  mode: string;
  goal: number;
  corpusName?: string;
  since: number;
  runs: number;
  variantA?: string;
  variantB?: string;
}

function parseArgs(): Args {
  const argv = process.argv.slice(2);
  const get = (flag: string): string | undefined => {
    const idx = argv.indexOf(flag);
    return idx !== -1 ? argv[idx + 1] : undefined;
  };

  return {
    mode: get("--mode") || "list",
    goal: parseInt(get("--goal") || "0", 10),
    corpusName: get("--corpus") || get("--name"),
    since: parseFloat(get("--since") || "8"),
    runs: parseInt(get("--runs") || "3", 10),
    variantA: get("--variant-a"),
    variantB: get("--variant-b"),
  };
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs();

  console.error(`[benchmark] mode=${args.mode} goal=${args.goal || "all"} corpus=${args.corpusName || "—"}`);

  switch (args.mode) {
    case "freeze":  await modeFreeze(args); break;
    case "matrix":  await modeMatrix(args); break;
    case "ab":      await modeAB(args); break;
    case "variance": await modeVariance(args); break;
    case "metrics": await modeMetrics(args); break;
    case "list":    await modeList(); break;
    default:
      console.error(`Unknown mode: ${args.mode}`);
      console.error("Modes: freeze | matrix | ab | variance | metrics | list");
      process.exit(1);
  }
}

main().catch((err) => {
  console.error(`[benchmark] Fatal: ${err.message}`);
  process.exit(1);
});
