#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["pytest>=8.0.0", "beautifulsoup4>=4.13"]
# ///
"""The teachback coverage audit must find EVERY `.check(...)` call, however its label is built.

The audit exists to list checks that no mutation exercises. Its first implementation — written in
Eon-Labs/alpha-forge#527, where this skill was originally built before being promoted to this
marketplace repo — discovered them with a regex that accepted only a literal double-quoted first
argument, so nine call sites whose label is an f-string were missing from the numerator, the
denominator and the "no mutation" list at once — an instrument built to find silently-omitted
checks, silently omitting checks. It reported a total of 88 where there were 98.

These tests pin the structural discovery that replaced it. They are deliberately about the SHAPES a
label can take, not about today's counts, which change whenever a check is added.
"""

from __future__ import annotations

import ast
import importlib.util
import pathlib
import sys

import pytest

# This module lives at <skill>/tests/, so the gates sit in its parent directory:
# parents[0] == <skill>/tests, parents[1] == <skill>.
SKILL = pathlib.Path(__file__).resolve().parents[1]
MUTATE_GATE = SKILL / "mutate_gate.py"

pytestmark = pytest.mark.skipif(not MUTATE_GATE.exists(), reason="teachback skill not present in this checkout")


def _load():
    """Import mutate_gate.py by path. It is a PEP 723 script, not an installed module."""
    spec = importlib.util.spec_from_file_location("teachback_mutate_gate", MUTATE_GATE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


SOURCE = """
class G:
    def check(self, label, ok=True, detail=""): ...

g = G()
scheme = "dark"
plan = [1, 2, 3]
KEY = "teachback:annotations"
LABEL_FROM_A_VARIABLE = "computed elsewhere"

g.check("a plain literal label", True)
g.check(f"{scheme}: interpolation at the START", True)
g.check(f"an interpolation in the MIDDLE of {len(plan)} items", True)
g.check(f'localStorage stores only "{KEY}"', True)
g.check(LABEL_FROM_A_VARIABLE, True)
g.check(
    "a literal split across lines",
    True,
)
"""


def test_every_call_site_is_found_regardless_of_label_shape():
    sites = _load().discover_checks(SOURCE)
    assert len(sites) == 6, [s.label for s in sites]


def test_f_string_labels_keep_their_literal_text_for_matching():
    labels = [s.label for s in _load().discover_checks(SOURCE)]
    assert "{}: interpolation at the START" in labels
    assert "an interpolation in the MIDDLE of {} items" in labels
    assert 'localStorage stores only "{}"' in labels


def test_a_label_that_cannot_be_known_statically_is_null_not_omitted():
    """Unknown must not read as satisfied, and must not vanish from the denominator either."""
    sites = _load().discover_checks(SOURCE)
    unknown = [s for s in sites if s.label is None]
    assert len(unknown) == 1
    assert unknown[0].expression == "LABEL_FROM_A_VARIABLE"


def test_a_purely_interpolated_label_is_treated_as_unknown():
    module = _load()
    node = ast.parse('f"{x}"', mode="eval").body
    assert module.static_label(node) is None


def test_the_real_gates_contain_f_string_labels_that_discovery_finds():
    """A regression guard on the actual defect: the gates DO use f-string labels."""
    module = _load()
    for gate in ("verify_explainer.py", "verify_rendered.py"):
        sites = module.discover_checks((SKILL / gate).read_text())
        assert sites, gate
        interpolated = [s for s in sites if s.label and "{}" in s.label]
        assert interpolated, f"{gate} has no f-string labels; this test no longer guards the defect"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
