#!/usr/bin/env bash
# Test fixture: SC2164 - cd without error check

function bad_function() {
    # Silent failure - cd might fail!
    cd /nonexistent/path
    rm -rf *  # Dangerous if cd failed!
}
