---
name: python-api-documentation
description: Document Python packages with Pydantic v2 and FastAPI. Use when creating API docs, JSON schemas, data models, or implementing OpenAPI specifications and standards.
allowed-tools: Read, Edit, Write
---

# Pydantic API Documentation Skill

## Quick Reference

**When to use this skill:**

- Documenting a Python package's public API
- Creating reusable data structures with validation
- Generating JSON schemas for AI agents or external consumers
- Building FastAPI applications with auto-generated OpenAPI docs
- Migrating from fragmented documentation (README.md + llms.txt + AGENTS.md)

## Pattern Overview

### The 3-Layer Architecture

**Layer 1: Literal Types (Define Valid Values)**

```python
from typing import Literal

PairType = Literal["EURUSD", "GBPUSD", "XAUUSD"]
TimeframeType = Literal["1m", "5m", "15m", "1h", "4h", "1d"]
```

**Layer 2: Pydantic Models (Data Structure + Validation)**

```python
from pydantic import BaseModel, Field

class UpdateResult(BaseModel):
    months_added: int = Field(ge=0, description="Number of months added")
    duckdb_size_mb: float = Field(ge=0, description="Database size in MB")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {"months_added": 12, "duckdb_size_mb": 2345.6}
            ]
        }
    }
```

**Layer 3: Rich Docstrings (Usage & Examples)**

```python
def update_data(
    self,
    pair: PairType,
    start_date: str
) -> UpdateResult:
    """
    Download and update forex data incrementally.

    This method appends new data to the existing dataset without
    re-downloading historical records.

    Args:
        pair: Currency pair (e.g., "EURUSD")
        start_date: ISO format date (e.g., "2022-01-01")

    Returns:
        UpdateResult with download statistics

    Example:
        >>> processor = ForexProcessor("data.db")
        >>> result = processor.update_data("EURUSD", "2022-01-01")
        >>> print(f"Added {result.months_added} months of data")

    Raises:
        ValueError: If pair not supported or date format invalid
    """
```

## Key Benefits

✓ **Single Source of Truth** - Code = Documentation
✓ **AI Agent Discovery** - `help()`, `inspect.signature()`, `Model.model_json_schema()` work automatically
✓ **IDE Support** - Type hints enable autocomplete and navigation
✓ **Runtime Validation** - Pydantic enforces constraints automatically
✓ **Zero Sync Burden** - Change code once, updates everywhere

## Best Practices

1. **Use Literal types** for all enums (not Enum class)
2. **Add `description` to every Field()** - Machine-readable constraints
3. **Embed examples** in `model_config` json_schema_extra
4. **Type all method returns** - Use Pydantic models for complex returns
5. **Add @staticmethod helpers** - e.g., `supported_pairs()` for agent discovery
6. **Avoid separate docs files** - No README.md API sections, no llms.txt duplication

## Migration Path

1. Define Literal types for all enums
2. Create Pydantic models for all return types
3. Add Field(description=...) to every field
4. Embed examples in model_config
5. Update method signatures with typed returns
6. Add rich docstrings with Examples section
7. Add @staticmethod helpers
8. Remove redundant documentation files

## AI Agent Discovery Workflow

When Claude, Copilot, or other AI agents encounter an API, they:

1. Call `help(ClassName)` → reads rich docstrings
2. Use `inspect.signature(method)` → discovers typed parameters
3. Call `Model.model_json_schema()` → gets machine-readable schema
4. Use `get_args(PairType)` → discovers valid enum values
5. Access `Model.model_config` → reads embedded examples

This gives AI agents the complete picture without separate documentation.

## See Also

- **Reference**: See `REFERENCE.yaml` for complete specification and comparison matrix
- **Performance**: Pydantic v2 is 4-50x faster than v1.9.1 due to Rust core
- **Industry Adoption**: 8000+ PyPI packages use Pydantic (FAANG companies included)
