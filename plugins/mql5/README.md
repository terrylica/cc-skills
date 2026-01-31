# mql5

MQL5 development tools for Claude Code: indicator patterns, mql5.com article extraction, Python workspace, and log reading.

Merged from `mql5-tools` + `mql5com` plugins.

## Skills

| Skill                     | Description                                                   |
| ------------------------- | ------------------------------------------------------------- |
| `mql5-indicator-patterns` | Buffer management, display scaling, recalculation, debugging  |
| `article-extractor`       | Extract and organize technical trading articles from mql5.com |
| `python-workspace`        | Configure Python workspace for MQL5-Python integration        |
| `log-reader`              | Read MetaTrader 5 log files to validate indicator execution   |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install mql5@cc-skills
```

## Usage

Skills are model-invoked — Claude automatically activates them based on context.

**Trigger phrases:**

- "create an MQL5 indicator" → mql5-indicator-patterns
- "indicator shows blank window" → mql5-indicator-patterns
- "extract articles from mql5.com" → article-extractor
- "MQL5 Python workspace" → python-workspace
- "read MT5 logs" → log-reader

## Key Features

### Indicator Development

- Display scale fixes for small value ranges
- Buffer architecture (visible + hidden)
- Recalculation and warmup patterns

### MQL5.com Operations

- Article extraction and organization
- Python development workspace
- Log file analysis

## Dependencies

| Component    | Required | Installation                                         |
| ------------ | -------- | ---------------------------------------------------- |
| MetaTrader 5 | Yes      | [Download](https://www.metatrader5.com/en/download)  |
| MetaEditor   | Yes      | Bundled with MetaTrader 5                            |
| Python 3.11+ | Optional | `mise use python@3.11` (for Python-MQL5 integration) |
| MetaTrader5  | Optional | `uv pip install MetaTrader5` (Python package)        |

## License

MIT
