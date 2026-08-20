# doc-tools Plugin

> Comprehensive documentation: ASCII diagrams, markdown standards, LaTeX build, Pandoc PDF generation.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [plugin-dev CLAUDE.md](../plugin-dev/CLAUDE.md)

## Skills

- [academic-pdf-to-gfm](./skills/academic-pdf-to-gfm/SKILL.md)
- [ascii-diagram-validator](./skills/ascii-diagram-validator/SKILL.md)
- [documentation-standards](./skills/documentation-standards/SKILL.md)
- [glossary-management](./skills/glossary-management/SKILL.md)
- [markdown-table-validator](./skills/markdown-table-validator/SKILL.md) — detect/fix GFM tables that won't render (unescaped pipes, column mismatch); manual counterpart to the `itp-hooks` per-edit table guard
- [latex-build](./skills/latex-build/SKILL.md)
- [latex-setup](./skills/latex-setup/SKILL.md)
- [latex-tables](./skills/latex-tables/SKILL.md)
- [pandoc-pdf-generation](./skills/pandoc-pdf-generation/SKILL.md)
- [plotext-financial-chart](./skills/plotext-financial-chart/SKILL.md)
- [teachback](./skills/teachback/SKILL.md) — single-file interactive HTML explainer (MathJax 3, exploratory assessment, terminology loop); ships three PEP 723 gates: `verify_explainer.py` (static), `verify_rendered.py` (headless browser), `mutate_gate.py` (negative fixtures)
- [terminal-print](./skills/terminal-print/SKILL.md)

## Conventions

- Merged from `doc-tools` + `doc-build-tools` plugins
- Hub-and-spoke progressive disclosure patterns
- Section numbering rules for Pandoc PDF generation

## teachback invariants (do not break)

- **Gates are PEP 723 scripts, invoked with `uv run --no-project --script`.** Document that spelling,
  but do **not** repeat the rationale this file originally carried. It claimed `--no-project` was
  load-bearing because plain `uv run` adopts the surrounding uv workspace; that was inferred from a
  `DEBUG Found workspace root:` line — which reports discovery, not adoption — and measurement
  refutes it. On uv 0.11.28, run from a directory whose `pyproject.toml` declares an unresolvable
  dependency (fixture first confirmed hostile: a plain `uv run python -c ...` there fails to
  resolve), all of `uv run`, `uv run --script` and `uv run --no-project --script` reached the gate's
  argparse. uv reports `--no-project is a no-op for Python scripts with inline metadata; ignoring`.
  Keep the flag — it is free, it is correct for non-PEP-723 invocations such as `uv run pytest`,
  which genuinely does resolve an enclosing project, and it stays correct if a gate ever loses its
  inline metadata. `mutate_gate.py` spawns its children without the flag; that is consistent with
  the above and is deliberately left alone, because editing it would break the property that the
  promoted gates are AST-identical to the alpha-forge originals.
- **The skill directory is resolved at call time with `cc-plugin-root doc-tools`**, which prints the
  live install path. The CLAUDE_PLUGIN_ROOT placeholder (named here without a dollar sign
  deliberately) is **not** a shell variable — Claude Code substitutes it only inside plugin manifests
  and injects it only into hook and MCP subprocesses, never into the Bash tool. Spelled in a skill
  body it expands to empty and yields an absolute-looking `/skills/teachback/...` that reads like a
  missing file rather than a missing variable. Globbing the plugin version cache is not a fallback:
  it retains orphaned versions and the highest semver is routinely not the live one.
- **teachback pages are single-file and CSP-locked, with exactly one permitted remote origin.** They
  are **not** zero-network, and an earlier draft of this bullet said they were. The truth, read off
  the gates rather than off intent: `verify_rendered.py:45` sets
  `ALLOWED_ORIGINS = ("https://cdn.jsdelivr.net",)` and its check is labelled _"no request to an
  origin outside the allowlist"_, passing with the detail _"only the pinned CDN"_ — so the gate
  permits a request, it does not forbid all of them. That request is the version-pinned, SRI-hashed
  MathJax bundle, which SKILL.md mandates; a page needing true zero-network pre-renders the
  mathematics to SVG instead. The two layers are also easy to invert, so state them separately: the
  **CSP** names an **origin** and `verify_explainer.py:527` checks only _"CSP allows at most one
  remote origin"_, while the **exact-URL** pin (`ALLOWED_REMOTE_URL`, `verify_explainer.py:62`) is
  enforced against the **markup reference** at `:574`. Rewriting `font-src` to the `.js` URL — the
  error the inverted wording invites — silently breaks MathJax's web-font fetches. The privacy
  control is the deny-by-default policy plus that single audited exception, not an absence of
  requests. **Never wire teachback to the `html-showcase` CDN CSS kernel** or any other shared
  stylesheet: a second origin fails the CSP check outright.
- **Layout invariants belong to the rendered gate only.** Matching CSS source text is unsound —
  `.shell{display:grid` matches while the equivalent `.shell { display: grid; }` does not. Do not
  move a layout assertion into the static gate.
- **Provenance**: built in [Eon-Labs/alpha-forge](https://github.com/Eon-Labs/alpha-forge) and merged
  there as PR #527 after eleven review rounds; promoted here 2026-08-20. **This copy is canonical —
  edit it here.** The alpha-forge path `.claude/skills/teachback/` is to be reduced to a redirect stub
  carrying no gate scripts; until that lands, two full copies exist and only this one is authoritative.
  If you find yourself editing the alpha-forge copy, stop and edit this one.
