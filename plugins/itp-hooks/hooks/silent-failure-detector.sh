#!/usr/bin/env bash
#
# Silent Failure Detector - PostToolUse hook for itp-hooks
#
# Detects silent failure patterns in code and emits LOUD warnings to Claude Code CLI.
# Uses the "decision: block" JSON format for visibility (per ADR 2025-12-17).
#
# Detection:
# - Bash tool: Non-zero exit codes with stderr
# - Write/Edit on .sh/.bash: ShellCheck analysis
# - Write/Edit on .py: Ruff silent failure rules (E722, S110, S112, BLE001)
# - Write/Edit on .js/.ts: Oxlint analysis
#
# Exit behavior:
# - Always exits 0 (non-blocking) - Claude continues but sees the warning
# - Uses "decision: block" in JSON for visibility, not execution blocking
#

set -euo pipefail

# Read JSON input from Claude Code
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Emit warning in Claude-visible format with FIX GUIDANCE
# Per ADR 2025-12-17: "decision: block" is required for Claude to see PostToolUse output
# IMPORTANT: Only the "reason" field is visible to Claude - all content must go there
emit_warning() {
    local category="$1"
    local message="$2"
    local file_path="${3:-}"
    local details="${4:-}"
    local fix_guidance="${5:-}"

    # Build the complete reason string - this is ALL Claude sees
    local full_reason="[$category] $message"

    if [[ -n "$file_path" ]]; then
        full_reason="$full_reason

FILE: $file_path"
    fi

    if [[ -n "$details" ]]; then
        full_reason="$full_reason

ISSUES DETECTED:
$details"
    fi

    if [[ -n "$fix_guidance" ]]; then
        full_reason="$full_reason

$fix_guidance"
    fi

    # Output JSON - ONLY decision and reason are read by Claude Code
    jq -n --arg reason "$full_reason" '{decision: "block", reason: $reason}'
}

# === BASH TOOL: Check exit code and stderr patterns ===
if [[ "$TOOL_NAME" == "Bash" ]]; then
    EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_output.exit_code // 0')
    STDERR=$(echo "$INPUT" | jq -r '.tool_output.stderr // ""')
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

    # Skip if exit code is 0 (success)
    if [[ "$EXIT_CODE" -eq 0 ]]; then
        exit 0
    fi

    # Skip certain expected failures (grep no match, diff has differences, etc.)
    if [[ "$EXIT_CODE" -eq 1 ]] && [[ "$COMMAND" =~ ^(grep|diff|test|\[) ]]; then
        exit 0
    fi

    # Non-zero exit with meaningful stderr indicates potential failure
    if [[ -n "$STDERR" ]]; then
        # Truncate long stderr for readability
        STDERR_TRUNCATED="${STDERR:0:500}"
        if [[ ${#STDERR} -gt 500 ]]; then
            STDERR_TRUNCATED="${STDERR_TRUNCATED}..."
        fi

        BASH_FIX_GUIDANCE="SILENT FAILURE PRINCIPLE: Commands that fail silently cause cascading issues. YOU MUST:
1. ACKNOWLEDGE the failure explicitly - do not proceed as if it succeeded
2. DIAGNOSE the root cause from the stderr message above
3. FIX the underlying issue (missing dependency, wrong path, permission, etc.)
4. RE-RUN the command to verify it succeeds (exit code 0)
5. If the command is expected to fail sometimes, handle it explicitly with '|| true' or conditionals

NEVER ignore non-zero exit codes. Every failure has a cause that must be addressed."

        emit_warning "BASH-FAILURE" \
            "Command exited with code $EXIT_CODE - STOP and fix before continuing" \
            "" \
            "$STDERR_TRUNCATED" \
            "$BASH_FIX_GUIDANCE"
    fi

    exit 0
fi

# === WRITE/EDIT TOOL: Run static analysis on new/modified files ===
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

    # Early exit for empty paths or non-existent files
    [[ -z "$FILE_PATH" ]] && exit 0
    [[ ! -f "$FILE_PATH" ]] && exit 0

    # Principle-based fix guidance for each language
    SHELL_FIX_GUIDANCE="SHELL SILENT FAILURE PRINCIPLES:
1. NEVER mask return values - if a command can fail, its exit status must be checkable
2. ALWAYS handle cd/pushd failures - use 'cd dir || exit 1' or 'cd dir || return 1'
3. SPLIT declaration from assignment when capturing command output - 'local var; var=\$(cmd)'
4. USE 'set -euo pipefail' at script start to fail fast on errors
5. CHECK exit codes explicitly for critical operations

Fix each issue at the line indicated. The error message explains what pattern to fix."

    PYTHON_FIX_GUIDANCE="PYTHON SILENT FAILURE PRINCIPLES:
1. NEVER use bare 'except:' - it catches KeyboardInterrupt, SystemExit, and hides real bugs
2. NEVER use 'except: pass' - errors must be logged, re-raised, or explicitly handled
3. CATCH SPECIFIC exceptions - use 'except ValueError:' or 'except (TypeError, KeyError):'
4. ALWAYS log or handle exceptions - at minimum: logging.exception('Context message')
5. RE-RAISE if you can't handle - 'except SomeError: logger.error(...); raise'

Fix each pattern to make failures VISIBLE and ACTIONABLE, not silent."

    JS_FIX_GUIDANCE="JAVASCRIPT/TYPESCRIPT SILENT FAILURE PRINCIPLES:
1. NEVER use empty catch blocks - 'catch (e) {}' hides all errors completely
2. ALWAYS handle or log errors - at minimum: console.error('Context:', e)
3. AWAIT all promises or attach .catch() - floating promises lose errors silently
4. USE try/catch around await - async errors need explicit handling
5. RE-THROW if you can't handle - 'catch (e) { logger.error(e); throw e; }'

Fix each pattern to make failures VISIBLE. Silent failures compound into debugging nightmares."

    case "$FILE_PATH" in
        # === Shell Scripts: ShellCheck ===
        *.sh|*.bash)
            if command -v shellcheck &>/dev/null; then
                SHELLCHECK_OUTPUT=$(shellcheck \
                    -f json \
                    -e SC1091 \
                    "$FILE_PATH" 2>/dev/null || true)

                if [[ -n "$SHELLCHECK_OUTPUT" ]] && [[ "$SHELLCHECK_OUTPUT" != "[]" ]]; then
                    ISSUE_COUNT=$(echo "$SHELLCHECK_OUTPUT" | jq 'length')

                    ISSUES_SUMMARY=$(echo "$SHELLCHECK_OUTPUT" | jq -r '
                        .[0:3] | .[] |
                        "Line \(.line): SC\(.code) - \(.message)"
                    ' | head -5)

                    if [[ "$ISSUE_COUNT" -gt 0 ]]; then
                        emit_warning "SHELLCHECK" \
                            "Found $ISSUE_COUNT shell issue(s) - fix before continuing" \
                            "$FILE_PATH" \
                            "$ISSUES_SUMMARY" \
                            "$SHELL_FIX_GUIDANCE"
                    fi
                fi
            fi
            ;;

        # === Python: Ruff for silent failure patterns ===
        *.py)
            if command -v ruff &>/dev/null; then
                RUFF_OUTPUT=$(ruff check \
                    --select=E722,S110,S112,BLE001 \
                    --output-format=json \
                    "$FILE_PATH" 2>/dev/null || true)

                if [[ -n "$RUFF_OUTPUT" ]] && [[ "$RUFF_OUTPUT" != "[]" ]]; then
                    ISSUE_COUNT=$(echo "$RUFF_OUTPUT" | jq 'length')

                    ISSUES_SUMMARY=$(echo "$RUFF_OUTPUT" | jq -r '
                        .[0:3] | .[] |
                        "Line \(.location.row): \(.code) - \(.message)"
                    ' | head -5)

                    if [[ "$ISSUE_COUNT" -gt 0 ]]; then
                        emit_warning "RUFF-SILENT-FAILURE" \
                            "Found $ISSUE_COUNT Python silent failure pattern(s) - fix before continuing" \
                            "$FILE_PATH" \
                            "$ISSUES_SUMMARY" \
                            "$PYTHON_FIX_GUIDANCE"
                    fi
                fi
            fi
            ;;

        # === JavaScript/TypeScript: Oxlint ===
        *.js|*.ts|*.mjs|*.tsx|*.jsx)
            if command -v oxlint &>/dev/null; then
                OXLINT_OUTPUT=$(oxlint "$FILE_PATH" 2>&1 || true)

                ERROR_COUNT=$(echo "$OXLINT_OUTPUT" | grep -c "error" || true)
                WARNING_COUNT=$(echo "$OXLINT_OUTPUT" | grep -c "warning" || true)
                TOTAL_COUNT=$((ERROR_COUNT + WARNING_COUNT))

                if [[ "$TOTAL_COUNT" -gt 0 ]]; then
                    ISSUES_SUMMARY=$(echo "$OXLINT_OUTPUT" | grep -E "error|warning" | head -5)

                    emit_warning "OXLINT" \
                        "Found $TOTAL_COUNT JS/TS issue(s) - fix before continuing" \
                        "$FILE_PATH" \
                        "$ISSUES_SUMMARY" \
                        "$JS_FIX_GUIDANCE"
                fi
            fi
            ;;
    esac
fi

# Always exit 0 - we're non-blocking, visibility comes from JSON format
exit 0
