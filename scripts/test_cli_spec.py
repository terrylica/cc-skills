"""Drift + completeness gate for cc-skills' machine-readable Python ``cli_spec.json`` SSoT.

Same CLI-first doctrine gate as ccmax-monitor / opendeviationbar-patterns: the
committed ``cli_spec.json`` must equal a fresh regeneration (no stale spec), and
every Python ``argparse`` CLI in the repo must be represented (no silent omission
when a skill CLI is added/removed). Fast (<2s), stdlib-only, no network.

Run via ``mise run cli-spec-check`` or
``uv run --python 3.14 --no-project --with pytest pytest scripts/test_cli_spec.py``.
Regenerate the spec with ``mise run cli-spec``.
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[1]
_GENERATOR_PATH = _REPO_ROOT / "scripts" / "cli_spec.py"
_SPEC_PATH = _REPO_ROOT / "cli_spec.json"


def _load_generator():
    """Load ``scripts/cli_spec.py`` by path (cc-skills is not an importable package)."""
    spec = importlib.util.spec_from_file_location("ccskills_cli_spec_generator", _GENERATOR_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_GEN = _load_generator()


def test_cli_spec_json_exists() -> None:
    assert _SPEC_PATH.exists(), "cli_spec.json missing; run `mise run cli-spec`."


def test_cli_spec_json_is_not_stale() -> None:
    """The committed cli_spec.json must equal a fresh in-memory regeneration."""
    expected = _GEN.serialize_spec_document(_GEN.build_cli_spec_document(_REPO_ROOT))
    actual = _SPEC_PATH.read_text(encoding="utf-8")
    assert actual == expected, "cli_spec.json is stale; run `mise run cli-spec` and commit the diff."


def test_every_argparse_cli_is_represented() -> None:
    """Completeness: every discovered argparse CLI appears in the spec (no silent omission)."""
    discovered = {p.relative_to(_REPO_ROOT).as_posix() for p in _GEN.discover_argparse_files(_REPO_ROOT)}
    document = json.loads(_SPEC_PATH.read_text(encoding="utf-8"))
    assert discovered == set(document["commands"]), (
        "Discovered argparse CLIs differ from cli_spec.json commands; run `mise run cli-spec`."
    )
    assert discovered, "Expected to discover at least one argparse CLI."


def test_no_hidden_or_vendored_dirs_leak_in() -> None:
    """Discovery must exclude .build/checkouts, node_modules, and other dot-dirs."""
    document = json.loads(_SPEC_PATH.read_text(encoding="utf-8"))
    for name in document["commands"]:
        parts = name.split("/")[:-1]  # directory components only
        assert not any(p.startswith(".") for p in parts), f"{name}: hidden-dir command leaked in"
        assert "node_modules" not in parts, f"{name}: node_modules command leaked in"


def test_spec_declares_json_schema_2020_12_dialect() -> None:
    document = json.loads(_SPEC_PATH.read_text(encoding="utf-8"))
    assert document["$schema"] == _GEN.JSON_SCHEMA_DIALECT_2020_12


def test_each_command_is_an_object_schema() -> None:
    document = json.loads(_SPEC_PATH.read_text(encoding="utf-8"))
    for name, schema in document["commands"].items():
        assert schema["type"] == "object", f"{name}: command schema must be type=object"
        assert "properties" in schema, f"{name}: command schema must declare properties"
        assert schema["additionalProperties"] is False, f"{name}: must forbid additionalProperties"


def test_property_types_are_json_schema_scalars() -> None:
    allowed = {"string", "integer", "number", "boolean"}
    document = json.loads(_SPEC_PATH.read_text(encoding="utf-8"))
    for name, schema in document["commands"].items():
        for prop_name, prop in schema["properties"].items():
            assert prop["type"] in allowed, f"{name}.{prop_name}: type {prop['type']!r} not a JSON scalar"


def test_serialization_is_deterministic_and_sorted() -> None:
    document = _GEN.build_cli_spec_document(_REPO_ROOT)
    first = _GEN.serialize_spec_document(document)
    second = _GEN.serialize_spec_document(document)
    assert first == second
    assert first.endswith("\n")
    assert json.loads(first) == document


def test_check_mode_passes_on_committed_spec() -> None:
    """`cli_spec.py --check` returns 0 when the committed file is current."""
    assert _GEN.main(["--check"]) == 0
