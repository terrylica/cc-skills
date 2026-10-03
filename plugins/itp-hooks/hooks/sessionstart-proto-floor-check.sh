#!/usr/bin/env bash
# SessionStart: warn, into the session's context, when this machine's proto is
# too old for the marketplace's bare `bun` hook commands. Silent when the floor
# holds. Never blocks: SessionStart cannot, and a warning is the honest signal.
# The check itself lives in scripts/proto-floor.sh (shared with itp-hooks:setup).
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../scripts/proto-floor.sh
source "$PLUGIN_ROOT/scripts/proto-floor.sh"

rc=0
message="$(proto_floor_check)" || rc=$?
if (( rc != 0 )); then
    echo "[itp-hooks] ${message}"
fi
exit 0
