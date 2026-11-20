#!/usr/bin/env bun
/**
 * braille-tally — print, read, draw and rank Braille Tallies (see skills/braille-tally/SKILL.md).
 *
 *   braille-tally tally 2 8 8 [--levels]          ⣀⣿⣿   (--levels: "⣀⣿⣿ (2·8·8)")
 *   braille-tally parse ⣀⣿⣿                        2 8 8
 *   braille-tally legend [--axes "Value,Risk,Effort"]
 *   braille-tally html 2 8 8 [--ink "#3c4043"] [--levels]
 *   braille-tally rank [--tie 1,0,2] < items.jsonl  one JSON object per line: {"id","levels":[…],"label"?}
 *   braille-tally spec                              this command set as JSON (machine-readable)
 *
 * Add --json to tally, parse and rank for JSON output. Exit 2 on a usage error.
 */
import { DEFAULT_AXES, DEFAULT_TIE_ORDER, html, htmlWithLevels, type Item, legend, levelsOf, ranked, tally, tallyWithLevels } from "../lib/tally.ts";

export const SPEC = {
  name: "braille-tally",
  commands: {
    tally: { args: "LEVEL… (1-8 each)", flags: { "--levels": "append the levels, e.g. (2·8·8)", "--json": "JSON output" } },
    parse: { args: "TALLY", flags: { "--json": "JSON output" } },
    legend: { args: "", flags: { "--axes": "comma-separated axis names (default Importance,Urgency,Simplicity)" } },
    html: { args: "LEVEL…", flags: { "--ink": "CSS colour of the dots (default currentColor)", "--levels": "append the levels in small grey" } },
    rank: { args: "JSON lines on stdin: {id, levels, label?}", flags: { "--tie": "axis positions that break ties inside a front (default 1,0,2)", "--json": "JSON output" } },
    spec: { args: "", flags: {} },
  },
} as const;

function flag(args: string[], name: string): string | undefined {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
}

/** Flags that take a value; everything else starting with "--" is a switch. */
const VALUE_FLAGS = new Set(["--ink", "--axes", "--tie"]);

/** The positional arguments: everything that is not a flag or a flag's value. */
function positional(args: string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < args.length; i++) {
    if (VALUE_FLAGS.has(args[i]!)) i++;
    else if (!args[i]!.startsWith("--")) out.push(args[i]!);
  }
  return out;
}

/** Levels from the positional arguments: each a whole number; at least one. Clamped to 1-8 like the library. */
function levelsArg(args: string[]): number[] {
  const pos = positional(args);
  if (pos.length < 1) throw new Error("give at least one level, 1-8");
  const bad = pos.filter((a) => !/^-?\d+$/.test(a));
  if (bad.length) throw new Error(`levels are whole numbers 1-8; not: ${bad.join(" ")}`);
  return pos.map((a) => Math.min(8, Math.max(1, Number(a))));
}

export async function main(argv: string[], io = { out: (s: string) => console.log(s), stdin: () => Bun.stdin.text() }): Promise<number> {
  const [cmd, ...args] = argv;
  const json = args.includes("--json");
  try {
    switch (cmd) {
      case "tally": {
        const l = levelsArg(args);
        io.out(json ? JSON.stringify({ tally: tally(l), levels: l }) : args.includes("--levels") ? tallyWithLevels(l) : tally(l));
        return 0;
      }
      case "parse": {
        const l = levelsOf(positional(args)[0] ?? "");
        if (!l) throw new Error("not a Braille Tally");
        io.out(json ? JSON.stringify({ levels: l }) : l.join(" "));
        return 0;
      }
      case "legend": {
        const axes = flag(args, "--axes")?.split(",").map((s) => s.trim()).filter(Boolean) ?? [...DEFAULT_AXES];
        io.out(legend(axes));
        return 0;
      }
      case "html": {
        const l = levelsArg(args);
        const o = { ink: flag(args, "--ink") };
        io.out(args.includes("--levels") ? htmlWithLevels(l, o) : html(l, o));
        return 0;
      }
      case "rank": {
        const tie = flag(args, "--tie")?.split(",").map(Number) ?? [...DEFAULT_TIE_ORDER];
        const items: Item[] = (await io.stdin()).split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l));
        for (const it of items) if (typeof it.id !== "string" || !Array.isArray(it.levels)) throw new Error("each line needs id and levels");
        const r = ranked(items, tie);
        if (json) io.out(JSON.stringify(r.map(({ item, front }, i) => ({ rank: i + 1, front, tally: tally(item.levels), ...item }))));
        else for (const [i, { item, front }] of r.entries()) io.out(`${i + 1}. ${tally(item.levels)}  front ${front}  ${item.id}${item.label ? `  ${item.label}` : ""}`);
        return 0;
      }
      case "spec":
        io.out(JSON.stringify(SPEC, null, 1));
        return 0;
      default:
        io.out("usage: braille-tally tally|parse|legend|html|rank|spec … (braille-tally spec for details)");
        return 2;
    }
  } catch (e) {
    io.out(`braille-tally: ${(e as Error).message}`);
    return 2;
  }
}

if (import.meta.main) process.exit(await main(process.argv.slice(2)));
