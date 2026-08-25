import { describe, expect, test } from "bun:test"
import { colouredRuns, isDefaultColour, normColour } from "./attribution-parse.ts"

/**
 * The failure these tests exist to prevent is NOT a crash — it is a confident wrong answer about
 * who wrote which line. Each case below corresponds to a measured real-world failure mode.
 */

describe("normColour — one visual colour has many spellings", () => {
  // A thread that round-trips Outlook -> Gmail gets its colours rewritten each hop. Keying
  // authorship on the literal attribute string splits ONE author into several, and the parser
  // then reports three participants where there are two, each internally coherent.
  test.each([
    ["blue", "#0000ff"],
    ["#00F", "#0000ff"],
    ["#0000FF", "#0000ff"],
    ["rgb(0,0,255)", "#0000ff"],
    ["rgb(0, 0, 255)", "#0000ff"],
    ["rgba(0,0,255,1)", "#0000ff"],
  ])("%s collapses to %s", (input, want) => {
    expect(normColour(input)).toBe(want)
  })

  test("Outlook's signature blue survives a Gmail round-trip as the same key", () => {
    expect(normColour("#1F497D")).toBe(normColour("rgb(31,73,125)"))
  })

  test("non-colours are null, not a colour named 'inherit'", () => {
    for (const c of ["inherit", "initial", "auto", "currentColor", "windowtext", "transparent"]) {
      expect(normColour(c)).toBeNull()
    }
  })
})

describe("isDefaultColour — black is the default, not an authorship marker", () => {
  test.each(["#000", "#000000", "black", "rgb(0,0,0)"])("%s is default", (c) => {
    expect(isDefaultColour(normColour(c))).toBe(true)
  })

  test("blue is NOT default", () => {
    expect(isDefaultColour(normColour("#0000ff"))).toBe(false)
  })
})

describe("colouredRuns — the legacy <font color> trap", () => {
  // Gmail emits <font color="#0000ff">, NOT css style="color:". A detector that greps only for
  // `color:` returns ZERO on a message full of blue, and zero reads as "no colour was used".
  test("finds the legacy font attribute form", () => {
    const runs = colouredRuns('<div>quoted<font color="#0000ff">their reply here</font>more</div>')
    expect(runs).toHaveLength(1)
    expect(runs[0]?.colour).toBe("#0000ff")
    expect(runs[0]?.text).toBe("their reply here")
  })

  test("finds the css form too", () => {
    const runs = colouredRuns('<span style="color:#0000FF">their reply</span>')
    expect(runs[0]?.colour).toBe("#0000ff")
  })

  test("both forms in one message collapse to ONE author key", () => {
    const runs = colouredRuns('<font color="blue">a</font><span style="color:rgb(0,0,255)">b</span>')
    expect(new Set(runs.map((r: { colour: string }) => r.colour)).size).toBe(1)
  })

  test("a coloured region containing nested markup yields ONE run, not fragments", () => {
    // A naive regex between <font> and </font> splits on every inner tag, turning one sentence
    // into several "separate" replies.
    const runs = colouredRuns('<font color="#0000ff">first <b>bold</b> and <i>ital</i> tail</font>')
    expect(runs).toHaveLength(1)
    expect(runs[0]?.text).toBe("first bold and ital tail")
  })

  test("black text is not reported as an authorship signal", () => {
    expect(colouredRuns('<font color="#000000">ordinary quoted text</font>')).toHaveLength(0)
  })

  test("entities inside a coloured run are decoded", () => {
    const runs = colouredRuns('<font color="blue">a &gt; b &amp; c</font>')
    expect(runs[0]?.text).toBe("a > b & c")
  })

  test("no colour anywhere returns empty rather than throwing", () => {
    expect(colouredRuns("<div>plain quoted thread</div>")).toEqual([])
  })
})
