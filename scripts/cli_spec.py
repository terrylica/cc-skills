#!/usr/bin/env python3
"""Machine-readable CLI spec generator for cc-skills' Python skill CLIs (SSoT).

Realizes the cross-repo **CLI-first + machine-readable-docs** doctrine
(``~/.claude/cli-first-machine-readable-docs-CLAUDE.md``) for cc-skills (repo 2 of
the 4-repo rollout; repo 1 = ccmax-monitor). Emits a single repo-root
``cli_spec.json`` (JSON Schema 2020-12) so an AI coding agent can learn every
Python skill CLI's flags **without parsing ``--help`` prose**.

This is the same portable, stdlib-only, AST-based pattern shipped in ccmax-monitor
and opendeviationbar-patterns (the long-term de-dup is the cross-repo-promotion ADR;
until then each repo carries a near-identical copy so it stays self-contained):

- **AST-based, zero-import discovery.** cc-skills' skill CLIs build their parser
  inline; importing them would run side effects. We *parse each file's AST* (never
  execute it) and read the ``argparse.ArgumentParser(...)`` + ``.add_argument(...)``
  calls statically, so the extracted defaults are the *source literals*.
- **One command per file**, keyed by repo-relative path (CLIs live under
  ``plugins/*/skills/*/scripts/`` + the root ``scripts/`` dir); each
  ``.add_argument`` becomes a typed JSON-Schema property.
- cc-skills has no Go binary, so there is no ``x-go-cli`` pointer (unlike
  ccmax-monitor). TS/JS CLIs (bun) are a separate emitter, out of scope here.

The generator is itself a ``--output``/``--check`` CLI (CLI-first dogfooding)::

    uv run --python 3.14 --no-project python scripts/cli_spec.py --output cli_spec.json
    uv run --python 3.14 --no-project python scripts/cli_spec.py --check   # drift gate

A machine-readable parameter SSoT verified-against-source is a *no-silent-drift*
control: the drift+completeness gate (``scripts/test_cli_spec.py`` /
``mise run cli-spec-check``) fails if this file is stale or a CLI was added/removed.
"""

from __future__ import annotations

import argparse
import ast
import json
import sys
from pathlib import Path
from typing import Any

JSON_SCHEMA_DIALECT_2020_12 = "https://json-schema.org/draft/2020-12/schema"
CLI_SPEC_VERSION = "1"
GENERATED_BY = "scripts/cli_spec.py"
CANONICAL_OUTPUT_FILENAME = "cli_spec.json"

# Directories never scanned: VCS/vendored/build caches, generated output dirs, and
# the test harness (test files are not shipped CLIs even if a fixture builds a parser).
_EXCLUDE_DIR_NAMES = frozenset(
    {
        ".git",
        ".venv",
        "venv",
        "node_modules",
        "__pycache__",
        ".mypy_cache",
        ".ruff_cache",
        ".pytest_cache",
        "dist",
        "build",
        "target",
        "tests",
        "outputs",
        "tmp",
    }
)

_UNKNOWN = object()
_TYPE_NAME_TO_JSON_TYPE = {"int": "integer", "float": "number", "str": "string", "bool": "boolean"}


def repo_root() -> Path:
    """Return the repository root (``scripts/cli_spec.py`` -> up 2)."""
    return Path(__file__).resolve().parents[1]


def default_spec_output_path() -> Path:
    """Return the canonical repo-root ``cli_spec.json`` path."""
    return repo_root() / CANONICAL_OUTPUT_FILENAME


# --- literal extraction helpers (deterministic, source-only) -----------------


def _string_value(node: ast.expr | None) -> str | None:
    """Return the string for a literal/adjacent-concatenated/``a + b`` str node, else None."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _string_value(node.left)
        right = _string_value(node.right)
        if left is not None and right is not None:
            return left + right
    return None


def _constant_value(node: ast.expr | None) -> Any:
    """Return a Python literal for a constant node, else _UNKNOWN."""
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub) and isinstance(node.operand, ast.Constant):
        val = node.operand.value
        if isinstance(val, (int, float)):
            return -val
    return _UNKNOWN


def _enum_values(node: ast.expr | None) -> list[Any] | None:
    """Return the list of constant choices for a tuple/list/set ``choices=`` node, else None."""
    if isinstance(node, (ast.Tuple, ast.List, ast.Set)):
        values = [_constant_value(elt) for elt in node.elts]
        if all(v is not _UNKNOWN for v in values):
            return values
    return None


def _name_id(node: ast.expr | None) -> str | None:
    """Return the bare name of a ``Name`` node (``int`` -> 'int'), else None."""
    return node.id if isinstance(node, ast.Name) else None


# --- argparse AST -> JSON Schema ---------------------------------------------


def _is_argument_parser_call(node: ast.Call) -> bool:
    """True for ``argparse.ArgumentParser(...)`` or a bare ``ArgumentParser(...)`` call."""
    func = node.func
    if isinstance(func, ast.Attribute) and func.attr == "ArgumentParser":
        return True
    return isinstance(func, ast.Name) and func.id == "ArgumentParser"


def _argument_parser_description(tree: ast.AST) -> str | None:
    """Return the first ``ArgumentParser(description=...)`` literal description, else None."""
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and _is_argument_parser_call(node):
            for kw in node.keywords:
                if kw.arg == "description":
                    return _string_value(kw.value)
    return None


def _add_argument_calls(tree: ast.AST) -> list[ast.Call]:
    """Return every ``<parser>.add_argument(...)`` call node, in source order."""
    return [
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "add_argument"
    ]


def _json_type(kwargs: dict[str, ast.expr], action: str | None) -> str:
    """Infer the JSON Schema scalar type from action / type= / default literal."""
    if action in {"store_true", "store_false"}:
        return "boolean"
    if action == "count":
        return "integer"
    type_name = _name_id(kwargs.get("type"))
    if type_name in _TYPE_NAME_TO_JSON_TYPE:
        return _TYPE_NAME_TO_JSON_TYPE[type_name]
    default = _constant_value(kwargs.get("default"))
    if isinstance(default, bool):
        return "boolean"
    if isinstance(default, int):
        return "integer"
    if isinstance(default, float):
        return "number"
    return "string"


def _default_value(kwargs: dict[str, ast.expr], action: str | None) -> Any:
    """Return the literal default for the property, or _UNKNOWN if non-literal/absent."""
    if "default" in kwargs:
        return _constant_value(kwargs.get("default"))
    if action == "store_true":
        return False
    if action == "store_false":
        return True
    return _UNKNOWN


def _argument_to_property(call: ast.Call) -> tuple[str, dict[str, Any], bool] | None:
    """Map one ``add_argument(...)`` call to ``(key, json_schema_property, required)``."""
    positionals = [_string_value(arg) for arg in call.args]
    option_strings = [p for p in positionals if p and p.startswith("-")]
    positional_names = [p for p in positionals if p and not p.startswith("-")]

    kwargs = {kw.arg: kw.value for kw in call.keywords if kw.arg is not None}
    action = _string_value(kwargs.get("action"))
    dest = _string_value(kwargs.get("dest"))

    long_opts = [o for o in option_strings if o.startswith("--")]
    if long_opts:
        key = max(long_opts, key=len)
    elif option_strings:
        key = option_strings[0]
    elif positional_names:
        key = positional_names[0]
    elif dest:
        key = dest
    else:
        return None

    prop: dict[str, Any] = {"type": _json_type(kwargs, action)}

    help_text = _string_value(kwargs.get("help"))
    if help_text:
        prop["description"] = help_text

    default_val = _default_value(kwargs, action)
    if default_val is not _UNKNOWN and default_val is not None:
        prop["default"] = default_val

    enum_vals = _enum_values(kwargs.get("choices"))
    if enum_vals is not None:
        prop["enum"] = enum_vals

    if option_strings:
        prop["x-option-strings"] = option_strings
    if dest:
        prop["x-dest"] = dest
    if not option_strings and positional_names:
        prop["x-positional"] = True

    required = _constant_value(kwargs.get("required")) is True
    return key, prop, required


def build_command_schema(*, source: str, command_name: str) -> dict[str, Any]:
    """Parse Python ``source`` and build the JSON-Schema object for its argparse CLI."""
    tree = ast.parse(source)
    properties: dict[str, Any] = {}
    required: list[str] = []
    for call in _add_argument_calls(tree):
        result = _argument_to_property(call)
        if result is None:
            continue
        key, prop, is_required = result
        properties[key] = prop
        if is_required:
            required.append(key)

    schema: dict[str, Any] = {
        "type": "object",
        "title": command_name,
        "properties": properties,
        "additionalProperties": False,
    }
    description = _argument_parser_description(tree)
    if description:
        schema["description"] = description
    if required:
        schema["required"] = sorted(required)
    return schema


# --- repo scan + document assembly -------------------------------------------


def _file_builds_argument_parser(source: str) -> bool:
    """True if the source's AST contains an ``ArgumentParser(...)`` construction."""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return False
    return any(isinstance(node, ast.Call) and _is_argument_parser_call(node) for node in ast.walk(tree))


def discover_argparse_files(root: Path) -> list[Path]:
    """Return every ``.py`` under ``root`` that builds an argparse parser, path-sorted."""
    found: list[Path] = []
    for path in root.rglob("*.py"):
        # Skip vendored/build/test dirs (by name) and ANY hidden (dot-prefixed) directory
        # component, e.g. Swift-PM `.build/checkouts/` third-party Python helpers. The
        # filename itself (last part) is not subjected to the dot check.
        dir_parts = path.relative_to(root).parts[:-1]
        if any(part in _EXCLUDE_DIR_NAMES or part.startswith(".") for part in dir_parts):
            continue
        try:
            source = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if _file_builds_argument_parser(source):
            found.append(path)
    return sorted(found, key=lambda p: p.relative_to(root).as_posix())


def build_cli_spec_document(root: Path) -> dict[str, Any]:
    """Build the full ``cli_spec.json`` document for the repo's Python CLI surface."""
    commands: dict[str, Any] = {}
    for path in discover_argparse_files(root):
        rel = path.relative_to(root).as_posix()
        commands[rel] = build_command_schema(source=path.read_text(encoding="utf-8"), command_name=rel)

    return {
        "$schema": JSON_SCHEMA_DIALECT_2020_12,
        "x-spec-version": CLI_SPEC_VERSION,
        "x-generated-by": GENERATED_BY,
        "x-note": (
            "Machine-readable SSoT of every Python argparse CLI in cc-skills (skill "
            "helper scripts under plugins/*/skills/*/scripts/ + the root scripts/ dir), "
            "for AI-agent introspection. Regenerate with `mise run cli-spec`; the drift+"
            "completeness gate (scripts/test_cli_spec.py / `mise run cli-spec-check`) "
            "fails if this is stale or a CLI was added/removed without regenerating."
        ),
        "commands": commands,
    }


def serialize_spec_document(document: dict[str, Any]) -> str:
    """Serialize deterministically (sorted keys, 2-space indent, trailing LF)."""
    return json.dumps(document, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


# --- CLI entry point (CLI-first dogfooding) ----------------------------------


def build_arg_parser() -> argparse.ArgumentParser:
    """Build the generator's own argument parser (itself reflected into the spec)."""
    parser = argparse.ArgumentParser(
        prog="scripts/cli_spec.py",
        description="Generate / verify cc-skills' machine-readable Python cli_spec.json SSoT.",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output path for cli_spec.json (default: repository-root cli_spec.json).",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Drift gate: regenerate in-memory and exit non-zero if the committed file is stale.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Generate (or ``--check``) the canonical ``cli_spec.json``."""
    args = build_arg_parser().parse_args(argv)
    root = repo_root()
    output_path = Path(args.output) if args.output is not None else default_spec_output_path()
    document = build_cli_spec_document(root)
    expected = serialize_spec_document(document)
    n_cmds = len(document["commands"])

    if args.check:
        if not output_path.exists():
            print(f"[cli_spec] MISSING: {output_path} does not exist; run `mise run cli-spec`.")
            return 1
        if output_path.read_text(encoding="utf-8") != expected:
            print(f"[cli_spec] STALE: {output_path} differs from generated spec; run `mise run cli-spec`.")
            return 1
        print(f"[cli_spec] OK: {output_path} is current ({n_cmds} Python CLIs).")
        return 0

    output_path.write_text(expected, encoding="utf-8")
    print(f"[cli_spec] wrote {output_path} ({n_cmds} Python CLIs).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
