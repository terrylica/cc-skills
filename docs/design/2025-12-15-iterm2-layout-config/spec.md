**ADR**: [iTerm2 Layout Configuration Separation](/docs/adr/2025-12-15-iterm2-layout-config.md)

# Design Spec: iTerm2 Layout Config Separation

## Overview

Refactor `default-layout.py` to load configuration from `~/.config/iterm2/layout.toml` instead of hardcoded values.

## Implementation Steps

### Phase 1: Add Configuration Loading

**File**: `/Users/terryli/scripts/iterm2/default-layout.py`

Add after imports:

```python
import tomllib
from pathlib import Path

CONFIG_PATH = Path("~/.config/iterm2/layout.toml").expanduser()

DEFAULT_CONFIG = {
    "layout": {
        "left_pane_ratio": 0.20,
        "settle_time": 0.3,
    },
    "commands": {
        "left": "br --sort-by-type-dirs-first",
        "right": "zsh",
    },
    "worktrees": {
        "alpha_forge_root": None,
        "worktree_pattern": "*.worktree-*",
    },
    "tabs": [],
}
```

### Phase 2: Config Loading Function

```python
def load_config() -> dict | None:
    """Load configuration with defaults fallback."""
    if not CONFIG_PATH.exists():
        return None

    try:
        with open(CONFIG_PATH, "rb") as f:
            user_config = tomllib.load(f)
        return deep_merge(DEFAULT_CONFIG, user_config)
    except tomllib.TOMLDecodeError as e:
        print(f"ERROR: Invalid TOML syntax in {CONFIG_PATH}")
        print(f"  {e}")
        return None


def deep_merge(base: dict, override: dict) -> dict:
    """Recursively merge override into base."""
    result = base.copy()
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result
```

### Phase 3: Config Validation in main()

```python
async def main(connection):
    config = load_config()
    if config is None:
        print("=" * 60)
        print("ERROR: Layout configuration not found")
        print("=" * 60)
        print(f"\nExpected config file: {CONFIG_PATH}")
        print("\nTo create one:")
        print("  1. Copy the example template:")
        print(f"     cp ~/scripts/iterm2/layout.example.toml {CONFIG_PATH}")
        print("  2. Edit with your workspace paths")
        print("\nSee: ~/scripts/iterm2/CLAUDE.md for documentation")
        print("\n[Layout creation cancelled]")
        return

    if not config.get("tabs"):
        print("WARNING: No tabs configured in layout.toml")
        print("Add [[tabs]] entries to create workspace tabs")
        print("\n[Layout creation cancelled]")
        return

    # Continue with config...
```

### Phase 4: Replace Hardcoded Values

| Current             | Replace With                              |
| ------------------- | ----------------------------------------- |
| `TABS = [...]`      | `config["tabs"]`                          |
| `LEFT_COMMAND`      | `config["commands"]["left"]`              |
| `RIGHT_COMMAND`     | `config["commands"]["right"]`             |
| `SETTLE_TIME`       | `config["layout"]["settle_time"]`         |
| `LEFT_PANE_RATIO`   | `config["layout"]["left_pane_ratio"]`     |
| `~/eon/alpha-forge` | `config["worktrees"]["alpha_forge_root"]` |

### Phase 5: Create Template

**File**: `/Users/terryli/scripts/iterm2/layout.example.toml`

```toml
# iTerm2 Layout Configuration
# Copy to: ~/.config/iterm2/layout.toml

[layout]
left_pane_ratio = 0.20
settle_time = 0.3

[commands]
left = "br --sort-by-type-dirs-first"
right = "zsh"

[worktrees]
# alpha_forge_root = "~/projects/my-project"
# worktree_pattern = "my-project.worktree-*"

[[tabs]]
name = "home"
dir = "~"

[[tabs]]
name = "config"
dir = "~/.config"
```

## Config Schema

| Section       | Key                | Type   | Default  | Description               |
| ------------- | ------------------ | ------ | -------- | ------------------------- |
| `[layout]`    | `left_pane_ratio`  | float  | 0.20     | Left pane width (0.0-1.0) |
| `[layout]`    | `settle_time`      | float  | 0.3      | Wait after cd (seconds)   |
| `[commands]`  | `left`             | string | br...    | Left pane command         |
| `[commands]`  | `right`            | string | zsh      | Right pane command        |
| `[worktrees]` | `alpha_forge_root` | string | null     | Worktree root (optional)  |
| `[[tabs]]`    | `dir`              | string | required | Directory path            |
| `[[tabs]]`    | `name`             | string | basename | Tab display name          |

## Files Changed

| File                                   | Action        |
| -------------------------------------- | ------------- |
| `~/scripts/iterm2/default-layout.py`   | Refactor      |
| `~/scripts/iterm2/layout.example.toml` | Create        |
| `~/scripts/iterm2/CLAUDE.md`           | Update        |
| `~/.config/iterm2/layout.toml`         | Create (user) |

## Testing

1. Verify script works with config file
2. Verify graceful error when config missing (check Script Console)
3. Restart iTerm2 to test AutoLaunch
