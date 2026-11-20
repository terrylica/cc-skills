import { describe, expect, test } from "bun:test";
import { CELLS, cell, dominates, fronts, html, leadingTally, legend, levelsOf, outOfRank, ranked, tally, tallyWithLevels } from "../lib/tally.ts";
import { denyMessage, ESCAPE_TOKEN, problems } from "../hooks/askuserquestion-tally-guard.ts";
import { main, SPEC } from "../scripts/braille-tally.ts";

const bits = (c: string) => c.codePointAt(0)! - 0x2800;
const dotCount = (b: number) => b.toString(2).replaceAll("0", "").length;
const it = (id: string, ...levels: number[]) => ({ id, levels });
const drawn = (h: string) => [...h.matchAll(/<span style="display:inline-block;width:\d+px;margin-right:(\d+)px[^"]*">((?:<span style="display:block[^"]*"><\/span>)+)<\/span>/g)]
  .map((c) => ({ right: Number(c[1]), rows: [...c[2]!.matchAll(/background-color:([^"]+)"/g)].map((m) => (m[1] === "transparent" ? 0 : 1)).join("") }));
const q = (labels: string[], question = "Braille Tally: Importance · Urgency · Simplicity, ⡀ lowest to ⣿ highest. Which?") =>
  ({ questions: [{ question, header: "Pick", multiSelect: false, options: labels.map((label) => ({ label, description: "d" })) }] });
const run = async (stdin: string) => {
  const p = Bun.spawn(["bun", `${import.meta.dir}/../hooks/askuserquestion-tally-guard.ts`], { stdin: new Blob([stdin]), stdout: "pipe" });
  const out = await new Response(p.stdout).text();
  return { code: await p.exited, out };
};
const cli = async (argv: string[], stdin = "") => {
  const lines: string[] = [];
  const code = await main(argv, { out: (s) => lines.push(s), stdin: async () => stdin });
  return { code, out: lines.join("\n") };
};

describe("cells", () => {
  test("eight Braille patterns; level n has exactly n dots and keeps every dot of level n-1; the bottom row fills first", () => {
    const b = [...CELLS].map(bits);
    expect(b).toHaveLength(8);
    b.forEach((x, i) => {
      expect(x).toBeGreaterThan(0);
      expect(x).toBeLessThanOrEqual(0xff);
      expect(dotCount(x)).toBe(i + 1);
      if (i) expect(x & b[i - 1]!).toBe(b[i - 1]!);
    });
    expect(b[1]).toBe(0x40 | 0x80);
    expect(b[7]).toBe(0xff);
  });
  test("tally, clamping, levels in text, and reading back", () => {
    expect(tally([2, 8, 8])).toBe("⣀⣿⣿");
    expect(tally([1, 4, 8])).toBe("⡀⣤⣿");
    expect(cell(0)).toBe("⡀");
    expect(cell(9)).toBe("⣿");
    expect(cell(4.6)).toBe("⣴");
    expect(tallyWithLevels([2, 8, 8])).toBe("⣀⣿⣿ (2·8·8)");
    expect(tallyWithLevels([0, 9, 3])).toBe("⡀⣿⣠ (1·8·3)");
    expect(levelsOf("⣠⣴⣾")).toEqual([3, 5, 7]);
    expect(levelsOf("⣀⣿x")).toBeUndefined();
    expect(levelsOf("⣀⠁")).toBeUndefined();
    expect(levelsOf("")).toBeUndefined();
  });
  test("a leading tally is 2-6 cells and one space", () => {
    expect(leadingTally("⣿⣶⣴ Keep it (Recommended)")).toEqual({ levels: [8, 6, 5], rest: "Keep it (Recommended)" });
    expect(leadingTally("⣿⣶ Two axes")).toEqual({ levels: [8, 6], rest: "Two axes" });
    expect(leadingTally("⣿ One cell")).toBeUndefined();
    expect(leadingTally("⣿⣿⣿⣿⣿⣿⣿ Seven")).toBeUndefined();
    expect(leadingTally("⣿⣶⣴Keep")).toBeUndefined();
    expect(leadingTally("Keep ⣿⣶⣴")).toBeUndefined();
  });
  test("the legend names the axes and the two ends", () => {
    expect(legend()).toBe("Braille Tally: Importance · Urgency · Simplicity, each column ⡀ (lowest) to ⣿ (highest), relative to the other items.");
    expect(legend(["Value", "Risk"])).toStartWith("Braille Tally: Value · Risk, each column ⡀");
  });
});

describe("ranking", () => {
  test("dominance needs at least as high everywhere and higher somewhere, on equal lengths", () => {
    expect(dominates([3, 3, 3], [3, 3, 2])).toBe(true);
    expect(dominates([3, 3, 3], [3, 3, 3])).toBe(false);
    expect(dominates([4, 1, 9], [3, 3, 3])).toBe(false);
    expect(dominates([3, 3], [2, 2, 2])).toBe(false);
  });
  test("Pareto fronts with urgency, then importance, then simplicity, then id breaking ties", () => {
    const f = fronts([it("a", 2, 8, 8), it("b", 8, 6, 8), it("c", 6, 6, 8), it("d", 1, 1, 1), it("e", 8, 6, 8)]);
    expect(f.map((x) => x.map((y) => y.id))).toEqual([["a", "b", "e"], ["c"], ["d"]]);
    expect(ranked([it("x", 5, 5, 5), it("y", 5, 5, 5)]).map((r) => `${r.item.id}${r.front}`)).toEqual(["x1", "y1"]);
    expect(fronts([it("p", 4, 5, 9), it("q", 5, 5, 3)], [2]).flat().map((y) => y.id)).toEqual(["p", "q"]);
    expect(fronts([])).toEqual([]);
  });
  test("outOfRank finds the first later item that beats an earlier one", () => {
    expect(outOfRank([[8, 6, 5], [5, 6, 8], [4, 3, 8]])).toBeUndefined();
    expect(outOfRank([[4, 3, 8], [8, 6, 8]])).toEqual([0, 1]);
    expect(outOfRank([[8, 8, 8], [1, 1, 1], [2, 2, 2]])).toEqual([1, 2]);
  });
});

describe("html", () => {
  test("each level is drawn as exactly the dots of its Braille pattern, two columns of four, bottom-aligned boxes", () => {
    for (let n = 1; n <= 8; n++) {
      const b = bits(cell(n));
      const want = [[0x01, 0x02, 0x04, 0x40], [0x08, 0x10, 0x20, 0x80]].map((col) => col.map((x) => (b & x ? 1 : 0)).join(""));
      expect(drawn(html([n])).map((c) => c.rows)).toEqual(want);
    }
    expect(drawn(html([2, 8, 1])).map((c) => c.right)).toEqual([1, 4, 1, 4, 1, 0]);
    const h = html([2, 8, 1], { ink: "#123456" });
    expect(h).toContain("background-color:#123456");
    expect(h).toContain('aria-label="Braille Tally 2, 8, 1 of 8"');
    expect(h).not.toMatch(/<table|src=|url\(/);
    expect(html([1], { label: 'a "b"' })).toContain('aria-label="a &quot;b&quot;"');
  });
});

describe("AskUserQuestion guard", () => {
  test("a tallied, legended, ranked question passes", () => {
    expect(problems(q(["⣿⣶⣴ Guard (Recommended)", "⣴⣶⣿ Reminder", "⣤⣠⣿ Rule only"]))).toEqual([]);
  });
  test("a label without a tally is named", () => {
    const p = problems(q(["⣿⣶⣴ Guard", "Reminder"]));
    expect(p).toHaveLength(1);
    expect(p[0]).toContain('"Pick": 1 option label(s) do not start with a Braille Tally');
    expect(p[0]).toContain('"Reminder"');
  });
  test("a missing legend, mixed cell counts and an out-of-rank order are each named", () => {
    expect(problems(q(["⣿⣶⣴ A", "⣴⣶⣿ B"], "Which?"))[0]).toContain("needs the legend");
    expect(problems(q(["⣿⣶⣴ A", "⣴⣶ B"]))[0]).toContain("same number of cells");
    const r = problems(q(["⣤⣠⣿ Rule only", "⣿⣶⣿ Guard"]));
    expect(r[0]).toContain("option 2 (⣿⣶⣿) beats option 1 (⣤⣠⣿)");
  });
  test("the escape token, other payload shapes and the second question", () => {
    expect(problems({ ...q(["Plain"]), note: ESCAPE_TOKEN })).toEqual([]);
    expect(problems(q([`Plain ${ESCAPE_TOKEN}`]))).toEqual([]);
    expect(problems(null)).toEqual([]);
    expect(problems({ questions: "x" })).toEqual([]);
    expect(problems({ questions: [null, { question: "Braille Tally", options: [{ label: "x" }] }] })[0]).toStartWith("question 2:");
  });
  test("the deny message teaches the format but never names the escape token", () => {
    const m = denyMessage(["x"]);
    expect(m).toContain("⡀ ⣀ ⣠ ⣤ ⣴ ⣶ ⣾ ⣿");
    expect(m).toContain("- x");
    expect(m).not.toContain(ESCAPE_TOKEN);
  });
  test("the hook process denies a bad question, allows a good one and fails open on junk", async () => {
    const bad = await run(JSON.stringify({ tool_name: "AskUserQuestion", tool_input: q(["Plain"]) }));
    expect(bad.code).toBe(0);
    expect(JSON.parse(bad.out).hookSpecificOutput.permissionDecision).toBe("deny");
    expect((await run(JSON.stringify({ tool_name: "AskUserQuestion", tool_input: q(["⣿⣶⣴ A", "⣴⣶⣿ B"]) }))).out).toBe("");
    expect((await run(JSON.stringify({ tool_name: "Bash", tool_input: q(["Plain"]) }))).out).toBe("");
    expect(await run("not json")).toEqual({ code: 0, out: "" });
  });
});

describe("CLI", () => {
  test("tally, parse, legend, html", async () => {
    expect(await cli(["tally", "2", "8", "8"])).toEqual({ code: 0, out: "⣀⣿⣿" });
    expect((await cli(["tally", "2", "8", "8", "--levels"])).out).toBe("⣀⣿⣿ (2·8·8)");
    expect(JSON.parse((await cli(["tally", "1", "2", "--json"])).out)).toEqual({ tally: "⡀⣀", levels: [1, 2] });
    expect((await cli(["parse", "⣠⣴⣾"])).out).toBe("3 5 7");
    expect((await cli(["parse", "abc"])).code).toBe(2);
    expect((await cli(["legend", "--axes", "Value, Risk"])).out).toStartWith("Braille Tally: Value · Risk,");
    expect((await cli(["html", "8", "--ink", "#000", "--levels"])).out).toContain("background-color:#000");
    expect((await cli(["tally"])).code).toBe(2);
    expect((await cli(["html", "8", "--ink", "3"])).out).toContain('aria-label="Braille Tally 8 of 8"'); // a flag's value is not a level (review)
    expect((await cli(["tally", "2.5", "8"])).code).toBe(2);
    expect((await cli(["tally", "2", "x", "8"])).out).toContain("not: x");
    expect(JSON.parse((await cli(["tally", "0", "9", "--json"])).out)).toEqual({ tally: "⡀⣿", levels: [1, 8] });
  });
  test("rank reads JSON lines and prints the ranked list or JSON", async () => {
    const input = ['{"id":"low","levels":[1,1,1]}', '{"id":"top","levels":[8,8,8],"label":"Top"}', ""].join("\n");
    expect((await cli(["rank"], input)).out).toBe("1. ⣿⣿⣿  front 1  top  Top\n2. ⡀⡀⡀  front 2  low");
    expect(JSON.parse((await cli(["rank", "--json"], input)).out)[0]).toMatchObject({ rank: 1, front: 1, tally: "⣿⣿⣿", id: "top" });
    expect((await cli(["rank"], '{"id":1}')).code).toBe(2);
  });
  test("spec lists every command, and an unknown command is a usage error", async () => {
    expect(Object.keys(JSON.parse((await cli(["spec"])).out).commands)).toEqual(Object.keys(SPEC.commands));
    expect((await cli(["nope"])).code).toBe(2);
  });
});
