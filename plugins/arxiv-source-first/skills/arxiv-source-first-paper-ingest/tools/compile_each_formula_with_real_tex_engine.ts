/**
 * compile_each_formula_with_real_tex_engine.ts
 *
 * The authoritative test of whether a recovered formula is usable: hand it to a real TeX engine and
 * see whether it compiles.
 *
 * WHY NOT JUST A SIMILARITY SCORE. A token-overlap score between a recovered formula and its source
 * can sit at 0.97 while the recovered string is not compilable LaTeX at all — one dropped brace
 * costs a couple of percent of similarity and costs 100% of usability. Similarity answers "does this
 * look like the formula", which is not the question an implementer has.
 *
 * WHY NOT JUST A PARSER LIBRARY. Lenient parsers accept input a TeX engine rejects, so a library
 * verdict of "ok" is evidence of very little. TeX Live is the definition of the thing.
 *
 * EACH FORMULA COMPILES IN ITS OWN DIRECTORY. The first version of this harness ran every job
 * concurrently against one shared `-output-directory`, where the jobs overwrote each other's `.aux`
 * and `.log` files and EVERY compile failed — including the authors' own published LaTeX, which
 * obviously compiles. A harness that reports 0/28 for a published paper is measuring itself.
 * Isolating the directories and bounding concurrency fixes it.
 *
 * ALIGNMENT ENVIRONMENTS ARE WRAPPED, NOT INLINED. A body containing `&` comes from an `align`
 * environment and is invalid inside `\[ … \]`; it is wrapped in `align*` so the engine judges the
 * mathematics rather than the wrapper.
 */
import { $ } from "bun";
import { mkdirSync, writeFileSync, rmSync, existsSync } from "node:fs";
import { join } from "node:path";

const WORK_ROOT = "/tmp/lambdarankic/texcheck";
const TEX_ENGINE_TIMEOUT_MILLISECONDS = 30_000;
const MAX_CONCURRENT_TEX_ENGINES = 6;

const PREAMBLE = String.raw`\documentclass[11pt]{article}
\usepackage{amsmath,amssymb,amsfonts,bm}
\begin{document}
\thispagestyle{empty}
`;

interface FormulaUnderTest {
  readonly label: string;
  readonly latex: string;
}

interface CompileOutcome {
  readonly label: string;
  readonly compiled: boolean;
  readonly firstTexError: string | null;
}

function wrapForEngine(latexBody: string): string {
  const body = latexBody.replace(/\\tag\{[^}]*\}/g, "").replace(/\\label\{[^}]*\}/g, "").trim();
  const needsAlignment = /(?<!\\)&/.test(body) || /\\\\/.test(body);
  return needsAlignment
    ? `\\begin{align*}\n${body}\n\\end{align*}\n`
    : `\\[\n${body}\n\\]\n`;
}

async function compileOne(batch: string, item: FormulaUnderTest, index: number): Promise<CompileOutcome> {
  // Namespaced by BATCH as well as index. Without the batch segment the second batch reuses the
  // first batch's directories, finds its leftover formula.pdf, and reports a pass for every job the
  // first batch happened to compile — which silently made the OCR score converge on the source
  // score. A harness that reuses output directories is measuring its own leftovers.
  const directory = join(WORK_ROOT, batch, `job_${String(index).padStart(3, "0")}`);
  mkdirSync(directory, { recursive: true });
  const texPath = join(directory, "formula.tex");
  writeFileSync(texPath, `${PREAMBLE}${wrapForEngine(item.latex)}\\end{document}\n`);
  // `.nothrow()` rather than a bare try/catch: batchmode exits non-zero on a TeX error, which is a
  // RESULT, and a catch block that swallows everything cannot tell that result apart from the
  // harness itself being broken. The first version of this chained `.timeout()`, which does not
  // exist on this Bun version, so every job threw a TypeError that the catch reported as a failed
  // compile — including for the authors' published LaTeX. A harness must fail loudly or it becomes
  // the measurement.
  const run = await $`pdflatex -interaction=batchmode -halt-on-error -output-directory=${directory} ${texPath}`
    .quiet()
    .nothrow();
  if (run.exitCode !== 0 && !existsSync(join(directory, "formula.log"))) {
    throw new Error(`pdflatex produced no log for ${item.label}; the harness, not the formula, is broken`);
  }
  const compiled = existsSync(join(directory, "formula.pdf"));
  let firstTexError: string | null = null;
  if (!compiled) {
    const logPath = join(directory, "formula.log");
    if (existsSync(logPath)) {
      const log = await Bun.file(logPath).text();
      firstTexError = log.split("\n").find((l) => l.startsWith("!"))?.trim() ?? null;
    }
  }
  return { label: item.label, compiled, firstTexError };
}

async function compileAll(batch: string, items: FormulaUnderTest[], heading: string): Promise<CompileOutcome[]> {
  const outcomes: CompileOutcome[] = [];
  for (let start = 0; start < items.length; start += MAX_CONCURRENT_TEX_ENGINES) {
    const slice = items.slice(start, start + MAX_CONCURRENT_TEX_ENGINES);
    outcomes.push(...(await Promise.all(slice.map((item, i) => compileOne(batch, item, start + i)))));
  }
  const compiled = outcomes.filter((o) => o.compiled).length;
  console.log(heading);
  console.log(`  compiles under pdfTeX: ${compiled}/${items.length}  (${((compiled / items.length) * 100).toFixed(0)}%)`);
  const failures = outcomes.filter((o) => !o.compiled);
  for (const failure of failures.slice(0, 5)) {
    const source = items.find((i) => i.label === failure.label)?.latex ?? "";
    console.log(`    FAILS ${failure.label}: ${failure.firstTexError ?? "(no TeX error line)"}`);
    console.log(`           ${source.replace(/\s+/g, " ").slice(0, 100)}`);
  }
  if (failures.length > 5) console.log(`    … and ${failures.length - 5} more`);
  console.log();
  return outcomes;
}

if (existsSync(WORK_ROOT)) rmSync(WORK_ROOT, { recursive: true, force: true });
mkdirSync(WORK_ROOT, { recursive: true });

const sourceFormulas = JSON.parse(await Bun.file("/tmp/lambdarankic/validity_source.json").text()) as FormulaUnderTest[];
const ocrFormulas = JSON.parse(await Bun.file("/tmp/lambdarankic/validity_ocr.json").text()) as FormulaUnderTest[];

await compileAll("authors-latex", sourceFormulas, "AUTHORS' OWN LATEX (arXiv e-print source) — the control");
await compileAll("unlimited-ocr", ocrFormulas, "UNLIMITED-OCR READING THE RENDERED PDF");
