# Meta-Prompt: Autonomous Polyglot Monorepo Bootstrap

> **Role**: You are a Principal Software Architect specializing in AI-native monorepo design.
> **Mission**: Construct a production-grade polyglot monorepo from scratch, optimized for agentic workflows with Claude Code CLI.
> **Constraint**: The human will not touch any code. You execute everything autonomously, verifying at each phase.

---

## Tooling Stack: Pants + mise

This bootstrap uses **Pants + mise** for 10-50 Python-heavy polyglot packages:

| Tool      | Responsibility                                                         |
| --------- | ---------------------------------------------------------------------- |
| **mise**  | Runtime versions (Python, Node, Rust) + environment variables          |
| **Pants** | Build orchestration + native affected detection + dependency inference |

→ See [polyglot-affected.md](./polyglot-affected.md) for tool comparison and scaling guidance

---

## Phase 0: Pre-Flight Verification

Before creating any files, verify the environment:

```bash
# Check required tools exist
command -v mise && mise --version
command -v git && git --version
command -v cargo && cargo --version
command -v uv && uv --version
command -v bun && bun --version
command -v pants && pants --version
```

If any tool is missing, install via mise (Pants via pip):

```bash
mise use -g rust@latest python@3.12 node@lts bun@latest uv@latest
pip install pantsbuild.pants
```

Create project root and initialize git:

```bash
mkdir -p ~/projects/hft-monorepo && cd ~/projects/hft-monorepo
git init
```

---

## Phase 1: Foundational Structure

Create the canonical directory structure for a polyglot HFT monorepo:

```
hft-monorepo/
├── CLAUDE.md                    # Hub: Link Farm root (this file)
├── mise.toml                    # Orchestrator: tools + env vars
├── pants.toml                   # Build system: orchestration + affected
├── BUILD                        # Root BUILD file
├── .mise/                       # Mise local config
├── .mcp.json                    # MCP server configuration
├── docs/                        # Deep documentation (spoke)
│   ├── ARCHITECTURE.md
│   ├── LOGGING.md
│   ├── TESTING.md
│   └── WORKFLOWS.md
├── skills/                      # Claude Code skill modules (spoke)
│   ├── python/
│   │   └── SKILL.md
│   ├── rust/
│   │   └── SKILL.md
│   └── bun/
│       └── SKILL.md
├── packages/                    # Polyglot packages
│   ├── core-python/             # Python: shared utilities
│   │   ├── CLAUDE.md            # Child hub
│   │   ├── BUILD                # Pants target: python_sources()
│   │   ├── pyproject.toml
│   │   └── src/
│   ├── core-rust/               # Rust: performance-critical
│   │   ├── CLAUDE.md            # Child hub
│   │   ├── BUILD                # Pants target: cargo_package()
│   │   ├── Cargo.toml
│   │   └── src/
│   ├── core-bun/                # Bun: async I/O, APIs
│   │   ├── CLAUDE.md            # Child hub
│   │   ├── BUILD                # Pants target: javascript_sources()
│   │   ├── package.json
│   │   └── src/
│   └── shared-types/            # Cross-language type definitions
│       ├── CLAUDE.md
│       ├── BUILD
│       └── schemas/
├── services/                    # Deployable services
│   ├── data-ingestion/
│   │   ├── CLAUDE.md
│   │   └── BUILD
│   ├── strategy-engine/
│   │   ├── CLAUDE.md
│   │   └── BUILD
│   └── execution-gateway/
│       ├── CLAUDE.md
│       └── BUILD
└── logs/                        # Local log output (gitignored)
```

Execute creation:

```bash
mkdir -p docs skills/{python,rust,bun} packages/{core-python/src,core-rust/src,core-bun/src,shared-types/schemas} services/{data-ingestion,strategy-engine,execution-gateway} logs
touch .gitignore BUILD
```

---

## Phase 2: Root CLAUDE.md — The Hub

Create the root `CLAUDE.md` as the Link Farm hub with Progressive Disclosure:

```markdown
# HFT Polyglot Monorepo

> **Navigation**: This file is the single entry point. Each section links to deeper documentation. Child directories contain their own `CLAUDE.md` files that Claude loads on-demand.

## Quick Reference

| Action         | Command                                       |
| -------------- | --------------------------------------------- |
| Build affected | `pants --changed-since=origin/main package`   |
| Test affected  | `pants --changed-since=origin/main test`      |
| Lint all       | `pants lint ::`                               |
| Generate BUILD | `pants tailor`                                |
| Search code    | Use `ck` MCP tool: `semantic_search("query")` |

## Architecture Overview

**Stack**: Python (uv) · Rust (cargo) · Bun · Pants (build) · Mise (runtimes)
**Pattern**: Polyglot monorepo with independent semantic versioning
**AI Interface**: Claude Code CLI via MCP servers

→ Deep dive: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Package Map

| Package        | Language | Purpose                       | Entry                                                              |
| -------------- | -------- | ----------------------------- | ------------------------------------------------------------------ |
| `core-python`  | Python   | Shared utilities, data models | [packages/core-python/CLAUDE.md](packages/core-python/CLAUDE.md)   |
| `core-rust`    | Rust     | Performance-critical compute  | [packages/core-rust/CLAUDE.md](packages/core-rust/CLAUDE.md)       |
| `core-bun`     | Bun/TS   | Async I/O, HTTP APIs          | [packages/core-bun/CLAUDE.md](packages/core-bun/CLAUDE.md)         |
| `shared-types` | Multi    | Cross-language schemas        | [packages/shared-types/CLAUDE.md](packages/shared-types/CLAUDE.md) |

## Workflow Protocol

When modifying code in this repo:

1. **Explore** — Read the relevant `CLAUDE.md` in the target directory
2. **Search** — Use `semantic_search` MCP tool to find related code
3. **Affected** — Run `pants --changed-since=origin/main list` to identify impacted targets
4. **Plan** — State approach before editing (ultrathink if complex)
5. **Implement** — Make changes, running `pants lint` after each file
6. **Test** — Run `pants --changed-since=origin/main test` before committing
7. **Verify** — Confirm logs emit correctly to `logs/`

→ Deep dive: [docs/WORKFLOWS.md](docs/WORKFLOWS.md)
```

---

## Phase 3: Configuration Files

### pants.toml

```toml
# SSoT-OK: placeholder versions for documentation
[GLOBAL]
pants_version = "<version>"
backend_packages = [
    "pants.backend.python",
    "pants.backend.python.lint.ruff",
    "pants.backend.experimental.rust",
    "pants.backend.experimental.javascript",
]

[python]
interpreter_constraints = [">=3.12"]

[source]
root_patterns = ["packages/*", "services/*"]

[python-bootstrap]
search_path = ["<PATH>"]

[anonymous-telemetry]
enabled = false
```

### mise.toml

```toml
[env]
LOG_DIR = "{{config_root}}/logs"
ENV = "dev"
PANTS_CONCURRENT = "true"

# SSoT-OK: placeholder versions for documentation
[tools]
python = "<version>"
rust = "<version>"
node = "<version>"
bun = "<version>"
uv = "<version>"

# Convenience wrappers for Pants commands
[tasks."test:affected"]
description = "Test affected packages via Pants"
run = "pants --changed-since=origin/main test"

[tasks."lint:affected"]
description = "Lint affected packages via Pants"
run = "pants --changed-since=origin/main lint"

[tasks.lint]
description = "Lint all packages"
run = "pants lint ::"

[tasks.test]
description = "Test all packages"
run = "pants test ::"

[tasks.affected]
description = "List packages affected by git changes"
run = "pants --changed-since=origin/main list"

[tasks."pants:tailor"]
description = "Generate BUILD files"
run = "pants tailor"
```

### pyproject.toml (example for core-python)

```toml
# SSoT-OK: example project configuration
[project]
name = "core-python"
version = "<version>"
requires-python = ">=3.12"
dependencies = [
    "loguru",
    "platformdirs",
    "pydantic",
]

[tool.uv]
dev-dependencies = [
    "pytest",
    "pytest-asyncio",
    "ruff",
]
```

### BUILD Files (Auto-generated by `pants tailor`)

```python
# packages/core-python/BUILD
python_sources()
python_tests()

# packages/core-rust/BUILD
cargo_package()

# packages/core-bun/BUILD
javascript_sources()
javascript_tests()
```

### .mcp.json

```json
{
  "mcpServers": {
    "mise": {
      "command": "mise",
      "args": ["mcp"],
      "env": {
        "MISE_EXPERIMENTAL": "1"
      }
    },
    "code-search": {
      "command": "ck",
      "args": ["--serve"],
      "cwd": "."
    },
    "shell": {
      "command": "uvx",
      "args": ["mcp-shell-server"],
      "env": {
        "ALLOW_COMMANDS": "mise,git,jq,pants,cargo,uv,bun,cat,ls,grep,head,tail,find"
      }
    }
  }
}
```

### .gitignore

```gitignore
# Logs
logs/
*.jsonl

# Dependencies
node_modules/
target/
.venv/
__pycache__/
*.pyc

# Build outputs
dist/
build/
*.egg-info/

# Pants
.pants.d/
.pids/

# IDE
.idea/
.vscode/
*.swp

# OS
.DS_Store
Thumbs.db

# Mise
.mise.local.toml

# Secrets (never commit)
.env.local
*.key
*.pem
```

---

## Phase 4: Verification Checklist

After creating all files, verify the setup:

```bash
# 1. Directory structure
find . -name "CLAUDE.md" -o -name "BUILD" | head -20

# 2. Mise configuration
mise doctor
mise tasks

# 3. Pants configuration
pants --version
pants tailor          # Generate BUILD files if needed
pants list ::         # List all targets

# 4. Affected detection (Pants native)
pants --changed-since=origin/main list

# 5. MCP configuration
cat .mcp.json | jq .

# 6. Log directory
mkdir -p logs
ls -la logs/

# 7. Git status
git status
git add -A
git commit -m "chore: initial monorepo scaffold with Pants + mise"
```

---

## Phase 5: Post-Bootstrap Tasks

Once the scaffold is complete, initialize each package:

### Python Package

```bash
cd packages/core-python
uv init
uv add loguru platformdirs pydantic
uv add --dev pytest pytest-asyncio ruff
pants tailor  # Generate BUILD file
```

### Rust Package

```bash
cd packages/core-rust
cargo init --lib
# Add dependencies to Cargo.toml per skill guide
pants tailor  # Generate BUILD file
```

### Bun Package

```bash
cd packages/core-bun
bun init -y
bun add pino zod
bun add -d @biomejs/biome @types/bun
pants tailor  # Generate BUILD file
```

---

## Success Criteria

The bootstrap is complete when:

- [ ] All `CLAUDE.md` files exist and link correctly
- [ ] `pants list ::` shows all targets
- [ ] `pants --changed-since=origin/main list` runs without error
- [ ] `mise tasks` shows convenience wrappers
- [ ] `.mcp.json` is valid JSON
- [ ] Each package has BUILD file
- [ ] `logs/` directory exists (gitignored)
- [ ] Initial commit is made

---

## Maintenance Protocol

When adding new packages:

1. Create directory under `packages/` or `services/`
2. Add `CLAUDE.md` following existing pattern
3. Run `pants tailor` to generate BUILD file
4. Link from root `CLAUDE.md` package map
5. Run `mise run reindex` for code search

---

## Related Resources

- [polyglot-affected.md](./polyglot-affected.md) - Tool comparison and Pants + mise guide
- [Level 11: Pants + mise](../SKILL.md#level-11-polyglot-monorepo-with-pants--mise) - Quick reference
- [Pants Documentation](https://www.pantsbuild.org/)
- [mise Documentation](https://mise.jdx.dev/)
