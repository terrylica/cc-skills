#!/usr/bin/env bash
# proto-floor.sh — the one check that hook commands may call `bun` bare.
#
# Sourced by scripts/install-dependencies.sh (itp-hooks:setup) and by
# hooks/sessionstart-proto-floor-check.sh. Plain bash on purpose: it must not
# itself run through the proto shim whose behaviour it is checking.
#
# Why a floor exists: hooks.json invokes `bun` bare since 2026-10-02. When that
# `bun` is a proto shim, proto older than 0.61.2 writes an "AI agent
# environment" NDJSON banner to STDOUT ahead of the hook's JSON, so Claude Code
# discards the hook's decision at exit 0 (moonrepo/proto#1105). Before 0.61.3 a
# FAILING shim also wrote its reason to STDOUT and left STDERR empty
# (moonrepo/proto#1110). Until 2026-10-02 every command carried
# `env -u AI_AGENT -u CLAUDECODE` to dodge both; this floor replaces that.
#
# proto_floor_check prints one line and returns:
#   0  bun is not a proto shim, or proto is at or above the floor
#   1  bun is a proto shim and proto is below the floor (hooks are unsafe)
#   2  bun is a proto shim but proto's version could not be read

PROTO_MINIMUM_VERSION_FOR_BARE_HOOK_COMMANDS="0.61.3"

proto_floor_check() {
    local bun_path proto_bin proto_version_line proto_version lowest
    bun_path="$(command -v bun 2>/dev/null || true)"
    if [[ "$bun_path" != */.proto/shims/* ]]; then
        echo "proto floor: bun is not a proto shim (${bun_path:-not found}); nothing to check"
        return 0
    fi

    proto_bin="$(command -v proto 2>/dev/null || true)"
    [[ -z "$proto_bin" && -x "$HOME/.proto/bin/proto" ]] && proto_bin="$HOME/.proto/bin/proto"
    if [[ -z "$proto_bin" ]]; then
        echo "proto floor: bun is a proto shim but the proto CLI was not found"
        return 2
    fi

    proto_version_line="$(env -u AI_AGENT -u CLAUDECODE "$proto_bin" --version 2>/dev/null | head -1 || true)"
    proto_version="${proto_version_line##* }"
    if [[ ! "$proto_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        echo "proto floor: could not read proto's version (got '${proto_version_line}')"
        return 2
    fi

    lowest="$(printf '%s\n%s\n' "$proto_version" "$PROTO_MINIMUM_VERSION_FOR_BARE_HOOK_COMMANDS" | sort -V | head -1)"
    if [[ "$lowest" == "$PROTO_MINIMUM_VERSION_FOR_BARE_HOOK_COMMANDS" ]]; then
        echo "proto floor: proto ${proto_version} >= ${PROTO_MINIMUM_VERSION_FOR_BARE_HOOK_COMMANDS}"
        return 0
    fi
    echo "proto floor: proto ${proto_version} is below ${PROTO_MINIMUM_VERSION_FOR_BARE_HOOK_COMMANDS}; cc-skills hooks run bun through its shim and their decisions may be silently discarded. Fix: proto upgrade"
    return 1
}
