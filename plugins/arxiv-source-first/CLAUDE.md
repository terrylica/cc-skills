# arxiv-source-first Plugin

> Read an arXiv paper from the authors' own LaTeX instead of OCR-ing its PDF.

**Hub**: [plugins/CLAUDE.md](../CLAUDE.md) | **Sibling**: [unlimited-ocr](../unlimited-ocr/CLAUDE.md) (the OCR route this plugin measures itself against)

User-facing overview lives in [README.md](./README.md). This file is for whoever edits the plugin.

## Why this plugin exists

`arxiv.org/e-print/<id>` serves the source the PDF was rendered _from_. It carries each formula's `\label`, its environment, and whether it is a stated proposition or a step inside a proof — structure that is destroyed by rendering, so no vision model can recover it from the PDF.

The claim is measured, not asserted. [`references/OCR-VERSUS-AUTHOR-LATEX-GROUND-TRUTH.md`](./references/OCR-VERSUS-AUTHOR-LATEX-GROUND-TRUTH.md) is the SSoT for that measurement; quote it from there rather than restating the numbers, so a re-run updates one file.

**The headline finding drives the whole design**: OCR scores 0.958 mean token overlap yet only 49% of its formulas compile, against 98% for the source. High similarity and unusable output coexist — which is why compilation, not similarity, is this plugin's acceptance test.

## Layout

| Path                                                     | Role                                                                                |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `skills/arxiv-source-first-paper-ingest/SKILL.md`        | The workflow: fetch e-print → extract → verify                                      |
| `.../tools/arxiv-latex-display-math-extractor/`          | Rust. Every display equation with label, environment, enclosing proposition, MathML |
| `.../tools/latex-math-validity-oracle/`                  | Rust. Does this string parse as mathematics, are its braces balanced                |
| `.../tools/compile_each_formula_with_real_tex_engine.ts` | Bun. The authoritative test: does it compile under pdfTeX                           |
| `references/OCR-VERSUS-AUTHOR-LATEX-GROUND-TRUTH.md`     | The measurement that motivates all of it                                            |

## Invariants

**Similarity is not a pass. Compilation is.** A formula that scores well on token overlap and fails pdfTeX is a failure. Never add or promote a similarity-only acceptance check — that is the exact trap the ground-truth measurement documents.

**The Rust tools are invoked through `cargo run --release --manifest-path`, never through a committed binary.** Cargo rebuilds from source on demand, so `target/` is git-ignored repo-wide; a previously committed `target/` shipped ~75 MB of stale, architecture-specific objects to everyone installing the marketplace and was never read. Keep `Cargo.lock` tracked — the builds are meant to be reproducible.

**Do not switch this plugin to a PDF or OCR route.** If a paper has no e-print source, say so and stop; silently degrading to OCR reintroduces the failure mode this plugin exists to avoid. `unlimited-ocr` is the right tool when the only artefact is a scan.

## Editing the Rust tools

Both crates are ordinary `cargo` projects with no workspace parent. Build and test each from its own manifest:

```bash
SKILL_DIR=plugins/arxiv-source-first/skills/arxiv-source-first-paper-ingest
cargo test  --manifest-path "$SKILL_DIR/tools/arxiv-latex-display-math-extractor/Cargo.toml"
cargo build --release --manifest-path "$SKILL_DIR/tools/latex-math-validity-oracle/Cargo.toml"
```

Background/long cargo invocations must go through PUEUE — a backgrounded `cargo` suspends on TTY access. See [/docs/cargo-tty-suspension-prevention.md](/docs/cargo-tty-suspension-prevention.md); the `cargo-tty-guard` PreToolUse hook enforces it.

## Verification

```bash
bun scripts/validate-plugins.mjs          # marketplace registration + skill frontmatter
```

An end-to-end check needs a real TeX engine on PATH (`pdftex`); without one, `compile_each_formula_with_real_tex_engine.ts` cannot render its verdict and the run is inconclusive rather than passing.
