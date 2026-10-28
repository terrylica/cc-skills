/**
 * HTML text-measure detector: finds CSS that fixes where a line of text ends, whatever the reader's window.
 *
 * Operator, 2026-10-28: "There shouldn't be any hard wrapping of lines" in anything presented as HTML, made a
 * forced convention for every Orca artifact and HTML page. The page equivalent of a hard-wrapped paragraph is a
 * fixed measure: prose stopped at 72em inside a 1560px page ends well short of the table beside it and cannot
 * reflow when the window widens. Text must follow the window.
 *
 * Flagged:
 *   - a text measure: max-width in em, ch or rem, also inside min()/clamp(); width in ch;
 *   - a page-width cap: a px max-width on a page container (body, main, article, .inner, .topin, .wrap,
 *     .container, .page, .content, .viz-root, .explain), in a CSS rule or an inline style on <body>/<main>;
 *   - pre-style whitespace (white-space: pre, pre-wrap, pre-line) on anything but code (pre, code, kbd, samp,
 *     textarea, .code, .mono), which renders the source's own line breaks.
 * Allowed: @media conditions, images, charts, tooltips, banners, table columns (min-width), code blocks.
 *
 * A repository may also enforce this rule at build time with its own copy of the rule list; such a copy should
 * pass the vectors in pretooluse-html-measure-guard.test.ts. Pure functions, no I/O.
 */

export const HTML_MEASURE_ESCAPE_MARKER = "HTML-MEASURE-OK";

const TEXT_CAP = /max-width\s*:\s*(?:[\d.]+(?:em|ch|rem)\b|(?:min|clamp)\([^)]*?[\d.](?:em|ch|rem)\b)/g;
const CH_WIDTH = /(?<![\w-])width\s*:\s*[\d.]+ch\b/g;
const PX_CAP = /max-width\s*:\s*[\d.]+px\b/g;
const PRE_WS = /white-space\s*:\s*pre(?:-wrap|-line)?\b/g;
const CONTAINER =
  /(?:^|[\s,>}])(?:body|main|article|\.inner|\.topin|\.wrap|\.container|\.page|\.content|\.viz-root|\.explain)(?:\.[\w-]+)*\s*$/;
const CODE = /(?:^|[\s,>.#])(?:pre|code|kbd|samp|textarea)\b|\.(?:code|mono)\b/;
const INLINE_CAP_TAGS = /<(body|main)\b[^>]*?style=(['"])([\s\S]*?)\2/g;
const INLINE_PRE_TAGS = /<(p|li|div|span|td|blockquote)\b[^>]*?style=(['"])([\s\S]*?)\2/g;

/** Files whose text can carry page CSS: pages, stylesheets, and the sources that build them. */
const PAGE_OR_BUILDER_EXTENSION =
  /\.(?:html?|css|scss|sass|less|py|ts|tsx|js|jsx|mjs|cjs|vue|svelte|astro|sh|bash|jinja2?|j2|hbs|njk|liquid|erb)$/i;

export function isPageOrPageBuilderPath(filePath: string): boolean {
  return PAGE_OR_BUILDER_EXTENSION.test(filePath);
}

/** True when the declaration at `start` is a condition: `@media (max-width:…)`, a nested `min(…)`. */
function isCondition(text: string, start: number): boolean {
  let i = start - 1;
  while (i >= 0 && /\s/.test(text[i]!)) i--;
  return i >= 0 && text[i] === "(";
}

/** The selector of the CSS rule containing `start` (single or doubled f-string braces), or null outside a rule. */
function selectorAt(text: string, start: number): string | null {
  const open = text.lastIndexOf("{", start);
  if (open < 0 || text.slice(open, start).includes("}")) return null;
  const end = open > 0 && text[open - 1] === "{" ? open - 1 : open;
  let from = -1;
  for (const c of ["}", ";", '"', "'", "\n"]) from = Math.max(from, text.lastIndexOf(c, end - 1));
  return text.slice(from + 1, end);
}

function tail(selector: string): string {
  const s = selector.trim();
  return s.length > 30 ? s.slice(-30) : s;
}

/**
 * Every fixed text width in `text` (a page, a stylesheet or a builder's source), as short descriptions.
 * Empty when the text carries the HTML-MEASURE-OK marker.
 */
export function findTextMeasureViolations(text: string): string[] {
  if (!text || text.includes(HTML_MEASURE_ESCAPE_MARKER)) return [];
  const out: string[] = [];
  for (const re of [TEXT_CAP, CH_WIDTH]) {
    for (const m of text.matchAll(re)) if (!isCondition(text, m.index!)) out.push(m[0]);
  }
  for (const m of text.matchAll(PX_CAP)) {
    if (isCondition(text, m.index!)) continue;
    const sel = selectorAt(text, m.index!);
    if (sel !== null && CONTAINER.test(sel)) out.push(`${tail(sel)} {${m[0]}}`);
  }
  for (const m of text.matchAll(PRE_WS)) {
    const sel = selectorAt(text, m.index!);
    if (sel !== null && sel.trim() && !CODE.test(sel)) out.push(`${tail(sel)} {${m[0]}}`);
  }
  for (const m of text.matchAll(INLINE_CAP_TAGS)) {
    for (const x of m[3]!.matchAll(PX_CAP)) out.push(`<${m[1]} style> ${x[0]}`);
  }
  for (const m of text.matchAll(INLINE_PRE_TAGS)) {
    for (const x of m[3]!.matchAll(PRE_WS)) out.push(`<${m[1]} style> ${x[0]}`);
  }
  return out;
}

/** Findings in `after` that `before` does not already have (multiset difference), for Edit-time checks. */
export function netNewTextMeasureViolations(before: string, after: string): string[] {
  const left = new Map<string, number>();
  for (const f of findTextMeasureViolations(before)) left.set(f, (left.get(f) ?? 0) + 1);
  const added: string[] = [];
  for (const f of findTextMeasureViolations(after)) {
    const n = left.get(f) ?? 0;
    if (n > 0) left.set(f, n - 1);
    else added.push(f);
  }
  return added;
}
