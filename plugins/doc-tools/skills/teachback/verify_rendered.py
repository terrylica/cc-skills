#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["playwright>=1.48"]
# ///
"""teachback — rendered gate for a generated explainer page.

    TB="$(cc-plugin-root doc-tools)/skills/teachback"
    uv run --no-project --script "$TB/verify_rendered.py" <page.html>
    uv run --no-project --script "$TB/verify_rendered.py" <page.html> --browser /path/to/chrome

Exits non-zero if any check fails. Needs nothing preinstalled but uv: the PEP 723 metadata above
makes this file self-contained, and `--no-project` keeps uv from walking upward and adopting the uv
workspace that happens to surround the page being checked. A Chromium build is also required; pass
--browser, or let Playwright use its own (`uv run --no-project --with playwright playwright install
chromium`) — launch_chromium below installs it on first use if it is absent.

WHY THIS FILE EXISTS. verify_explainer.py deliberately checks nothing about layout. Layout
invariants — "the shell fills the viewport", "body text is not width-capped", "every grid child is
placed" — are properties of the RENDERED page, and asserting them against CSS source text is
unsound in principle: whitespace and declaration order are insignificant in CSS, so `.shell{display:grid`
matched while the equivalent `.shell { display: grid; }` sailed past the very check meant to catch it
(Eon-Labs/alpha-forge#527 review, finding 4). Here the same invariants are read back from getComputedStyle and from
real measured geometry, where formatting cannot affect the answer.

It also checks the three things a static parse can never see: that the symbol role classes survive
into the rendered maths as DISTINCT colours, that the annotation toggle actually toggles, and that
loading the page emits no request to an origin outside the declared allowlist.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright

VIEWPORTS = [2560, 1920, 1600, 1440, 1200, 1024, 820, 620, 480, 390]
ROLE_PREFIX = "sym-"
ALLOWED_ORIGINS = ("https://cdn.jsdelivr.net",)
ANNOTATION_KEY = "teachback:annotations"


def is_offsite(url: str) -> bool:
    """Is this request to an origin other than the one allowed one?

    Compares the PARSED origin. `url.startswith("https://cdn.jsdelivr.net")` is a prefix test, and
    `https://cdn.jsdelivr.net.evil.example/leak.css?private=context` starts with exactly that string
    — an attacker-registered hostname that the previous predicate declared trusted.
    """
    if not url.startswith(("http://", "https://")):
        return False
    parsed = urlparse(url)
    return f"{parsed.scheme}://{parsed.netloc}" not in ALLOWED_ORIGINS


def launch_chromium(pw: Any, executable: str | None) -> Any:
    """Launch Chromium, installing Playwright's own build on first use if it is absent.

    PEP 723 resolves the playwright PACKAGE; it does not download the BROWSER. So the documented
    command failed on any machine that had not run Playwright before, with 'Executable doesn't
    exist' — the same class of problem as the Bun dependency it replaced, just one layer down. A
    release gate that cannot run is not a gate, so this bootstraps itself rather than documenting a
    prerequisite nobody will read.
    """
    if executable:
        return pw.chromium.launch(headless=True, executable_path=executable)
    try:
        return pw.chromium.launch(headless=True)
    except PlaywrightError as exc:
        # Only a missing-browser failure is worth a bootstrap; anything else must surface.
        if "Executable doesn't exist" not in str(exc) and "playwright install" not in str(exc):
            raise
        print("  [info] Chromium not present; running `playwright install chromium` once…")
        subprocess.run(
            [sys.executable, "-m", "playwright", "install", "chromium"],
            check=True,
        )
        return pw.chromium.launch(headless=True)


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


def main() -> int:
    ap = argparse.ArgumentParser(description="Rendered gate for a teachback explainer page.")
    ap.add_argument("page", type=Path)
    ap.add_argument("--browser", default=None, help="path to a Chromium executable")
    ap.add_argument("--settle-ms", type=int, default=3500, help="time to allow MathJax to typeset")
    args = ap.parse_args()

    url = args.page.resolve().as_uri()
    g = Gate()

    with sync_playwright() as pw:
        browser = launch_chromium(pw, args.browser)

        # ---------------------------------------------------------------- maths and colour
        g.section("RENDERED MATHEMATICS AND SEMANTIC COLOUR")
        colours: dict[str, dict[str, str]] = {}
        for scheme in ("light", "dark"):
            ctx = browser.new_context(viewport={"width": 1600, "height": 1100}, color_scheme=scheme)
            page = ctx.new_page()
            errors: list[str] = []
            offsite: list[str] = []
            page.on("pageerror", lambda e: errors.append(str(e)))
            page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
            page.on("request", lambda r: offsite.append(r.url) if is_offsite(r.url) else None)
            page.goto(url, wait_until="load")
            page.wait_for_timeout(args.settle_ms)

            if scheme == "light":
                containers = page.evaluate("()=>document.querySelectorAll('mjx-container').length")
                g.check("MathJax typeset the page", containers > 0, f"{containers} container(s)")
                g.check("no JavaScript console errors", not errors, "; ".join(errors[:2]))
                # A generated page is built from private working context; any off-allowlist request
                # is an exfiltration channel regardless of which API opened it.
                g.check(
                    "no request to an origin outside the allowlist",
                    not offsite,
                    "; ".join(sorted(set(offsite))[:3]) if offsite else "only the pinned CDN",
                )

            # Collect EVERY occurrence per role, not the last one. Storing a single colour per role
            # meant one occurrence rendered in the body colour was overwritten by the next and never
            # seen. And "every role differs from the body colour" is the claim — not "not all of
            # them do", which one black role among five satisfied.
            measured = page.evaluate(
                """()=>{const out={}; const base=getComputedStyle(document.body).color;
                     document.querySelectorAll('mjx-container [class*="%s"]').forEach(el=>{
                       const c=getComputedStyle(el).color;
                       el.classList.forEach(k=>{ if(k.startsWith('%s')) (out[k]=out[k]||[]).push(c); });
                     });
                     return {base: base, roles: out};}"""
                % (ROLE_PREFIX, ROLE_PREFIX)
            )
            base = measured["base"]
            per_role = {k: sorted(set(v)) for k, v in measured["roles"].items()}
            colours[scheme] = {k: v[0] for k, v in per_role.items()}

            inconsistent = [f"{k}={v}" for k, v in per_role.items() if len(v) > 1]
            g.check(
                f"{scheme}: each role renders in ONE colour everywhere",
                not inconsistent,
                "; ".join(inconsistent) if inconsistent else f"{len(per_role)} role(s)",
            )
            invisible = [k for k, v in per_role.items() if base in v]
            g.check(
                f"{scheme}: EVERY role differs from the body text colour",
                not invisible,
                f"{', '.join(sorted(invisible))} render as body text ({base})"
                if invisible
                else f"body {base}, all {len(per_role)} role(s) distinct from it",
            )
            distinct = len({v[0] for v in per_role.values()})
            g.check(
                f"{scheme}: every role resolves to a distinct colour",
                len(per_role) >= 3 and distinct == len(per_role),
                f"{len(per_role)} role(s), {distinct} distinct colour(s)",
            )
            ctx.close()

        g.check(
            "light and dark use different palettes",
            colours.get("light") != colours.get("dark"),
            "a hue chosen against white can vanish on near-black",
        )

        # PER EQUATION, FROM THE RENDERED OUTPUT. The static gate looks for the string "\class{sym-"
        # in each equation's source, which is a different claim from "this equation is visually
        # colour-coded": strip the wrappers and it fails, but neutralise the colour in CSS
        # (`color: inherit !important`) and the source still contains the string while the reader
        # sees undifferentiated black. Read the computed colours instead.
        ctx = browser.new_context(viewport={"width": 1600, "height": 1100})
        page = ctx.new_page()
        page.goto(url, wait_until="load")
        page.wait_for_timeout(args.settle_ms)
        flat = page.evaluate(
            """()=>{const base=getComputedStyle(document.body).color;
                 return [...document.querySelectorAll('div.eq')]
                   .filter(d=>d.querySelector('span.eqid'))
                   .map(d=>{
                     const syms=[...d.querySelectorAll('mjx-container [class*="sym-"]')];
                     const cols=new Set(syms.map(s=>getComputedStyle(s).color));
                     // ANY symbol matching the body colour is invisible as a role, even if its
                     // siblings are coloured. `every(...)` asked whether ALL of them were.
                     const bodyish=syms.filter(s=>getComputedStyle(s).color===base).length;
                     return {id:(d.querySelector('span.eqid').textContent||'?').trim(),
                             symbols:syms.length, distinct:cols.size, bodyish:bodyish};});}"""
        )
        uncoloured = [
            f"{e['id']}: {e['symbols']} symbol(s), {e['distinct']} colour(s), {e['bodyish']} in body colour"
            for e in flat
            if e["symbols"] == 0 or e["distinct"] < 2 or e["bodyish"] > 0
        ]
        g.check(
            "every numbered equation is visibly colour-coded in the RENDERED output",
            not uncoloured,
            "; ".join(uncoloured) if uncoloured else f"{len(flat)} equations, each with 2+ computed colours",
        )
        ctx.close()

        # ---------------------------------------------------------------- layout, measured
        g.section("LAYOUT (measured, not matched against CSS text)")
        ctx = browser.new_context(viewport={"width": 1600, "height": 1100})
        page = ctx.new_page()
        page.goto(url, wait_until="load")
        page.wait_for_timeout(args.settle_ms)

        ratio = page.evaluate(
            "()=>{const s=document.querySelector('.shell'); return s? s.getBoundingClientRect().width/window.innerWidth : 0;}"
        )
        g.check("shell occupies >=92% of the viewport", ratio >= 0.92, f"{ratio:.3f}")
        fills = page.evaluate(
            """()=>{const p=[...document.querySelectorAll('main p')].filter(e=>e.offsetParent!==null);
                 if(!p.length) return null;
                 const shell=document.querySelector('.shell').getBoundingClientRect().width;
                 const widest=Math.max(...p.map(e=>e.getBoundingClientRect().width));
                 return widest/shell;}"""
        )
        g.check(
            "body text fills the content column",
            fills is not None and fills >= 0.98,
            f"widest paragraph is {fills:.3f} of the shell" if fills else "no paragraphs found",
        )

        # Every direct child of a grid must be explicitly placed. An unplaced child auto-flows into
        # the next free cell — column 1 — which is how the revision ledger once rendered inside the
        # narrow contents rail. Asked of the RENDERED box, so CSS formatting cannot hide it.
        # Read the COMPUTED PLACEMENT, not the width. Inferring placement from width was vacuous in
        # the common case and wrong in the uncommon one: in a single-column grid every auto-flowed
        # child is full width and the check passed while nothing was placed, and a deliberately
        # narrow but explicitly placed child would have been reported as a fault.
        # `gridColumnStart` alone, deliberately. The previous predicate also required
        # `cs.gridArea.split('/')[1].trim() === 'auto'`, and Chromium computes gridArea for an
        # unplaced child as the single token "auto" — no slashes — so `split('/')[1]` is undefined
        # and `.trim()` THREW. The guard was therefore inoperative in the one situation it exists
        # for: it crashed instead of naming the unplaced child. It went unnoticed because `.shell`
        # is not a grid today (SKILL.md: "do not make .shell a grid"), so the early return meant the
        # predicate never ran. A guard that has never executed is not a guard.
        unplaced = page.evaluate(
            """()=>{const s=document.querySelector('.shell');
                 if(!s || getComputedStyle(s).display!=='grid') return [];
                 return [...s.children]
                   .filter(c=>getComputedStyle(c).gridColumnStart==='auto')
                   .map(c=>c.tagName.toLowerCase()+'.'+(c.getAttribute('class')||'').split(' ')[0]);}"""
        )
        is_grid = page.evaluate(
            "()=>{const s=document.querySelector('.shell'); return !!s && getComputedStyle(s).display==='grid';}"
        )
        g.check(
            "every grid child has an explicit grid-column",
            not unplaced,
            ", ".join(unplaced)
            if unplaced
            else ("shell is a grid, all children placed" if is_grid else "shell is not a grid"),
        )
        ctx.close()

        overflowing: list[str] = []
        for width in VIEWPORTS:
            ctx = browser.new_context(viewport={"width": width, "height": 900})
            page = ctx.new_page()
            page.goto(url, wait_until="load")
            page.wait_for_timeout(2200)
            over = page.evaluate("()=>document.documentElement.scrollWidth-window.innerWidth")
            if over > 0:
                offenders = page.evaluate(
                    """()=>{const vw=window.innerWidth;
                         const clipped=el=>{for(let a=el.parentElement;a&&a!==document.body;a=a.parentElement){
                           const o=getComputedStyle(a).overflowX; if(o==='auto'||o==='scroll'||o==='hidden') return true;} return false;};
                         return [...document.querySelectorAll('body *')]
                           .filter(e=>e.getBoundingClientRect().right>vw+1 && !clipped(e))
                           .map(e=>e.tagName.toLowerCase()+'.'+(e.getAttribute('class')||'').split(' ')[0])
                           .slice(0,3);}"""
                )
                overflowing.append(f"{width}px:+{over}px ({', '.join(offenders) or 'unattributed'})")
            ctx.close()
        g.check(
            f"no horizontal overflow at any of {len(VIEWPORTS)} viewports",
            not overflowing,
            "; ".join(overflowing) if overflowing else f"{VIEWPORTS[0]}px down to {VIEWPORTS[-1]}px",
        )

        # ---------------------------------------------------------------- interaction
        g.section("INTERACTION")
        ctx = browser.new_context(viewport={"width": 1500, "height": 1000})
        page = ctx.new_page()
        page.goto(url, wait_until="load")
        page.wait_for_timeout(args.settle_ms)

        if page.query_selector("#annotToggle"):
            before = page.evaluate(
                "()=>[...document.querySelectorAll('.reads')].filter(e=>e.offsetParent!==null).length"
            )
            page.click("#annotToggle")
            page.wait_for_timeout(300)
            after = page.evaluate(
                "()=>[...document.querySelectorAll('.reads')].filter(e=>e.offsetParent!==null).length"
            )
            g.check("annotation toggle hides the readings", before > 0 and after == 0, f"{before} -> {after}")
            # MEASURE THE COLOUR, not the element count. This asked only whether elements carrying a
            # sym- class still EXIST after the toggle, which is true of elements that are hidden, and
            # true of elements rendered in the body colour. `display:none` on every coloured symbol
            # left the count untouched and the check green — the same presence-for-property
            # substitution the static gate was corrected for, in the check whose entire subject is
            # whether the colour is still there.
            after_colour = page.evaluate(
                """()=>{const base=getComputedStyle(document.body).color;
                     const els=[...document.querySelectorAll('mjx-container [class*="sym-"]')];
                     const shown=els.filter(e=>e.getClientRects().length>0);
                     const cols=[...new Set(shown.map(e=>getComputedStyle(e).color))];
                     return {total: els.length, shown: shown.length, distinct: cols.length,
                             bodyish: shown.filter(e=>getComputedStyle(e).color===base).length};}"""
            )
            g.check(
                "colour survives the toggle",
                after_colour["shown"] > 0 and after_colour["distinct"] >= 2 and after_colour["bodyish"] == 0,
                f"{after_colour['shown']}/{after_colour['total']} still shown, "
                f"{after_colour['distinct']} distinct colour(s), {after_colour['bodyish']} in body colour",
            )
            g.check(
                "the notation key survives the toggle",
                page.evaluate(
                    "()=>[...document.querySelectorAll('.keychips .chip')].filter(e=>e.offsetParent!==null).length"
                )
                > 0,
                "hiding the only key strands the reader with an undocumented colour code",
            )
            page.click("#annotToggle")
            page.wait_for_timeout(200)
        else:
            g.check("annotation toggle present", False, "#annotToggle not found")

        # THE READER MUST NEVER BE LOCKED OUT — and that can only be observed AFTER solving.
        # Reading the initial disabled count proved nothing: code that disables the other options
        # only once the correct one is chosen is invisible before the question is answered. So drive
        # a question to the solved state first, then click a distractor and confirm it still speaks.
        # EVERY question, not just the first. Hard-coding qs[0] sampled the contract: a page could
        # handle question 1 correctly and lock out or ignore distractors in any later one and still
        # be certified. "The reader is never locked out" is a claim about the whole assessment.
        plan = page.evaluate(
            """()=>{const data=document.getElementById('assessment-data');
                 if(!data) return null;
                 return JSON.parse(data.textContent).questions.map(q=>{
                   const i=q.options.findIndex(o=>o.ok===true);
                   const ds=q.options.map((o,ix)=>[ix,o.fb||""]).filter((_,ix)=>q.options[ix].ok===false);
                   return {qid: q.id, index: i, distractors: ds};});}"""
        )
        if not plan:
            g.check("assessment data readable for the lock-out check", False, "no parseable assessment block")
        else:
            read_fb = """(qid)=>{const el=document.querySelector(`input[name='${qid}']`);
                 const q=el?el.closest('.q'):null; const fb=q?q.querySelector('.fb'):null;
                 return fb? (fb.textContent||'').trim() : null;}"""
            locked: list[str] = []
            silent: list[str] = []
            unreachable: list[str] = []
            for q in plan:
                qid = q["qid"]
                inputs = page.query_selector_all(f"input[name='{qid}']")
                indices = [q["index"], *[d[0] for d in q["distractors"]]]
                if q["index"] < 0 or not q["distractors"] or len(inputs) <= max(indices):
                    unreachable.append(str(qid))
                    continue
                # Guarded for the same reason as the distractor clicks below, and found the same way:
                # a page that disables inputs GLOBALLY once any question is solved leaves the second
                # question unclickable, so this line — not the distractor loop — was where the gate
                # spent 30 seconds and then died with a traceback instead of reporting the lock-out.
                try:
                    inputs[q["index"]].click(timeout=5000)
                except PlaywrightError:
                    locked.append(f"{qid}: the correct answer never became clickable")
                    continue
                page.wait_for_timeout(250)
                state = page.evaluate(
                    """(qid)=>{const i=[...document.querySelectorAll(`input[name='${qid}']`)];
                         return {disabled: i.filter(x=>x.disabled).length, total: i.length};}""",
                    qid,
                )
                if state["total"] == 0 or state["disabled"] > 0:
                    locked.append(f"{qid}: {state['disabled']}/{state['total']} disabled")
                    # STOP HERE for this question. The lock-out has been detected and recorded, and
                    # there is by definition nothing explorable left to click. Continuing cost the
                    # check its own verdict: `click()` on a disabled input waits for actionability,
                    # timed out after 30s, and raised — so the gate exited with a traceback and
                    # printed no result at all. A guard that detects the fault and then dies before
                    # reporting it is indistinguishable, to the caller, from a broken tool.
                    continue
                # EVERY distractor, not just the first. `findIndex(o => !o.ok)` returns index 0 of
                # three, so a handler that ignores the second or third one passed. The contract says
                # all three stay explorable, so all three are clicked.
                for d_index, d_fb in q["distractors"]:
                    # Capture the feedback FIRST. Asserting only that .fb is non-empty after the
                    # click accepts the stale message from the previous selection: a handler that
                    # ignores this distractor leaves the earlier text in place and passes.
                    before_fb = page.evaluate(read_fb, qid)
                    # A click that never becomes actionable is a RESULT — "this option is not
                    # explorable" — not an error. Left unguarded it aborts the whole gate on a
                    # 30-second actionability timeout, converting a reportable page defect into a
                    # traceback with no verdict.
                    try:
                        inputs[d_index].click(timeout=5000)
                    except PlaywrightError:
                        locked.append(f"{qid}: option {d_index} never became clickable")
                        continue
                    page.wait_for_timeout(220)
                    after_fb = page.evaluate(read_fb, qid)
                    # Match the FULL feedback string, not a 60-character prefix. The static gate
                    # requires whole fb strings to be unique but says nothing about their prefixes,
                    # so two distractors sharing 60 leading characters were indistinguishable here:
                    # showing the wrong one still satisfied "changed" and "contains the fragment".
                    # Full-string containment identifies the option exactly, precisely BECAUSE the
                    # static gate guarantees the full strings are unique.
                    want = str(d_fb or "")
                    shows_want = bool(want) and want in str(after_fb)
                    # And it must not be showing SOMEONE ELSE'S explanation as well.
                    others = [str(fb) for ix, fb in q["distractors"] if ix != d_index and str(fb) != want]
                    shows_other = any(o and o in str(after_fb) for o in others)
                    if not (after_fb and after_fb != before_fb and shows_want) or shows_other:
                        why = "shows another option's feedback" if shows_other else "wrong or unchanged feedback"
                        silent.append(f"{qid}[opt {d_index}]: {why} — {str(after_fb)[:50]!r}")

            g.check(
                f"after solving, no option is disabled in ANY of {len(plan)} questions",
                not locked,
                "; ".join(locked) if locked else f"{len(plan)} questions checked",
            )
            g.check(
                f"a distractor shows ITS OWN explanation after solving, in ANY of {len(plan)} questions",
                not silent,
                "; ".join(silent[:3]) if silent else f"{len(plan)} questions checked",
            )
            g.check("every question's options were reachable", not unreachable, ", ".join(unreachable))

        # OBSERVE THE STORAGE, DO NOT ARGUE ABOUT THE SYNTAX. The static gate bans computed global
        # access and runtime-built property keys, but that is a constraint on SHAPE: it closes the
        # spellings we thought of. This reads what the page ACTUALLY stored after being exercised —
        # every question answered and the annotation toggle flipped — so it does not matter whether
        # the code said localStorage.setItem, globalThis["local"+"Storage"], or something nobody has
        # proposed yet. If a second key exists, it is here.
        if page.query_selector("#annotToggle"):
            page.click("#annotToggle")
            page.wait_for_timeout(200)
            page.click("#annotToggle")
            page.wait_for_timeout(200)
        # ENUMERATE EVERY PERSISTENCE SURFACE, not a curated three. Reading localStorage,
        # sessionStorage and cookies left IndexedDB, the Cache API and the Origin Private File
        # System entirely unexamined — reader state written to any of them satisfied every storage
        # assertion. Chasing storage APIs one at a time is the same losing game as chasing Window
        # aliases was; ask the browser what actually persists.
        stored = page.evaluate(
            """async ()=>{
                 const out = {
                   local: Object.keys(localStorage),
                   session: Object.keys(sessionStorage),
                   cookies: document.cookie ? document.cookie.split(';').length : 0,
                   indexeddb: [], caches: [], opfs: []
                 };
                 try { if (indexedDB.databases) {
                   out.indexeddb = (await indexedDB.databases()).map(d=>d.name);
                 } } catch (e) { out.indexeddb = ['<unqueryable: ' + e.name + '>']; }
                 try { if (window.caches) { out.caches = await caches.keys(); } }
                 catch (e) { out.caches = ['<unqueryable: ' + e.name + '>']; }
                 try { if (navigator.storage && navigator.storage.getDirectory) {
                   const dir = await navigator.storage.getDirectory();
                   for await (const name of dir.keys()) { out.opfs.push(name); }
                 } } catch (e) { /* OPFS unavailable on this origin: nothing can be stored there */ }
                 return out;
               }"""
        )
        other_stores = {k: stored[k] for k in ("indexeddb", "caches", "opfs") if stored[k]}
        g.check(
            "no IndexedDB database, Cache Storage entry or OPFS file was created",
            not other_stores,
            "; ".join(f"{k}={v}" for k, v in other_stores.items()) if other_stores else "all three empty",
        )
        # EXACT SET, not a subset. `[k for k in keys if k != ANNOTATION_KEY]` is empty when keys is
        # EMPTY, so a page whose permitted write is dead code — or immediately removed — satisfied
        # the check by storing nothing at all. Absence passing as compliance is the same defect this
        # gate exists to catch, one level up.
        g.check(
            f'after exercising the page, localStorage holds exactly {{"{ANNOTATION_KEY}"}}',
            set(stored["local"]) == {ANNOTATION_KEY},
            f"found {sorted(stored['local']) or 'nothing'}",
        )
        g.check(
            "nothing was written to sessionStorage or cookies",
            not stored["session"] and stored["cookies"] == 0,
            f"session={stored['session']} cookies={stored['cookies']}",
        )

        # A key existing is still not the contract; the PREFERENCE PERSISTING is. Prove it by
        # surviving a reload in both directions, so a write that lands but is never read back —
        # or is read back and ignored — cannot pass.
        if page.query_selector("#annotToggle"):
            restored: list[str] = []
            for want_off in (True, False):
                is_off = page.evaluate("()=>document.body.classList.contains('no-annot')")
                if is_off != want_off:
                    page.click("#annotToggle")
                    page.wait_for_timeout(200)
                page.reload(wait_until="load")
                page.wait_for_timeout(1200)
                after = page.evaluate("()=>document.body.classList.contains('no-annot')")
                if after != want_off:
                    restored.append(f"chose {'off' if want_off else 'on'}, reloaded as {'off' if after else 'on'}")
            g.check(
                "the annotation choice survives a reload in both directions",
                not restored,
                "; ".join(restored) if restored else "off and on both restored",
            )
        ctx.close()
        browser.close()

    g.section("RESULT")
    print("ALL RENDERED CHECKS PASSED" if g.failures == 0 else f"{g.failures} CHECK(S) FAILED")
    return 0 if g.failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
