#!/usr/bin/env bash
# Prove the guard in BOTH directions: it must fire on umbrella targets and stay
# silent on everything else. A guard only tested in the firing direction is a
# guard that might deny everything.
#
# No pipelines into early-exiting readers: the decision is matched with `case`
# on captured text, so there is no SIGPIPE race to invert a boolean.
set -uo pipefail
H="$HOME/eon/cc-skills/plugins/itp-hooks/hooks/pretooluse-umbrella-no-repo-guard.ts"
PY=/usr/bin/python3

json() { printf '%s' "$1" | "$PY" -c 'import json,sys;print(json.dumps(sys.stdin.read()))'; }

check() { # $1 = label, $2 = expect(deny|allow), $3 = cwd, $4 = cmd
  local payload out got
  payload=$(printf '{"tool_name":"Bash","cwd":%s,"tool_input":{"command":%s}}' "$(json "$3")" "$(json "$4")")
  out=$(printf '%s' "$payload" | bun "$H" 2>/dev/null)
  case "$out" in
    *'"permissionDecision":"deny"'*) got=deny ;;
    *) got=allow ;;
  esac
  if [ "$got" = "$2" ]; then
    printf '  PASS  %-52s -> %s\n' "$1" "$got"
  else
    printf '  FAIL  %-52s -> %s (expected %s)\n' "$1" "$got" "$2"
    FAILED=$((FAILED + 1))
  fi
}

FAILED=0

echo "MUST FIRE:"
check "git init in ~/459ecs"             deny  "$HOME/459ecs" "git init"
check "git init ~/459ecs from elsewhere" deny  "$HOME"        "git init ~/459ecs"
check "git init . in ~/eon"              deny  "$HOME/eon"    "git init ."
check "gh repo create in ~/vj"           deny  "$HOME/vj"     "gh repo create myrepo --private"
check "cd then init (compound)"          deny  "$HOME"        "cd /tmp && git init $HOME/own"
check "git init --bare on umbrella"      deny  "$HOME/459ecs" "git init --bare"
check "clone ONTO umbrella"              deny  "$HOME"        "git clone https://x/y.git $HOME/459ecs"

echo "MUST NOT FIRE:"
check "git init in a SUBDIR of umbrella" allow "$HOME"        "git init $HOME/459ecs/newthing"
check "git init in an unrelated dir"     allow "/tmp"         "git init"
check "git status in umbrella"           allow "$HOME/459ecs" "git status"
check "clone INTO a subdir"              allow "$HOME"        "git clone https://x/y.git $HOME/459ecs/y"
check "escape hatch honoured"            allow "$HOME/459ecs" "ALLOW_UMBRELLA_REPO=1 git init"
check "unrelated command mentioning git" allow "$HOME/459ecs" "echo git init"

printf '\n%s\n' "failures: $FAILED"
exit "$FAILED"
