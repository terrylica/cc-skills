# Ralph Adapters

Ralph uses project-specific adapters to determine completion criteria and loop behavior.

## Adapter Detection

When Ralph starts, it scans the project directory to detect which adapter should handle the workflow. The first matching adapter is used.

## Available Adapters

### Alpha-Forge Adapter

**Status**: Production

The Alpha-Forge adapter provides specialized support for ML research workflows with metrics-based convergence detection.

**Detection Criteria** (any match triggers):

| Criterion                | Description                                      |
| ------------------------ | ------------------------------------------------ |
| `pyproject.toml` content | Contains `alpha-forge` or `alpha_forge`          |
| Directory structure      | `packages/alpha-forge-core/` exists              |
| Output directory         | `outputs/runs/` exists                           |
| Parent directories       | Any parent matches above (handles git worktrees) |

**Completion Signals**:

- **Sharpe ratio improvement** - Checks for significant improvement thresholds
- **WFE (Walk-Forward Efficiency)** - Minimum threshold for out-of-sample robustness
- **Diminishing returns** - Detects when improvements plateau
- **Patience counter** - Configurable iterations before triggering exploration

**Metrics Source**: `outputs/runs/*/summary.json`

### Generic Adapter (Planned)

**Status**: Not implemented - See [Issue #13](https://github.com/terrylica/cc-skills/issues/13)

A generic adapter for non-Alpha-Forge projects is planned but not yet implemented. Track progress:

- [#12](https://github.com/terrylica/cc-skills/issues/12) - Remove Alpha-Forge exclusivity gate
- [#13](https://github.com/terrylica/cc-skills/issues/13) - Create generic adapter
- [#14](https://github.com/terrylica/cc-skills/issues/14) - Pluggable completion detection
- [#15](https://github.com/terrylica/cc-skills/issues/15) - Alternative success criteria

## Non-Alpha-Forge Projects

For non-Alpha-Forge projects, Ralph hooks currently:

1. **Detect** the project is not Alpha-Forge
2. **Skip** all processing (zero overhead)
3. **Output** a JSON reason explaining why:

```json
{
  "ralph_skipped": true,
  "reason": "Not an Alpha-Forge project",
  "detection_criteria": [
    "pyproject.toml contains 'alpha-forge' or 'alpha_forge'",
    "packages/alpha-forge-core/ directory exists",
    "outputs/runs/ directory exists"
  ],
  "help": "Ralph is designed exclusively for Alpha-Forge ML research workflows."
}
```

## Creating Custom Adapters

Custom adapters can be created by implementing the `BaseAdapter` protocol:

```python
from core.protocols import BaseAdapter
from pathlib import Path

class MyAdapter(BaseAdapter):
    name = "my-project"

    @staticmethod
    def detect(project_path: Path) -> bool:
        """Return True if this adapter should handle the project."""
        return (project_path / "my-marker-file").exists()

    def get_completion_signals(self) -> dict:
        """Return completion signal configuration."""
        return {
            "use_time_limits": True,
            "use_iteration_limits": True,
        }
```

Place adapter files in `plugins/ralph/hooks/adapters/` and they will be auto-discovered.

## Related Documentation

- [README.md](../README.md) - Ralph overview and quick start
- [MENTAL-MODEL.md](../MENTAL-MODEL.md) - Alpha-Forge ML research methodology
- [core/protocols.py](../hooks/core/protocols.py) - Adapter protocol definitions
