---
adr: /docs/adr/2025-12-09-clickhouse-pydantic-config-skill.md
status: accepted
created: 2025-12-09
plugin: devops-tools
skill: clickhouse-pydantic-config
---

# Implementation Spec: ClickHouse Pydantic Config Skill

**ADR**: [Add ClickHouse Pydantic Config Skill](/docs/adr/2025-12-09-clickhouse-pydantic-config-skill.md)

## Critical Design Principle: Semi-Prescriptive Adaptation

**This skill is NOT a rigid template.** It provides a SSoT pattern that MUST be adapted to each repository's structure and local database situation.

### Executor Guidelines

When implementing this skill, the AI agent MUST:

1. **Discover repository structure first** - Scan for existing `.mise.toml`, connection configs, `.env` patterns
2. **Validate local database availability** - Test ClickHouse connectivity before generating configs
3. **Adapt Pydantic model fields** - Add/remove fields based on repository-specific requirements
4. **Wire to existing SSoT** - If mise `[env]` already exists, extend it rather than replace
5. **Verify generated output** - Never trust generated configs without testing DBeaver import

### mise `[env]` as Single Source of Truth

This skill follows the `itp:mise-configuration` pattern where **mise `[env]` is the SSoT** for all configurable values:

```toml
# .mise.toml - The ONE place to configure connections
[env]
CLICKHOUSE_HOST = "localhost"
CLICKHOUSE_PORT = "8123"
CLICKHOUSE_DATABASE = "default"
```

**Key principles:**

1. **All config values in `[env]`** - Never hardcode in scripts
2. **Scripts read from `os.environ`** - With backward-compatible defaults
3. **Works with or without mise** - Graceful degradation
4. **Repository-specific overrides** - Each project's `.mise.toml` can override

## File Structure

| File                                 | Size   | Purpose                  |
| ------------------------------------ | ------ | ------------------------ |
| `SKILL.md`                           | ~4KB   | Main skill documentation |
| `.mise.toml`                         | ~1.5KB | mise env + tasks         |
| `scripts/generate_dbeaver_config.py` | ~5KB   | Main generator           |
| `scripts/validate_config.py`         | ~2KB   | Schema validation        |
| `references/pydantic-model.md`       | ~3KB   | Model documentation      |
| `references/dbeaver-format.md`       | ~2KB   | DBeaver format spec      |

**Location**: `plugins/devops-tools/skills/clickhouse-pydantic-config/`

## Pydantic Model Design

```python
from pydantic import BaseModel, Field, computed_field, model_validator
from typing import Literal
from enum import Enum
import os
import secrets

class ConnectionMode(str, Enum):
    LOCAL = "local"
    CLOUD = "cloud"

class ClickHouseConnection(BaseModel):
    """ClickHouse connection configuration - Single Source of Truth."""

    name: str = Field(default="clickhouse-local", description="Connection display name")
    mode: ConnectionMode = Field(default=ConnectionMode.LOCAL, description="local or cloud")
    host: str = Field(default="localhost", description="ClickHouse hostname")
    port: int = Field(default=8123, description="HTTP port (8123 local, 8443 cloud)")
    database: str = Field(default="default", description="Default database")
    ssl_enabled: bool = Field(default=False, description="Enable SSL/TLS")
    ssl_mode: Literal["disable", "require", "verify-ca", "verify-full"] = Field(default="disable")
    connection_type: Literal["dev", "test", "prod"] = Field(default="dev")

    @model_validator(mode='after')
    def validate_mode_settings(self) -> 'ClickHouseConnection':
        if self.mode == ConnectionMode.CLOUD:
            self.port = 8443
            self.ssl_enabled = True
            self.ssl_mode = "require"
        return self

    @computed_field
    @property
    def jdbc_url(self) -> str:
        protocol = "https" if self.ssl_enabled else "http"
        return f"jdbc:clickhouse:{protocol}://{self.host}:{self.port}/{self.database}"

    @computed_field
    @property
    def connection_id(self) -> str:
        return f"clickhouse-jdbc-{secrets.token_hex(8)}"

    def to_dbeaver_config(self) -> dict:
        """Generate DBeaver data-sources.json connection entry."""
        config = {
            "provider": "clickhouse",
            "driver": "com_clickhouse",
            "name": self.name,
            "configuration": {
                "host": self.host,
                "port": str(self.port),
                "database": self.database,
                "url": self.jdbc_url,
                "type": self.connection_type,
                "auth-model": "native"
            }
        }
        if self.ssl_enabled:
            config["configuration"]["handler-ssl"] = "openssl"
            config["configuration"]["ssl-mode"] = self.ssl_mode

        # Credential handling by mode
        if self.mode == ConnectionMode.LOCAL:
            config["configuration"]["user"] = "default"
            config["configuration"]["password"] = ""
        elif self.mode == ConnectionMode.CLOUD:
            config["configuration"]["user"] = os.environ.get("CLICKHOUSE_USER_READONLY", "default")
            config["configuration"]["password"] = os.environ.get("CLICKHOUSE_PASSWORD_READONLY", "")

        return config

    @classmethod
    def from_env(cls, prefix: str = "CLICKHOUSE_") -> 'ClickHouseConnection':
        return cls(
            name=os.environ.get(f"{prefix}NAME", "clickhouse-local"),
            mode=ConnectionMode(os.environ.get(f"{prefix}MODE", "local")),
            host=os.environ.get(f"{prefix}HOST", "localhost"),
            port=int(os.environ.get(f"{prefix}PORT", "8123")),
            database=os.environ.get(f"{prefix}DATABASE", "default"),
            connection_type=os.environ.get(f"{prefix}TYPE", "dev")
        )
```

## mise Configuration

```toml
# .mise.toml
min_version = "2024.9.5"

[env]
CLICKHOUSE_NAME = "clickhouse-local"
CLICKHOUSE_MODE = "local"
CLICKHOUSE_HOST = "localhost"
CLICKHOUSE_PORT = "8123"
CLICKHOUSE_DATABASE = "default"
CLICKHOUSE_TYPE = "dev"
DBEAVER_CONFIG_PATH = ".dbeaver/data-sources.json"
CONNECTION_SCHEMA_PATH = ".dbeaver/connection.schema.json"
DBEAVER_BIN = "/Applications/DBeaver.app/Contents/MacOS/dbeaver"

[tasks.db-client-generate]
description = "Generate DBeaver config from Pydantic model"
run = "uv run scripts/generate_dbeaver_config.py --output ${DBEAVER_CONFIG_PATH}"

[tasks.db-client-validate]
description = "Validate DBeaver config against schema"
run = "uv run scripts/validate_config.py --config ${DBEAVER_CONFIG_PATH}"

[tasks.dbeaver]
description = "Launch DBeaver with project workspace"
run = '"${DBEAVER_BIN}" -data .dbeaver-workspace &'

[tasks."db-client:cloud"]
description = "Generate config for ClickHouse Cloud"
run = "uv run scripts/generate_dbeaver_config.py --mode cloud --output ${DBEAVER_CONFIG_PATH}"
```

## DBeaver data-sources.json Format

```json
{
  "folders": {},
  "connections": {
    "clickhouse-jdbc-a1b2c3d4e5f6": {
      "provider": "clickhouse",
      "driver": "com_clickhouse",
      "name": "ClickHouse Local",
      "configuration": {
        "host": "localhost",
        "port": "8123",
        "database": "default",
        "url": "jdbc:clickhouse:http://localhost:8123/default",
        "type": "dev",
        "auth-model": "native"
      }
    }
  }
}
```

## Credential Handling by Mode

| Mode      | Credential Approach                     | Rationale                                          |
| --------- | --------------------------------------- | -------------------------------------------------- |
| **Local** | Hardcode `default` user, empty password | Local ClickHouse uses default user. Zero friction. |
| **Cloud** | Pre-populate from `.env`                | Read from environment, write to gitignored JSON.   |

**Key principle**: The generated `data-sources.json` is gitignored anyway. Pre-populating credentials trades zero security risk for maximum developer convenience.

## Repository Adaptation Workflow

### Pre-Implementation Discovery (Phase 0)

Before writing any code, the executor MUST:

```bash
# 1. Discover existing configuration patterns
fd -t f ".mise.toml" .
fd -t f ".env*" .
fd -t d ".dbeaver" .

# 2. Test ClickHouse connectivity (local)
clickhouse-client --host localhost --port 9000 --query "SELECT 1"

# 3. Check for existing connection configs
fd -t f "data-sources.json" .
fd -t f "dataSources.xml" .
```

### Adaptation Decision Matrix

| Discovery Finding                  | Adaptation Action                                      |
| ---------------------------------- | ------------------------------------------------------ |
| Existing `.mise.toml` at repo root | Extend existing `[env]` section, don't create new file |
| Existing `.dbeaver/` directory     | Merge connections, preserve existing entries           |
| Non-standard CLICKHOUSE\_\* vars   | Map to repository's naming convention                  |
| Multiple databases (local + cloud) | Generate multiple connection entries                   |
| No ClickHouse available            | Warn and generate placeholder config                   |

### Validation Checklist (Post-Generation)

The executor MUST verify:

- [ ] Generated JSON is valid (`jq . .dbeaver/data-sources.json`)
- [ ] No credentials in generated files (`grep -r password .dbeaver/`)
- [ ] DBeaver can import the config (launch and verify connection appears)
- [ ] mise tasks execute without error (`mise run db-client-generate`)
- [ ] `.dbeaver/` added to `.gitignore`

## Critical macOS Notes

1. **DBeaver binary**: Use `/Applications/DBeaver.app/Contents/MacOS/dbeaver` (NOT `open -a`)
2. **No `${VAR}` substitution**: DBeaver does NOT support env var substitution - pre-populate at generation
3. **Gitignore**: Add `.dbeaver/` to `.gitignore`

## Cross-Skill Integration

| Skill                                      | Integration                         |
| ------------------------------------------ | ----------------------------------- |
| `devops-tools:clickhouse-cloud-management` | Credential retrieval for cloud mode |
| `quality-tools:clickhouse-architect`       | Schema design context               |
| `devops-tools:doppler-secret-validation`   | Secure credential storage patterns  |
| `itp:mise-configuration`                   | SSoT environment variable patterns  |

## Success Criteria

- [ ] `mise run db-client-generate` produces valid `.dbeaver/data-sources.json`
- [ ] `mise run db-client-validate` passes schema validation
- [ ] `mise run dbeaver` launches DBeaver correctly on macOS
- [ ] Cloud mode (`mise run db-client:cloud`) configures SSL correctly
- [ ] JSON Schema generated for IDE IntelliSense
- [ ] No credentials in any generated files
- [ ] Skill passes `quick_validate.py` validation
