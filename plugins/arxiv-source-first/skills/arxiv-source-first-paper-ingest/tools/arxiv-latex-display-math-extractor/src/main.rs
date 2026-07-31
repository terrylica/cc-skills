//! arxiv-latex-display-math-extractor — recover every display equation from an arXiv e-print's
//! LaTeX source, with the surrounding structure that gives it meaning, and render each to MathML.
//!
//! WHY THIS EXISTS RATHER THAN AN OCR PASS. For an arXiv paper the PDF is a *rendering* of
//! something we can obtain losslessly: the authors' own LaTeX, served at `arxiv.org/e-print/<id>`.
//! Reading formulas back out of the PDF with a vision model reconstructs, with error, a artifact we
//! already hold exactly. OCR is the right tool only when no source exists.
//!
//! WHAT "WITH STRUCTURE" MEANS, and why a bare list of equations is not enough. An implementer
//! needs to know that a given formula is the statement of Proposition 2 rather than an intermediate
//! step inside its proof — those carry completely different authority. So every equation is emitted
//! with its `\label`, its environment, and the nearest enclosing theorem-like block and that
//! block's title.
//!
//! Output is JSON on stdout: one record per display equation.

use pulldown_latex::{config::DisplayMode, mathml::push_mathml, Parser, Storage};
use serde::Serialize;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

/// Environments whose body is display mathematics we want to capture.
const DISPLAY_MATH_ENVIRONMENT_NAMES: &[&str] = &[
    "equation", "equation*", "align", "align*", "gather", "gather*", "multline", "multline*",
    "eqnarray", "eqnarray*", "flalign", "flalign*", "displaymath",
];

/// Environments that carry mathematical authority: a formula inside one is a stated result.
const THEOREM_LIKE_ENVIRONMENT_NAMES: &[&str] = &[
    "theorem", "proposition", "lemma", "corollary", "definition", "assumption", "remark", "proof",
    "claim", "conjecture", "example",
];

#[derive(Serialize)]
struct ExtractedDisplayEquation {
    /// Source file relative to the e-print root, so a record points back at something a human opens.
    source_file: String,
    /// 1-based line where the environment opens.
    opening_line_number: usize,
    environment_name: String,
    /// The `\label{...}` if the authors gave one; this is how the paper's own prose cites it.
    label: Option<String>,
    /// Nearest enclosing theorem-like environment, e.g. `proposition`. None at top level.
    enclosing_theorem_environment: Option<String>,
    /// The bracketed title of that environment, e.g. `$\Delta$RankIC` in
    /// `\begin{proposition}[$\Delta$RankIC]`.
    enclosing_theorem_title: Option<String>,
    /// True when the authors boxed it. In this corpus that reliably marks the headline result.
    is_boxed_by_authors: bool,
    /// The LaTeX body exactly as written, with no normalisation whatsoever. Ground truth.
    latex_body_verbatim: String,
    /// MathML rendering, or the reason it could not be produced.
    mathml: Option<String>,
    mathml_error: Option<String>,
}

/// Find `\begin{name}` / `\end{name}` pairs, honouring nesting of the SAME environment name.
fn find_environment_spans(text: &str, environment_name: &str) -> Vec<(usize, usize)> {
    let open_tag = format!("\\begin{{{environment_name}}}");
    let close_tag = format!("\\end{{{environment_name}}}");
    let mut spans = Vec::new();
    let mut cursor = 0usize;
    while let Some(relative_open) = text[cursor..].find(&open_tag) {
        let body_start = cursor + relative_open + open_tag.len();
        let mut depth = 1usize;
        let mut scan = body_start;
        let body_end = loop {
            let next_open = text[scan..].find(&open_tag).map(|i| scan + i);
            let next_close = text[scan..].find(&close_tag).map(|i| scan + i);
            match (next_open, next_close) {
                (_, None) => break text.len(),
                (Some(o), Some(c)) if o < c => {
                    depth += 1;
                    scan = o + open_tag.len();
                }
                (_, Some(c)) => {
                    depth -= 1;
                    if depth == 0 {
                        break c;
                    }
                    scan = c + close_tag.len();
                }
            }
        };
        spans.push((body_start, body_end));
        cursor = body_end.saturating_add(close_tag.len()).min(text.len());
        if cursor >= text.len() {
            break;
        }
    }
    spans
}

/// Display math written with raw delimiters rather than a named environment.
///
/// FOUND BY DISAGREEMENT, 2026-07-31. On arXiv:2402.02592 this extractor reported 5 equations while
/// an OCR pass over the same PDF reported 14. The OCR was right and this tool was blind: that paper
/// writes five of its display blocks as `\[ … \]` and this scanner only looked for
/// `\begin{env} … \end{env}`. An extractor that silently returns a subset is worse than one that
/// fails, because the number it reports looks like an answer.
const RAW_DISPLAY_MATH_DELIMITER_PAIRS: &[(&str, &str)] = &[("\\[", "\\]"), ("$$", "$$")];

/// Spans of display math delimited by `\[ … \]` or `$$ … $$`, non-nesting by construction.
fn find_raw_delimited_display_math_spans(text: &str, open: &str, close: &str) -> Vec<(usize, usize)> {
    let mut spans = Vec::new();
    let mut cursor = 0usize;
    while let Some(relative_open) = text[cursor..].find(open) {
        let absolute_open = cursor + relative_open;
        // An escaped `\\[` opens a line-break option, not display math.
        let preceded_by_backslash = absolute_open > 0 && text.as_bytes()[absolute_open - 1] == b'\\';
        let body_start = absolute_open + open.len();
        let Some(relative_close) = text[body_start..].find(close) else { break };
        let body_end = body_start + relative_close;
        if !preceded_by_backslash {
            spans.push((body_start, body_end));
        }
        cursor = body_end + close.len();
        if cursor >= text.len() {
            break;
        }
    }
    spans
}

fn line_number_at_byte_offset(text: &str, offset: usize) -> usize {
    text[..offset.min(text.len())].bytes().filter(|b| *b == b'\n').count() + 1
}

/// The `\label{...}` declared inside a body, if any.
fn extract_label(body: &str) -> Option<String> {
    let start = body.find("\\label{")? + "\\label{".len();
    let end = body[start..].find('}')? + start;
    Some(body[start..end].trim().to_string())
}

/// The theorem-like environment enclosing `offset`, and its bracketed title.
fn find_enclosing_theorem_environment(text: &str, offset: usize) -> (Option<String>, Option<String>) {
    let mut best: Option<(usize, String, Option<String>)> = None;
    for name in THEOREM_LIKE_ENVIRONMENT_NAMES {
        for (body_start, body_end) in find_environment_spans(text, name) {
            if body_start <= offset && offset < body_end {
                // Optional bracketed title immediately after \begin{name}
                let title = text[body_start..].strip_prefix('[').and_then(|rest| {
                    rest.find(']').map(|end| rest[..end].trim().to_string())
                });
                let is_tighter = best.as_ref().is_none_or(|(s, _, _)| body_start > *s);
                if is_tighter {
                    best = Some((body_start, (*name).to_string(), title));
                }
            }
        }
    }
    match best {
        Some((_, name, title)) => (Some(name), title),
        None => (None, None),
    }
}

/// Strip the bookkeeping that is not mathematics, so the body can be handed to a MathML converter.
fn strip_non_mathematical_directives(body: &str) -> String {
    let mut out = String::with_capacity(body.len());
    let mut rest = body;
    loop {
        let Some(at) = rest.find("\\label{") else {
            out.push_str(rest);
            break;
        };
        out.push_str(&rest[..at]);
        let after = &rest[at + "\\label{".len()..];
        match after.find('}') {
            Some(end) => rest = &after[end + 1..],
            None => break,
        }
    }
    out.replace("\\boxed", "").replace("\\notag", "").replace("\\nonumber", "")
}

fn render_latex_to_mathml(latex_body: &str) -> Result<String, String> {
    let storage = Storage::new();
    let parser = Parser::new(latex_body, &storage);
    let mut mathml = String::new();
    let config = pulldown_latex::config::RenderConfig {
        display_mode: DisplayMode::Block,
        ..Default::default()
    };
    push_mathml(&mut mathml, parser, config).map_err(|e| e.to_string())?;
    Ok(mathml)
}

fn main() {
    let root: PathBuf = std::env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            eprintln!("usage: arxiv-latex-display-math-extractor <eprint-source-directory>");
            std::process::exit(2);
        });

    let mut records: Vec<ExtractedDisplayEquation> = Vec::new();

    for entry in WalkDir::new(&root).into_iter().filter_map(Result::ok) {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("tex") {
            continue;
        }
        let Ok(text) = std::fs::read_to_string(path) else { continue };
        let relative = path
            .strip_prefix(&root)
            .unwrap_or(path)
            .to_string_lossy()
            .to_string();

        let mut spans_with_origin: Vec<(usize, usize, String)> = Vec::new();
        for environment_name in DISPLAY_MATH_ENVIRONMENT_NAMES {
            for span in find_environment_spans(&text, environment_name) {
                spans_with_origin.push((span.0, span.1, (*environment_name).to_string()));
            }
        }
        for (open, close) in RAW_DISPLAY_MATH_DELIMITER_PAIRS {
            let origin = if *open == "$$" { "$$…$$" } else { "\\[…\\]" };
            for span in find_raw_delimited_display_math_spans(&text, open, close) {
                spans_with_origin.push((span.0, span.1, origin.to_string()));
            }
        }

        {
            for (body_start, body_end, environment_name) in spans_with_origin {
                let body = &text[body_start..body_end];
                let (enclosing, title) = find_enclosing_theorem_environment(&text, body_start);
                let cleaned = strip_non_mathematical_directives(body);
                let (mathml, mathml_error) = match render_latex_to_mathml(cleaned.trim()) {
                    Ok(m) => (Some(m), None),
                    Err(e) => (None, Some(e)),
                };
                records.push(ExtractedDisplayEquation {
                    source_file: relative.clone(),
                    opening_line_number: line_number_at_byte_offset(&text, body_start),
                    environment_name: environment_name.clone(),
                    label: extract_label(body),
                    enclosing_theorem_environment: enclosing,
                    enclosing_theorem_title: title,
                    is_boxed_by_authors: body.contains("\\boxed"),
                    latex_body_verbatim: body.trim().to_string(),
                    mathml,
                    mathml_error,
                });
            }
        }
    }

    records.sort_by(|a, b| {
        (a.source_file.as_str(), a.opening_line_number)
            .cmp(&(b.source_file.as_str(), b.opening_line_number))
    });

    println!("{}", serde_json::to_string_pretty(&records).expect("serialise"));
    eprintln!(
        "extracted {} display equations; {} rendered to MathML, {} failed",
        records.len(),
        records.iter().filter(|r| r.mathml.is_some()).count(),
        records.iter().filter(|r| r.mathml.is_none()).count()
    );
    let _ = Path::new("/dev/null");
}
