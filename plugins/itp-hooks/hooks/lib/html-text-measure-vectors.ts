/**
 * Reference vectors for the HTML text-measure rule (lib/html-text-measure-detector.ts).
 *
 * Shared so every copy of the rule is tested against the same inputs: the guard's own test
 * (pretooluse-html-measure-guard.test.ts) and orca-tools' full-width-artifact script, which carries a copy
 * because skills install per plugin. Change a vector here and both tests follow.
 *
 * HTML-MEASURE-OK: these strings are test inputs, not a page; the marker keeps the Write|Edit guard off this file.
 */

export const FLAGGED = [
  "p,li{max-width:72em}",
  ".cap{margin:0;max-width:60ch}",
  "article{max-width:min(100%,70ch)}",
  "p{width:66ch}",
  "body{margin:0;max-width:1560px}",
  "main{{max-width:1180px}}",
  ".inner{margin:0 auto; max-width:1000px}",
  "<body style='max-width:1200px;margin:auto'>",
  "p.note{white-space:pre-line}",
  '<div style="white-space:pre-wrap">text</div>',
  // Orca's own Markdown template (measured 2026-10-29): why a .md artifact is a narrow column.
  "body{font-family:system-ui;line-height:1.6;max-width:820px;margin:40px auto;padding:0 24px}",
];

export const ALLOWED = [
  "@media (max-width:640px){x{font-size:1em}}",
  "@media (max-width:40em){p{margin:0}}",
  "img{max-width:100%}",
  "figure.narrow img{max-width:min(100%,1100px)}",
  ".tip{max-width:320px}",
  "td.d{min-width:22em}",
  "pre{white-space:pre} textarea.code{white-space:pre}",
  "<!-- HTML-MEASURE-OK: outside page archived verbatim --><style>p{max-width:40em}</style>",
];
