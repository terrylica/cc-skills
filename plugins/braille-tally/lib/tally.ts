/**
 * Braille Tally — rank anything human-readable on a few axes at once, as one word-sized shape.
 *
 * A Braille Tally is a short run of Braille cells, one per axis. Level n (1-8) is a cell with exactly n dots, filled from
 * the bottom row up, so a taller column always means "more" and every cell has one width and one bottom line. One font
 * draws every Braille pattern, which is why a tally stays evenly spaced and bottom-aligned even in plain text (a mail
 * subject line, a terminal, a chat), where the Unicode block characters ▁…█ come from several fonts and do not line up.
 *
 * The default axes, in this order: Importance · Urgency · Simplicity. Any other axes need a legend that names them.
 * The SSoT for the convention is skills/braille-tally/SKILL.md; this file is its only implementation in the plugin.
 */

/** The eight levels, lowest first: level n has n dots (U+2840 … U+28FF). */
export const CELLS = "⡀⣀⣠⣤⣴⣶⣾⣿";
export const MAX_LEVEL = 8;
export const DEFAULT_AXES = ["Importance", "Urgency", "Simplicity"] as const;
/** Ranking ties inside a Pareto front break on these axis positions, in order (default axes: urgency, importance, simplicity). */
export const DEFAULT_TIE_ORDER = [1, 0, 2] as const;
/** A tally has between MIN_AXES and MAX_AXES cells. */
export const MIN_AXES = 2;
export const MAX_AXES = 6;

const CELL_LIST = [...CELLS];
const clamp = (n: number) => Math.min(MAX_LEVEL, Math.max(1, Math.round(n)));

/** One cell for one level (clamped to 1-8). */
export function cell(level: number): string {
  return CELL_LIST[clamp(level) - 1]!;
}

/** The tally for a list of levels, e.g. [2, 8, 8] → "⣀⣿⣿". */
export function tally(levels: readonly number[]): string {
  return levels.map(cell).join("");
}

/** The tally followed by its levels for plain text, e.g. "⣀⣿⣿ (2·8·8)". */
export function tallyWithLevels(levels: readonly number[]): string {
  return `${tally(levels)} (${levels.map(clamp).join("·")})`;
}

/** The levels a string of cells stands for, or undefined when any character is not a tally cell. */
export function levelsOf(s: string): number[] | undefined {
  const chars = [...s];
  if (chars.length === 0) return undefined;
  const v = chars.map((c) => CELL_LIST.indexOf(c) + 1);
  return v.every((n) => n >= 1) ? v : undefined;
}

/** A tally at the start of a line or label: the cells and the rest after one space. */
export const LEADING_TALLY = new RegExp(`^([${CELLS}]{${MIN_AXES},${MAX_AXES}}) (.*)$`, "su");

export function leadingTally(text: string): { levels: number[]; rest: string } | undefined {
  const m = LEADING_TALLY.exec(text);
  if (!m) return undefined;
  return { levels: levelsOf(m[1]!)!, rest: m[2]! };
}

/** The legend line every tallied list carries once, e.g. at its head or in a question's text. */
export function legend(axes: readonly string[] = DEFAULT_AXES): string {
  return `Braille Tally: ${axes.join(" · ")}, each column ${CELL_LIST[0]} (lowest) to ${CELL_LIST[MAX_LEVEL - 1]} (highest), relative to the other items.`;
}

/** a dominates b: at least as high on every axis and higher on one. */
export function dominates(a: readonly number[], b: readonly number[]): boolean {
  if (a.length !== b.length) return false;
  return a.every((x, i) => x >= b[i]!) && a.some((x, i) => x > b[i]!);
}

export interface Item { id: string; levels: number[]; label?: string }

/**
 * Pareto fronts: front 1 is what no other item beats on every axis at once, front 2 what only front 1 beats, and so on.
 * No weights, so the axes are never merged into one number. Inside a front, ties break on tieOrder, then on id.
 */
export function fronts<T extends Item>(items: readonly T[], tieOrder: readonly number[] = DEFAULT_TIE_ORDER): T[][] {
  const left = [...items];
  const out: T[][] = [];
  while (left.length) {
    const front = left.filter((x) => !left.some((y) => y !== x && dominates(y.levels, x.levels)));
    front.sort((a, b) => {
      for (const i of tieOrder) if ((b.levels[i] ?? 0) !== (a.levels[i] ?? 0)) return (b.levels[i] ?? 0) - (a.levels[i] ?? 0);
      return a.id.localeCompare(b.id);
    });
    out.push(front);
    for (const f of front) left.splice(left.indexOf(f), 1);
  }
  return out;
}

/** Items in rank order with their front number. */
export function ranked<T extends Item>(items: readonly T[], tieOrder?: readonly number[]): { item: T; front: number }[] {
  return fronts(items, tieOrder).flatMap((f, i) => f.map((item) => ({ item, front: i + 1 })));
}

/** The first pair (earlier, later) in a list where the later item dominates the earlier one, i.e. the list is out of rank. */
export function outOfRank(levelsInOrder: readonly (readonly number[])[]): [number, number] | undefined {
  for (let i = 0; i < levelsInOrder.length; i++)
    for (let j = i + 1; j < levelsInOrder.length; j++) if (dominates(levelsInOrder[j]!, levelsInOrder[i]!)) return [i, j];
  return undefined;
}

/** Braille dot bits, top row first: the left column is dots 1, 2, 3, 7 and the right column dots 4, 5, 6, 8. */
const LEFT = [0x01, 0x02, 0x04, 0x40];
const RIGHT = [0x08, 0x10, 0x20, 0x80];

export interface HtmlOptions { dot?: number; gap?: number; cellGap?: number; ink?: string; label?: string }

/**
 * The tally drawn in HTML without any font: per level two columns of four places, a dot where the level's Braille pattern
 * has one. Columns are inline-blocks holding block-level dots, so the drawing sits on the text baseline inside a sentence.
 * Works in Gmail and Apple Mail and on the web; a mail app without inline-block (Outlook for Windows) shows nothing, so
 * keep the levels in text beside it (htmlWithLevels).
 */
export function html(levels: readonly number[], o: HtmlOptions = {}): string {
  const dot = o.dot ?? 3, gap = o.gap ?? 1, cellGap = o.cellGap ?? 4, ink = o.ink ?? "currentColor";
  const label = o.label ?? `Braille Tally ${levels.map(clamp).join(", ")} of ${MAX_LEVEL}`;
  const column = (bits: number, rows: readonly number[], right: number) =>
    `<span style="display:inline-block;width:${dot}px;margin-right:${right}px;vertical-align:baseline;font-size:0;line-height:0">` +
    rows.map((bit, r) => `<span style="display:block;width:${dot}px;height:${dot}px;margin-bottom:${r < 3 ? gap : 0}px;border-radius:50%;background-color:${bits & bit ? ink : "transparent"}"></span>`).join("") +
    `</span>`;
  const cells = levels.map((n, i) => {
    const bits = cell(n).codePointAt(0)! - 0x2800;
    return column(bits, LEFT, gap) + column(bits, RIGHT, i < levels.length - 1 ? cellGap : 0);
  });
  return `<span role="img" aria-label="${label.replaceAll('"', "&quot;")}" style="display:inline-block;white-space:nowrap;vertical-align:baseline;font-size:0;line-height:0">${cells.join("")}</span>`;
}

/** The drawn tally followed by its levels in small grey text. */
export function htmlWithLevels(levels: readonly number[], o: HtmlOptions = {}): string {
  return `${html(levels, o)}&nbsp;<span style="font-size:11px;color:#5f6368">${levels.map(clamp).join("·")}</span>`;
}
