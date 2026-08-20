#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["beautifulsoup4>=4.13"]
# ///
"""teachback — static gate for a generated explainer page.

    TB="$(cc-plugin-root doc-tools)/skills/teachback"
    uv run --no-project --script "$TB/verify_explainer.py" <page.html>
    uv run --no-project --script "$TB/verify_explainer.py" <page.html> --revision

Exits non-zero if any check fails.

Needs nothing preinstalled but uv. The PEP 723 inline metadata above makes this file self-contained,
so uv resolves the one dependency into an ephemeral environment: the gate carries its own runtime
rather than borrowing the toolchain of whatever project the page happens to live in. `--no-project`
is what makes that true anywhere — plain `uv run`, and even `uv run --script`, walk upward and adopt
the surrounding uv workspace, so the gate would inherit a project it knows nothing about.

Three design rules, each earned from Eon-Labs/alpha-forge#527 review feedback:

1. NEVER ASSERT A PER-ITEM CONTRACT WITH A DOCUMENT-WIDE COUNT. An aggregate check cannot see a
   per-item failure, and it fails in the FAVOURABLE direction: extras on one equation mask a total
   absence on another, and a question with two correct answers is cancelled out by one with none.
   Every contract below that says "every X" groups X and asserts on each group.

2. DO NOT CHECK A RENDERED PROPERTY WITH A TEXT MATCH. Layout invariants — "the shell fills the
   viewport", "body text is not width-capped", "every grid child is placed" — are properties of the
   RENDERED page, not of the source bytes. Matching CSS source text for them is unsound in principle
   (whitespace and declaration order are insignificant per CSS Syntax Level 3) and was unsound in
   practice: `.shell{display:grid` matched while the equivalent `.shell { display: grid; }` sailed
   past the very check meant to catch it. Those checks now live in verify_rendered.py, which reads
   getComputedStyle from a real browser. This file deliberately checks NOTHING about layout.

3. ASSERT THE ELEMENT, NOT THE STRING. A regex over whole-file text cannot tell markup from a
   comment: the old gate certified "MathJax 3 loaded" and "pinned CDN fallback" on a page whose only
   mention of either was inside `<!-- ... -->`, with no script element at all.

The hard-wrap invariant is the one exception to rule 3: it is checked against RAW SOURCE BYTES,
never the parse tree, because parsing normalises exactly the whitespace the invariant is about.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

from bs4 import BeautifulSoup, Tag

MAIN_OPEN = '<main id="main">'
MAIN_CLOSE = "</main>"
ANNOTATION_KEY = "teachback:annotations"

# The ONE remote resource this page may reference, pinned by exact URL and by exact bytes. An
# origin-level allowlist is not enough: any URL on the allowed origin can carry private page content
# in its query string, so <img src="https://cdn.jsdelivr.net/x?leak=..."> would have been admitted.
ALLOWED_REMOTE_URL = "https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-mml-chtml.js"
ALLOWED_REMOTE_INTEGRITY = "sha384-Wuix6BuhrWbjDBs24bXrjf4ZQ5aFeFWBuKkFekO2t8xFU0iNaLQfp2K6/1Nxveei"

# Elements whose mere presence can issue a request. The CSP must precede every one of them: a policy
# in <meta> does not apply to markup the parser has already seen, so a LATE policy leaves everything
# above it ungoverned.
REQUESTING_ELEMENTS = (
    "script",
    "img",
    "link",
    "iframe",
    "form",
    "video",
    "audio",
    "source",
    "embed",
    "object",
    "track",
    "input",
    # <style> belongs here: @import url(...) and url(...) inside a stylesheet are requests, and a
    # <style> block placed above the policy is fetched before the policy applies.
    "style",
)

# Computed access to a global defeats any scan for a literal identifier: globalThis["local"+"Storage"]
# reaches localStorage while containing no such token. A generated teaching page has no legitimate
# use for computed global access or dynamic code evaluation, so the CONSTRUCT is banned outright
# rather than its consequences being chased. That is a positive constraint on code shape, which is
# enforceable; enumerating every way to spell a global is not.
DYNAMIC_ACCESS_PATTERNS = (
    # Every reachable Window alias, not just the obvious three: document.defaultView is the same
    # object by another name, and so are frames / parent / top.
    r"globalThis\s*\[",
    r"\bwindow\s*\[",
    r"\bself\s*\[",
    r"\bframes\s*\[",
    r"\bparent\s*\[",
    r"\btop\s*\[",
    r"\bdocument\s*\.\s*defaultView",
    r"\beval\s*\(",
    r"\bnew\s+Function\s*\(",
    r"\bFunction\s*\(\s*[\"']",
    r"\bimport\s*\(",
    # A property key BUILT at runtime, whatever object it is applied to. Naming aliases one by one
    # is a losing game; the giveaway is the construction of the key itself.
    r"\[\s*[\"'][^\"']*[\"']\s*\+",
    r"\[\s*[A-Za-z_$][\w$]*\s*\+\s*[\"']",
)


# Content thresholds. Deliberately low: the gate's job is to reject an EMPTY skeleton, not to grade
# prose. A one-word "reading" is not a plain-language restatement of an equation, and a chip with no
# text names nothing.
MIN_READING_CHARS = 40
MIN_CHIP_CHARS = 6
MIN_KEY_CHIPS = 3
MIN_LATEX_CHARS = 20  # shorter than the shortest real equation body; only excludes an empty panel


def _text_len(el: Any) -> int:
    """Visible text length of an element, or 0 when the element is absent.

    Absent and empty deliberately collapse to the same answer: both mean "this annotation is not
    there", and only one of them used to be caught.
    """
    if not isinstance(el, Tag):
        return 0
    return len(el.get_text(" ", strip=True))


def revision_id(html: str) -> str:
    """First 12 hex of sha256 over the bytes from <main id="main"> to </main> inclusive.

    Hashing <main> alone is deliberate: the revision ledger lives in the <footer>, so writing a
    revision id into the page cannot alter the value being recorded. Hashing the whole file would be
    self-referential and could never settle.
    """
    start = html.find(MAIN_OPEN)
    end = html.find(MAIN_CLOSE)
    if start == -1 or end == -1:
        return "no-main-element"
    return hashlib.sha256(html[start : end + len(MAIN_CLOSE)].encode()).hexdigest()[:12]


def attr(el: Any, name: str) -> str:
    """A bs4 attribute as a plain string, never None and never a list.

    Multi-valued attributes (class, rel) come back as a list; a missing one comes back as None.
    Normalising here keeps every call site free of the `str | list | None` dance.
    """
    if not isinstance(el, Tag):
        return ""
    value = el.get(name)
    if value is None:
        return ""
    if isinstance(value, list):
        return " ".join(str(v) for v in value)
    return str(value)


class Gate:
    def __init__(self) -> None:
        self.failures = 0

    def section(self, title: str) -> None:
        print(f"\n=== {title} ===")

    def check(self, label: str, ok: bool, detail: str = "") -> bool:
        print(f"  [{'PASS' if ok else 'FAIL'}] {label}{f' — {detail}' if detail else ''}")
        if not ok:
            self.failures += 1
        return ok


def check_hard_wrapping(g: Gate, src: str) -> None:
    g.section("ZERO HARD-WRAPPING INVARIANT (release-blocking)")
    # Pair each <p ...> with its OWN nearest </p>. The naive whole-document alternative
    # <p\b[^>]*>[\s\S]*?[\r\n][\s\S]*?</p> is non-greedy ACROSS the document: it opens in one <p>,
    # crosses that element's </p> and the following newline, and closes at a LATER </p>, so it fires
    # on any document with two well-formed adjacent paragraphs on separate lines.
    bodies = re.findall(r"<p\b[^>]*>(.*?)</p>", src, re.S)
    wrapped = [b for b in bodies if "\n" in b or "\r" in b]
    g.check("no <p> element contains a newline", not wrapped, f"{len(wrapped)} of {len(bodies)}")
    for b in wrapped[:5]:
        print(f"      offender: {b[:100]!r}")
    g.check("no <br> or <wbr> inside any <p>", not any(re.search(r"<w?br\b", b) for b in bodies))
    g.check("no newline entities inside any <p>", not any(re.search(r"&#1[03];", b) for b in bodies))
    g.check("white-space:nowrap not used", "white-space:nowrap" not in re.sub(r"\s", "", src))
    naive = len(re.findall(r"<p\b[^>]*>.*?[\r\n].*?</p>", src, re.S))
    print(f"      (naive cross-boundary regex reports {naive}; it spans elements — not the gate)")


def check_structure(g: Gate, src: str, soup: BeautifulSoup) -> None:
    g.section("STRUCTURE AND ACCESSIBILITY")
    g.check("doctype first", src.lstrip().lower().startswith("<!doctype html>"))
    g.check("lang attribute", bool(attr(soup.find("html"), "lang")))
    g.check("viewport meta", soup.find("meta", attrs={"name": "viewport"}) is not None)
    g.check("exactly one <h1>", len(soup.find_all("h1")) == 1)
    for name in ("main", "nav", "header", "footer"):
        g.check(f"<{name}> landmark", soup.find(name) is not None)
    g.check("skip link", bool(soup.select(".skip")))
    g.check("noscript fallback", soup.find("noscript") is not None)
    g.check("visible focus styles", "focus-visible" in src)
    g.check("dark mode", bool(re.search(r"prefers-color-scheme:\s*dark", src)))
    g.check("print styles", "@media print" in src)

    levels = [int(h.name[1]) for h in soup.find_all(re.compile(r"^h[1-6]$"))]
    skipped = [lv for prev, lv in zip(levels, levels[1:]) if lv > prev + 1]
    g.check("no skipped heading levels", not skipped, ",".join(str(s) for s in skipped))

    ids = {attr(el, "id") for el in soup.select("[id]")}
    dangling = [
        attr(a, "href")[1:]
        for a in soup.select('a[href^="#"]')
        if len(attr(a, "href")) > 1 and attr(a, "href")[1:] not in ids
    ]
    g.check("every in-page anchor resolves", not dangling, ",".join(dangling))


def check_mathematics(g: Gate, soup: BeautifulSoup) -> list[Tag]:
    g.section("MATHEMATICS")
    scripts = [s for s in soup.find_all("script") if isinstance(s, Tag)]
    mj = [s for s in scripts if "tex-mml-chtml" in attr(s, "src")]
    g.check(
        "a real <script> element loads MathJax",
        bool(mj),
        "asserted as markup, not as a string that could sit in a comment"
        if mj
        else "no <script src=...tex-mml-chtml...> element exists",
    )
    pinned = [s for s in mj if re.search(r"mathjax@\d+\.\d+\.\d+", attr(s, "src"))]
    g.check(
        "the MathJax source is version-pinned",
        bool(pinned),
        attr(pinned[0], "src") if pinned else "no pinned src on any MathJax script element",
    )
    local = [attr(s, "src") for s in mj if attr(s, "src").startswith("file:")]
    g.check(
        "no machine-specific file:// source",
        not local,
        f"{local} cannot travel with the artifact" if local else "portable",
    )
    remote_scripts = [s for s in scripts if attr(s, "src").startswith("http")]
    unpinned = [attr(s, "src") for s in remote_scripts if not attr(s, "integrity")]
    g.check(
        "integrity hash on every remote script",
        not unpinned,
        ", ".join(unpinned) if unpinned else f"{len(remote_scripts)} remote script(s) pinned",
    )
    g.check("no equation images", not soup.select('img[src*="eq"], img[src*="math"], img[src*="formula"]'))

    eq_divs = [d for d in soup.select("div.eq") if isinstance(d, Tag)]
    numbered = [d for d in eq_divs if d.select_one("span.eqid") is not None]
    eq_ids: list[int] = []
    for d in numbered:
        span = d.select_one("span.eqid")
        digits = re.sub(r"\D", "", span.get_text() if span else "")
        eq_ids.append(int(digits) if digits else -1)
    g.check(
        "equation identifiers are stable and contiguous",
        eq_ids == list(range(1, len(eq_ids) + 1)),
        f"({', '.join(str(n) for n in eq_ids)})",
    )
    # The contract is that the LaTeX is RECOVERABLE, so check the panel's contents, not its label. A
    # <details> whose <summary> says "LaTeX source" over an empty body satisfied the old test while
    # recovering nothing — presence standing in for content again.
    missing = []
    for n, d in zip(eq_ids, numbered):
        panels = [p for p in d.select("details") if any("LaTeX source" in s.get_text() for s in p.select("summary"))]
        recoverable = False
        for p in panels:
            body = "".join(c.get_text() for c in p.children if getattr(c, "name", None) != "summary")
            if "\\" in body and len(body.strip()) >= MIN_LATEX_CHARS:
                recoverable = True
        if not recoverable:
            missing.append(str(n))
    g.check(
        "every numbered equation exposes recoverable LaTeX",
        not missing,
        f"missing or empty on equation(s) {', '.join(missing)}" if missing else f"{len(eq_ids)}/{len(eq_ids)}",
    )
    return numbered


def check_notation(g: Gate, src: str, soup: BeautifulSoup, numbered: list[Tag]) -> None:
    g.section("NOTATION ACCESSIBILITY (release-blocking, per equation)")
    g.check(
        "html extension is in the loader, not merely the package list",
        bool(re.search(r"loader:\s*\{[^}]*\[tex\]/html", src)),
        r"without the loader entry \class renders as literal red text",
    )
    g.check("html package enabled", bool(re.search(r"packages:\s*\{\s*'\[\+\]':\s*\[[^\]]*'html'", src)))

    pairs = class_pairs(src)
    roles = sorted({r for r, _ in pairs})
    g.check("a systematic role vocabulary is in use", 3 <= len(roles) <= 8, ", ".join(roles) or "none")
    # Look in the STYLE blocks. `f".{r}" not in src` was satisfied by any mention of ".sym-out"
    # anywhere — a comment, or prose explaining the palette — so a role could be documented in words
    # and have no rule at all.
    styles = "\n".join(s.get_text() for s in soup.find_all("style"))
    undefined = [r for r in roles if not re.search(rf"\.{re.escape(r)}\s*[,{{ ]", styles)]
    g.check("every role used has a CSS rule", not undefined, ", ".join(undefined) or f"{len(roles)} roles")
    dark = dark_regions(src)
    no_dark = [r for r in roles if f"--{r}:" not in dark]
    g.check("every role has a dark-scheme value", not no_dark, ", ".join(no_dark) if no_dark else f"{len(roles)} roles")

    by_symbol: dict[str, set[str]] = {}
    for role, sym in pairs:
        by_symbol.setdefault(sym, set()).add(role)
    two = {s: r for s, r in by_symbol.items() if len(r) > 1}
    g.check(
        "no symbol carries two different roles",
        not two,
        "; ".join(f"{s} -> {'/'.join(sorted(r))}" for s, r in two.items())
        or f"{len(by_symbol)} symbols, one role each",
    )

    # THE PER-ITEM CHECK. Every numbered equation must carry all four aids IN ITS OWN CONTAINER.
    # Document-wide counts let two readings under one equation compensate for another having none,
    # and the old chip check even tolerated one equation missing them outright (>= n - 1).
    deficient: list[str] = []
    for d in numbered:
        span = d.select_one("span.eqid")
        label = span.get_text().strip() if span else "?"
        # PRESENCE IS NOT CONTENT. `select_one(".reads") is not None` is satisfied by an EMPTY
        # <div class="reads"></div>, and `.chips .chip` by an empty <span class="chip"></span>. A
        # generator that emits the right skeleton with nothing in it was certified as complete —
        # the same shape as the empty-localStorage-set defect, one layer down.
        lacks = []
        if _text_len(d.select_one(".reads")) < MIN_READING_CHARS:
            lacks.append("reading")
        if _text_len(d.select_one(".numbers")) < MIN_READING_CHARS:
            lacks.append("worked numbers")
        # COVERAGE PER SYMBOL, NOT PER ROLE. Counting chips was satisfied by an equation with six
        # coloured roles and one chip; comparing ROLE SETS was the first fix, and it was still too
        # weak — an equation colouring both `g` and `n` as sym-out with a single sym-out chip has
        # identical sets on both sides and passes while `n` goes unexplained. That is the real case
        # in equations (1), (2) and (4) of the reference page.
        #
        # The contract is per SYMBOL, so each chip declares the symbols it explains in `data-symbol`,
        # verbatim as they appear inside \class{...}{...}, separated by `|`. Declaring is required
        # rather than inferred: the chip renders `μ_p` as glyphs and the source says `\mu_{p}`, so any
        # inference would be a normalisation guess, and a guess that fails silently reads as coverage.
        chips = [c for c in d.select(".chips .chip") if _text_len(c) >= MIN_CHIP_CHARS]
        used = set(class_pairs(d.decode()))
        declared: set[tuple[str, str]] = set()
        for c in chips:
            # NOT `roles` — that name holds the page-wide role list this function's notation-key
            # check reads further down, and rebinding it here left that check comparing against the
            # last chip's classes. It then reported "5 documented, 1 used" and PASSED. Caught only
            # because a mutation that should have tripped it came back MISDIRECTED.
            chip_roles = [cls for cls in attr(c, "class").split() if cls.startswith("sym-")]
            for sym in (s.strip() for s in attr(c, "data-symbol").split("|") if s.strip()):
                declared |= {(r, sym) for r in chip_roles}
        missing = used - declared
        if not used:
            lacks.append("role colouring")
        elif not chips:
            lacks.append("chips with content")
        elif missing:
            lacks.append("chips for " + ", ".join(f"{r}:{s}" for r, s in sorted(missing)))
        if lacks:
            deficient.append(f"{label} no {', '.join(lacks)}")
    g.check(
        "EVERY numbered equation carries reading + numbers + chips + colour",
        not deficient,
        "; ".join(deficient) if deficient else f"all {len(numbered)} equations complete",
    )

    key = soup.select_one(".notationkey")
    all_eq = soup.select("div.eq")
    first_eq = all_eq[0] if all_eq else None
    key_chips = [c for c in (key.select(".chip") if isinstance(key, Tag) else []) if _text_len(c) >= MIN_CHIP_CHARS]
    key_roles = {cls for c in key_chips for cls in attr(c, "class").split() if cls.startswith("sym-")}
    # Again coverage, not a count: a three-chip key satisfied a >= 3 threshold while the page used
    # six roles, leaving half the colour vocabulary undocumented. The key must introduce every role
    # the page actually uses, or it is not a key.
    undocumented = set(roles) - key_roles
    g.check(
        "the notation key documents EVERY role the page uses",
        not undocumented and bool(key_roles),
        f"missing: {', '.join(sorted(undocumented))}"
        if undocumented
        else f"{len(key_roles)} role(s) documented, {len(roles)} used",
    )
    g.check(
        "notation key precedes the first equation",
        key is not None and first_eq is not None and precedes(key, first_eq),
        "absent" if key is None else "",
    )
    g.check(
        "notation key survives the expert switch",
        bool(re.search(r"body\.no-annot\s+\.keychips\{display:flex\}", src)),
        "hiding the only key strands the reader with an undocumented colour code",
    )
    # Inside the equation blocks — the check is named "inside the equation", and a \underbrace in a
    # comment or in prose about the technique satisfied the whole-source form without any equation
    # carrying one.
    braced = sum(d.decode().count("\\underbrace{") for d in all_eq)
    g.check(
        "multi-term groups are named inside the equation (signalling)",
        braced > 0,
        f"{braced} inside .eq blocks",
    )
    g.check(
        "equation and annotation blocks can scroll their maths locally",
        bool(re.search(r"\.eq,\.reads,\.numbers\{overflow-x:auto\}", src)),
        "an unbreakable formula otherwise becomes page-level horizontal scroll",
    )
    g.check("annotation toggle present", soup.select_one("#annotToggle") is not None)
    g.check("toggle exposes pressed state", soup.select_one("[aria-pressed]") is not None)

    total = len(re.findall(r"\\class\{sym-", src))
    inside = sum(d.decode().count("\\class{sym-") for d in all_eq)
    g.check(
        "the encoding extends into prose, not only the equation blocks",
        total - inside >= 10,
        f"{total - inside} of {total} outside .eq blocks",
    )


def check_assessment(g: Gate, src: str, soup: BeautifulSoup) -> None:
    g.section("ASSESSMENT (exploratory, not an examination; per question)")
    block = soup.select_one('script[type="application/json"]#assessment-data')
    questions: list[dict[str, Any]] = []
    if not g.check(
        "assessment is a parseable JSON data block",
        block is not None,
        "regexing a JS object literal cannot soundly verify a per-question contract",
    ):
        pass
    else:
        raw = block.string if block is not None and block.string is not None else ""
        try:
            questions = list(json.loads(raw).get("questions", []))
            g.check("assessment JSON parses", True, f"{len(questions)} question(s)")
        except (ValueError, AttributeError) as exc:
            g.check("assessment JSON parses", False, str(exc))

    g.check("3-8 questions", 3 <= len(questions) <= 8, str(len(questions)))
    qids = [str(q.get("id", "")) for q in questions]
    dupes = sorted({i for i in qids if qids.count(i) > 1})
    g.check("no duplicate question ids", not dupes, ", ".join(dupes))

    # Per question, never per document — and the option COUNT is part of the contract. Counting only
    # `ok is True` and `ok is False` left a gap: a fifth option whose `ok` is missing or non-boolean
    # satisfies "one true, three false" while the question plainly has five choices.
    shape: list[str] = []
    for q in questions:
        opts = list(q.get("options", []))
        n_ok = sum(1 for o in opts if o.get("ok") is True)
        n_no = sum(1 for o in opts if o.get("ok") is False)
        non_bool = [i for i, o in enumerate(opts) if not isinstance(o.get("ok"), bool)]
        if len(opts) != 4:
            shape.append(f"{q.get('id')}: {len(opts)} options (need exactly 4)")
        if non_bool:
            shape.append(f"{q.get('id')}: option(s) {non_bool} have a non-boolean 'ok'")
        if n_ok != 1 or n_no != 3:
            shape.append(f"{q.get('id')}: {n_ok} correct / {n_no} distractors")
    g.check(
        "EVERY question has exactly four options: one correct, three distractors",
        not shape,
        "; ".join(shape) if shape else f"all {len(questions)} questions well-formed",
    )

    no_fb = [
        f"{q.get('id')}[{i}]"
        for q in questions
        for i, o in enumerate(q.get("options", []))
        if not str(o.get("fb", "")).strip()
    ]
    g.check("every option carries feedback", not no_fb, ", ".join(no_fb))
    fbs = [str(o.get("fb", "")) for q in questions for o in q.get("options", [])]
    g.check("all feedback is unique", len(set(fbs)) == len(fbs), f"{len(fbs) - len(set(fbs))} duplicate(s)")
    forbidden = [
        str(q.get("id"))
        for q in questions
        for o in q.get("options", [])
        if re.search(r"all of the above|none of the above", str(o.get("t", "")), re.I)
    ]
    g.check("no forbidden option text", not forbidden, ", ".join(forbidden))
    g.check("every question states an objective", all(str(q.get("objective", "")).strip() for q in questions))

    # Cover the equivalent spellings, not just the property assignment: setAttribute("disabled", …),
    # a `disabled` attribute in generated markup, and toggleAttribute all lock the reader out just as
    # effectively. This static check is a smoke test — the authoritative one drives a question to the
    # SOLVED state in verify_rendered.py, because code that disables options only after success is
    # invisible to any source scan.
    flat = re.sub(r"\s", "", src)
    locks = [
        pattern
        for pattern in (
            ".disabled=true",
            'setAttribute("disabled"',
            "setAttribute('disabled'",
            'toggleAttribute("disabled"',
        )
        if pattern.replace(" ", "") in flat
    ]
    g.check(
        "no option-disabling code (smoke test; verify_rendered.py is authoritative)",
        not locks,
        ", ".join(locks) if locks else "a solved question must stay explorable",
    )
    g.check("distractor exploration is tracked", "explored" in src)
    g.check("per-question reset", "Reset this question" in src)
    g.check("reset all", soup.select_one("#resetAll") is not None)
    g.check("live summary region", soup.select_one("#summary") is not None and "aria-live" in src)


def check_privacy(g: Gate, src: str, soup: BeautifulSoup) -> None:
    g.section("PRIVACY (no outbound channel, no reader state)")
    # A blacklist of JS APIs cannot cover <img>, <form>, WebSocket or EventSource. CSP is the
    # standards-based primitive that denies by default and allows only what is named.
    csp = soup.find("meta", attrs={"http-equiv": re.compile(r"^content-security-policy$", re.I)})
    if g.check(
        "a Content Security Policy is declared in <meta>",
        csp is not None,
        "an API blacklist cannot cover markup-driven requests",
    ):
        content = attr(csp, "content")
        g.check("CSP denies everything by default", "default-src 'none'" in content, content[:120])
        g.check("CSP forbids form submission", "form-action 'none'" in content)
        g.check("CSP pins a base URI", "base-uri 'none'" in content)
        origins = set(re.findall(r"https://[\w.-]+", content))
        g.check("CSP allows at most one remote origin", len(origins) <= 1, ", ".join(sorted(origins)) or "none")

    # CSP ORDERING. A policy in <meta> governs only what follows it, so "a CSP exists somewhere" is
    # not the contract — "the CSP precedes everything it must govern" is. Without this, an <img> on
    # the allowed origin placed ABOVE a late policy is requested before the policy applies, encoding
    # private page content in its query string, and both gates still pass.
    if csp is not None:
        # Scan a comment-blanked copy. Raw-source scanning matched `<img>` and `<form action>` inside
        # the very comment that documents the policy — the third time in this gate that prose has
        # been mistaken for markup, so the fix belongs in the check, not in the wording.
        scan = blank_html_comments(src)
        # Anchor on the START of the CSP's own tag. Using the offset of the attribute TEXT put the
        # policy's own `<meta` before its measured position, so the check reported the CSP as a tag
        # above itself.
        csp_tag = re.search(r"<meta\b[^>]*Content-Security-Policy", scan, re.I)
        csp_pos = csp_tag.start() if csp_tag else scan.find("Content-Security-Policy")
        # Assert POSITION, not a denylist of element names. Enumerating request-capable elements
        # cannot be complete — it missed <style>, and then missed style="" on an ordinary <div>,
        # which is a request surface on any element at all. The documented contract is stronger and
        # is checkable exactly: the policy is the FIRST tag after <meta charset>.
        tags = [
            (m.start(), m.group(1).lower())
            for m in re.finditer(r"<([a-zA-Z][\w-]*)\b", scan)
            if m.group(1).lower() not in ("html", "head")
        ]
        before = [(pos, name) for pos, name in tags if pos < csp_pos]
        allowed_before = {"meta"}  # only <meta charset> may precede it
        offenders = [
            f"<{name}> at {pos}"
            for pos, name in before
            if name not in allowed_before or "charset" not in scan[pos : pos + 60]
        ]
        g.check(
            "the CSP is the first tag after <meta charset>",
            not offenders,
            f"{len(offenders)} tag(s) above the policy: {', '.join(offenders[:3])}"
            if offenders
            else f"policy at offset {csp_pos}, {len(before)} tag(s) above it (charset only)",
        )

    remote: list[tuple[str, str]] = []
    for el in soup.find_all(list(REQUESTING_ELEMENTS)):
        url = attr(el, "src") or attr(el, "href") or attr(el, "action")
        if url.startswith(("http://", "https://", "//")):
            remote.append((str(el.name), url))
    # Exact URL, not merely the allowed ORIGIN: any path on that origin can carry a payload in its
    # query string, and the rendered gate treats that origin as trusted.
    off = [(t, u) for t, u in remote if u != ALLOWED_REMOTE_URL]
    g.check(
        "the only remote reference is the exact pinned MathJax script",
        not off,
        "; ".join(f"<{t}> {u}" for t, u in off) if off else f"{len(remote)} reference(s), all exact",
    )
    # CSS is a request surface too. @import and url() inside a <style> block or a style="" attribute
    # fetch from wherever they name, and neither appears in any element's src/href/action.
    css_sources = [str(t.string or "") for t in soup.find_all("style")] + [
        attr(el, "style") for el in soup.select("[style]")
    ]
    # re.findall with TWO capture groups yields TUPLES, and the previous comprehension kept a value
    # only when the whole match was a str — which never happens with two groups. css_urls was
    # therefore ALWAYS empty and the check below could not fail. It was not caught by mutation
    # testing because the @import mutation was killed by the CSP-ordering check instead: a mutation
    # killed for the wrong reason hides a dead check behind a live one.
    css_urls = [
        candidate.strip("\"' ")
        for block in css_sources
        for groups in re.findall(r"url\(\s*([^)]+?)\s*\)|@import\s+(?:url\()?\s*([\"'][^\"']+[\"'])", block)
        for candidate in (groups if isinstance(groups, tuple) else (groups,))
        if candidate
    ]
    css_remote = [u for u in css_urls if u.startswith(("http://", "https://", "//")) and u != ALLOWED_REMOTE_URL]
    g.check(
        "no stylesheet fetches a remote resource",
        not css_remote,
        "; ".join(css_remote) if css_remote else f"{len(css_urls)} url() reference(s), none remote",
    )

    hashes = [attr(s, "integrity") for s in soup.find_all("script") if attr(s, "src") == ALLOWED_REMOTE_URL]
    g.check(
        "the pinned script carries the expected integrity hash",
        bool(hashes) and all(h == ALLOWED_REMOTE_INTEGRITY for h in hashes),
        f"got {hashes}" if hashes else "no script element matched the pinned URL",
    )
    # Search executable script bodies with comments stripped, not the whole document. Matching raw
    # file text flagged this page's own explanatory comment — the sentence "none of them calls
    # fetch()" — which is precisely the confusion between prose and code that rule 3 exists to stop.
    code = "\n".join(
        strip_js_comments(s.string or "")
        for s in soup.find_all("script")
        if isinstance(s, Tag) and not attr(s, "type").endswith("json")
    )
    calls = re.findall(r"\b(fetch|XMLHttpRequest|sendBeacon|WebSocket|EventSource)\s*\(", code)
    g.check("no scripted network transmission", not calls, ", ".join(sorted(set(calls))))
    # Scan code, not prose — a page that DOCUMENTS "this never touches sessionStorage" was failed by
    # the old whole-source scan, the mirror image of the fetch() false positive fixed just above. The
    # bracket spelling is included because `document["cookie"]` is neither a computed key nor a Window
    # alias, so the dynamic-access rules did not see it either.
    stores = re.findall(r"sessionStorage|document\s*\.\s*cookie|document\s*\[\s*[\"']cookie", code)
    g.check("no cookies or session storage", not stores, ", ".join(sorted(set(stores))))

    # localStorage: ONE named key, and every access individually guarded. The old gate accepted any
    # key beginning "teachback:", so a page persisting reader answers under teachback:responses
    # passed; and it proved only that "localStorage" appeared somewhere inside some try block.
    # Scan EVERY mention of localStorage and require each to match the one permitted form. Scanning
    # only for `localStorage.setItem(` was an allowlist with an open back door: `localStorage["setItem"]`
    # is ordinary JavaScript, produced zero detected accesses AND zero unguarded offsets, so a page
    # persisting reader answers was certified by both storage checks at once. Enumerate the
    # references, then subtract the ones that are provably fine — never the reverse.
    allowed_form = re.compile(
        r"localStorage\.(?:get|set|remove)Item\(\s*([A-Za-z_$][\w$]*|\"[^\"]*\")",
    )
    declared = {m for m in re.findall(r"var\s+([A-Za-z_$][\w$]*)\s*=\s*\"" + re.escape(ANNOTATION_KEY) + r"\"", src)}
    mentions = [m.start() for m in re.finditer(r"\blocalStorage\b", code)]
    recognised = {m.start() for m in allowed_form.finditer(code)}
    unrecognised = [code[p : p + 60] for p in mentions if p not in recognised]
    g.check(
        "every localStorage reference uses the one permitted call form",
        not unrecognised,
        f"{len(unrecognised)} other form(s), first: {unrecognised[0]!r}"
        if unrecognised
        else f"{len(mentions)} reference(s)",
    )
    dynamic = [
        code[m.start() : m.start() + 60] for pattern in DYNAMIC_ACCESS_PATTERNS for m in re.finditer(pattern, code)
    ]
    g.check(
        "no computed global access or dynamic code evaluation",
        not dynamic,
        f"{len(dynamic)} occurrence(s), first: {dynamic[0]!r}"
        if dynamic
        else 'globalThis["local"+"Storage"] would otherwise reach storage with no matching token',
    )

    accesses = allowed_form.findall(code)
    stray = [k for k in accesses if k not in declared and k.strip('"') != ANNOTATION_KEY]
    g.check(
        f'localStorage stores only "{ANNOTATION_KEY}"',
        not stray,
        f"stray key(s): {', '.join(stray)}" if stray else f"{len(accesses)} guarded access(es)",
    )
    unguarded = unguarded_storage(src)
    g.check(
        "every localStorage access sits inside its own try/catch",
        not unguarded,
        f"{len(unguarded)} unguarded at offset(s) {unguarded[:3]}"
        if unguarded
        else "private-browsing mode degrades to 'not remembered'",
    )
    g.check("no analytics", not re.search(r"google-analytics|gtag\(|plausible|hotjar|segment\.io", src, re.I))


def check_ledger(g: Gate, src: str, soup: BeautifulSoup) -> None:
    g.section("TERMINOLOGY LOOP AND REVISION LEDGER")
    g.check("terminology request form present", soup.select_one("#termRequest") is not None)
    # Scan the SCRIPT that composes the instruction, not the whole document. `"--terms" in src` was
    # satisfied by this page's own revision-ledger row, which quotes a past --terms invocation in a
    # <td>: delete the form's entire clipboard logic and the check still passed. Same defect as the
    # notation-key check that matched its own CSS rule — prose is not code.
    composer = "\n".join(
        strip_js_comments(s.string or "")
        for s in soup.find_all("script")
        if isinstance(s, Tag) and not attr(s, "type").endswith("json")
    )
    g.check(
        "form emits a /teachback --terms instruction",
        "--terms" in composer and "--update" in composer,
        "the instruction must be COMPOSED by the form, not merely mentioned somewhere on the page",
    )
    g.check("revision ledger present", soup.select_one("#ledger") is not None)
    rows = soup.select("tr[data-revision]")
    g.check("ledger has at least one revision row", bool(rows), f"{len(rows)} row(s)")
    declared = [attr(r, "data-revision-id") for r in rows if attr(r, "data-revision-id")]
    computed = revision_id(src)
    g.check(
        "latest declared revision id matches the computed hash of <main>",
        bool(declared) and declared[-1] == computed,
        f"computed {computed}",
    )


def blank_html_comments(html: str) -> str:
    """Replace every HTML comment's contents with spaces, preserving byte offsets.

    Offsets are preserved deliberately: the CSP-ordering check compares POSITIONS, so deleting the
    comments would shift everything after them and quietly invalidate the comparison.
    """
    out = list(html)
    for m in re.finditer(r"<!--.*?-->", html, re.S):
        for i in range(m.start(), m.end()):
            if out[i] != "\n":
                out[i] = " "
    return "".join(out)


def strip_js_comments(code: str) -> str:
    """Remove // and /* */ comments so an API name mentioned in prose is not read as a call.

    String literals are preserved: a "//" inside a quoted URL must not start a comment. This is a
    lexer, not a parser — enough to tell code from commentary, which is the only distinction needed.
    """
    out: list[str] = []
    i, n = 0, len(code)
    quote: str | None = None
    while i < n:
        ch = code[i]
        if quote:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(code[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
        elif ch in "\"'`":
            quote = ch
            out.append(ch)
            i += 1
        elif code.startswith("//", i):
            i = code.find("\n", i)
            if i == -1:
                break
        elif code.startswith("/*", i):
            end = code.find("*/", i + 2)
            i = n if end == -1 else end + 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def class_pairs(text: str) -> list[tuple[str, str]]:
    r"""Extract (role, symbol) from \class{role}{symbol}, counting braces.

    Brace counting rather than a bracket-class regex because symbols nest:
    \tilde{\mathbf{w}}^{\star} is ONE symbol, and a regex truncates it at the first inner brace.
    """
    out: list[tuple[str, str]] = []
    for m in re.finditer(r"\\class\{(sym-[a-z-]+)\}\{", text):
        depth, i = 1, m.end()
        while i < len(text) and depth:
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
            i += 1
        symbol = text[m.end() : i - 1].strip()
        if "\\class" not in symbol:
            out.append((m.group(1), symbol))
    return out


def dark_regions(text: str) -> str:
    """Concatenate every prefers-color-scheme:dark block, brace-counted.

    A page normally has SEVERAL dark blocks nested one level deep, so a lazy regex to the first
    "\\n}" stops inside the first block and reports every role declared in later ones as missing.
    """
    out: list[str] = []
    for m in re.finditer(r"@media\s*\(prefers-color-scheme:\s*dark\)\s*\{", text):
        depth, i = 1, m.end()
        start = i
        while i < len(text) and depth:
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
            i += 1
        out.append(text[start : i - 1])
    return "".join(out)


def precedes(a: Tag, b: Tag) -> bool:
    """Does element a start before element b in the SOURCE?

    Uses the parser's recorded position rather than searching for the element's re-serialised text.
    The previous implementation was `src.find(a.decode()[:60]) < src.find(b.decode()[:60])`, and
    `str.find` returns -1 when the needle is absent — so an element bs4 re-serialises differently from
    the source (it normalises `class = "x"` to `class="x"` and a bare `data-x` to `data-x=""`) scored
    -1, and `-1 < pos_b` is True. The check then PASSED for any ordering at all, including the wrong
    one. Absent data resolving to the favourable answer; the same class as Eon-Labs/alpha-forge#484.

    `sourceline`/`sourcepos` come from html.parser and are exact. If either is unavailable the answer
    is unknown, and unknown must not read as satisfied.
    """
    if a.sourceline is None or b.sourceline is None:
        return False
    return (a.sourceline, a.sourcepos or 0) < (b.sourceline, b.sourcepos or 0)


def unguarded_storage(src: str) -> list[int]:
    """Offsets of localStorage accesses not enclosed by a try { ... } block.

    Walks braces outward from each access rather than checking that "try" occurs near
    "localStorage": the previous form matched any try block whose first "}" came after the word,
    which proved nothing about the access itself.
    """
    bad: list[int] = []
    for m in re.finditer(r"localStorage\.(?:get|set|remove)Item\(", src):
        depth, i, guarded = 0, m.start(), False
        while i > 0:
            ch = src[i]
            if ch == "}":
                depth += 1
            elif ch == "{":
                if depth == 0:
                    if re.search(r"\btry\s*$", src[max(0, i - 40) : i]):
                        guarded = True
                        break
                else:
                    depth -= 1
            i -= 1
        if not guarded:
            bad.append(m.start())
    return bad


def main() -> int:
    ap = argparse.ArgumentParser(description="Static gate for a teachback explainer page.")
    ap.add_argument("page", type=Path, help="the generated .html file")
    ap.add_argument("--revision", action="store_true", help="print the revision id and exit")
    args = ap.parse_args()

    src = args.page.read_text()
    if args.revision:
        print(revision_id(src))
        return 0

    soup = BeautifulSoup(src, "html.parser")
    g = Gate()
    check_hard_wrapping(g, src)
    check_structure(g, src, soup)
    numbered = check_mathematics(g, soup)
    check_notation(g, src, soup, numbered)
    check_assessment(g, src, soup)
    check_privacy(g, src, soup)
    check_ledger(g, src, soup)

    g.section("RESULT")
    print("ALL CHECKS PASSED" if g.failures == 0 else f"{g.failures} CHECK(S) FAILED")
    print("(layout is deliberately NOT checked here — run verify_rendered.py for that)")
    return 0 if g.failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
