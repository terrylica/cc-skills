#!/usr/bin/env bash
#
# Code Correctness Guard - PostToolUse hook for itp-hooks
#
# Detects code correctness issues that cause runtime failures:
# 1. Silent failure patterns (swallowed exceptions, missing error handling)
# 2. Cross-language syntax errors (shell variables in Python, etc.)
#
# Uses the "decision: block" JSON format for visibility (per ADR 2025-12-17).
#
# Detection:
# - Bash tool: Non-zero exit codes with stderr
# - Write/Edit on .sh/.bash: ShellCheck analysis (SC2155, SC2164, SC2181, SC2086 etc.)
# - Write/Edit on .py: Ruff silent failure rules + shell variable syntax detection
# - Write/Edit on .js/.ts: Oxlint + custom floating promise detection
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
1. SC2155: SPLIT declaration from assignment - 'local var=\$(cmd)' masks exit code
   FIX: 'local var; var=\$(cmd)' - now \$? reflects command exit status
2. SC2164: ALWAYS handle cd/pushd failures - 'cd dir' silently continues if dir missing
   FIX: 'cd dir || exit 1' or 'cd dir || { echo 'Failed'; exit 1; }'
3. SC2181: DON'T use \$? in conditionals - 'if [ \$? -eq 0 ]' is fragile
   FIX: 'if command; then' - directly test the command
4. SC2086: QUOTE variable expansions - unquoted vars cause word splitting bugs
   FIX: Use \"\$var\" instead of \$var
5. USE 'set -euo pipefail' at script start to fail fast on errors

Fix each issue at the line indicated. The error message explains what pattern to fix."

    PYTHON_FIX_GUIDANCE="PYTHON SILENT FAILURE PRINCIPLES:
1. NEVER use bare 'except:' - it catches KeyboardInterrupt, SystemExit, and hides real bugs
2. NEVER use 'except: pass' - errors must be logged, re-raised, or explicitly handled
3. CATCH SPECIFIC exceptions - use 'except ValueError:' or 'except (TypeError, KeyError):'
4. ALWAYS log or handle exceptions - at minimum: logging.exception('Context message')
5. RE-RAISE if you can't handle - 'except SomeError: logger.error(...); raise'
6. ALWAYS use subprocess.run(..., check=True) - without check=True, non-zero exits are silent
   - PLW1510: subprocess.run() without check= silently ignores command failures

Fix each pattern to make failures VISIBLE and ACTIONABLE, not silent."

    SHELL_VAR_FIX_GUIDANCE="CROSS-LANGUAGE SYNTAX ERROR:
Python does NOT expand shell variables like \$HOME, \$USER, \$PATH.
The string \"\$HOME/.config\" is interpreted LITERALLY, creating a directory named '\$HOME'.

CORRECT PATTERNS:
  Path.home() / '.config'              # pathlib (recommended)
  os.path.expanduser('~/.config')      # os module
  os.environ['HOME'] + '/.config'      # explicit env var
  os.path.expandvars('\$HOME/.config')  # if you must use \$HOME syntax

WRONG PATTERNS:
  Path('\$HOME/.config')               # Creates literal '\$HOME' directory!
  open('\$HOME/.config/file')          # FileNotFoundError or wrong location
  subprocess.run(cwd='\$HOME/...')     # Wrong working directory

This is a common mistake when doing bulk find-replace across polyglot codebases."

    JS_FIX_GUIDANCE="JAVASCRIPT/TYPESCRIPT SILENT FAILURE PRINCIPLES:
1. EMPTY CATCH: Never use 'catch (e) {}' - it hides all errors completely
   FIX: 'catch (e) { console.error('Context:', e); throw e; }'
2. FLOATING PROMISES: .then() without .catch() silently drops rejections
   FIX: Always chain .catch() OR use try/await/catch pattern
3. UNHANDLED ASYNC: async functions without try/catch lose errors
   FIX: Wrap await in try/catch: 'try { await fn(); } catch (e) { handle(e); }'
4. SWALLOWED ERRORS: 'catch (e) { /* ignore */ }' hides bugs
   FIX: At minimum log: 'catch (e) { console.error('Failed:', e); }'
5. RE-THROW UNKNOWN: If you can't handle it, re-throw
   FIX: 'catch (e) { if (e instanceof Expected) handle(); else throw e; }'

Silent JS failures are debugging nightmares. Make every error VISIBLE."

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

        # === Python: Ruff for silent failure patterns + shell variable detection ===
        *.py)
            # Check 1: Shell variables in Python strings (e.g., Path("$HOME/..."))
            # This catches the bug where bulk sed replace puts shell syntax in Python
            # Pattern 1: Function calls like Path("$HOME"), open("$HOME"), chdir("$HOME")
            # Pattern 2: Keyword args like cwd="$HOME", path="$HOME"
            SHELL_VAR_ISSUES=$(grep -nE '(Path|open|chdir)\s*\(\s*["\x27]\$[A-Z_]+|(cwd|path|dir|directory|folder|home)\s*=\s*["\x27]\$[A-Z_]+' "$FILE_PATH" 2>/dev/null || true)
            if [[ -n "$SHELL_VAR_ISSUES" ]]; then
                SHELL_VAR_COUNT=$(echo "$SHELL_VAR_ISSUES" | wc -l | tr -d ' ')
                SHELL_VAR_SUMMARY=$(echo "$SHELL_VAR_ISSUES" | head -3 | sed 's/^\([0-9]*\):.*/Line \1: Shell variable in Python string/')
                emit_warning "SHELL-VAR-IN-PYTHON" \
                    "Found $SHELL_VAR_COUNT shell variable(s) in Python - Python doesn't expand \$HOME" \
                    "$FILE_PATH" \
                    "$SHELL_VAR_SUMMARY" \
                    "$SHELL_VAR_FIX_GUIDANCE"
            fi

            # Check 2: Ruff for silent failure patterns
            if command -v ruff &>/dev/null; then
                RUFF_OUTPUT=$(ruff check \
                    --select=E722,S110,S112,BLE001,PLW1510 \
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

        # === JavaScript/TypeScript: Oxlint + Custom patterns ===
        *.js|*.ts|*.mjs|*.tsx|*.jsx)
            ISSUES_FOUND=""
            ISSUE_COUNT=0

            # Run Oxlint if available
            if command -v oxlint &>/dev/null; then
                OXLINT_OUTPUT=$(oxlint "$FILE_PATH" 2>&1 || true)

                # Extract actual issue lines (format: " × error" or " ⚠ warning")
                # Exclude summary line like "Found 0 warnings and 0 errors."
                OXLINT_ISSUES=$(echo "$OXLINT_OUTPUT" | grep -E '^\s*(×|⚠)\s+(error|warning)' || true)
                OXLINT_COUNT=0
                if [[ -n "$OXLINT_ISSUES" ]]; then
                    OXLINT_COUNT=$(echo "$OXLINT_ISSUES" | wc -l | tr -d ' ')
                fi

                if [[ "$OXLINT_COUNT" -gt 0 ]]; then
                    ISSUES_FOUND=$(echo "$OXLINT_ISSUES" | head -3)
                    ISSUE_COUNT=$((ISSUE_COUNT + OXLINT_COUNT))
                fi
            fi

            # Custom: Detect floating promises (.then without .catch on same logical block)
            # Pattern: .then( without .catch( within 3 lines
            FLOATING_PROMISES=$(grep -n '\.then(' "$FILE_PATH" 2>/dev/null | while read -r line; do
                LINE_NUM=$(echo "$line" | cut -d: -f1)
                # Check if .catch exists within 3 lines after
                if ! sed -n "${LINE_NUM},$((LINE_NUM + 3))p" "$FILE_PATH" | grep -q '\.catch('; then
                    echo "Line $LINE_NUM: Floating promise - .then() without .catch()"
                fi
            done || true)

            if [[ -n "$FLOATING_PROMISES" ]]; then
                FLOATING_COUNT=$(echo "$FLOATING_PROMISES" | wc -l | tr -d ' ')
                ISSUE_COUNT=$((ISSUE_COUNT + FLOATING_COUNT))
                if [[ -n "$ISSUES_FOUND" ]]; then
                    ISSUES_FOUND="$ISSUES_FOUND
$FLOATING_PROMISES"
                else
                    ISSUES_FOUND="$FLOATING_PROMISES"
                fi
            fi

            # Custom: Detect empty catch blocks
            EMPTY_CATCH=$(grep -nE 'catch\s*\([^)]*\)\s*\{\s*\}' "$FILE_PATH" 2>/dev/null | \
                head -3 | sed 's/^\([0-9]*\):.*/Line \1: Empty catch block - errors silently swallowed/' || true)

            if [[ -n "$EMPTY_CATCH" ]]; then
                EMPTY_COUNT=$(echo "$EMPTY_CATCH" | wc -l | tr -d ' ')
                ISSUE_COUNT=$((ISSUE_COUNT + EMPTY_COUNT))
                if [[ -n "$ISSUES_FOUND" ]]; then
                    ISSUES_FOUND="$ISSUES_FOUND
$EMPTY_CATCH"
                else
                    ISSUES_FOUND="$EMPTY_CATCH"
                fi
            fi

            # Emit warning if any issues found
            if [[ "$ISSUE_COUNT" -gt 0 ]]; then
                ISSUES_SUMMARY=$(echo "$ISSUES_FOUND" | head -5)
                emit_warning "JS-SILENT-FAILURE" \
                    "Found $ISSUE_COUNT JS/TS silent failure pattern(s) - fix before continuing" \
                    "$FILE_PATH" \
                    "$ISSUES_SUMMARY" \
                    "$JS_FIX_GUIDANCE"
            fi
            ;;
    esac
fi

# Always exit 0 - we're non-blocking, visibility comes from JSON format
exit 0
