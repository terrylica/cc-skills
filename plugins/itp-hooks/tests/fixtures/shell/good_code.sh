#!/usr/bin/env bash
# Test fixture: GOOD shell code (should pass)
set -euo pipefail

function good_function() {
    local result
    result=$(some_command) || return 1
    echo "$result"
}

function good_cd() {
    cd /some/path || exit 1
    echo "In directory"
}
