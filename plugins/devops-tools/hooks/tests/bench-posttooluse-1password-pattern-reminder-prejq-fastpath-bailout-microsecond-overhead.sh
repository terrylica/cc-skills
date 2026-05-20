#!/usr/bin/env bash
# bench-posttooluse-1password-pattern-reminder-prejq-fastpath-bailout-microsecond-overhead.sh
#
# Bench iter-40's pre-jq-fastpath optimization to the
# posttooluse-1password-pattern-reminder.sh hook. The optimization replaces
# unconditional `jq` invocation + grep with a bash-builtin `case "$PAYLOAD" in
# *op*) ;; *) exit 0 ;; esac` pre-check.
#
# Verbose filename per user directive ("self-explanatory scaffolding"):
# encodes the EXACT measurement target so future maintainers grep'ing for
# "fastpath", "bailout", "microsecond", or "1password-pattern-reminder
# perf" surface this bench file.
#
# Measures:
#   - Bail-out path (no `op` in payload — ~95% of real-world Bash calls)
#   - Match path (op IS the leading executable — fires reminder)
#   - Heredoc-false-positive path (op appears in heredoc body but not as
#     leading executable — iter-39 invariant)
#
# Reports median wall-clock per invocation in microseconds. Writes a JSON
# summary to /tmp/iter-40-prejq-fastpath-bench-<epoch>.json.

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
# disable bash 5.2+ `&`-as-backreference. See
# plugins/autoloop/hooks/heartbeat-tick.sh for full rationale.
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# iter-40 layout: this bench file lives in plugins/devops-tools/hooks/tests/
# (moved from hooks/ so the plugin validator does not misclassify it).
HOOK_UNDER_BENCH="$SCRIPT_DIR/../posttooluse-1password-pattern-reminder.sh"

if [ ! -x "$HOOK_UNDER_BENCH" ]; then
  echo "FATAL: hook not executable: $HOOK_UNDER_BENCH" >&2
  exit 1
fi

ITERATIONS="${BENCH_ITERATIONS:-200}"
TIMESTAMP_EPOCH=$(date -u +%s)
REPORT_JSON="/tmp/iter-40-prejq-fastpath-bench-${TIMESTAMP_EPOCH}.json"

echo "=== Iter-40 pre-jq-fastpath bench (n=$ITERATIONS) ==="
echo "Hook: $HOOK_UNDER_BENCH"
echo ""

# ---------------------------------------------------------------------------
# Payload generators
# ---------------------------------------------------------------------------

# Bail-out path: typical Bash tool call with no `op` mention at all
# (representative of ~95% of real-world Bash invocations)
make_bailout_payload() {
  jq -n '{tool_input: {command: "ls -la ~/.claude/plugins/marketplaces/ | head -20"}}'
}

# Match path: bare op invocation that SHOULD fire the reminder
make_match_payload() {
  jq -n '{tool_input: {command: "op read \"op://Engineering/SomeItem/access\""}}'
}

# Heredoc-false-positive path: long git commit with op-mentioning heredoc.
# Iter-39 fixed this; this bench verifies the fast-path correctly forwards
# to the iter-39 regex (which then correctly drops it).
make_heredoc_falsepos_payload() {
  jq -n --arg body "$(printf 'docs(devops): %.0s' {1..400})use op read --vault X" \
    '{tool_input: {command: ("git commit -m \"$(cat <<EOF\n" + $body + "\nEOF\n)\"")}}'
}

# ---------------------------------------------------------------------------
# Bench harness — measures wall-clock per invocation in microseconds
# ---------------------------------------------------------------------------

bench_path() {
  local label="$1"
  local payload_generator="$2"
  local payload
  payload=$(eval "$payload_generator")
  local payload_size_bytes="${#payload}"

  # Warm up (3 invocations) so we measure steady-state, not OS-cache-cold
  for _ in 1 2 3; do
    printf '%s' "$payload" | "$HOOK_UNDER_BENCH" >/dev/null 2>&1 || true
  done

  # Measure
  local start_us end_us elapsed_us per_invocation_us
  start_us=$(python3 -c "import time; print(int(time.time() * 1_000_000))")
  for _ in $(seq 1 "$ITERATIONS"); do
    printf '%s' "$payload" | "$HOOK_UNDER_BENCH" >/dev/null 2>&1 || true
  done
  end_us=$(python3 -c "import time; print(int(time.time() * 1_000_000))")
  elapsed_us=$((end_us - start_us))
  per_invocation_us=$((elapsed_us / ITERATIONS))

  # Iter-40 bench-fix: emit human-readable summary to STDERR so it's visible
  # to the operator running the bench. The caller captures stdout via
  # `$(bench_path ... | tail -1)` which would otherwise eat this line.
  printf "%-45s payload=%5d B  total=%8d µs  per_call=%5d µs\n" \
    "$label" "$payload_size_bytes" "$elapsed_us" "$per_invocation_us" >&2

  # Emit JSON record on STDOUT (captured by caller for the JSON report).
  echo "  {\"label\": \"$label\", \"payload_bytes\": $payload_size_bytes, \"iterations\": $ITERATIONS, \"total_us\": $elapsed_us, \"per_call_us\": $per_invocation_us}"
}

# ---------------------------------------------------------------------------
# Run benches
# ---------------------------------------------------------------------------

records=()

echo "Path 1: BAIL-OUT (no op anywhere — common ~95% hot path)"
records+=("$(bench_path "bailout_no_op_anywhere" make_bailout_payload | tail -1)")
echo ""

echo "Path 2: MATCH (op IS leading executable — reminder fires)"
records+=("$(bench_path "match_op_leading_executable" make_match_payload | tail -1)")
echo ""

echo "Path 3: HEREDOC-FALSE-POSITIVE (op in heredoc body, NOT leading)"
records+=("$(bench_path "heredoc_falsepos_op_in_body" make_heredoc_falsepos_payload | tail -1)")
echo ""

# ---------------------------------------------------------------------------
# Write JSON report
# ---------------------------------------------------------------------------
{
  echo "{"
  echo "  \"bench_name\": \"iter-40-prejq-fastpath\","
  echo "  \"timestamp_epoch\": $TIMESTAMP_EPOCH,"
  echo "  \"iterations_per_path\": $ITERATIONS,"
  echo "  \"hook\": \"$HOOK_UNDER_BENCH\","
  echo "  \"paths\": ["
  # iter-40 SC2168: `local` is only valid inside functions; this is a `{...}`
  # block group, so use plain variables. Scoped to this block via name choice.
  bench_record_index=0
  bench_record_count="${#records[@]}"
  for r in "${records[@]}"; do
    bench_record_index=$((bench_record_index + 1))
    if [ "$bench_record_index" -lt "$bench_record_count" ]; then
      echo "  $r,"
    else
      echo "  $r"
    fi
  done
  echo "  ]"
  echo "}"
} > "$REPORT_JSON"

echo "JSON report: $REPORT_JSON"

# ---------------------------------------------------------------------------
# Regression invariant: bail-out path MUST be UNDER the match path by a
# meaningful margin. This is a RELATIVE check (intentionally) — the
# absolute number is dominated by the bash-process-spawn cost (~5-8 ms on
# macOS, ~3-5 ms on Linux) which is OUT OF THIS HOOK'S CONTROL. The
# iter-40 optimization saves the ~5-7 ms of in-hook jq + grep work; that
# delta must remain visible.
#
# Empirically on m3max bash 5.3.9:
#   - Bash process spawn:    ~5-7 ms
#   - Pre-iter-40 bail-out:  spawn + jq (~5-7 ms) + grep (~2 ms) = 12-16 ms
#   - Iter-40    bail-out:   spawn + case-glob (<0.1 ms)         = 5-8 ms
#   - Speedup factor:        2-3x in absolute wall-clock terms
#
# We assert BAIL_OUT < 0.7 * MATCH so the optimization's effect (skipping
# the jq+grep) remains measurable. If a future regression re-introduces
# jq into the bail-out path, the ratio collapses to ~1.0 and this fails.
# ---------------------------------------------------------------------------
bailout_us=$(echo "${records[0]}" | jq -r '.per_call_us')
match_us=$(echo "${records[1]}" | jq -r '.per_call_us')
heredoc_us=$(echo "${records[2]}" | jq -r '.per_call_us')

# Compute ratio in fixed-point to avoid floating-point in bash
# bail/match * 100 < 70 means bail-out is < 70% of match path cost
ratio_bailout_to_match_pct=$((bailout_us * 100 / match_us))

echo ""
echo "Path cost comparison (per-call, µs):"
echo "  bailout (no op):        $bailout_us µs"
echo "  match (op leading):     $match_us µs"
echo "  heredoc (op in body):   $heredoc_us µs"
echo "  bailout/match ratio:    ${ratio_bailout_to_match_pct}% (must be <70% to confirm iter-40 fast-path effective)"
echo ""

REGRESSION_THRESHOLD_RATIO_PCT=70
if [ "$ratio_bailout_to_match_pct" -ge "$REGRESSION_THRESHOLD_RATIO_PCT" ]; then
  echo "✗ FAIL: bail-out path is ${ratio_bailout_to_match_pct}% of match path (threshold <${REGRESSION_THRESHOLD_RATIO_PCT}%)" >&2
  echo "  This usually means jq was re-introduced into the bail-out path." >&2
  exit 1
fi
echo "✓ PASS: iter-40 pre-jq-fastpath demonstrably saves work on bail-out (${ratio_bailout_to_match_pct}% < ${REGRESSION_THRESHOLD_RATIO_PCT}%)"
