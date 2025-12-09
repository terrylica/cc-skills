---
status: accepted
date: 2025-12-09
decision-maker: Terry Li
consulted:
  [DBeaver-Research-Agent, DataGrip-Research-Agent, CC-Skills-Naming-Agent]
research-method: multi-agent-parallel
clarification-iterations: 4
perspectives: [Developer-Experience, Architecture, Security, Maintainability]
---

# Add ClickHouse Pydantic Config Skill

**Design Spec**: [Implementation Spec](/docs/design/2025-12-09-clickhouse-pydantic-config-skill/spec.md)

## Context and Problem Statement

Developers using ClickHouse frequently misconfigure GUI database clients (DBeaver, DataGrip, TablePlus) because:

- Connection field semantics differ between tools (Username vs User, Database vs Schema)
- Local development settings differ from cloud production (HTTP:8123 vs HTTPS:8443)
- Credentials must be managed securely across environments
- No single source of truth exists for connection parameters

How can we provide a code-first, SSoT-driven approach to database client configuration that adapts to each repository's structure?

### Before/After

<!-- graph-easy source: before-diagram -->

```
    ⏮️ Before: Manual Configuration

                 ╭─────────────────────╮
                 │      Developer      │
                 ╰─────────────────────╯
                   │
                   │
                   ∨
┌──────────┐     ┌─────────────────────┐
│ DataGrip │     │     Copy/Paste      │
│          │ <── │ Connection Settings │
└──────────┘     └─────────────────────┘
  :                │
  :                │
  :                ∨
  :              ┌─────────────────────┐
  :              │       DBeaver       │
  :              └─────────────────────┘
  :                :
  :                :
  :                ∨
  :              ╔═════════════════════╗
  :              ║      Errors &       ║
  └············> ║    Inconsistency    ║
                 ╚═════════════════════╝
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏮️ Before: Manual Configuration"; flow: south; }
[ Developer ] { shape: rounded; }
[ Copy/Paste\nConnection Settings ]
[ DBeaver ]
[ DataGrip ]
[ Errors &\nInconsistency ] { border: double; }

[ Developer ] -> [ Copy/Paste\nConnection Settings ]
[ Copy/Paste\nConnection Settings ] -> [ DBeaver ]
[ Copy/Paste\nConnection Settings ] -> [ DataGrip ]
[ DBeaver ] ..> [ Errors &\nInconsistency ]
[ DataGrip ] ..> [ Errors &\nInconsistency ]
```

</details>

<!-- graph-easy source: after-diagram -->

```
⏭️ After: Pydantic SSoT + mise

╭─────────────────────────────╮
│          Developer          │
╰─────────────────────────────╯
  │
  │
  ∨
┌─────────────────────────────┐
│ mise run db-client-generate │
└─────────────────────────────┘
  │
  │
  ∨
╔═════════════════════════════╗
║    Pydantic Model (SSoT)    ║
╚═════════════════════════════╝
  │
  │
  ∨
┌─────────────────────────────┐
│ .dbeaver/data-sources.json  │
└─────────────────────────────┘
  │
  │
  ∨
╭─────────────────────────────╮
│        DBeaver Ready        │
╰─────────────────────────────╯
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "⏭️ After: Pydantic SSoT + mise"; flow: south; }
[ Developer ] { shape: rounded; }
[ mise run db-client-generate ]
[ Pydantic Model (SSoT) ] { border: double; }
[ .dbeaver/data-sources.json ]
[ DBeaver Ready ] { shape: rounded; }

[ Developer ] -> [ mise run db-client-generate ]
[ mise run db-client-generate ] -> [ Pydantic Model (SSoT) ]
[ Pydantic Model (SSoT) ] -> [ .dbeaver/data-sources.json ]
[ .dbeaver/data-sources.json ] -> [ DBeaver Ready ]
```

</details>

## Decision Drivers

- **Developer Experience**: Zero-friction connection setup for local and cloud
- **Single Source of Truth**: Pydantic models define connection configs once
- **mise Integration**: Environment variables in `[env]` section as SSoT
- **Security**: Credentials never committed to version control
- **Adaptability**: Semi-prescriptive pattern that adapts to repository structure

## Considered Options

1. **Manual configuration per project** - Copy/paste connection settings
2. **Shell scripts with environment variables** - Generate configs via bash
3. **Pydantic v2 models with mise integration** - Type-safe SSoT with task runner

## Decision Outcome

Chosen option: **Pydantic v2 models with mise integration**, because it provides:

- Type-safe configuration with validation
- JSON Schema generation for IDE IntelliSense
- mise `[env]` as single source of truth
- Semi-prescriptive pattern that adapts per repository

### Consequences

**Good**:

- Consistent connection configuration across all projects
- AI-maintainable (agents edit Python models, run generator)
- Self-documenting via Pydantic field descriptions
- Secure credential handling (gitignored output, mode-aware)

**Bad**:

- Requires Pydantic v2 dependency
- Initial learning curve for mise integration

**Neutral**:

- DBeaver-only initially (DataGrip/TablePlus future extension)

## Architecture

<!-- graph-easy source: architecture-diagram -->

```
                         Skill Architecture

                                   ┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐
                                   ╎                                ╎
                                   ╎ ┌────────────────────────────┐ ╎
                                   ╎ │      .env credentials      │ ╎
                                   ╎ └────────────────────────────┘ ╎
                                   ╎                                ╎
                                   └−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘
                                       │
                                       │
                                       │
┌−−−−−−−−−−−−−−−−−−−−−−−−−−−−┐         │
╎ mise SSoT:                 ╎         │
╎                            ╎         ∨
╎ ╔════════════════════════╗ ╎       ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
╎ ║     .mise.toml env     ║ ╎ ──>   ┃ ClickHouseConnection Model ┃
╎ ╚════════════════════════╝ ╎       ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
╎                            ╎
└−−−−−−−−−−−−−−−−−−−−−−−−−−−−┘
                                       │
                                       │
                                       ∨
  ┌────────────────────────┐         ┌────────────────────────────┐
  │ connection.schema.json │   <──   │ generate_dbeaver_config.py │
  └────────────────────────┘         └────────────────────────────┘
                                       │
                                       │
                                       ∨
                                     ┌────────────────────────────┐
                                     │ .dbeaver/data-sources.json │
                                     └────────────────────────────┘
```

<details>
<summary>graph-easy source</summary>

```
graph { label: "Skill Architecture"; flow: south; }
( mise SSoT:
  [ .mise.toml env ] { border: double; }
  [ .env credentials ]
)
[ ClickHouseConnection Model ] { border: bold; }
[ generate_dbeaver_config.py ]
[ .dbeaver/data-sources.json ]
[ connection.schema.json ]

[ .mise.toml env ] -> [ ClickHouseConnection Model ]
[ .env credentials ] -> [ ClickHouseConnection Model ]
[ ClickHouseConnection Model ] -> [ generate_dbeaver_config.py ]
[ generate_dbeaver_config.py ] -> [ .dbeaver/data-sources.json ]
[ generate_dbeaver_config.py ] -> [ connection.schema.json ]
```

</details>

### Key Components

| Component                    | Purpose                                                 |
| ---------------------------- | ------------------------------------------------------- |
| `ClickHouseConnection`       | Pydantic v2 model - SSoT for connection config          |
| `generate_dbeaver_config.py` | PEP 723 script - generates `.dbeaver/data-sources.json` |
| `.mise.toml`                 | Environment variables + task definitions                |
| `validate_config.py`         | JSON Schema validation of generated configs             |

### Credential Handling by Mode

| Mode      | Approach                                | Rationale                                       |
| --------- | --------------------------------------- | ----------------------------------------------- |
| **Local** | Hardcode `default` user, empty password | Zero friction, no security concern              |
| **Cloud** | Pre-populate from `.env`                | Read from environment, write to gitignored JSON |

## More Information

### Research Findings

**DBeaver Configuration**:

- Uses `.dbeaver/data-sources.json` format
- Does NOT support `${VAR}` substitution - must pre-populate at generation
- Connection ID format: `clickhouse-jdbc-{random-hex}`
- macOS launch: Use binary path, NOT `open -a`

**mise SSoT Pattern**:

- All config values in `[env]` section
- Scripts read via `os.environ.get()` with fallback defaults
- Works with or without mise installed

### Related ADRs

- [mise-env-centralized-config](/docs/adr/2025-12-08-mise-env-centralized-config.md) - SSoT pattern

### Cross-Skill Integration

| Skill                                      | Integration                         |
| ------------------------------------------ | ----------------------------------- |
| `devops-tools:clickhouse-cloud-management` | Credential retrieval for cloud mode |
| `quality-tools:clickhouse-architect`       | Schema design context               |
| `itp:mise-configuration`                   | SSoT environment variable patterns  |
