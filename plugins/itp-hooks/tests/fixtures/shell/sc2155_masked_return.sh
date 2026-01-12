#!/usr/bin/env bash
# Test fixture: SC2155 - masked return value

function bad_function() {
    # Silent failure - return value masked by local!
    local result=$(failing_command)
    echo "$result"
}
