# python-tools

Pydantic v2 API documentation patterns plugin for Claude Code.

## Skills

| Skill                        | Description                                                    |
| ---------------------------- | -------------------------------------------------------------- |
| **python-api-documentation** | Document Python packages with Pydantic v2 and FastAPI patterns |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install python-tools@cc-skills
```

## Usage

Skills are model-invoked — Claude automatically activates them based on context.

**Trigger phrases:**

- "document this Python API" → python-api-documentation
- "create Pydantic models" → python-api-documentation
- "generate JSON schema" → python-api-documentation
- "add type hints to this function" → python-api-documentation

## Key Features

### 3-Layer Architecture

1. **Literal Types** - Define valid values once
2. **Pydantic Models** - Data structure + validation
3. **Rich Docstrings** - Usage examples and descriptions

### Benefits

- **Single Source of Truth** - Code = Documentation
- **AI Agent Discovery** - Works with `help()`, `inspect`, `model_json_schema()`
- **IDE Support** - Type hints enable autocomplete
- **Runtime Validation** - Pydantic enforces constraints

## Requirements

- Python 3.11+
- Pydantic v2.x (`uv add pydantic`)

## License

MIT
