---
name: setup
description: "Install and verify the graphify engine (uv tool install graphifyy). Use for first-time setup, upgrades, or when the graphify CLI is missing/broken. TRIGGERS - install graphify, graphify setup, setup knowledge graph tool, graphify not found."
allowed-tools: Read, Bash, Glob, AskUserQuestion
---

# Graphify Setup

Install the [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) engine as an isolated uv tool and verify it works.

> **Naming gotcha**: the PyPI package is `graphifyy` (double-y, temporary while the `graphify` name is reclaimed). The CLI binary is still `graphify`. Do not `uv tool install graphify` — wrong package.

## Steps

### 1. Check current state

```bash
command -v graphify && graphify --version
uv tool list | grep -i graphifyy
```

If installed and healthy → report version and stop (idempotent).

### 2. Install (uv-first policy — never pip/pipx)

```bash
uv tool install "graphifyy[anthropic,gemini]"
```

**Install WITH the LLM-backend extras** — the bare package does AST-only extraction; semantic extraction of docs/images fails at runtime with "the 'anthropic'/'openai' package is required" (verified 2026-07-07). The `[anthropic]` extra enables `--backend claude`, `[gemini]` enables `--backend gemini` (uses the `openai` package under the hood).

Requires Python 3.10+; `uv tool` provisions its own interpreter, so the host repo's pinned Python is never touched (pin-wins rule unaffected).

Upgrade path:

```bash
uv tool upgrade graphifyy
```

### 3. Verify

```bash
graphify --version
graphify --help | head -20
```

Both must succeed. If `graphify` is not on PATH, run `uv tool update-shell` and re-source the shell profile.

### 4. Optional: register the Claude Code skill command

The engine ships its own `/graphify` skill installer:

```bash
graphify install
```

This writes `~/.claude/skills/graphify/SKILL.md`. **Skip by default** — this plugin's `build-graph` skill already wraps the CLI; installing both creates two overlapping invocation paths. Only run it if the operator explicitly wants the upstream `/graphify` command too.

## Failure modes

| Symptom                                                   | Fix                                                                                                                                                                                                                 |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `uv: command not found`                                   | mise provides uv globally; run `mise install` or check `~/.zshrc` mise activation                                                                                                                                   |
| `graphify` not on PATH after install                      | `uv tool update-shell`, then restart shell                                                                                                                                                                          |
| Installed `graphify` package by mistake                   | `uv tool uninstall graphify && uv tool install "graphifyy[anthropic,gemini]"`                                                                                                                                       |
| "the 'anthropic'/'openai' package is required" at runtime | Extras missing: `uv tool install "graphifyy[anthropic,gemini]" --force`                                                                                                                                             |
| `--backend claude` → HTTP 426 `wrapper_version_too_old`   | This fleet routes `ANTHROPIC_BASE_URL` through doorward, which rejects direct SDK calls lacking the `X-Ccmax-Wrapper-Version` header. Use `--backend gemini` (GEMINI_API_KEY is in the env) — see build-graph skill |
