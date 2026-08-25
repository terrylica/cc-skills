#!/usr/bin/env bun
/**
 * attribution-parse.ts — answer "who wrote which line" for a replied-to email, and REFUSE to guess.
 *
 * WHY THIS EXISTS
 * ---------------
 * When someone answers inline — inside the quoted text of the message they are replying to — their
 * words and the words they are answering end up interleaved in the same body. Getting that boundary
 * wrong is not a formatting nuisance: it means attributing your own sentences to your correspondent,
 * or silently dropping half of what they said and calling it a summary.
 *
 * Measured 2026-08-25 on a real thread: a message with 22 authored segments carried only 13 typed
 * markers, so marker-based parsing saw 59% of the sender. Swinging to colour-based parsing instead
 * loses the sender's TOP MATTER, which is not coloured — on that message, the top matter held the
 * single most important decision in the mail.
 *
 * THE MODEL: authorship ⊃ colour ⊃ marker
 * ---------------------------------------
 *   • QUOTE DEPTH is complete. In text/plain the sender's own lines are the ones NOT prefixed `>`.
 *     It captures top matter and inline insertions alike. It is the primary signal.
 *   • COLOUR is a proper subset. It only appears in text/html, and it exists to disambiguate
 *     insertions INSIDE a quoted region — exactly where depth gets unreliable, because clients
 *     re-quote inconsistently.
 *   • A TYPED MARKER (`>>>PT`, `@@@`, `[JS]`) is a proper subset of colour. It flags where a block
 *     STARTS. It is the weakest signal and must never be used alone.
 *
 * WHAT THIS TOOL WILL NOT DO
 * --------------------------
 * It will not silently pick a winner when the signals disagree. Conflicts and unattributable text
 * are reported as CONFLICT / UNKNOWN. A confident wrong attribution is the failure this exists to
 * prevent, so "I cannot tell" is a valid and preferred output.
 *
 * USAGE
 *   bun attribution-parse.ts --id <messageId> --token-cmd '<cmd printing an access token>'
 *   bun attribution-parse.ts --html msg.html --plain msg.txt
 *   bun attribution-parse.ts --id <id> --token-cmd '...' --json
 */

type Seg = {
  text: string
  depth: number
  colour: string | null
  marker: string | null
  verdict: "SENDER" | "QUOTED" | "CONFLICT" | "UNKNOWN"
  why: string
}

const args = process.argv.slice(2)
const flag = (n: string): string | undefined => {
  const i = args.indexOf(n)
  return i >= 0 ? args[i + 1] : undefined
}
const has = (n: string) => args.includes(n)

// `import.meta.main` guard: without it, importing this module for a unit test trips the
// no-arguments branch, prints help and calls process.exit(0) — which kills the test runner
// before a single assertion runs, and looks like a passing suite with no output.
if (import.meta.main && (has("-h") || has("--help") || args.length === 0)) {
  console.log(
    [
      "attribution-parse — who wrote which line in a replied-to email",
      "",
      "  --id <messageId>       Gmail message id (needs --token-cmd)",
      "  --token-cmd <cmd>      shell command that prints an OAuth access token",
      "  --html <file>          use a local text/html file instead of fetching",
      "  --plain <file>         use a local text/plain file instead of fetching",
      "  --marker <regex>       override marker detection (default: >>>XX / @@@ / [XX] / XX:)",
      "  --json                 machine-readable output",
      "",
      "Signals, in order of trust: quote depth (complete) > colour (html only) > typed marker.",
    ].join("\n"),
  )
  process.exit(0)
}

/** Default marker set. Deliberately conservative: a false marker is worse than a missed one, since
 * a missed marker still leaves depth and colour, while a false one invents an authorship boundary. */
const MARKER_RE = new RegExp(
  flag("--marker") ??
    [
      String.raw`^>{2,}\s*[A-Z]{1,4}\s*[:\-]`, // >>>PT:  >>PT -
      "^@{2,}", // @@@
      String.raw`^\[[A-Z]{1,4}\]`, // [JS]
      String.raw`^[A-Z]{2,4}\s*:`, // PT:  RH:
      "^<{2,}", // <<<
    ].join("|"),
)

async function sh(cmd: string): Promise<string> {
  const p = Bun.spawn(["/usr/bin/env", "bash", "-c", cmd], { stdout: "pipe", stderr: "pipe" })
  const out = await new Response(p.stdout).text()
  await p.exited
  return out.trim()
}

function b64urlDecode(s: string): string {
  return Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8")
}

/** Pull every non-default coloured run out of html, tracking nesting so a coloured region containing
 * further markup yields ONE run rather than a fragment per inner tag. Handles BOTH the legacy
 * `<font color=...>` attribute and css `style="color:..."`, because Gmail emits the former and a
 * detector that greps only for `color:` returns zero on a message full of colour — a wrong query
 * whose empty result reads as "no colour was used". */
export function colouredRuns(html: string): { colour: string; text: string }[] {
  const runs: { colour: string; text: string }[] = []
  const stack: (string | null)[] = []
  let cur: string[] = []
  let active: string | null = null
  for (const tok of html.split(/(<[^>]+>)/)) {
    if (tok.startsWith("<")) {
      const low = tok.toLowerCase()
      const open = /^<(font|span|div|p|b|i|strong|em)\b/.test(low)
      const close = /^<\/(font|span|div|p|b|i|strong|em)\b/.test(low)
      if (open) {
        const m =
          low.match(/color\s*=\s*["']?(#[0-9a-f]{3,8}|[a-z]+)/i) ??
          low.match(/(?:^|[;"'\s])color\s*:\s*(#[0-9a-f]{3,8}|rgba?\([^)]*\)|[a-z]+)/i)
        const c = m?.[1] ? normColour(m[1]) : null
        const isColour = !isDefaultColour(c)
        stack.push(isColour ? c : null)
        if (isColour && active === null) {
          active = c
          cur = []
        }
      } else if (close) {
        const popped = stack.pop() ?? null
        if (popped && popped === active) {
          const text = cur.join("").replace(/\s+/g, " ").trim()
          if (text) runs.push({ colour: active, text: decode(text) })
          active = null
          cur = []
        }
      } else if (active && /^<(br|div|p|tr|li)\b/.test(low)) {
        cur.push(" ")
      }
    } else if (active) {
      cur.push(tok)
    }
  }
  return runs
}

/** CSS named colours we actually need; anything else falls through as-is. */
const NAMED: Record<string, string> = {
  // `black` and `white` matter most: without them a message whose quoted body is explicitly
  // coloured black falls through as a NON-default colour, and every quoted line gets attributed
  // to the sender as if they had highlighted the entire thread.
  black: "#000000", white: "#ffffff",
  blue: "#0000ff", red: "#ff0000", green: "#008000", purple: "#800080", orange: "#ffa500",
  teal: "#008080", navy: "#000080", maroon: "#800000", olive: "#808000", fuchsia: "#ff00ff",
  aqua: "#00ffff", lime: "#00ff00", silver: "#c0c0c0", gray: "#808080", grey: "#808080",
  darkblue: "#00008b", darkred: "#8b0000", darkgreen: "#006400",
}

/**
 * Normalise a colour to a canonical `#rrggbb` BEFORE any equality test.
 *
 * One visual colour reaches you as `blue`, `#00F`, `#0000ff`, `#0000FF`, `rgb(0,0,255)` or
 * `rgb(0, 0, 255)` — sometimes several forms in ONE message, because a thread that round-trips
 * between Outlook and Gmail gets rewritten each hop. Keying authorship on the literal attribute
 * string therefore SPLITS ONE AUTHOR INTO SEVERAL: the parser reports three participants where
 * there are two, each with a plausible, internally coherent set of statements, and nothing looks
 * wrong. That is the worst failure shape available here.
 */
export function normColour(raw: string): string | null {
  const c = raw.trim().toLowerCase().replace(/\s+/g, "")
  if (!c || /^(inherit|initial|auto|currentcolor|windowtext|transparent)$/.test(c)) return null
  if (NAMED[c]) return NAMED[c]
  let m = c.match(/^#([0-9a-f]{3,4})$/)
  if (m?.[1])
    return (
      "#" +
      m[1]
        .slice(0, 3)
        .split("")
        .map((h) => h + h)
        .join("")
    )
  m = c.match(/^#([0-9a-f]{6})[0-9a-f]{0,2}$/)
  if (m?.[1]) return "#" + m[1]
  m = c.match(/^rgba?\((\d+),(\d+),(\d+)/)
  if (m) return "#" + [1, 2, 3].map((i) => Number(m![i]).toString(16).padStart(2, "0")).join("")
  return c
}

/** Black in any spelling is the default text colour, not an authorship marker. */
export function isDefaultColour(c: string | null): boolean {
  return c === null || c === "#000000"
}

function decode(s: string): string {
  return s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
}

/** Flatten a MIME payload tree. Hoisted out of main() because it captures nothing. */
function walkParts(p: any): any[] {
  return [p, ...((p?.parts ?? []) as any[]).flatMap(walkParts)]
}

const norm = (s: string) => s.replace(/\s+/g, " ").replace(/[“”]/g, '"').replace(/[‘’]/g, "'").trim().toLowerCase()

async function main() {
  let html = ""
  let plain = ""

  const htmlFile = flag("--html")
  const plainFile = flag("--plain")
  const id = flag("--id")
  const tokenCmd = flag("--token-cmd")

  if (htmlFile) html = await Bun.file(htmlFile).text()
  if (plainFile) plain = await Bun.file(plainFile).text()

  if (id) {
    if (!tokenCmd) throw new Error("--id needs --token-cmd (a command that prints an access token)")
    const tok = (await sh(tokenCmd)).split("\n").pop()!.trim()
    if (!tok) throw new Error("token command produced nothing — refusing to proceed blind")
    const res = await fetch(`https://gmail.googleapis.com/gmail/v1/users/me/messages/${id}?format=full`, {
      headers: { Authorization: `Bearer ${tok}` },
    })
    if (!res.ok) throw new Error(`Gmail API ${res.status} — ${await res.text()}`)
    const msg = (await res.json()) as any
    for (const p of walkParts(msg.payload)) {
      const data = p?.body?.data
      if (!data) continue
      if (p.mimeType === "text/html" && !html) html = b64urlDecode(data)
      if (p.mimeType === "text/plain" && !plain) plain = b64urlDecode(data)
    }
  }

  if (!plain && !html) throw new Error("nothing to parse — give --id, or --html/--plain")

  // ---- signal availability, stated up front so a missing signal is never mistaken for a finding --
  const runs = html ? colouredRuns(html) : []
  const palette = [...new Set(runs.map((r) => r.colour))]
  const signals = {
    quoteDepth: !!plain,
    colour: runs.length > 0,
    html: !!html,
    markers: 0,
  }

  // ---- segment the plain text by quote depth --------------------------------------------------
  const segs: Seg[] = []
  if (plain) {
    // Split on CRLF/CR/LF, not "\n". Real email is CRLF, and a trailing \r is a line TERMINATOR to
    // the regex engine: `.` will not match it and an unanchored `$` will not match before it, so a
    // `(.*)$` pattern fails on EVERY line and yields empty text for the whole message. Measured
    // 2026-08-25 — the parser reported 0 segments while confidently printing "quote depth: yes".
    for (const raw of plain.split(/\r\n|\r|\n/)) {
      const m = raw.match(/^((?:\s*>)+)?\s?(.*)/)
      const depth = (m?.[1]?.match(/>/g) ?? []).length
      const text = (m?.[2] ?? "").trim()
      if (!text) continue
      const marker = MARKER_RE.test(text) ? (text.match(MARKER_RE)?.[0] ?? null) : null
      if (marker) signals.markers++
      const inColour = runs.find((r) => norm(r.text).includes(norm(text)) && norm(text).length > 12)

      let verdict: Seg["verdict"]
      let why: string
      if (depth === 0) {
        verdict = "SENDER"
        why = "quote depth 0 — the sender's own line"
      } else if (inColour) {
        verdict = "SENDER"
        why = `inside quoted text but coloured ${inColour.colour}${marker ? ` and marked ${marker}` : " (continuation, no marker)"}`
      } else if (marker && signals.colour) {
        verdict = "CONFLICT"
        why = `carries marker ${marker} but is NOT coloured, while this message does use colour — verify by hand`
      } else if (marker) {
        verdict = "SENDER"
        why = `marker ${marker}; no colour anywhere in this message, so the marker is the only signal`
      } else if (signals.colour) {
        verdict = "QUOTED"
        why = "quoted depth, not coloured, in a message that uses colour"
      } else {
        verdict = "UNKNOWN"
        why = "quoted depth, and this message carries NO colour and no marker here — depth alone cannot separate an inline insertion"
      }
      segs.push({ text, depth, colour: inColour?.colour ?? null, marker, verdict, why })
    }
  }

  // colour present in html but never matched into plain text = something the plain part lost
  const orphanColour = runs.filter((r) => !segs.some((s) => norm(r.text).includes(norm(s.text)) && s.text.length > 12))

  if (has("--json")) {
    console.log(JSON.stringify({ signals, palette, segments: segs, orphanColour }, null, 1))
    return
  }

  const sender = segs.filter((s) => s.verdict === "SENDER")
  const conflict = segs.filter((s) => s.verdict === "CONFLICT")
  const unknown = segs.filter((s) => s.verdict === "UNKNOWN")

  console.log(`# Attribution${id ? ` — ${id}` : ""}\n`)
  console.log("## Signals available\n")
  console.log(`- quote depth: ${signals.quoteDepth ? "yes (primary, complete)" : "NO — text/plain missing"}`)
  console.log(
    `- colour: ${signals.colour ? `yes — ${runs.length} run(s), palette ${palette.join(", ")}` : html ? "none found in the html" : "NOT CHECKED — no text/html fetched, so colour-marked replies are INVISIBLE"}`,
  )
  console.log(`- typed markers: ${signals.markers}\n`)
  if (!html)
    console.log(
      "> ⚠ No html part. If this sender marks their inline replies by colour you cannot see it, and\n> anything below at quoted depth may be theirs. Re-run with --id/--token-cmd before attributing.\n",
    )
  if (signals.colour && signals.markers && runs.length !== signals.markers)
    console.log(
      `> ⚠ ${runs.length} coloured run(s) but ${signals.markers} marker(s). The difference is continuation\n> text the sender wrote WITHOUT a marker. Marker-based reading would miss it.\n`,
    )

  console.log(`## Attributed to the sender (${sender.length})\n`)
  for (const s of sender) console.log(`- [d${s.depth}${s.colour ? ` ${s.colour}` : ""}] ${s.text}\n      ↳ ${s.why}`)
  if (conflict.length) {
    console.log(`\n## 🔴 CONFLICT — signals disagree, do NOT quote these without checking (${conflict.length})\n`)
    for (const s of conflict) console.log(`- ${s.text}\n      ↳ ${s.why}`)
  }
  if (unknown.length) {
    console.log(`\n## ⚠ UNKNOWN — cannot attribute (${unknown.length})\n`)
    for (const s of unknown.slice(0, 20)) console.log(`- ${s.text}\n      ↳ ${s.why}`)
    if (unknown.length > 20) console.log(`  …and ${unknown.length - 20} more`)
  }
  if (orphanColour.length) {
    console.log(`\n## ⚠ Coloured in html but not matched in text/plain (${orphanColour.length})\n`)
    console.log("The plain part lost these. Treat the html as authoritative for them.\n")
    for (const r of orphanColour.slice(0, 10)) console.log(`- [${r.colour}] ${r.text.slice(0, 200)}`)
  }
  console.log(
    "\n---\n**Read to the end of every paragraph.** The decision is in sentence one; the condition is in sentence two; the condition is the part that binds you.",
  )
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(`attribution-parse: ${e.message}`)
    process.exit(1)
  })
}
