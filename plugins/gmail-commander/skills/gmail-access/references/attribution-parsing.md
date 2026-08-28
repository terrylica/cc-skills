# Inline-reply attribution — field reference

**What this is for.** Deciding **who wrote which line** in a replied-to email thread. That is a
different problem from reading the email, it is harder than it looks, and its failure mode is not a
crash — it is a fluent, confident, wrong answer that nobody catches.

**Read the doctrine in [SKILL.md](../SKILL.md) first**; this file is the catalogue behind it. The
tool that implements it is `scripts/attribution-parse.ts`, with unit tests in
`scripts/attribution-parse.test.ts` pinning the failure modes marked below.

**Provenance.** Assembled 2026-08-25 from a four-lens survey (108 raw conventions, deduplicated)
covering colour and formatting, typed markers, quote structure, and client artifacts that masquerade
as authorship signals. Prompted by a real incident in which a scan for css `color:` returned zero on
a message containing 25 legacy `<font color="#0000ff">` tags, and the zero was read as "the sender
used no colour". Where an entry says _measured_, it was observed on real mail; the rest is surveyed
and should be treated as a lead to verify, not as settled fact.

**How to use it.** Do not read start to finish. Find your layer, apply the detection rule, and pay
attention to the _silent failure_ line — that is the part that decides whether you notice you were
wrong.

---

# Inline-Reply Attribution: Field Reference

Determining who wrote which line in a quoted email thread. Organised by detection layer. Every rule assumes Layer 0 has already run — most "silent failures" below are really Layer 0 omissions surfacing three layers later.

## Layer 0 — Normalisation that must precede every rule

Skipping any of these produces a well-formed, confident, wrong answer with no exception raised.

### 0.1 Decode Content-Transfer-Encoding before splitting lines

**Looks like:** `Content-Transfer-Encoding: quoted-printable` with body lines such as `=3E=3E we can do 15 min`, or a line ending in a bare `=`; or `base64` with no visible text at all.

**Detect:** Decode the part's CTE first. In QP, `=3E` is `>`, `=20` is a trailing space (which is a `format=flowed` soft break), and `/=\r?\n/` is a soft break that must be removed to rebuild the logical line.

**Silent failure:** A regex over raw MIME source sees zero `>` characters and reports a flat single-author message — the whole quoted history is attributed to the last sender. The QP soft break is worse: a continuation appears at depth 0 while its head was at depth 2, manufacturing a phantom insertion that is really mid-sentence quoted text. Universal wherever the body has non-ASCII (accented names, 陳大文, curly quotes, em dashes) or lines over 78 chars; Exchange and most gateways re-encode aggressively.

### 0.2 Un-stuff and re-join `format=flowed` (RFC 3676)

**Looks like:** `Content-Type: text/plain; charset=utf-8; format=flowed; delsp=yes`. Soft-wrapped lines end in one trailing space; lines that would start with a space or `>` are space-stuffed with one extra leading space.

**Detect:** Read `format` and `delsp` from the part headers. Unstuff with `^(?P<q>>*)\x20(?P<rest>.*)$` — remove exactly ONE space after the quote prefix. Join a trailing-space line to the next line ONLY when both have identical quote depth (RFC 3676 forbids joining across depth); drop the joining space when `delsp=yes`. Do all of this before any `^`-anchored rule.

**Silent failure:** Join without comparing depth and an inline reply is glued onto the tail of the quoted line above it — one sentence written half by each party, reading as ordinary prose. Fail to unstuff and a phantom leading space defeats `^\[` and `^[A-Z]{1,4}:`; after rewrap a `>>>PT` or `[PT]` marker can land mid-line, so every anchored rule finds zero markers and the parser declares the whole quote to be sender text. Thunderbird, Apple Mail, Evolution, KMail, mutt, many mobile clients. Outlook never emits it; Gmail's plaintext part does not either.

### 0.3 Parse BOTH MIME alternatives; union, never prefer

**Looks like:** `text/plain` contains `>>>PT yes` while `text/html` has only `<div>yes</div>` inside a blockquote with no chevron — or the reverse, red text in HTML and flat text in plain.

**Detect:** Extract candidate insertions from each part independently, align by normalised text, take the UNION, record which part supplied each piece of evidence, and emit a disagreement flag when the two candidate sets differ in size or content.

**Silent failure:** A hard "prefer text/plain because it is simpler" policy discards 100% of the colour signal and, on Outlook, the quote-depth signal too. The parts are generated independently: Outlook's plaintext differs in line breaking, drops tables entirely, and substitutes `[cid:image001.jpg@01DC1234.5678ABCD]` where the HTML had content — so character offsets from one part cannot be mapped onto the other. Some clients synthesize the plain part by flattening the HTML, inventing `>` prefixes the user never typed.

### 0.4 Normalise colour to an integer RGB triple before any equality test

**Looks like:** One visual colour written as `blue`, `#00F`, `#0000ff`, `#0000FF`, `rgb(0,0,255)`, `rgb(0, 0, 255)`, `rgba(0,0,255,1)`, `hsl(240,100%,50%)` — sometimes several forms in one message.

**Detect:** Case-fold hex, expand 3- and 4-digit forms, strip interior whitespace in `rgb()`/`hsl()`, map all 148 CSS named colours, and classify `windowtext` / `currentColor` / `inherit` / `initial` / `auto` as "no colour".

**Silent failure:** Keying authorship on the literal attribute string splits one author into several — Outlook emits `#1F497D` and the same colour returns as `rgb(31,73,125)` after a Gmail round-trip in the same thread. The parser reports three participants where there are two, and each further round manufactures another phantom author with a plausible, internally coherent set of statements.

### 0.5 Entity-decode HTML text nodes before applying plaintext-shaped patterns

**Detect:** `<<<`, `>>>`, `<PT>` and `>` prefixes arrive in the HTML part as `&lt;&lt;&lt;`, `&gt;`. Decode text nodes first, then match — and match against text nodes only, never the raw document, or the pattern starts eating tag soup.

**Silent failure:** Run before decoding and the parser reports "no inline markers" with full confidence.

### 0.6 NFKC on a parallel copy for CJK full-width markers

**Looks like:** `＞＞` (U+FF1E) for `>>`, `：` (U+FF1A) for `:`, `【PT】` (U+3010/3011), `＠＠＠`, `（回复：…）`, `〉〉`, `※`.

**Detect:** NFKC-normalise a parallel copy for marker matching while keeping the unnormalised original for byte offsets. Or match codepoints directly: `[>＞〉》]{1,10}` for depth, `[:：]` for colons, `[【】［］]` for brackets.

**Silent failure:** `^>` never matches `＞`, so a Japanese thread quoted with full-width chevrons parses as 100% new text by the last replier — the entire prior conversation misattributed, nothing anomalous to flag. Conversely, blanket NFKC destroys offsets (extracted spans no longer map back to source) and folds `！！！`→`!!!`, silently changing what a punctuation fence looks like.

### 0.7 Word conditional comments and `<o:p>` fragment runs

**Looks like:** `<!--[if gte mso 9]><xml>…</xml><![endif]-->`, `<![if !supportLists]>`, `<span style='mso-list:Ignore'>`, empty `<o:p></o:p>` in every paragraph.

**Detect:** `/<!--\[if[^\]]*\]>/i` (downlevel-hidden), `/<!\[(?:end)?if[^\]]*\]>/` (downlevel-REVEALED — no `--`, therefore NOT an HTML comment), `/<o:p\b/i`, `/mso-[a-z-]+\s*:/i`. Merge adjacent text runs across empty `<o:p>` before segmenting.

**Silent failure:** A comment-stripper leaves downlevel-revealed markup in place while a comment-aware parser swallows the content after it; either way offsets shift and a colour span that bracketed the reply now brackets a list bullet. `<o:p></o:p>` splits one coloured reply into several, so the parser reports four inline replies where the human wrote one, each a sentence fragment. See also 2.4 — stripping HTML comments as a sanitising pre-pass deletes Word's entire embedded stylesheet.

### 0.8 Client priors from headers

| Header                                   | Client                 | Colour prior                | Depth prior                   |
| ---------------------------------------- | ---------------------- | --------------------------- | ----------------------------- |
| `X-Mailer: Microsoft Outlook 16.0`       | Outlook desktop        | high (stationery, `[Name]`) | none — plaintext has no `>`   |
| Message-ID `@mail.gmail.com`             | Gmail web/mobile       | very low                    | HTML: `gmail_quote` structure |
| `X-Mailer: iPhone Mail (21F90)`          | Apple Mail iOS         | none (bold at most)         | `blockquote type="cite"`      |
| `X-Mailer: Zimbra` / `Roundcube Webmail` | webmail                | medium                      | `border-left` blockquote      |
| `format=flowed` present                  | Thunderbird/Apple/mutt | n/a                         | reliable `>` depth            |

## Layer 1 — Quote structure (complete, sometimes lying)

### 1.1 Canonical `>` depth counting

**Looks like:** `>> On the 4x/day cadence:` or `> > > we can do 15 min` — tight or space-separated, with an optional single space after the last `>`.

**Detect:** `^(?<q>(?:[ \t]*>)+)[ \t]?`; depth = count of `>` in group `q`. Strip exactly ONE space after the final `>` — further spaces are content indentation. `>>>` and `> > >` must both yield depth 3.

**Silent failure:** `^>+` (no interleaved whitespace) scores `> > > text` as depth 1, collapsing three turns into one and attributing the oldest author's words to the most recent quoter. Stripping all leading whitespace destroys indented content (code, lists, tables) inside quotes.

### 1.2 Blank lines are depth-transparent

**Looks like:** Inside a depth-1 block the paragraph separator appears as `>`, as `>`, or as a completely empty line — inconsistently, sometimes all three in one message.

**Detect:** Classify `^(?:[ \t]*>)*[ \t]*$` as BLANK, not depth-0 content. A blank inherits the depth of the preceding non-blank line. Never let a blank terminate a quoted region or start a new author block.

**Silent failure:** MTAs strip trailing whitespace, turning `>` into `>` and `>` into ``. A naive counter reads depth 1 → 0 → 1 and reports an inline insertion at every paragraph break — dozens of empty "replies" that then swallow surrounding real text when segments merge. The stripping happens in transit, not at the composer, so it appears unpredictably mid-thread.

### 1.3 Depth dip = interleaved insertion (the core attribution rule)

**Looks like:** A quoted region reading depth 1,1,1,0,0,1,1 — the run of 0s is the replier answering inside the quote.

**Detect:** Within a maximal region bounded by an attribution line at depth _d_, find maximal runs whose depth is a LOCAL MINIMUM strictly less than both neighbours. Require ≥1 non-whitespace character and no match against signature/elision/disclaimer patterns (Layer 4). Attribute the run to the author of level _d_min_. Nested: a dip from 2 to 1 belongs to the level-1 author, not the sender.

**Silent failure:** Without the blank-line and signature guards it fires constantly on noise. Without the local-minimum requirement ("any depth-0 line inside quoted text") it captures the trailing signature and legal disclaimer as inline answers. Applied only at depth 0 it misses A answering inside B's quote of C, and attributes A's insertion to B. Highest-value rule in the catalogue and the most over-fired.

### 1.4 Attribution lines govern the NEXT level down (off-by-one)

**Looks like:** `On Mon, Aug 25, 2026 at 9:14 AM Alex Rivera <a.rivera@example.com> wrote:` at depth 0, immediately followed by depth-1 text.

**Detect:** An attribution at depth _d_ names the author of the depth-_d+1_ block that follows. Nested attributions live inside the quote — a `…wrote:` at depth 1 names the depth-2 author. Build the author stack by walking attributions in document order, pushing on depth increase. Localised generated forms: `^(Am|Le|El|Il|On|W dniu)\b.{0,120}\b(schrieb|a écrit|escribió|ha scritto|wrote|napisał)\s*[:：]\s*$`, plus `------------------ 原始邮件 ------------------` and `在 2026年8月25日 … 写道：`.

**Silent failure:** Assigning the attribution to the block it is textually adjacent to at the SAME depth shifts every author in the thread by one turn — a complete, plausible, fully-consistent transcript in which every statement belongs to the previous speaker.

### 1.5 HTML quote containers

**Looks like:** Gmail `<div class="gmail_quote gmail_quote_container"><div dir="ltr" class="gmail_attr">On … wrote:</div><blockquote class="gmail_quote" style="…border-left:1px solid rgb(204,204,204)…">`; Apple Mail/Thunderbird bare `<blockquote type="cite">` nesting; OWA/new Outlook `<div id="divRplyFwdMsg" dir="ltr">` preceded by `<hr style="display:inline-block;width:98%">` and `<div id="appendonsend"></div>`; Roundcube/Zimbra `<blockquote type="cite" style="padding-left:5px; border-left:#1010ff 2px solid; margin-left:5px">`.

**Detect:** Depth = `blockquote[type="cite"]` nesting count, or `class~=gmail_quote` nesting, or position relative to `id="divRplyFwdMsg"`. A Gmail inline reply is structurally a `<div>` that is a direct child of the blockquote sitting between two quoted `<div>`s, carrying no class, no style and no colour. `id="appendonsend"` is an empty div whose POSITION marks where composition ends.

**Silent failure:** Whitespace-collapsing or empty-element-dropping pre-passes delete `appendonsend` and destroy the only clean split point in an OWA message. Treating a coloured `border-left` as authorship inverts attribution wholesale (see 4.4).

### 1.6 Parent-body diff — the only sound discriminator

**Looks like:** Nothing at all: plain sentences typed between quoted paragraphs, inside `<blockquote>` or after `>`, with no prefix, no colour, no initials. This is the majority convention, because it is what happens when a user clicks inside the quote and types.

**Detect:** Resolve `In-Reply-To`/`References` → parent body. Normalise both sides (unstuff flowed, strip quote prefixes, NFKC, collapse whitespace). For each line or sentence inside the quote region, test membership in the parent's normalised line set with fuzzy match ≥0.90 to tolerate rewrap. Non-members inside the quote region are insertions by the current author; anything present in the parent is quoted regardless of what markers it carries.

**Silent failure:** Without the parent, everything inside the blockquote is attributed to the original sender: the recipient's answers vanish and the parser emits a clean, plausible reconstruction of a message nobody sent. This is the highest-frequency silent wrong answer in the entire problem and it never raises an exception.

### 1.7 Depth and markers accrete across rounds

**Looks like:** Round 1's `>>PT …` appears as `>>>PT …` in round 2 and `>>>>PT …` in round 3; `[PT]` becomes `> [PT]` then `> > [PT]`. A single message may contain six `[PT]` occurrences — two from this round at depth 0–1, four quoted from earlier rounds at greater depth.

**Detect:** Never key on a literal depth. Split first — `m = re.match(r'^(?P<d>(?:[>＞][ \t]?)*)(?P<rest>.*)$', line)` — count depth from `m['d']`, run every marker regex against `m['rest']` only. Map depth → round using the length of the `References` chain. Attribute a marker occurrence to the CURRENT author only when its depth equals the message's minimum depth, or when the surrounding text is absent from the parent body.

**Silent failure:** A rule written from one observed sample (`^>>>PT`) matches the newest round only; every earlier insertion by the same person is silently re-attributed to the original sender, and the output looks complete because the newest answers ARE present and correct. A global `findall` does the reverse — all six `[PT]` hits go to the latest sender, inflating one party and deleting the other's earlier answers. Error rate grows monotonically with thread length.

### 1.8 Indentation-only insertion

**Looks like:** Two or more leading spaces or a tab on the answer line; in HTML, `<div style="margin-left:40px">` or a bare `<blockquote>` (no `type="cite"`, no `border-left`) wrapping the REPLY rather than the quote.

**Detect:** Plaintext `^(?P<indent>[ \t]{2,})(?=\S)` constrained by the parent diff — the corresponding parent line must NOT be indented. HTML: blockquote lacking both `type="cite"` and a `border-left` declaration, or `div[style*="margin-left"]` nested at a depth inconsistent with the surrounding cite chain.

**Silent failure:** Indentation is also how code blocks, ASCII tables and wrapped list continuations are represented, so a pasted code block flips into "the recipient's inline answer". Symmetrically, WYSIWYG editors use `<blockquote>` purely for visual indent, making brand-new text look quoted — attribution inverted, output well-formed.

### 1.9 Outlook plaintext has no quote marks at all

**Looks like:** The `text/plain` alternative of an Outlook reply places the replier's text and the quoted history at the SAME left margin, separated only by `-----Original Message-----` or a `From:/Sent:/To:/Subject:` block. No `>`, no colour, no bold, no indentation.

**Detect:** Survivors are only (a) the `[Name]` comment prefix, (b) `>` depth in clients that use it, (c) `/^-{2,}\s*Original Message\s*-{2,}/` or `/^(From|Sent|To|Cc|Subject):\s/m`, (d) `/^On .{0,200}wrote:\s*$/m`. For Outlook plaintext with no `[Name]` marker, inline replies are NOT RECOVERABLE — return unknown.

**Silent failure:** The parser splits a flat blob at a confidently wrong place. This is the reason plaintext-only parsing collapses on enterprise threads.

## Layer 2 — HTML-only signals (colour, weight, highlight)

Colour is a SUBSET signal: it exists only in the HTML part, only for some clients, and only sometimes means authorship. Use it to disambiguate inside a quoted region already located by Layer 1 — never as the primary segmentation.

### 2.1 Baseline test: does a colour convention exist at all?

**Detect:** Before any colour rule, compute distinct RESOLVED `(colour, background, weight, style)` tuples weighted by VISIBLE CHARACTER COUNT. Declare a marker convention present only if some non-default tuple covers roughly 0.5%–60% of visible characters AND occurs at ≥1 position inside a quoted region. Below the floor it is noise (a link, a banner); above the ceiling it is the body font.

**Silent failure:** Without this gate every message "has colour" — links, disclaimers, `color:windowtext` resets, `elementToProof`'s `rgb(0,0,0)` — so the parser always returns some segmentation and never returns "unknown". For a plain Gmail thread the correct output is "no colour convention detected; fall back to structural quote-depth parsing". Emitting a confident split where no convention exists is the dominant failure mode of this entire category, and it is invisible downstream because the output is well-formed.

### 2.2 Inline `style="color:…"` span — the modern default marker

**Looks like:** `<span style="color:#1F497D">`, `<span style="color:rgb(226,80,65)">`, Word's single-quoted `<span style='font-size:11.0pt;font-family:"Calibri",sans-serif;color:#1F497D'>`.

**Detect:** `/style\s*=\s*(["'])(?:(?!\1).)*?(?<![-\w])color\s*:\s*([^;"']+)/i`. The `(?<![-\w])` guard is not optional, and single-quoted style attributes must be accepted (Word always emits them).

**Silent failure:** Without the negative lookbehind, `background-color`, `border-color`, `border-left-color`, `outline-color` and `-webkit-text-fill-color` all match — every grey Gmail quote bar and every yellow highlight registers as a coloured reply. Second: Word emits `color:windowtext` and `color:black` as explicit resets, so "has a colour declaration ⇒ marked" flags 100% of a Word-origin message including the sender's own text. Used by Outlook 2007+, OWA, Gmail web picker, Apple Mail, Thunderbird 78+, Zimbra, Roundcube/TinyMCE, Superhuman, Front, Missive.

### 2.3 Legacy `<font color>` wrapper

**Looks like:** `<font color="#0000FF" face="Calibri" size="2">my answer</font>`, or unquoted `<font color=blue>`. Notes emits `<font size=2 color=#0000FF face="sans-serif">` as house style.

**Detect:** `/<font\b[^>]*\bcolor\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s">]+))/i` — the third alternation is mandatory, pre-HTML5 emitters write `color=blue` unquoted. Scope ends at `</font>`, which is frequently absent; cap the scope at the enclosing block element.

**Silent failure:** Quoted-value-only regexes miss `color=blue` and attribute the replier's text to the sender. Separately, Notes and Outlook Express routinely leave `<font>` unclosed, so a parser assuming balanced tags lets the colour scope run to end-of-document and reports the entire quoted history as the recipient's inline reply — a fluent, wholly inverted answer. Still common in HCL/IBM Notes, Outlook Express, Outlook 2003 RTF→HTML, GroupWise, old Thunderbird.

### 2.4 Class-based colour with an embedded stylesheet

**Looks like:** `<style><!-- span.EmailStyle21 {font-family:"Calibri",sans-serif; color:#1F497D;} p.MsoNormal {color:windowtext} --></style>` … `<span class="EmailStyle21">my answer</span>`.

**Detect:** Element-local regex cannot work. Parse `<style>` bodies INCLUDING the HTML-comment wrapper `<!-- … -->` Word always emits, build a selector→declaration map, resolve colour per node from class + tag + inheritance. Match `/span\.EmailStyle\d+/` — Word renumbers the class per message (17, 18, 21…), so a literal name never generalises.

**Silent failure:** A `style=`-only scanner sees `<span class="EmailStyle21">` with no inline colour, concludes "unmarked", and hands the replier's answers back as the sender's words — no exception, no low-confidence flag. Two compounding failures: stripping HTML comments as a sanitising pre-pass deletes the entire stylesheet, converting a coloured message into an uncoloured one before any rule runs; and Gmail rewrites received class names to `m_-8452901234567890123EmailStyle21` and may drop the `<style>`, so the class survives while its definition does not.

### 2.5 Nested spans and the inner reset

**Looks like:** `<span style='color:#1F497D'>Thanks — <span style='color:windowtext'>see attached</span> for the numbers.</span>`; Word nests three to five deep routinely.

**Detect:** Resolve colour by walking the ancestor chain upward from each text node; the NEAREST ancestor bearing a colour declaration wins, and `windowtext`/`black`/`#000000` mean "author colour ended here". Never take the outermost span; never take the first regex match in document order.

**Silent failure:** "First colour wins" over-attributes the reset region to the replier; "innermost element wins" under-attributes when the innermost span sets only `font-size`. Either way the authorship boundary lands mid-sentence and the output is one grammatical sentence assembled from two people's words — which reads as fluent prose and passes human review.

### 2.6 Outlook Personal Stationery colours the WHOLE reply, not the insertion

**Looks like:** Every run the sender typed — greeting, inline answers, sign-off, signature — in one identical non-black colour, while the quoted history carries `color:windowtext`, `#000000`, or nothing.

**Detect:** Do not treat colour as an "insertion marker". Build a histogram of resolved colour → visible character count, take the dominant non-default colour as `author_colour`, and attribute EVERY run of that colour to the replier whether or not it sits inside a blockquote. Corroborate with `X-Mailer: Microsoft Outlook 16.0`.

**Silent failure:** Parsers that assume "coloured text inside the quote = inline reply, coloured text at the top = ordinary body" double-classify the same colour under two rules and emit contradictory attributions in one message. Worse, the companion setting _Pick a new color when replying or forwarding_ rotates the colour per correspondent, so a hard-coded blue/`#1F497D` test passes on the sample thread and fails on the same user's next one. Source: File → Options → Mail → Stationery and Fonts → Personal Stationery. Absent from OWA, new Outlook, and mobile.

### 2.7 Highlight: `background`, `background-color`, `bgcolor`, `<mark>`

**Looks like:** Gmail `<span style="background-color:rgb(255,255,0)">`; Word/Outlook `<span style='background:yellow;mso-highlight:yellow'>`; Apple Mail `<span style="background-color: rgb(255, 255, 0);">`; `<td bgcolor="#FFFF00">` or a two-column "question | response" table; `<mark>agreed</mark>`, `<mark style="background-color:#fff2cc">`.

**Detect:** `/(?:^|;)\s*background(?:-color)?\s*:\s*([^;"']+)/i` — the shorthand alternation is essential. `/mso-highlight\s*:/i` corroborates Word/Outlook. `/<(?:table|tr|td|th|body)\b[^>]*\bbgcolor\s*=\s*(["']?)(#?[0-9a-fA-F]{3,6}|[a-zA-Z]+)\1/`. `/<mark\b[^>]*>/i` is unambiguous when present. Exclude `transparent`, `none`, `white`, `#FFF`, `#FFFFFF`, `rgb(255,255,255)`.

**Silent failure:** Matching only `background-color` misses every Word and Outlook highlight — the commonest enterprise highlight path emits the `background` shorthand — so the parser reports "no marking found" on a message the user is looking at in bright yellow. Mirror failure: counting Word's `background:white` resets (emitted on nearly every `MsoNormal` paragraph) marks the entire quoted block as a reply. For `bgcolor`, signature blocks, newsletter fragments and gateway banner tables in the quoted history fire the rule constantly; the inverse miss is worse — answers pasted into a coloured table cell produce zero span-level markers, so every span rule reports "unmarked" on a visibly colour-coded message. `<mark>` is vanishingly rare in real mail (ProseMirror/TipTap/Quill clients only — Superhuman, Front, Missive, Zoho, HubSpot, some TinyMCE 6 Roundcube builds; never Gmail, Outlook desktop or Apple Mail), so a catalogue that leads with it passes its own fixtures and finds nothing in production — and Outlook's sanitizer drops it, so the same sentence parses correctly in round 1 and wrongly in round 2 with no error at either step.

### 2.8 Bold / italic / underline as the marker

**Looks like:** `<b>`, `<strong>`, `<i>`, `<em>`, `<u>`, `style="font-weight:bold"`, `font-weight:700`, Word's `<b><span style='…'>`. Plaintext analogues: `*asterisks*`, `_underscores_`.

**Detect:** `/<(b|strong|i|em|u)\b/i` OR `/font-weight\s*:\s*(bold|[6-9]00)/i` OR `/font-style\s*:\s*italic/i`. Exclude structural bold: `<th>`, `<h1>`–`<h6>`, and Outlook's quote-header labels `<b>From:</b> <b>Sent:</b> <b>To:</b> <b>Subject:</b>`.

**Silent failure:** Outlook bolds `From:/Sent:/To:/Subject:` in EVERY forward's `-----Original Message-----` block, so "bold inside a quoted region = inline reply" fires on every Outlook forward in existence and returns the sender's routing header as the recipient's answer. Underline fails twice: every `<a href>` is underlined by default and Word emits `text-decoration:underline` explicitly on links, so "underlined = marked" returns every URL in the quoted history as a reply. Bold is nonetheless the universal fallback — it is the ONLY rich-text control on Outlook mobile, Gmail mobile and Apple Mail iOS, so mobile repliers bold where desktop users colour.

### 2.9 Colour that means something other than "this is my reply"

**Looks like:** Link palettes `#0563C1` (Word), `#1155cc` (Gmail), `#0000EE` (UA default), `#954F72` (Word visited); red confidentiality footers `<span style="color:#FF0000">CONFIDENTIAL</span>`; orange `[EXTERNAL SENDER]` gateway banners; multi-coloured corporate signature blocks.

**Detect:** Exclude any run whose ancestor chain contains `<a>` or whose colour matches a known link palette. Exclude runs inside banner containers — match id/class against `/external|banner|warning|caution|mimecast|proofpoint|barracuda/i` and the wrapper `<table … style="background:#FFEB9C">`. Exclude trailing disclaimer regions by keyword.

**Silent failure:** The single largest false-positive source in the category. Every hyperlink in the quoted history is a coloured run, so an unguarded "coloured text = inline reply" parser returns the sender's own URLs, their signature's coloured job title, and the legal disclaimer as the recipient's inline answers — long, confident, entirely fabricated, no error condition anywhere. Present in most enterprise mail regardless of composing client (Mimecast, Proofpoint, Defender, Barracuda, Exclaimer, CodeTwo, Word link styling).

### 2.10 Colour collision — two authors, same colour, different rounds

**Looks like:** Round 1: A answers in `#0000FF`. Round 2: B answers in `#0000FF`, and A's blue is now quoted one level deeper.

**Detect:** Colour alone is insufficient. Key authorship on the tuple `(normalised colour, blockquote/quote depth, position relative to the nearest attribution header)` — `gmail_attr` / `divRplyFwdMsg` / `-----Original Message-----` / `^On .{0,200}wrote:`. Depth disambiguates: B's blue sits at depth 0, A's identical blue at depth ≥1.

**Silent failure:** Merging on colour alone fuses A and B into one speaker and emits a single coherent block of interleaved statements from two people — the most dangerous output here, because it is grammatical, on-topic, and impossible to spot without the source. Outlook's _Pick a new color_ exists to prevent this and is OFF by default, so the collision is the common case whenever both parties run Outlook defaults.

### 2.11 Dark-mode colour rewriting

**Looks like:** `<meta name="color-scheme" content="light dark">`, `<style>@media (prefers-color-scheme:dark){ .x{color:#fff !important} }</style>`, Outlook's rewriter output `[data-ogsc]` / `[data-ogsb]`.

**Detect:** `/@media[^{]*prefers-color-scheme/i`, `/\[data-ogs[cb]\]/`, `/color-scheme\s*:/i`, `/<meta[^>]+name=["']color-scheme/i`. Treat the light-mode declaration as canonical; ignore the dark override.

**Silent failure:** Outlook.com and Outlook mobile rewrite inline colours at render time, and some clients persist the rewritten values into the quote carried by the NEXT reply. `#1F497D` returns as a lightened `#8AB6E8`, so cross-round matching of one author's colour fails and their contributions split across two invented participants — while the `!important` dark rule simultaneously makes an unmarked run look marked.

## Layer 3 — Typed text markers (weakest; require corroboration)

Every rule here MUST validate the captured label against thread participants (`From`/`To`/`Cc` display names and their initials) and must run against `m['rest']` after the quote prefix has been split off (1.7). A typed marker alone is never sufficient evidence.

### 3.1 Bracketed name or initials — `[PT]`, `[Ricky Chan]`, `【PT】`

**Looks like:** `<span style='color:#1F497D'>[RC] </span>Yes, 4×/day is the product limit.` in HTML and `[Ricky Chan] Yes, 4×/day is the product limit.` in the text/plain part. Also `[P.T.]`, `[Ricky – confirmed]`, mid-line `...by Friday [PT: no, Monday]`, CJK `【PT】`.

**Detect:** HTML `/^\s*(?:<[^>]+>\s*)*\[([^\]\n]{1,40})\]\s*/` at run start; plaintext `/^\[([^\]\n]{1,40})\]\s/` at line start inside the quoted region; general form `(?<![A-Za-z0-9])[\[［【]\s*(?P<who>[A-Z][A-Za-z.]{0,11}|[A-Z]{2,4})\s*(?P<sep>[:：\-–—]?)\s*(?P<body>[^\]］】]{0,300})[\]］】]`. Accept ONLY when `who` matches a participant's initials or first name.

**Silent failure:** This is the one colour-adjacent marker that survives HTML→text conversion, so a colour-only catalogue discards the single signal still present in the plaintext part. In the other direction, a lazy `/^\[.*\]/` collides with Gmail's `[image: inline-image.png]`, `[cid:image001.png@01DC1234.5678ABCD]`, gateway `[EXTERNAL]`/`[SPAM?]` banners, `[PATCH v2]`, `[REDACTED]`, `[Quoted text hidden]` and footnote `[1]` — each becomes a phantom author named "image" or "EXTERNAL", and the message gets split at a security banner. Source: Outlook for Windows only, Personal Stationery → "Mark my comments with:". Not in OWA, new Outlook, or mobile.

### 3.2 Initials-colon prefix — `JS:`, `Alex —`, `陳：`

**Detect:** `^\s*(?:[>＞]+\s*)?(?P<who>[A-Z][A-Za-z]{0,11}|[A-Z]{1,4})[\s ]*(?P<sep>[:：]|\s[-–—])\s+(?=\S)`. Require `who` ∈ participants AND `who` ∉ stoplist `{From,To,Cc,Bcc,Sent,Date,Subject,Re,RE,AW,Fw,Fwd,PS,NB,FYI,Q,A,Note,Tel,Fax,Mobile,Cell,Web,Email,T,M,E,W}`.

**Silent failure:** Matches the header block of an embedded forward, so a forwarded header is reported as an inline reply and the whole forwarded message is attributed to the replier. Also matches vCard-style signature lines — `T: 555-0142` / `M: …` / `E: a.rivera@example.com` — turning one signature block into four inline replies by four different "people".

### 3.3 Name-before-angle — `PT>`, `TL>>`

**Detect:** `^\s*(?P<who>[A-Za-z]{1,5})(?P<depth>>{1,6})\s?`. Require `who` ∈ participants, and require either ≥2 consecutive matching lines or that the remainder matches parent-body text.

**Silent failure:** Inverted attribution, the worst class: `^>+` depth logic finds no leading `>`, so the SENDER's quoted words are classified as new text by the REPLIER, fully confidently, with no anomaly to flag. The over-correction (stripping `^\w*>`) mangles code (`if (a>b)`), math (`n>0`), and inline addresses (`Terry <t@x.com> wrote`). Usenet, Notes veterans, German and Japanese list culture.

### 3.4 Depth run fused with initials — `>>>PT`

**Looks like:** `>>>PT Yes, the invoice went out Friday.` — a run of `>` immediately followed by 1–4 letters with no space, inside an otherwise normally-quoted block.

**Detect:** `^(?P<depth>[>＞]{1,10})\s?(?P<tag>[A-Z]{1,4}|[A-Z][a-z]{1,3})(?=[\s:>\-–—]|$)` then REQUIRE two confirmations: `tag` ∈ initials derived from `From`/`To`/`Cc` display names, and the line with depth stripped is NOT present in the parent body.

**Silent failure:** A naive counter reads `>>>PT …` as depth-3 quoted text and attributes the replier's own answer to whoever wrote at depth 3 — complete-looking and confidently inverted. Mirror failure: over-eager stripping of `^>+\s*[A-Z]{1,4}` silently eats the first word of genuine deep quotes (`>>> ACME will invoice` loses `ACME`).

### 3.5 Parenthetical or trailing signature — `(PT: …)`, `-PT`, `~rc`

**Detect:** Opener `[\(\[]\s*(?P<who>[A-Z][A-Za-z.]{0,11})\s*[:：\-–—]\s*(?P<body>[^)\]]{1,300})[\)\]]`. Trailer `(?:^|\s)[-–—~/]{1,2}\s*(?P<who>[A-Z]{1,4}|[A-Z][a-z]{1,11})\s*$`. Both require `who` ∈ participants.

**Silent failure:** The trailer matches the RFC 3676 `--` signature delimiter, ordinary em-dash prose ("— finally"), and negative units (`-40C`). The opener matches citations (`Smith: 2003`), aspect ratios (`16:9`), times (`9:00`) and Windows paths (`C:\…`). A false boundary lands mid-sentence and one paragraph is split across two authors, each half fully plausible. Note: for shared ROLE mailboxes (a shared `frontdesk@`-style treatment-coordinator account) the trailing initials are the ONLY author signal in the message.

### 3.6 Fences and labelled rules — `@@@`, `***`, `--- my reply ---`

**Detect:** Bare fence `^\s*(?:>+\s*)?(?P<c>[@#*%+~/!^=_-])(?P=c){1,}\s*(?P<label>[^\n]{0,60}?)\s*(?:(?P=c){2,})?\s*$` — trust only when the run occurs ≥2× (open/close pair) or `label` matches a reply-word list. Labelled rule `^\s*(?:>+\s*)?[-=~_*<>#]{2,}\s*(?P<label>[^\n]{1,60}?)\s*[-=~_*<>#]{2,}\s*$` with `(?i)\b(reply|replies|answer|answers|response|comment|note|mine|below|回复|回覆|答复|回答|返信|답변|antwort|réponse|respuesta)\b` applied to `label`. Run the Layer 4 stoplist FIRST.

**Silent failure:** Shape-identical to markdown headings (`###`), thematic breaks (`***`, `---`, `___`), setext underlines (`====`), diff hunks (`@@ -1,7 +1,6 @@`), and — fatally — the RFC 3676 signature delimiter `--` (dash dash SPACE). Treating the signature delimiter as a fence truncates the body there, dropping every inline answer below it while returning a well-formed result. Symmetrically, lumping all rule-shaped lines into "quote starts here" attributes everything below the user's own `--- my reply ---` to the sender — the entire reply is dropped and the output still validates.

### 3.7 Wraps — `<<< … >>>`, `<PT>…</PT>`, `<reply>`

**Detect:** Plaintext `<{2,}\s*(?P<body>.+?)\s*>{2,}` (DOTALL, cap ~500 chars); HTML entity-decode first (0.5), then apply to text nodes only. Pseudo-tags MUST run against RAW HTML source, never `innerText`: `<\s*/?\s*(?P<tag>[A-Za-z][\w.-]{0,20})\s*>` with `tag` ∉ known HTML elements AND (`tag` ∈ participant initials OR `tag` ∈ `{reply,answer,me,mine,comment,note,ans}`).

**Silent failure:** Sanitizers and `innerText` extraction drop unknown elements entirely — the marker evaporates and the inserted sentence is glued to the quoted sentences around it, producing a grammatical, plausible, WRONG sentence attributed to the sender. Some clients escape to `&lt;PT&gt;` in one MIME part and drop it in the other, so the parts disagree about how many replies exist. Chevron wraps collide with git conflict markers (`<<<<<<< HEAD`), Python REPL prompts (`>>>`), shell here-strings (`<<<`), and mail-merge placeholders (`<<FirstName>>`).

### 3.8 ALL-CAPS insertion

**Detect:** `cased = [c for c in line if c.isalpha()]`; flag when `len(cased) >= 12` and `sum(c.isupper() for c in cased)/len(cased) >= 0.90` and `len(line.split()) >= 3` and `re.search(r'[A-Za-z]{4,}', line)`. The `len(cased) > 0` guard is mandatory.

**Silent failure:** `line == line.upper()` is True for any line with NO cased characters — pure CJK, digits, punctuation, emoji, URLs — so an entire Chinese or Japanese quoted block is flagged as the recipient's insertion. Also fires on `CONFIDENTIALITY NOTICE` footers, `CAUTION: EXTERNAL SENDER` banners, acronym-dense lines (`RE: PIPA/HPA MSA SOW`) and `-----ORIGINAL MESSAGE-----`. Genuine sender emphasis in caps gets re-attributed to the replier.

### 3.9 Arrows, dingbats, emoji at line start

**Detect:** `^\s*(?:[>＞]+\s*)?(?P<m>=>|->|⇒|→|»|›|▶|►|➤|✔|✅|◆|■|●|※)\s+(?=\S)`, or for emoji a grapheme-aware match handling ZWJ sequences and U+FE0F. Require the SAME glyph ≥2× in the message AND that it does not also occur in the parent body.

**Silent failure:** `»` and `›` are genuine quotation marks in German, French, Russian and Danish — treating a `»`-prefixed line in a German thread as an answer inverts attribution. `->` and `=>` appear in pasted code, stack traces, logs and migration prose ("Hamachi -> SharePoint"). Depth counters scanning for `>` unanchored miscount the `>` inside `=>`. Emoji are decorative — they appear in signatures (📱, ✉️), quoted marketing, and the sender's own bullets — so a single occurrence yields a false boundary; naive per-codepoint regexes split one grapheme into two "markers" and double the reported insertion count.

### 3.10 CJK labelled answers — `回复：`, `答：`, `【回答】`, `답변:`

**Detect:** `^\s*(?:[>＞]+\s*)?(?:[【\[（(]\s*)?(?P<lbl>我的回复|回复|回覆|答复|答覆|回答|批注|返信|追記|회신|답변|답|答)\s*(?:[】\]）)]\s*)?[:：]?\s*` — anchored at line start ONLY, never searched unanchored.

**Silent failure:** CJK has no word boundaries, so `\b` anchors are useless and an unanchored search fires mid-sentence: `答` / `注` / `答复` occur constantly in ordinary quoted prose (`请答复此邮件`, `备注`), splitting a quoted paragraph in half and attributing the tail to the replier. Chinese webmail attribution furniture also ends in `：` — `在 2026年8月25日 … 写道：`, `------------------ 原始邮件 ------------------`, `发件人:/发送时间:/收件人:/主题:` — and matches loose label patterns. Sources: NetEase 163/126, QQ Mail, Foxmail, localised Outlook zh-CN/ja-JP/ko-KR.

### 3.11 Locale-spaced European labels — `Réponse :`, `AW:`

**Detect:** `^\s*(?:>+\s*)?(?P<lbl>R[ée]ponse|Antwort|AW|Respuesta|Risposta|Resposta|Antwoord|Svar|Odpowied[źz])[\s  ]*[:：]\s*` — the character class must contain U+00A0 and U+202F literally.

**Silent failure:** A colon regex with no NBSP allowance misses every French marker, because the separator is U+00A0 or U+202F — invisible in the source and not matched by a literal space or by `\s` in some regex flavours. `AW:` is also the German subject prefix for `RE:`, so it matches quoted subject lines inside forwards. `«»` are real quotation marks in FR/DE/RU, so treating them as insertion delimiters inverts authorship for ordinary quoted speech.

### 3.12 Convention-declaring preamble — "my answers below in red"

**Detect:** Search ONLY the top-of-body region, before the first attribution or quote line: `(?i)\b(answers?|replies|responses?|comments?)\b.{0,40}\b(below|inline|interspersed|in\s+(red|blue|green|bold|italics|caps|capitals|brackets))\b`, plus `(?i)\b(see|reply|respond(ed)?)\s+inline\b` and `回复见|答复如下|见下方|红色|蓝色`. Use the hit to SELECT which detector to trust — never as a boundary.

**Silent failure:** Two-sided. Treating the matched sentence as a marker cuts the message at the preamble and discards the real content. Ignoring it is worse and far more common: without reading it the parser has no reason to prefer the HTML part (where the red exists) over text/plain (where it does not), and returns a clean, confident "no inline replies" for a message that is 90% inline replies. Effectively standard in vendor, MSP and procurement questionnaire threads.

### 3.13 Hand-typed attribution — "Alex wrote:"

**Detect:** `^\s*(?:>+\s*)?(?P<who>[A-Z][\w.'-]{1,20}(?:\s+[A-Z][\w.'-]{1,20}){0,2})\s+(wrote|writes|said|says|asked|noted|schrieb|a écrit|escribió|写道)\s*[:：]\s*$`. Cross-check `who` against participants AND verify whether the following lines actually match the parent body (a real quote) or not (a label only).

**Silent failure:** Parsers treat "X wrote:" as the canonical quote start and cut there. When a user types it as a heading for their OWN summary, everything after — including all their answers — is discarded as quoted text. The reverse trips on ordinary prose: "Simon wrote the script:" triggers a mid-paragraph cut. Gmail and Thunderbird generate the identical string, so no lexical test distinguishes typed from generated — only the parent-body match does.

## Layer 4 — Client artifacts that masquerade as signals

Run this stoplist BEFORE any Layer 3 rule. These are generated, not typed, but shape-identical to hand-typed markers — which is exactly why they poison a naive catalogue.

| Artifact                             | Raw form                                                                                                                                                                                                                                                             | Rule                                                                                                                                                                          | Silent failure                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Separators                           | `-----Original Message-----`, `---------- Forwarded message ---------`, `------------------ 原始邮件 ------------------`, `Ursprüngliche Nachricht`, `Message d'origine`, `________________________________` (Outlook `<hr>` flattened)                              | `^\s*-{4,}\s*(Original Message\|Forwarded message\|Ursprüngliche Nachricht\|Message d'origine\|原始邮件\|原始郵件\|転送されたメッセージ)\s*-*\s*$` · `^_{10,}\s*$`            | Classed as a user marker → boilerplate reported as somebody's inline reply. Classed as "quote starts here" when the user BOTTOM-POSTED below it → every answer dropped                                                                                                                                                                                                                                                                                    |
| Signature delimiter                  | `--` (dash dash SPACE)                                                                                                                                                                                                                                               | `^--[ \t]?$` — treat as body/signature boundary, never a fence                                                                                                                | A single trailing space decides whether the next forty lines are body or signature, and many MTAs strip trailing whitespace in transit, so the same message parses differently depending on which hop captured it                                                                                                                                                                                                                                         |
| Elision / footer                     | `[Quoted text hidden]`, `Sent from my iPhone`, `Get Outlook for iOS`                                                                                                                                                                                                 | `^\[Quoted text hidden\]$` · `^(Sent\|Get) from my \w+`                                                                                                                       | Counted as depth-0 content inside a quote, it becomes a phantom inline reply and anchors a bogus segment boundary                                                                                                                                                                                                                                                                                                                                         |
| Outlook forward header labels        | `<b>From:</b> <b>Sent:</b> <b>To:</b> <b>Subject:</b>`                                                                                                                                                                                                               | Exclude from every bold rule (2.8) and from the initials-colon rule (3.2)                                                                                                     | "Bold inside a quote = reply" returns the sender's routing header as the recipient's answer, on every Outlook forward in existence                                                                                                                                                                                                                                                                                                                        |
| Gmail grey quote bar                 | `border-left:1px solid rgb(204,204,204)` on `blockquote.gmail_quote`                                                                                                                                                                                                 | Structural marker only; `#ccc` is byte-identical for every author on every message                                                                                            | Colour can never disambiguate participants in Gmail. "Absence of colour ⇒ not a reply" silently drops the overwhelming majority of Gmail inline replies (plain black text typed inside the blockquote) and reports a clean parse                                                                                                                                                                                                                          |
| Roundcube/Zimbra blue bar            | `border-left:#1010ff 2px solid` — colour written FIRST in the shorthand                                                                                                                                                                                              | `/border-left\s*:\s*[^;"']*(#[0-9a-f]{3,6}\|rgb\(\|\b(?:blue\|navy\|red\|green\|gray\|grey)\b)/i`; the CSS shorthand is order-independent, so `/\d+px\s+solid\s+#/` misses it | The bar marks quote DEPTH, not authorship — it is drawn around the text being answered. "Coloured construct ⇒ replier" inverts attribution wholesale. Saturated blue looks far more deliberate than Gmail's `#ccc`, which is why it gets misread                                                                                                                                                                                                          |
| OWA `elementToProof`                 | `<div class="elementToProof" style="font-family:Aptos,…;color:rgb(0,0,0)">`                                                                                                                                                                                          | `/class="[^"]*\belementToProof\b/` marks composed runs; `id="appendonsend"` marks the insertion point; `id="divRplyFwdMsg"` the quoted header                                 | It is a SPELLCHECK wrapper carrying an explicit black; "has explicit colour ⇒ marked" flags every paragraph the OWA user typed, signature included. Dropping empty elements deletes `appendonsend`, the only clean split point                                                                                                                                                                                                                            |
| Word resets                          | `p.MsoNormal {color:windowtext}`, `background:white`, `<o:p></o:p>`                                                                                                                                                                                                  | Classify `windowtext`/`black`/`#000000`/`white` as "no colour"; merge runs across empty `<o:p>`                                                                               | "Has a colour declaration ⇒ marked" flags 100% of a Word-origin message; `background:white` marks the entire quoted block as a reply; `<o:p>` splits one reply into four fragments                                                                                                                                                                                                                                                                        |
| Gateway banners & signature managers | `[EXTERNAL]`, `[SPAM?]`, `CAUTION: EXTERNAL SENDER`, `<table style="background:#FFEB9C">`, Exclaimer/CodeTwo coloured signature blocks                                                                                                                               | Exclude by id/class `/external\|banner\|warning\|caution\|mimecast\|proofpoint\|barracuda/i` and by keyword region                                                            | The message is split at a security banner and the banner is reported as the recipient's inline reply, with "EXTERNAL" as the author name                                                                                                                                                                                                                                                                                                                  |
| Gmail placeholders                   | `[image: inline-image.png]`, `[cid:image001.png@01DC1234.5678ABCD]`                                                                                                                                                                                                  | Exclude before the bracket rule (3.1)                                                                                                                                         | Phantom authors named "image" and "cid"                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Reader-side quote colours            | NOTHING in the transmitted bytes — Apple Mail and Thunderbird apply blue/green/red/purple level colours from their own stylesheets at render time (`mail.citation_color`, `mail.quoted_style`, `userContent.css` `blockquote[type=cite] { color: navy !important }`) | Count `blockquote[type="cite"]` nesting depth; never look for colour here                                                                                                     | The most seductive false report in the problem: the user shows a screenshot with four distinct colours and says "the colours show who said what", but the source has zero colour declarations. A parser specified from that screenshot hunts for colours that were never transmitted and returns "no inline replies found" on a message that visibly contains several. (Thunderbird's Display-options colour setting applies to PLAIN TEXT messages only) |
| Dark-mode rewrites                   | `[data-ogsc]`, `[data-ogsb]`, `@media (prefers-color-scheme:dark)`                                                                                                                                                                                                   | See 2.11 — light-mode declaration is canonical                                                                                                                                | One author's colour splits across two invented participants across rounds                                                                                                                                                                                                                                                                                                                                                                                 |
| Mobile: no marker by construction    | Gmail Android/iOS `<div dir="ltr">` unstyled; Apple Mail iOS `<div dir="auto">`; Outlook mobile `<div id="divRplyFwdMsg" dir="ltr">` + `<hr>`; Samsung `<div>` + `<br>`                                                                                              | Detect the composing client (0.8) and lower the colour prior accordingly                                                                                                      | A catalogue tuned on desktop Outlook reports "no inline reply" for every mobile-authored message. Since mobile is exactly where short one-line inline answers get typed, the miss is systematic and DIRECTION-BIASED: the parser under-reports the recipient's contributions specifically, and reports the run as clean                                                                                                                                   |

## Ordering — which signal to trust first

1. **Layer 0 first, unconditionally.** Every other rule's failure mode reduces to "Layer 0 did not run". A depth counter on undecoded quoted-printable, or a `^`-anchored marker on un-joined `format=flowed`, is not a weak signal — it is a random one.
2. **Parent-body diff (1.6) is the ground truth whenever `In-Reply-To`/`References` resolves.** It is the only rule that is independent of the composing client, survives every round-trip, and correctly handles the null convention (unmarked typed text), which is the most common case in the wild. If you have the parent, everything below is corroboration.
3. **Quote structure (Layer 1) next, because it is COMPLETE.** Every quoted message has a structure — `>` depth, `blockquote` nesting, or an attribution block — and structure covers 100% of the message including the runs nobody marked. It is unreliable in exactly three known ways, all enumerable and all detectable: whitespace-stripped blank lines (1.2), Outlook plaintext with no `>` at all (1.9), and depth accretion across rounds (1.7). Detect those three conditions explicitly and downgrade rather than guessing.
4. **Colour and highlight (Layer 2) third, and only as a DISAMBIGUATOR inside a region Layer 1 already located.** Colour is a strict subset signal: absent from `text/plain`, absent from most mobile clients, absent from Gmail's dominant plain-black-inside-the-blockquote pattern. Its real power is separating two authors inside one quoted region, where depth alone cannot — and even there, only as the tuple `(colour, depth, nearest attribution)` (2.10). Gate the entire layer behind the baseline test (2.1); if no convention exists, say so and fall back to structure.
5. **Typed markers (Layer 3) last, and never alone.** They are user habits, not protocol: they collide with markdown, code, signatures, banners and CJK prose, they accrete or vanish across rounds, and they survive into only one MIME part. Use a typed marker to CONFIRM a boundary that structure or colour already proposed, or to recover an insertion in the one case where nothing else survives (Outlook plaintext with `[Name]`, 1.9). A typed marker that contradicts the parent-body diff is wrong.
6. **The preamble (3.12) is a router, not a boundary.** Read it before anything else and let it select which layer to trust — "my answers below in red" says use Layer 2 on the HTML part, "answers in caps" says use 3.8, "see inline" says trust Layer 1 depth dips. It should never contribute a segment boundary of its own.
7. **Return `unknown` rather than a guess.** For Outlook `text/plain` with no `[Name]` marker and no resolvable parent, inline replies are genuinely unrecoverable. Every failure mode in this document produces well-formed, grammatical, on-topic output; "no error was raised" is not evidence of a correct parse.

## Red flags — stop and verify

- **The evidence is a screenshot.** Coloured quote levels in Apple Mail and Thunderbird are applied by the READER's stylesheet and appear nowhere in the bytes. Ask for the raw source before writing any rule.
- **The parser found exactly one author** in a thread whose `References` chain has three or more entries.
- **The parser found more authors than the `From`/`To`/`Cc` headers name.** Colour string aliasing (0.4) or a re-quoted marker (1.7) is manufacturing phantoms.
- **A reported "inline reply" is a URL, a phone number, a job title, `CONFIDENTIAL`, `[EXTERNAL]`, or `From:`/`Sent:`/`To:`/`Subject:`.** Layer 4 was not applied.
- **An attribution boundary lands mid-sentence,** or an output sentence is grammatical but stitched from two speakers. Symptom of nested-span resolution (2.5) or unjoined flowed lines (0.2).
- **The two MIME parts disagree** on the number of insertions. Do not silently prefer one.
- **A `<font>` or `<span>` colour scope runs to end-of-document.** Unclosed tag (2.3).
- **`text/plain` contains zero `>` characters.** Either Outlook (1.9 — likely unrecoverable) or undecoded quoted-printable (0.1 — fixable).
- **A `<style>` block exists but no element carries an inline colour.** Class-based colouring (2.4); an element-local regex will report "unmarked".
- **The result changed after a sanitising or whitespace-collapsing pre-pass.** That pass deleted Word's stylesheet, `appendonsend`, `<mark>`, or a pseudo-tag.
- **The dominant non-default colour covers >60% or <0.5% of visible characters.** That is the body font or noise, not a marker (2.1).
- **Every reported inline reply comes from the newest round and the earlier rounds look clean.** Classic 1.7 accretion loss — the older insertions were silently handed back to the original sender.
- **A rule was validated on one sample thread from one client.** Personal Stationery rotates colour per correspondent (2.6), Word renumbers `EmailStyle\d+` per message (2.4), and depth shifts by one per round (1.7). One sample proves nothing.
