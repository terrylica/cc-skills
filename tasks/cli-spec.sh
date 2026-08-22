#!/usr/bin/env bash
#MISE description="Regenerate the machine-readable Python cli_spec.json (JSON Schema 2020-12 SSoT of every argparse skill CLI under plugins/*/skills/*/scripts/ + scripts/, for AI-agent introspection without parsing --help). AST-based (never imports the CLIs); excludes vendored/.build/node_modules. Run after adding/changing a Python CLI, then commit the diff."
set -euo pipefail

cd "${MISE_PROJECT_ROOT:-$(git rev-parse --show-toplevel)}"
uv run --python 3.14 --no-project python scripts/cli_spec.py --output cli_spec.json
