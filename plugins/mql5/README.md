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

## Troubleshooting

| Issue                        | Cause                          | Solution                                            |
| ---------------------------- | ------------------------------ | --------------------------------------------------- |
| Indicator shows blank window | Scale not set for small values | Set INDICATOR_MINIMUM/MAXIMUM explicitly            |
| Indicator values drifting    | Rolling window not reset       | Use new bar detection with hidden buffer            |
| Log file not found           | Wrong date or path             | Verify YYYYMMDD.log format and MQL5_ROOT env var    |
| Python MT5 connection failed | Terminal not running           | Start MetaTrader 5 before Python connection         |
| Article extraction fails     | mql5.com structure changed     | Check for updates to article-extractor skill        |
| Compilation errors in logs   | MQL5 syntax issues             | Read log file for specific error messages and lines |
| MetaTrader5 import error     | Package not installed          | Run `uv pip install MetaTrader5`                    |
| Log encoding issues          | UTF-16LE not handled           | Read tool handles encoding automatically            |

## License

MIT
