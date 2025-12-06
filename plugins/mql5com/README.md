# mql5com Plugin

Skills for operating mql5.com website - article extraction, data research, Python workspace configuration, and MetaTrader 5 log reading.

## Skills

| Skill                       | Description                                                        |
| --------------------------- | ------------------------------------------------------------------ |
| **article-extractor**       | Extract and organize technical trading articles from mql5.com      |
| **data-ingestion-research** | Research documentation for tick data ingestion into MetaTrader 5   |
| **python-workspace**        | Configure Python development workspace for MQL5-Python integration |
| **log-reader**              | Read MetaTrader 5 log files to validate indicator execution        |

## Installation

```bash
/plugin install mql5com@cc-skills
```

## Usage

Each skill activates automatically based on context:

- **Article extraction**: "extract articles from mql5.com", "download mql5 documentation"
- **Data ingestion**: "tick data format", "MT5 custom symbols", "data ingestion research"
- **Python workspace**: "MQL5 Python", "indicator translation", "MetaTrader Python API"
- **Log reader**: "read MT5 logs", "check Experts pane", "indicator execution"

## Notes

- `data-ingestion-research` is marked as UNVALIDATED - research documentation not yet tested in live MT5
- All skills focus on mql5.com website/platform operations (not MQL5 language patterns)

## License

MIT
