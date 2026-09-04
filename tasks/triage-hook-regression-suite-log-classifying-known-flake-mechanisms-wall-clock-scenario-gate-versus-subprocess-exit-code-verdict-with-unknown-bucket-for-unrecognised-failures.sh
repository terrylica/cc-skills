#!/usr/bin/env bash
#MISE description="Triage a repo:test-hooks suite log into the known intermittent-failure mechanisms so a red run is diagnosed from evidence instead of re-run until green. Reads a captured suite log (moon run repo:test-hooks > log 2>&1) and classifies each failing assertion as CLASS A (a wall-clock scenario gate exceeded its cap — load-sensitive), CLASS A? (two harness invocations disagreed and the failing scenario is UNNAMED, so the reduction to CLASS A is INFERRED, not observed), CLASS B (the iter-160 doctor ran and reported a non-healthy verdict — a CRITICAL check returned non-zero, which is fork/exec pressure rather than elapsed time), CLASS C (a genuine mode-dispatch or JSON-leak defect, positively distinguished from CLASS A by the harness reporting that NO scenario failed), or UNKNOWN (matches no known mechanism — deliberately never absorbed into the nearest bucket, so a third mechanism has to announce itself). Prints the margin on every wall-clock failure because a 0.9%-over run and a 300%-over run are different diagnoses and must never render identically."
#
# ═══════════════════════════════════════════════════════════════════════════
#  Provenance
# ═══════════════════════════════════════════════════════════════════════════
#
# Built 2026-09-03 from three real red runs captured at 18:08-18:10 while five
# concurrent full suites plus a 36-process doctor repro were running on the same
# box. Six consecutive green runs immediately beforehand, with the identical
# command and the identical tree, are why "re-run it" was never going to find
# this: the variable was another process tree, invisible from inside either one.
#
# The classes are empirical, not designed. Each one is a failure shape that was
# actually observed and hand-triaged; the UNKNOWN bucket exists because that
# hand-triage twice found a shape the previous pass had not predicted.
#
# ═══════════════════════════════════════════════════════════════════════════
#  Two corrections found by READING the harness, not by running it
# ═══════════════════════════════════════════════════════════════════════════
#
#  1. The wall-clock pattern MUST be anchored to the `✗` form. The harness has a
#     CC_SKILLS_SKIP_PERF_TIMING path that emits a PASSING line still containing
#     the literal "median=NNNms > cap=NNNms". An unanchored substring match reads
#     that success as a CLASS A failure — a classifier that invents a red run.
#
#  2. `median=...` alone cannot be trusted to mean "a gate failed", for the same
#     reason. Every match below requires the failure marker on the same line.
#
# ═══════════════════════════════════════════════════════════════════════════
#  Usage
# ═══════════════════════════════════════════════════════════════════════════
#
#   moon run repo:test-hooks > /tmp/suite.log 2>&1 || true
#   bash tasks/triage-hook-regression-suite-log-...-unrecognised-failures.sh /tmp/suite.log
#
# Exits 0 always: this is a diagnostic, not a gate. A triage tool that can fail
# gives you two problems to debug instead of one.

set -euo pipefail

if [[ $# -eq 0 ]]; then
    printf 'usage: %s <suite.log> [more.log ...]\n' "$0" >&2
    printf '       %s --self-test\n' "$0" >&2
    printf '\n  Capture one with:  moon run repo:test-hooks > /tmp/suite.log 2>&1 || true\n' >&2
    exit 2
fi

# ═══════════════════════════════════════════════════════════════════════════
#  --self-test: negative-control the instrument against synthetic fixtures
# ═══════════════════════════════════════════════════════════════════════════
#
# Nobody negative-controls the instrument, which is why the instrument is
# likelier to be wrong than the thing it measures. Five separate diagnostic
# defects on 2026-09-03 were each caught by another pair of eyes or by a
# deliberately-broken input — never by re-reading the code that had the bug.
#
# The FIRST fixture is the one that matters most: a PASSING skip-path line that
# still contains the literal "median=NNNms > cap=NNNms". An unanchored CLASS A
# matcher classifies that success as a wall-clock failure and prints a confident
# margin for a test that passed. This asserts it lands in GREEN.
#
# Deliberately NOT placed in tasks/tests/: that directory is auto-discovered and
# executed by the suite, and shipping an unverified test there would redden
# everyone else's runs — the exact half-written-edit failure this repo hit twice
# today. Run it by hand; promote it once it has passed.
#
# NOTE: no heredocs anywhere in this file, by choice. cc-skills#113 is an
# unterminated heredoc that makes the runner discover 113 tests, run zero, and
# exit 0. printf with explicit newlines cannot fail that way.
if [[ "${1:-}" == "--self-test" ]]; then
    triage_self_test_directory=$(mktemp -d)
    trap 'rm -rf "$triage_self_test_directory"' EXIT
    triage_self_test_failure_count=0

    triage_assert_fixture_classifies_as() {
        local fixture_name="$1"
        local expected_marker="$2"
        local fixture_body="$3"
        local fixture_path="$triage_self_test_directory/$fixture_name.log"
        printf '%s\n' "$fixture_body" > "$fixture_path"
        local actual_output
        # `bash "$0"`, not `"$0"`: this file carries no executable bit (matching
        # every other tasks/*.sh, which the suite invokes as `bash <path>`), so
        # direct invocation dies with "Permission denied" before classification
        # is ever reached. Found by running the self-test — all eight fixtures
        # reported MISCLASSIFIED for a reason that had nothing to do with
        # classification, which is precisely the false signal a self-test is
        # supposed to catch rather than emit.
        actual_output=$(bash "$0" "$fixture_path" 2>&1 || true)
        # NO PIPE. `printf … | grep -q` is a SIGPIPE race under `pipefail`: the
        # early-exiting reader kills the producer, the pipeline inherits 141,
        # and in an `if` condition the boolean INVERTS — grep finds the marker
        # and the test reports failure anyway. A self-test that lies about
        # itself is worse than no self-test. The captured text is already in a
        # variable; matching it directly removes the reader and the race.
        if [[ "$actual_output" == *"$expected_marker"* ]]; then
            printf '  ✓ %-34s → %s\n' "$fixture_name" "$expected_marker"
        else
            printf '  ✗ %-34s → expected %s, got:\n' "$fixture_name" "$expected_marker"
            printf '%s\n' "$actual_output" | awk '{ print "      " $0 }'
            triage_self_test_failure_count=$((triage_self_test_failure_count + 1))
        fi
    }

    printf '\nSELF-TEST — classifier against synthetic fixtures\n\n'

    # THE load-bearing one. A passing skip-path line carrying the scary string.
    triage_assert_fixture_classifies_as "skip-path-passing-line" "GREEN" \
'  ✓ A5: iter-165 pending-release aggregator: median=308ms > cap=305ms — perf timing NOT gated (CC_SKILLS_SKIP_PERF_TIMING)
  ✓ FILE-PASS: test-iter174-harness'

    triage_assert_fixture_classifies_as "genuine-wall-clock-failure" "CLASS A — WALL-CLOCK" \
'  ✗ A5: iter-165 pending-release aggregator (backlog=5 commits): median=308ms > cap=305ms (REGRESSION: 1% over cap)
  ✗ FILE-FAIL: test-iter174-harness
  ✓ FILE-PASS: test-something-else'

    triage_assert_fixture_classifies_as "vacuous-suite-ran-nothing" "VACUOUS" \
'→ Discovered 113 test file(s)
tasks/test-marketplace-hook-regression-suite: line 386: warning: here-document at line 257 delimited by end-of-file'

    triage_assert_fixture_classifies_as "doctor-verdict-degraded" "CLASS B" \
'  ✓ D1: --json summary critical_passed≥10 (total 13)
  ✗ D2: --json summary verdict still TOOLKIT_HEALTHY after iter-163 extension (substring missing)
  ✗ FILE-FAIL: test-iter163-status-doctor
  ✓ FILE-PASS: test-something-else'

    triage_assert_fixture_classifies_as "disagreement-scenario-named" "CLASS A (CONFIRMED)" \
'  ✗ E2: human-mode + --json mode verdict inconsistency
      [HARNESS-SCENARIO-FAILURE] --json: the envelope reports a regression
  ✗ FILE-FAIL: test-iter180-dogfood
  ✓ FILE-PASS: test-something-else'

    triage_assert_fixture_classifies_as "disagreement-genuine-defect" "CLASS C" \
'  ✗ C1: human-mode 7/7-PASS + no-JSON-leak invariant violated
      clause 3 FAILED: iter174_schema_version LEAKED into human-mode text output
      [HARNESS-NO-SCENARIO-FAILURE] no scenario line in the capture
  ✗ FILE-FAIL: test-iter182-measurement-context
  ✓ FILE-PASS: test-something-else'

    triage_assert_fixture_classifies_as "disagreement-old-log-no-token" "CLASS A?" \
'  ✗ E2: human-mode + --json mode verdict inconsistency — mode dispatch may have regressed
  ✗ FILE-FAIL: test-iter180-dogfood
  ✓ FILE-PASS: test-something-else'

    triage_assert_fixture_classifies_as "unrecognised-assertion" "UNKNOWN" \
'  ✗ Z9: an assertion nobody has classified yet
  ✗ FILE-FAIL: test-brand-new-thing
  ✓ FILE-PASS: test-something-else'

    printf '\n'
    if (( triage_self_test_failure_count == 0 )); then
        printf 'SELF-TEST: all fixtures classified correctly\n\n'
        exit 0
    fi
    printf 'SELF-TEST: %s fixture(s) MISCLASSIFIED\n\n' "$triage_self_test_failure_count"
    exit 1
fi

# A line reporting a wall-clock cap breach. The `✗` is load-bearing — see
# correction 1 in the header. Kept in one variable so the UNKNOWN filter below
# cannot drift out of sync with the CLASS A matcher above it.
TRIAGE_WALL_CLOCK_FAILURE_PATTERN='✗ .*median=[0-9]+ms > cap=[0-9]+ms'

# Covers the pre-2026-09-03 message text AND the replacement that names the
# failing clause, because old captured logs outlive the code that wrote them.
TRIAGE_INVOCATION_DISAGREEMENT_PATTERN='✗ (E2|C1):.*(verdict inconsistency|human-mode regressed|invariant violated)'

TRIAGE_DOCTOR_VERDICT_FAILURE_PATTERN='✗ D2:.*verdict still TOOLKIT_HEALTHY'

for triage_each_log_path in "$@"; do
    if [[ ! -r "$triage_each_log_path" ]]; then
        printf '\n=== %s\n  UNREADABLE — no such file, or not readable\n' "$triage_each_log_path"
        continue
    fi

    printf '\n=== %s\n' "$triage_each_log_path"

    triage_failing_file_count=$(grep -cE '^  ✗ FILE-FAIL:' "$triage_each_log_path" || true)
    triage_passing_file_count=$(grep -cE '✓ FILE-PASS:' "$triage_each_log_path" || true)
    triage_executed_file_count=$(( triage_failing_file_count + triage_passing_file_count ))

    # ── VACUOUS: the suite discovered tests and then ran none of them ────────
    #
    # cc-skills#113: an unterminated heredoc in the runner is a bash WARNING,
    # which `set -euo pipefail` does not catch. The suite prints "Discovered 113
    # test file(s)", executes ZERO, and exits 0. It fires on a DIRTY tree —
    # precisely when someone is mid-edit and most wants the gate.
    #
    # Absence of failures is NOT evidence of success, and this branch exists
    # because the first version of THIS FILE made exactly that mistake: it
    # keyed GREEN off "no FILE-FAIL lines", which a run of zero tests satisfies
    # perfectly. A triage tool that certifies a vacuous suite as green is worse
    # than no triage tool, because it converts a loud failure into a quiet one.
    triage_discovered_file_count=$(
        grep -oE 'Discovered [0-9]+ test file' "$triage_each_log_path" |
            awk 'NR==1 { print $2 }' || true
    )
    if (( triage_executed_file_count == 0 )); then
        # The discovered count is OMITTED when the log does not carry it —
        # absent is a state, not a value to invent a word for.
        if [[ -n "$triage_discovered_file_count" ]]; then
            printf '  ⛔ VACUOUS — discovered %s test file(s), EXECUTED ZERO.\n' \
                "$triage_discovered_file_count"
        else
            printf '  ⛔ VACUOUS — EXECUTED ZERO test files.\n'
        fi
        printf '     This log proves NOTHING. Exit 0 here is not a pass (see cc-skills#113:\n'
        printf '     an unterminated heredoc in the runner warns, runs nothing, and exits 0).\n'
        printf '     Check first:  grep -n "here-document" <this log>\n'
        continue
    fi

    if [[ -n "$triage_discovered_file_count" ]] && (( triage_executed_file_count < triage_discovered_file_count )); then
        printf '  ⚠ PARTIAL — discovered %s test file(s) but only %s executed.\n' \
            "$triage_discovered_file_count" "$triage_executed_file_count"
        printf '     The run aborted early; anything not listed below was never checked.\n'
    fi

    if (( triage_failing_file_count == 0 )); then
        printf '  GREEN — %s test file(s) executed, none failed\n' "$triage_executed_file_count"
        continue
    fi
    printf '  %s failing test file(s), %s executed\n' \
        "$triage_failing_file_count" "$triage_executed_file_count"

    # ── CLASS A: a wall-clock gate exceeded its cap ──────────────────────────
    if grep -qE "$TRIAGE_WALL_CLOCK_FAILURE_PATTERN" "$triage_each_log_path"; then
        printf '\n  CLASS A — WALL-CLOCK SCENARIO GATE (load-sensitive)\n'
        grep -oE '✗ A[0-9]+:.*' "$triage_each_log_path" | awk 'NR<=5 { print "    " $0 }' || true

        # The margin IS the diagnosis. Per-mille then split, because integer
        # division renders a 3ms overshoot on a 305ms cap as "0%" — hiding the
        # single number that separates ambient contention from a real
        # regression. A sub-1% margin is contention; 300% is a broken script.
        #
        # Two-stage and ANCHORED. Extracting `median=… > cap=…` directly from
        # the file would re-admit the passing CC_SKILLS_SKIP_PERF_TIMING line
        # that correction 1 exists to exclude, and print a margin for a scenario
        # that PASSED — the same defect one layer down, which is exactly how a
        # diagnostic starts lying. Stage one keeps only failure lines; stage two
        # reads the numbers out of them.
        triage_margin_pairs_from_failure_lines=$(
            grep -oE "$TRIAGE_WALL_CLOCK_FAILURE_PATTERN" "$triage_each_log_path" |
                grep -oE 'median=[0-9]+ms > cap=[0-9]+ms' || true
        )
        printf '%s\n' "$triage_margin_pairs_from_failure_lines" | while read -r triage_each_margin_pair; do
            [[ -z "$triage_each_margin_pair" ]] && continue
            triage_observed_median_ms=${triage_each_margin_pair#median=}
            triage_observed_median_ms=${triage_observed_median_ms%%ms*}
            triage_pinned_cap_ms=${triage_each_margin_pair##*cap=}
            triage_pinned_cap_ms=${triage_pinned_cap_ms%ms}
            if (( triage_pinned_cap_ms > 0 )); then
                triage_margin_per_mille=$(( (triage_observed_median_ms - triage_pinned_cap_ms) * 1000 / triage_pinned_cap_ms ))
                printf '    margin: %sms over %sms cap (%s.%s%% over)\n' \
                    "$(( triage_observed_median_ms - triage_pinned_cap_ms ))" \
                    "$triage_pinned_cap_ms" \
                    "$(( triage_margin_per_mille / 10 ))" \
                    "$(( triage_margin_per_mille % 10 ))"
            fi
        done
    fi

    # ── CLASS A? / CLASS C: two harness invocations disagreed ────────────────
    #
    # Whether this is CLASS A depends on evidence the test now emits. When the
    # harness reported a failing scenario, the reduction is OBSERVED. When it
    # reported that no scenario failed, this is a genuine dispatch/leak defect
    # and belongs in its own class. When neither token is present the log
    # predates that diagnostic, and the reduction stays explicitly INFERRED.
    if grep -qE "$TRIAGE_INVOCATION_DISAGREEMENT_PATTERN" "$triage_each_log_path"; then
        if grep -qF '[HARNESS-SCENARIO-FAILURE]' "$triage_each_log_path"; then
            printf '\n  CLASS A (CONFIRMED) — invocation disagreement caused by a named scenario failure\n'
            grep -A2 -F '[HARNESS-SCENARIO-FAILURE]' "$triage_each_log_path" | awk 'NR<=8 { print "    " $0 }' || true
        elif grep -qF '[HARNESS-NO-SCENARIO-FAILURE]' "$triage_each_log_path"; then
            printf '\n  CLASS C — GENUINE MODE-DISPATCH / JSON-LEAK DEFECT\n'
            printf '    The harness reported that NO scenario failed, so this is NOT contention.\n'
            printf '    This is the real defect the old message used to claim without evidence.\n'
            grep -oE '✗ (E2|C1):.*' "$triage_each_log_path" | awk 'NR<=4 { print "    " $0 }' || true
        else
            printf '\n  CLASS A? — HARNESS INVOCATIONS DISAGREE (reduction to CLASS A is INFERRED)\n'
            grep -oE '✗ (E2|C1):.*' "$triage_each_log_path" | awk 'NR<=4 { print "    " $0 }' || true
            printf '    NOTE: this log predates the clause-naming diagnostic, so the failing\n'
            printf '          scenario is unnamed. Do NOT record this as a confirmed CLASS A.\n'
        fi
    fi

    # ── CLASS B: the doctor ran and reported a non-healthy verdict ───────────
    if grep -qE "$TRIAGE_DOCTOR_VERDICT_FAILURE_PATTERN" "$triage_each_log_path"; then
        printf '\n  CLASS B — VERDICT / SUBPROCESS EXIT CODE\n'
        if grep -qE '✓ D1:.*critical_passed' "$triage_each_log_path"; then
            printf '    ✓ D1 passed alongside ✗ D2 — critical_passed in [10,13] of 13, so between\n'
            printf '      1 and 3 CRITICAL checks returned non-zero.\n'
        else
            printf '    ⚠ D1 did NOT pass — the bound is wider than the 1-3 observed on 2026-09-03.\n'
        fi
        for triage_each_group_letter in A B C E; do
            if grep -qE "✗ ${triage_each_group_letter}[0-9]+:" "$triage_each_log_path"; then
                printf '    ⚠ group %s also failed — the doctor may NOT have run cleanly.\n' "$triage_each_group_letter"
            fi
        done
        printf '    (A/B/C/E all green ⇒ the doctor ran and emitted parseable JSON: not a crash,\n'
        printf '     not a spawn failure. Every one of its 15 verdicts is a subprocess exit code.)\n'
    fi

    # ── UNKNOWN: never absorbed into the nearest bucket ──────────────────────
    #
    # This is the anti-vacuous-gate property and the easiest one to lose in a
    # cleanup. If a future edit makes this branch unreachable, the tool starts
    # silently reporting every novel failure as one of the shapes it already
    # knows, which is worse than having no tool at all.
    triage_unclassified_assertions=$(
        grep -oE '✗ [A-Z][0-9]+:.*' "$triage_each_log_path" |
            grep -vE "$TRIAGE_WALL_CLOCK_FAILURE_PATTERN" |
            grep -vE "$TRIAGE_INVOCATION_DISAGREEMENT_PATTERN" |
            grep -vE "$TRIAGE_DOCTOR_VERDICT_FAILURE_PATTERN" || true
    )
    if [[ -n "$triage_unclassified_assertions" ]]; then
        printf '\n  UNKNOWN — matches no known mechanism; investigate rather than assume:\n'
        printf '%s\n' "$triage_unclassified_assertions" | awk 'NR<=10 { print "    " $0 }'
    fi
done
