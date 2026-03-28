#!/usr/bin/env bash
# Profile Metal GPU memory during streaming TTS synthesis.
#
# Usage: ./profile-tts-memory.sh [text]
# Monitors IOAccelerator (graphics) region count and footprint while
# a streaming TTS synthesis runs.

set -euo pipefail

PID=$(pgrep -x claude-tts-companion | head -1)
if [[ -z "$PID" ]]; then
    echo "ERROR: claude-tts-companion not running"
    exit 1
fi

TEXT="${1:-The autoreleasepool wraps each chunk in the streaming synthesis pipeline. It should drain ObjC Metal objects between synthesis calls. This is the third sentence for testing. The fourth sentence adds more synthesis load. Finally the fifth sentence completes the test paragraph.}"

LOG_DIR="/Users/terryli/eon/cc-skills/.planning/debug/scripts"
SAMPLE_FILE="$LOG_DIR/memory-samples-$(date +%Y%m%d-%H%M%S).tsv"

echo "Profiling PID $PID during streaming TTS synthesis"
echo "Output: $SAMPLE_FILE"

# Header
printf "timestamp\telapsed_s\trss_kb\tphys_footprint_mb\tioaccelerator_graphics_regions\tioaccelerator_graphics_mb\tnote\n" > "$SAMPLE_FILE"

get_memory_snapshot() {
    local note="$1"
    local elapsed="$2"
    local ts
    ts=$(date +%H:%M:%S)
    local rss
    rss=$(ps -p "$PID" -o rss= 2>/dev/null | tr -d ' ')

    # Get IOAccelerator (graphics) stats from footprint
    local footprint_output
    footprint_output=$(footprint "$PID" 2>/dev/null)

    local phys_fp
    phys_fp=$(echo "$footprint_output" | grep "phys_footprint:" | head -1 | awk '{print $2}')
    local phys_unit
    phys_unit=$(echo "$footprint_output" | grep "phys_footprint:" | head -1 | awk '{print $3}')

    # Convert to MB
    local phys_mb
    if [[ "$phys_unit" == "GB" ]]; then
        phys_mb=$(echo "$phys_fp * 1024" | bc 2>/dev/null || echo "?")
    elif [[ "$phys_unit" == "MB" ]]; then
        phys_mb="$phys_fp"
    else
        phys_mb="$phys_fp$phys_unit"
    fi

    local ioaccel_line
    ioaccel_line=$(echo "$footprint_output" | grep "IOAccelerator (graphics)" | head -1)
    local ioaccel_size
    ioaccel_size=$(echo "$ioaccel_line" | awk '{print $1, $2}')
    local ioaccel_regions
    ioaccel_regions=$(echo "$ioaccel_line" | awk '{print $NF}')

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$ts" "$elapsed" "$rss" "$phys_mb" "$ioaccel_regions" "$ioaccel_size" "$note" >> "$SAMPLE_FILE"
    printf "%s  elapsed=%ss  RSS=%sKB  phys=%s  IOAccel_graphics: regions=%s size=%s  [%s]\n" "$ts" "$elapsed" "$rss" "$phys_mb" "$ioaccel_regions" "$ioaccel_size" "$note"
}

# Baseline
echo ""
echo "=== BASELINE (idle) ==="
get_memory_snapshot "baseline" "0"

# Start sampling in background
START_TIME=$(date +%s)
(
    while true; do
        sleep 2
        ELAPSED=$(( $(date +%s) - START_TIME ))
        get_memory_snapshot "sampling" "$ELAPSED" 2>/dev/null || true
    done
) &
SAMPLER_PID=$!
trap "kill $SAMPLER_PID 2>/dev/null; wait $SAMPLER_PID 2>/dev/null" EXIT

# Trigger streaming TTS synthesis
echo ""
echo "=== TRIGGERING SYNTHESIS ==="
echo "Text: ${TEXT:0:80}..."

# Use /tts/stream endpoint
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:8780/tts/stream \
    -H "Content-Type: application/json" \
    -d "{\"text\": \"$TEXT\"}" 2>/dev/null || echo "CURL_FAILED")

HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -1)
echo "HTTP response: $HTTP_CODE"

# Wait for synthesis to complete (watch logs)
echo ""
echo "=== WAITING FOR SYNTHESIS PIPELINE ==="
TIMEOUT=120
WAITED=0
while [[ $WAITED -lt $TIMEOUT ]]; do
    sleep 3
    WAITED=$(( WAITED + 3 ))
    ELAPSED=$(( $(date +%s) - START_TIME ))

    # Check if pipeline completed
    LATEST=$(tail -5 /Users/terryli/.local/state/launchd-logs/claude-tts-companion/stderr.log 2>/dev/null | grep "Streaming TTS pipeline complete" || true)
    if [[ -n "$LATEST" ]]; then
        echo "Pipeline complete detected!"
        get_memory_snapshot "post-synthesis" "$ELAPSED"
        break
    fi
done

# Post-synthesis settle (let autoreleasepool drain, GC run)
echo ""
echo "=== POST-SYNTHESIS SETTLE (30s) ==="
for i in 5 10 15 20 25 30; do
    sleep 5
    ELAPSED=$(( $(date +%s) - START_TIME ))
    get_memory_snapshot "settle-${i}s" "$ELAPSED"
done

echo ""
echo "=== FINAL STATE ==="
ELAPSED=$(( $(date +%s) - START_TIME ))
get_memory_snapshot "final" "$ELAPSED"

# Kill sampler
kill $SAMPLER_PID 2>/dev/null || true
wait $SAMPLER_PID 2>/dev/null || true

echo ""
echo "Done! Results in: $SAMPLE_FILE"
echo ""
echo "=== SUMMARY ==="
column -t -s $'\t' "$SAMPLE_FILE"
