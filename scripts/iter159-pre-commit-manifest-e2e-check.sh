#!/usr/bin/env bash
#
# iter-159 empirical end-to-end validation harness for iter-158's
# .pre-commit-hooks.yaml manifest claim.
#
# Purpose: prove the iter-158 polyglot pre-commit framework integration is
# empirically real — not just structurally valid — by actually invoking the
# `pre-commit` binary against a sandbox repo that pins cc-skills as a hook
# source. Closes the credibility gap parallel to what iter-148 closed for
# iter-147's SSH multiplexing claim.
#
# Why this is separate from the iter-158 regression test:
#
#   • iter-158's regression test smoke-tests the entry-point STANDALONE
#     (invokes it directly with a synthetic commit-msg file). It also
#     verifies the YAML manifest structurally (parseable, declares
#     canonical fields). What it does NOT verify is the end-to-end
#     framework contract: does `pre-commit run --hook-stage commit-msg`
#     actually discover the manifest, clone cc-skills into its cache, find
#     the entry-point at the cached path, pass the commit-msg file path
#     correctly, and propagate the exit code back to git?
#
#   • This iter-159 harness exercises that full chain.
#
# Empirical-validation outputs:
#   ✓ Real pre-commit binary runs end-to-end against a local cc-skills source.
#   ✓ COMPOUND-PREFIX subject is REJECTED (git commit exit code != 0).
#   ✓ STANDARD-CONFORMANT subject is ACCEPTED (git commit exit code == 0).
#   ✓ Per-trial wall-clock latency reported to surface the framework's
#     overhead vs. iter-157's direct hook (which skips pre-commit's own
#     dispatch logic).
#
# Tunables:
#   ITER159_VALIDATION_TRIAL_COUNT_PER_SUBJECT_VARIANT (default 1)
#     Number of git-commit attempts per subject variant. Multiple trials
#     surface variance in the framework's dispatch overhead.

set -euo pipefail

ITER159_HARNESS_SCRIPT_DIRECTORY_ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITER159_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH="$(cd "$ITER159_HARNESS_SCRIPT_DIRECTORY_ABSOLUTE_PATH/.." && pwd)"
ITER159_VALIDATION_TRIAL_COUNT_PER_SUBJECT_VARIANT="${ITER159_VALIDATION_TRIAL_COUNT_PER_SUBJECT_VARIANT:-1}"

# Require the pre-commit binary on PATH. We do not auto-install — operators
# may have it in a venv (cc-skills' canonical workspace has it at
# $HOME/.venv/bin/pre-commit per the user's uv tooling preference).
if ! command -v pre-commit >/dev/null 2>&1; then
    echo "  ✗ iter-159 harness: 'pre-commit' binary not on PATH" >&2
    echo "    Install via: uv tool install pre-commit" >&2
    exit 1
fi

ITER159_PRE_COMMIT_BINARY_VERSION_REPORT=$(pre-commit --version 2>&1 | head -1)

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-159 EMPIRICAL END-TO-END PRE-COMMIT-FRAMEWORK VALIDATION HARNESS"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  cc-skills source: $ITER159_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH"
echo "  pre-commit:       $ITER159_PRE_COMMIT_BINARY_VERSION_REPORT"
echo "  trials/variant:   $ITER159_VALIDATION_TRIAL_COUNT_PER_SUBJECT_VARIANT"
echo ""

# ─── Set up sandbox repo + sandboxed pre-commit cache ───────────────────────
#
# We sandbox both the consumer repo AND the pre-commit framework cache via
# PRE_COMMIT_HOME, so that:
#
#   1. The harness is hermetic — no contamination of the operator's
#      global ~/.cache/pre-commit/ from harness runs.
#   2. We avoid the "stale-clone-keyed-by-HEAD" trap: pre-commit caches by
#      (URL, rev), and treats `rev: HEAD` as a stable string. If the
#      operator's global cache has a stale clone from before the current
#      iter-158 commit, the harness would resolve the iter-158 entry-point
#      to a missing file. Sandboxing the cache forces a fresh clone every
#      run, guaranteeing the iter-158 entry-point is the one we just
#      committed.

ITER159_SANDBOX_REPO_ABSOLUTE_PATH=$(mktemp -d -t iter159-empirical-sandbox-XXXXXX)
ITER159_SANDBOXED_PRE_COMMIT_FRAMEWORK_CACHE_HOME_DIRECTORY=$(mktemp -d -t iter159-precommit-cache-XXXXXX)
export PRE_COMMIT_HOME="$ITER159_SANDBOXED_PRE_COMMIT_FRAMEWORK_CACHE_HOME_DIRECTORY"
trap 'rm -rf "$ITER159_SANDBOX_REPO_ABSOLUTE_PATH" "$ITER159_SANDBOXED_PRE_COMMIT_FRAMEWORK_CACHE_HOME_DIRECTORY"' EXIT
echo "  sandbox repo:     $ITER159_SANDBOX_REPO_ABSOLUTE_PATH"
echo "  sandboxed cache:  $ITER159_SANDBOXED_PRE_COMMIT_FRAMEWORK_CACHE_HOME_DIRECTORY"

# Resolve cc-skills HEAD to a specific commit SHA. Pinning the rev to a
# stable SHA — rather than the literal string "HEAD" — eliminates the
# pre-commit framework's "mutable reference" warning and makes the cache
# key correctly reflect the current iter-158 commit content.
ITER159_CC_SKILLS_HEAD_COMMIT_SHA_FOR_STABLE_PRE_COMMIT_REV_PINNING=$(
    git -C "$ITER159_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH" rev-parse HEAD
)
echo "  cc-skills rev:    $ITER159_CC_SKILLS_HEAD_COMMIT_SHA_FOR_STABLE_PRE_COMMIT_REV_PINNING"

(
    cd "$ITER159_SANDBOX_REPO_ABSOLUTE_PATH"
    git init --quiet --initial-branch=main
    git config user.email iter159-harness@local.test
    git config user.name "iter-159 empirical harness"
    cat > .pre-commit-config.yaml <<EOF
default_install_hook_types:
  - commit-msg
repos:
  - repo: file://$ITER159_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH
    rev: $ITER159_CC_SKILLS_HEAD_COMMIT_SHA_FOR_STABLE_PRE_COMMIT_REV_PINNING
    hooks:
      - id: cc-skills-commits-advise-commit-msg
EOF
    git add .pre-commit-config.yaml
    git commit --no-verify --quiet -m "chore(init): iter-159 sandbox bootstrap"
)

# Install the commit-msg hook into the sandbox via the framework.
echo ""
echo "── Step 1: pre-commit install --hook-type commit-msg ──"
ITER159_PRE_COMMIT_INSTALL_OUTPUT=$(
    cd "$ITER159_SANDBOX_REPO_ABSOLUTE_PATH" \
        && pre-commit install --hook-type commit-msg 2>&1
)
echo "  $ITER159_PRE_COMMIT_INSTALL_OUTPUT"

# Pre-fetch cc-skills into the framework's cache so the first real trial
# doesn't include clone-cost variance.
echo ""
echo "── Step 2: pre-commit try-repo (pre-warm cache) ──"
ITER159_PRE_WARM_OUTPUT=$(
    cd "$ITER159_SANDBOX_REPO_ABSOLUTE_PATH" \
        && pre-commit run --hook-stage commit-msg --all-files 2>&1 | tail -5 || true
)
echo "$ITER159_PRE_WARM_OUTPUT" | awk '{ print "  " $0 }'

# ─── Helper: time a git commit attempt and check the expected exit code ─────

iter159_invoke_git_commit_through_pre_commit_framework_and_capture_exit_code_and_wall_clock_milliseconds() {
    local subject_label_for_logging="$1"
    local proposed_subject="$2"
    local expected_exit_code="$3"

    local trial_number=1
    local empirical_pass_count=0
    local empirical_fail_count=0
    local trial_wall_clock_durations_in_milliseconds=()

    while (( trial_number <= ITER159_VALIDATION_TRIAL_COUNT_PER_SUBJECT_VARIANT )); do
        # Ensure the worktree has something to commit (an empty commit suffices).
        (
            cd "$ITER159_SANDBOX_REPO_ABSOLUTE_PATH"
            local trial_start_nanoseconds
            local trial_end_nanoseconds
            local actual_exit_code=0
            trial_start_nanoseconds=$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time*1e9')
            git -c core.editor=true commit --allow-empty -m "$proposed_subject" >/dev/null 2>&1 \
                || actual_exit_code=$?
            trial_end_nanoseconds=$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time*1e9')
            local elapsed_milliseconds=$(( (trial_end_nanoseconds - trial_start_nanoseconds) / 1000000 ))
            printf '%d %d\n' "$actual_exit_code" "$elapsed_milliseconds"
        ) > "$ITER159_SANDBOX_REPO_ABSOLUTE_PATH/.trial-result-$trial_number"
        read -r actual_exit_code elapsed_milliseconds < "$ITER159_SANDBOX_REPO_ABSOLUTE_PATH/.trial-result-$trial_number"
        rm -f "$ITER159_SANDBOX_REPO_ABSOLUTE_PATH/.trial-result-$trial_number"

        trial_wall_clock_durations_in_milliseconds+=("$elapsed_milliseconds")
        if [[ "$actual_exit_code" -eq "$expected_exit_code" ]] \
           || { [[ "$expected_exit_code" -ne 0 ]] && [[ "$actual_exit_code" -ne 0 ]]; }; then
            empirical_pass_count=$((empirical_pass_count + 1))
        else
            empirical_fail_count=$((empirical_fail_count + 1))
        fi
        trial_number=$((trial_number + 1))
    done

    # Compute median latency across trials (no fancy stats — just report).
    local first_latency="${trial_wall_clock_durations_in_milliseconds[0]}"
    local latency_summary
    if (( ${#trial_wall_clock_durations_in_milliseconds[@]} > 1 )); then
        local all_latencies
        all_latencies=$(IFS=,; echo "${trial_wall_clock_durations_in_milliseconds[*]}")
        latency_summary="${first_latency}ms (trials: $all_latencies ms)"
    else
        latency_summary="${first_latency}ms"
    fi

    if (( empirical_fail_count == 0 )); then
        echo "  ✓ $subject_label_for_logging: $empirical_pass_count/$ITER159_VALIDATION_TRIAL_COUNT_PER_SUBJECT_VARIANT trials passed @ $latency_summary"
        return 0
    else
        echo "  ✗ $subject_label_for_logging: $empirical_fail_count/$ITER159_VALIDATION_TRIAL_COUNT_PER_SUBJECT_VARIANT trials FAILED @ $latency_summary"
        return 1
    fi
}

# ─── Step 3: empirical trials ───────────────────────────────────────────────

echo ""
echo "── Step 3: empirical commit trials through real pre-commit framework ──"

ITER159_TOTAL_VARIANT_FAILURES=0

iter159_invoke_git_commit_through_pre_commit_framework_and_capture_exit_code_and_wall_clock_milliseconds \
    "COMPOUND-PREFIX subject → expect REJECT" \
    "feat(scope)+docs: bad compound prefix iter-159 trial" \
    "1" \
    || ITER159_TOTAL_VARIANT_FAILURES=$((ITER159_TOTAL_VARIANT_FAILURES + 1))

iter159_invoke_git_commit_through_pre_commit_framework_and_capture_exit_code_and_wall_clock_milliseconds \
    "MISSING-TYPE subject → expect REJECT" \
    "just fix the bug in the parser iter-159 trial" \
    "1" \
    || ITER159_TOTAL_VARIANT_FAILURES=$((ITER159_TOTAL_VARIANT_FAILURES + 1))

iter159_invoke_git_commit_through_pre_commit_framework_and_capture_exit_code_and_wall_clock_milliseconds \
    "STANDARD-CONFORMANT subject → expect ACCEPT" \
    "feat(test): iter-159 empirical trial conformant" \
    "0" \
    || ITER159_TOTAL_VARIANT_FAILURES=$((ITER159_TOTAL_VARIANT_FAILURES + 1))

iter159_invoke_git_commit_through_pre_commit_framework_and_capture_exit_code_and_wall_clock_milliseconds \
    "breaking-change shorthand feat!: → expect ACCEPT" \
    "feat!: drop legacy API iter-159 trial" \
    "0" \
    || ITER159_TOTAL_VARIANT_FAILURES=$((ITER159_TOTAL_VARIANT_FAILURES + 1))

# ─── Final report ────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER159_TOTAL_VARIANT_FAILURES == 0 )); then
    echo "  ✓ ITER-159 EMPIRICAL VALIDATION: ALL 4 SUBJECT VARIANTS PASSED through real pre-commit framework"
    echo "    Iter-158 polyglot consumption claim is EMPIRICALLY REAL, not just structurally valid."
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-159 EMPIRICAL VALIDATION: $ITER159_TOTAL_VARIANT_FAILURES of 4 variants FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
