# pyi-stub-guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Hook: [`pretooluse-pyi-stub-guard.ts`](../hooks/pretooluse-pyi-stub-guard.ts), subhook `pyi-stub-guard` of the [PreToolUse Write/Edit orchestrator](./pretooluse-write-edit-orchestrator.md) (timeout 3000 ms).

Despite the file name, this guard is about package init files, not `.pyi` stubs in general: it keeps `__init__.py` and `__init__.pyi` thin re-export layers. Definitions belong in dedicated modules (`models.py`, `utils.py`, `constants.pyi`, …).

## What it blocks

A Write or Edit of a path ending in `__init__.py` or `__init__.pyi` whose new text (`content` for Write, `new_string` for Edit) has an unindented:

- `class Name…` definition,
- `def name(` or `async def name(` definition, or
- `@overload`, `@dataclass_transform` or `@final` decorator.

The scan ignores comment lines, indented lines, and text inside triple-quoted docstrings. The deny message lists at most five violations and suggests where each definition should live.

## Exemptions

- **Boilerplate** (`__init__.py` only; `__init__.pyi` follows the stricter PEP 561 rules): `def __getattr__(`, `def __dir__(`, `def __init_subclass__(` and `def _lazy_import(` — the PEP 562 lazy-import pattern.
- **Re-export-dominated Write**: if more than 70% of the non-blank, non-comment lines are `from …`/`import …` lines, the write is allowed. This applies to Write only, because an Edit's `new_string` is a fragment.
- **Escape hatch**: `# INIT-MONOLITH-OK` anywhere in the new text.

## Code

The classifier is `classifyInitFileTopLevelDefinitionMonolithGuardForOrchestrator`, exported to the orchestrator under the alias `classifyPyiStubGuardForOrchestrator`. The file also runs standalone (`bun pretooluse-pyi-stub-guard.ts < payload.json`) through its `import.meta.main` guard.
