#!/usr/bin/env bash
# scripts/lib/env-knob.sh — ONE home for reading an operator env knob that has a deprecated alias.
#
# The release and commits tooling used to name its env knobs after the iteration that added them
# (ITER134_PREFLIGHT_AUDIT_PARALLEL_LANES, ITER152_WORST_OFFENDER_CALLOUT_COUNT, …). Issue #224
# renamed them to say what they do. Old names keep working so nobody's shell setup breaks, and using
# one prints a single stderr line naming its replacement. When the aliases are retired, every
# `cc_knob VAR NEW OLD DEFAULT` call becomes `VAR="${NEW:-DEFAULT}"` and this file is deleted.
#
# It assigns through `printf -v` rather than printing, because `x="$(cc_knob …)"` forks a subshell
# per read, and the commits doctor's fork budget (tasks/tests/test-iter174-…) caught exactly that.
#
# The two Python scripts under scripts/ (iter144, iter147) cannot source this file and carry the
# same rule inline. Every shell reader sources it, including the commit-msg hook: installed
# repositories run that hook in place through an exec shim, not a copy (#229).
#
# Source it; do not execute it.

# cc_knob VAR NEW OLD DEFAULT — set VAR to NEW if set and non-empty, else to OLD (with a deprecation
# notice on stderr), else to DEFAULT. No subshell.
cc_knob() {
    local __cc_knob_var="$1" __cc_knob_new="$2" __cc_knob_old="$3" __cc_knob_default="$4"
    if [[ -n "${!__cc_knob_new:-}" ]]; then
        printf -v "$__cc_knob_var" '%s' "${!__cc_knob_new}"
    elif [[ -n "${!__cc_knob_old:-}" ]]; then
        printf '%s is deprecated; use %s (cc-skills #224)\n' "$__cc_knob_old" "$__cc_knob_new" >&2
        printf -v "$__cc_knob_var" '%s' "${!__cc_knob_old}"
    else
        printf -v "$__cc_knob_var" '%s' "$__cc_knob_default"
    fi
}
