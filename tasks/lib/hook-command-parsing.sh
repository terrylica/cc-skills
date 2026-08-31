#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared SSoT for parsing a hooks.json `command` string into its parts.
#
# WHY THIS EXISTS
# ---------------
# Every plugins/*/hooks/hooks.json command is prefixed with a literal
# `env -u AI_AGENT -u CLAUDECODE` before the interpreter:
#
#     env -u AI_AGENT -u CLAUDECODE bun ${CLAUDE_PLUGIN_ROOT}/hooks/foo.ts
#
# That prefix is load-bearing and MUST NOT be removed from hooks.json: a bare
# `bun`/`node` in a hook subprocess resolves to a proto shim which re-execs the
# proto CLI; proto sniffs AI_AGENT / CLAUDECODE and writes an NDJSON banner to
# STDOUT ahead of the hook's own JSON, so Claude Code's single JSON.parse fails
# and the hook's decision is SILENTLY DISCARDED (1,716 polluted hook events
# measured over three days). Both vars must be unset; -u AI_AGENT alone is
# insufficient.
#
# The prefix broke every audit/task parser that assumed "the first token of a
# hook command is the interpreter" (or that stripping a leading `bun `/`node `
# yields the script path) — those now return the literal string `env`. Rather
# than N ad-hoc regexes drifting apart, hook-command parsing lives here.
#
# CONTRACT — every function is robust to all four shapes in the marketplace:
#   1. no prefix at all ......... `bun ${CLAUDE_PLUGIN_ROOT}/hooks/foo.ts`
#   2. the env prefix ........... `env -u AI_AGENT -u CLAUDECODE bun …/foo.ts`
#   3. a non-bun interpreter .... `bash ${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh`
#   4. a bare shebang script .... `${CLAUDE_PLUGIN_ROOT}/hooks/foo.mjs`
# …and to trailing script arguments, which are never part of the script path.
#
# All functions are pure bash (no forks) so they are safe to call inside the
# per-hook classifier loops that iter-124 de-fork-stormed.
#
# USAGE
#   source "$REPO_ROOT/tasks/lib/hook-command-parsing.sh"
#   script_path=$(extract_hook_script_path_from_hook_command "$cmd")
#
# jq-side consumers: keep jq to the raw `.command` extraction and do the
# splitting here in bash, so this file stays the single parsing SSoT.

# ---------------------------------------------------------------------------
# strip_env_invocation_prefix_from_hook_command <command>
#
# Echo <command> with a leading `env` invocation removed — including its
# option arguments (`-i`, `--ignore-environment`, `-u VAR`, `-uVAR`,
# `--unset VAR`, `--unset=VAR`, `-C DIR`, `--chdir DIR`, `--chdir=DIR`) and any
# `VAR=value` assignments. A command with no `env` prefix is echoed unchanged.
# ---------------------------------------------------------------------------
strip_env_invocation_prefix_from_hook_command() {
    local hook_command_string="$1"
    local -a hook_command_tokens=()
    # shellcheck disable=SC2206 # deliberate word-splitting on whitespace
    read -r -a hook_command_tokens <<<"$hook_command_string"

    ((${#hook_command_tokens[@]} == 0)) && return 0

    local first_token="${hook_command_tokens[0]}"
    # Accept `env` and any absolute/relative path ending in /env.
    if [[ "$first_token" != "env" && "$first_token" != */env ]]; then
        echo "$hook_command_string"
        return 0
    fi

    local token_index=1
    while ((token_index < ${#hook_command_tokens[@]})); do
        local current_token="${hook_command_tokens[$token_index]}"
        case "$current_token" in
            # Options that consume a SEPARATE following argument.
            -u | --unset | -C | --chdir | -S | --split-string)
                token_index=$((token_index + 2))
                ;;
            # Options that carry their argument in the same token, plus the
            # standalone flags (-i, --ignore-environment, -0, --null, …).
            -*)
                token_index=$((token_index + 1))
                ;;
            # `VAR=value` assignments precede the program name.
            *=*)
                token_index=$((token_index + 1))
                ;;
            # First non-option, non-assignment token is the real program.
            *)
                break
                ;;
        esac
    done

    local hook_command_after_this_env_invocation="${hook_command_tokens[*]:$token_index}"

    # A nested `env` (e.g. `env FOO=bar /usr/bin/env bun x.ts`) is unwrapped
    # too — recurse only when the remainder actually shrank, so this can never
    # loop forever on a degenerate `env` with no program.
    if [[ "$hook_command_after_this_env_invocation" != "$hook_command_string" ]]; then
        strip_env_invocation_prefix_from_hook_command "$hook_command_after_this_env_invocation"
    else
        echo "$hook_command_after_this_env_invocation"
    fi
}

# ---------------------------------------------------------------------------
# extract_hook_interpreter_from_hook_command <command>
#
# Echo the interpreter the hook actually runs under (`bun`, `node`, `bash`, …)
# after the env prefix is stripped. Echoes the empty string for shape 4 (a
# bare shebang script with no explicit interpreter).
# ---------------------------------------------------------------------------
extract_hook_interpreter_from_hook_command() {
    local hook_command_without_env_prefix
    hook_command_without_env_prefix=$(strip_env_invocation_prefix_from_hook_command "$1")

    local -a tokens=()
    read -r -a tokens <<<"$hook_command_without_env_prefix"
    ((${#tokens[@]} == 0)) && return 0

    case "${tokens[0]##*/}" in
        bun | bunx | node | deno | npx | bash | sh | zsh | python | python3 | uv | uvx)
            echo "${tokens[0]}"
            ;;
        *)
            echo ""
            ;;
    esac
}

# ---------------------------------------------------------------------------
# extract_hook_script_path_from_hook_command <command>
#
# Echo the hook SCRIPT PATH — the token the interpreter executes — with the
# env prefix, the interpreter, any interpreter flags, a `bun run` / `deno run`
# subcommand, and trailing script arguments all removed. `${CLAUDE_PLUGIN_ROOT}`
# is NOT resolved here; callers substitute it before or after as they prefer.
# ---------------------------------------------------------------------------
extract_hook_script_path_from_hook_command() {
    local hook_command_without_env_prefix
    hook_command_without_env_prefix=$(strip_env_invocation_prefix_from_hook_command "$1")

    local -a tokens=()
    read -r -a tokens <<<"$hook_command_without_env_prefix"
    ((${#tokens[@]} == 0)) && return 0

    local token_index=0
    case "${tokens[0]##*/}" in
        bun | bunx | node | deno | npx | bash | sh | zsh | python | python3 | uv | uvx)
            token_index=1
            # Skip interpreter flags (`node --enable-source-maps x.js`) and the
            # `run` subcommand (`bun run x.ts`, `deno run x.ts`, `uv run x.py`).
            while ((token_index < ${#tokens[@]})); do
                case "${tokens[$token_index]}" in
                    -*) token_index=$((token_index + 1)) ;;
                    run) token_index=$((token_index + 1)) ;;
                    *) break ;;
                esac
            done
            ;;
        *)
            token_index=0
            ;;
    esac

    ((token_index >= ${#tokens[@]})) && return 0
    echo "${tokens[$token_index]}"
}

# ---------------------------------------------------------------------------
# extract_hook_script_basename_from_hook_command <command>
#
# Echo just the script's basename (`posttooluse-reminder.ts`). Equivalent to
# `basename "$(extract_hook_script_path_from_hook_command "$cmd")"` without the
# fork, and correct for every shape above.
# ---------------------------------------------------------------------------
extract_hook_script_basename_from_hook_command() {
    local script_path
    script_path=$(extract_hook_script_path_from_hook_command "$1")
    echo "${script_path##*/}"
}
