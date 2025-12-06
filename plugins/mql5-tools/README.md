# mql5-tools

MQL5 indicator development patterns plugin for Claude Code with battle-tested solutions for MetaTrader 5.

## Skills

| Skill                       | Description                                                               |
| --------------------------- | ------------------------------------------------------------------------- |
| **mql5-indicator-patterns** | Buffer management, display scaling, recalculation, and debugging patterns |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install mql5-tools@cc-skills
```

## Usage

Skills are model-invoked — Claude automatically activates them based on context.

**Trigger phrases:**

- "create an MQL5 indicator" → mql5-indicator-patterns
- "indicator shows blank window" → mql5-indicator-patterns
- "fix rolling window drift" → mql5-indicator-patterns
- "debug OnCalculate()" → mql5-indicator-patterns

## Key Patterns Covered

- **Display Scale** - Fix blank windows for small value ranges
- **Buffer Architecture** - Visible + hidden buffer patterns
- **Recalculation** - New bar detection to prevent drift
- **State Management** - Static variables for rolling windows
- **Warmup** - Proper PLOT_DRAW_BEGIN calculation

## Requirements

- MetaEditor for MQL5 development
- MetaTrader 5 for testing indicators

## License

MIT
