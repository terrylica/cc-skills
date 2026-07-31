//! latex-math-validity-oracle — does this LaTeX actually parse as mathematics?
//!
//! A similarity score between two LaTeX strings can be high while one of them is not valid LaTeX at
//! all: an unbalanced brace or a fused command changes the score by a few percent and changes
//! compilability from yes to no. Similarity therefore cannot answer the question an implementer
//! actually has, which is "can I use this?".
//!
//! This reads JSON `{"label": "...", "latex": "..."}` records on stdin and reports, per record,
//! whether a real LaTeX math parser accepts it. Acceptance is not proof of correctness — it is the
//! floor below which correctness is not even a meaningful question.
use pulldown_latex::{config::DisplayMode, mathml::push_mathml, Parser, Storage};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct Input { label: String, latex: String }

#[derive(Serialize)]
struct Verdict {
    label: String,
    parses_as_latex_mathematics: bool,
    failure_reason: Option<String>,
    unbalanced_brace_delta: i64,
}

fn brace_delta(s: &str) -> i64 {
    let bytes = s.as_bytes();
    let mut depth = 0i64;
    for (i, b) in bytes.iter().enumerate() {
        let escaped = i > 0 && bytes[i - 1] == b'\\';
        if escaped { continue; }
        if *b == b'{' { depth += 1; }
        if *b == b'}' { depth -= 1; }
    }
    depth
}

fn main() {
    let mut raw = String::new();
    std::io::Read::read_to_string(&mut std::io::stdin(), &mut raw).expect("read stdin");
    let inputs: Vec<Input> = serde_json::from_str(&raw).expect("parse input json");
    let verdicts: Vec<Verdict> = inputs
        .into_iter()
        .map(|item| {
            let storage = Storage::new();
            let parser = Parser::new(&item.latex, &storage);
            let mut out = String::new();
            let config = pulldown_latex::config::RenderConfig {
                display_mode: DisplayMode::Block,
                ..Default::default()
            };
            let result = push_mathml(&mut out, parser, config);
            Verdict {
                label: item.label,
                parses_as_latex_mathematics: result.is_ok(),
                failure_reason: result.err().map(|e| e.to_string()),
                unbalanced_brace_delta: brace_delta(&item.latex),
            }
        })
        .collect();
    println!("{}", serde_json::to_string_pretty(&verdicts).expect("serialise"));
}
