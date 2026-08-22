#!/usr/bin/env bash
#MISE description="Gate: fail if cli_spec.json drifted from the Python argparse CLI surface (stale spec OR a skill CLI added/removed without regenerating). Runs the fast stdlib --check drift gate then the pytest invariant suite (scripts/test_cli_spec.py: drift + completeness + no-vendored-leak + 2020-12 dialect + scalar types + determinism). Fix with 'mise run cli-spec'."
set -euo pipefail

cd "${MISE_PROJECT_ROOT:-$(git rev-parse --show-toplevel)}"
uv run --python 3.14 --no-project python scripts/cli_spec.py --check
uv run --python 3.14 --no-project --with pytest pytest scripts/test_cli_spec.py -q
