# Python Dead Code Detection with vulture

Advanced usage patterns for vulture in Python projects.

## Installation

```bash
# Recommended: project-local with uv
uv pip install vulture

# Or globally
pipx install vulture
```

## Command Reference

```bash
# Basic scan
vulture src/

# With confidence threshold (recommended: 80+)
vulture src/ --min-confidence 80

# Sort by size (prioritize large dead code blocks)
vulture src/ --sort-by-size

# Exclude patterns
vulture src/ --exclude "*_test.py,conftest.py,migrations/"

# Generate whitelist for false positives
vulture src/ --make-whitelist > vulture_whitelist.py

# Scan with whitelist
vulture src/ vulture_whitelist.py
```

## Whitelist File Format

```python
# vulture_whitelist.py
# Generated with: vulture src/ --make-whitelist

# Django views (called by URL routing)
handle_webhook  # unused function (src/views.py:45)

# pytest fixtures
db_session  # unused function (conftest.py:12)

# Celery tasks (called by broker)
process_queue  # unused function (src/tasks.py:78)

# __all__ exports
_.some_function  # unused attribute
```

## Configuration (pyproject.toml)

```toml
[tool.vulture]
# Minimum confidence for reporting (60-100)
min_confidence = 80

# Paths to scan
paths = ["src", "tests"]

# Exclude patterns
exclude = [
    "*_test.py",
    "conftest.py",
    "migrations/",
    "__pycache__/",
]

# Whitelist files
whitelist = ["vulture_whitelist.py"]

# Sort output by code size
sort_by_size = true
```

## Integration with ruff

vulture complements ruff's F401 (unused imports) and F841 (unused variables):

| Tool    | Scope                          | Confidence | Auto-fix |
| ------- | ------------------------------ | ---------- | -------- |
| ruff    | Imports, local variables       | 100%       | Yes      |
| vulture | Functions, classes, attributes | 60-100%    | No       |

**Recommended workflow**:

1. Run `ruff check --fix` first (handles imports/variables)
2. Run `vulture --min-confidence 80` for deeper analysis

## Framework-Specific Whitelists

### Django

```python
# django_whitelist.py
from django.views import View
View.get
View.post
View.put
View.delete
View.patch

# Common patterns
urlpatterns
app_name
default_app_config
```

### Flask

```python
# flask_whitelist.py
from flask import Blueprint
Blueprint.route
Blueprint.before_request
Blueprint.after_request
```

### pytest

```python
# pytest_whitelist.py
# Fixtures are discovered by name, not import
@pytest.fixture
def _():
    pass
```

## CI Integration

```yaml
# .github/workflows/dead-code.yml (if using CI)
- name: Check for dead code
  run: |
    uv pip install vulture
    vulture src/ vulture_whitelist.py --min-confidence 80
```

## Confidence Score Guide

| Score | Meaning                                   | Example                                  |
| ----- | ----------------------------------------- | ---------------------------------------- |
| 100%  | Definitely unused in scanned files        | Local variable never read                |
| 90%   | Very likely unused                        | Private function never called            |
| 80%   | Probably unused                           | Class attribute never accessed           |
| 70%   | Possibly unused (dynamic access possible) | Dict key, `getattr` target               |
| 60%   | Might be unused (framework magic likely)  | Decorated function, `__init__.py` export |

## Sources

- [vulture GitHub](https://github.com/jendrikseipp/vulture)
- [vulture PyPI](https://pypi.org/project/vulture/)
- [Django cleanup with vulture](https://adamj.eu/tech/2023/07/12/django-clean-up-unused-code-vulture/)
