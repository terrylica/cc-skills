#!/usr/bin/env bash
# test-code-correctness-guard-inline-ignore-convention.sh
#
# Regression test for the INLINE-IGNORE-AUDIT in code-correctness-guard.sh honouring the
# repository's own convention (2026-10-17). Reported: `# noqa: E402` after `sys.path.insert(...)`
# was flagged in a repository that uses that pattern in every script.
#
# Not flagged (convention):
#   (A) E402 in a file that changes sys.path before importing
#   (B) a code suppressed inline in >= 3 other tracked Python files
#   (C) a code the repository's ruff configuration ignores for this file (per-file glob, or an
#       ignored prefix such as E7 for E731)
# Still flagged (true positives):
#   (D) a one-off `# noqa: F401` with no convention behind it
#   (E) a bare `# noqa` (no code to look up)
#   (F) E402 without a sys.path change
#   (G) a per-file ignore whose glob names another path
#   (H) a code that is only in `select` (turned on, not ignored)

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_UNDER_TEST="$SCRIPT_DIR/../code-correctness-guard.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed (the hook needs it)"
  exit 0
fi

PASS=0
FAIL=0
assert_pass() { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

# NOT under a temp directory and NOT under */tests/*: the hook exits early for /tmp, $TMPDIR and
# /var/folders files, and the inline audit skips test paths, so a fixture there would pass vacuously.
FIXTURE_PARENT="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$FIXTURE_PARENT"
FIXTURE="$(mktemp -d "$FIXTURE_PARENT/cc-inline-ignore-XXXXXX")"
cleanup() { rm -rf -- "$FIXTURE"; }
trap cleanup EXIT

git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.email t@e.st
git -C "$FIXTURE" config user.name t
mkdir -p "$FIXTURE/pkg"
for n in 1 2 3; do
  printf 'LIMIT = 7  # noqa: PLR2004\n' > "$FIXTURE/pkg/other_$n.py"
done
mkdir -p "$FIXTURE/scripts"
printf '[tool.ruff.lint]\nselect = ["PLW0603"]\nignore = ["E7"]\n\n[tool.ruff.lint.per-file-ignores]\n"scripts/*.py" = ["B008"]\n' > "$FIXTURE/pyproject.toml"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" commit -qm fixtures

audit_fires_for() {
  local file="$1" content="$2" out
  printf '%s' "$content" > "$file"
  out=$(jq -n --arg f "$file" --arg c "$content" '{tool_name: "Write", tool_input: {file_path: $f, content: $c}}' \
    | "$HOOK_UNDER_TEST" 2>/dev/null) || true
  [[ "$out" == *"INLINE-IGNORE-AUDIT"* ]]
}

echo "=== convention: not flagged ==="
if audit_fires_for "$FIXTURE/a_syspath.py" $'import sys\nsys.path.insert(0, "lib")\nimport helper  # noqa: E402\n'; then
  assert_fail "(A) E402 after sys.path.insert was flagged"
else
  assert_pass "(A) E402 after sys.path.insert is not flagged"
fi

if audit_fires_for "$FIXTURE/c_common.py" $'THRESHOLD = 9  # noqa: PLR2004\n'; then
  assert_fail "(B) a code used in 3 other tracked files was flagged"
else
  assert_pass "(B) a code used in 3 other tracked files is not flagged"
fi

if audit_fires_for "$FIXTURE/scripts/d_config.py" $'def f(x=list()):  # noqa: B008\n    return x\n'; then
  assert_fail "(C) a code the ruff config ignores for this file (per-file glob) was flagged"
else
  assert_pass "(C) a code the ruff config ignores for this file (per-file glob) is not flagged"
fi

if audit_fires_for "$FIXTURE/c2_prefix.py" $'x = 1 if True else 2  # noqa: E731\n'; then
  assert_fail "(C2) a code covered by an ignored prefix (E7) was flagged"
else
  assert_pass "(C2) a code covered by an ignored prefix (E7) is not flagged"
fi

echo "=== true positives: still flagged ==="
if audit_fires_for "$FIXTURE/e_oneoff.py" $'import os  # noqa: F401\n'; then
  assert_pass "(D) a one-off noqa: F401 is flagged"
else
  assert_fail "(D) a one-off noqa: F401 was NOT flagged"
fi

if audit_fires_for "$FIXTURE/f_bare.py" $'import os  # noqa\n'; then
  assert_pass "(E) a bare # noqa is flagged"
else
  assert_fail "(E) a bare # noqa was NOT flagged"
fi

if audit_fires_for "$FIXTURE/g_e402_no_syspath.py" $'X = 1\nimport os  # noqa: E402\n'; then
  assert_pass "(F) E402 without a sys.path change is flagged"
else
  assert_fail "(F) E402 without a sys.path change was NOT flagged"
fi

if audit_fires_for "$FIXTURE/h_other_glob.py" $'def f(x=list()):  # noqa: B008\n    return x\n'; then
  assert_pass "(G) a per-file ignore for ANOTHER path does not excuse this file"
else
  assert_fail "(G) a per-file ignore for another path excused this file"
fi

if audit_fires_for "$FIXTURE/i_selected.py" $'global X  # noqa: PLW0603\n'; then
  assert_pass "(H) a code that is only SELECTED (turned on) is still flagged"
else
  assert_fail "(H) a code that is only selected was treated as ignored"
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
