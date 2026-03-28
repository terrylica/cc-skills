#!/usr/bin/env bash
# Profile MLX Metal GPU memory per TTS synthesis call
# Usage: bash profile-metal-memory.sh [num_calls]

set -euo pipefail

PID=$(pgrep claude-tts-companion || true)
if [[ -z "$PID" ]]; then
    echo "ERROR: claude-tts-companion not running"
    exit 1
fi

NUM_CALLS=${1:-3}
OUTPUT_FILE="/Users/terryli/eon/cc-skills/.planning/debug/scripts/metal-memory-profile-$(date +%Y%m%dT%H%M%S).log"

measure() {
    local label="$1"
    {
        echo "=== $label ==="
        echo "--- vmmap IOAccelerator summary ---"
        vmmap "$PID" 2>&1 | grep "IOAccelerator" | head -10
        echo ""
    } >> "$OUTPUT_FILE"

    # Count IOAccelerator regions and total size
    local ioacc_lines
    ioacc_lines=$(vmmap "$PID" 2>&1 | grep "^IOAccelerator" | grep -v "__TEXT\|__DATA" || true)
    local region_count=0
    local total_kb=0
    if [[ -n "$ioacc_lines" ]]; then
        region_count=$(echo "$ioacc_lines" | wc -l | tr -d ' ')
        # Parse the size column (4th field in brackets, e.g. [   16K ...])
        while IFS= read -r line; do
            local size_str
            size_str=$(echo "$line" | sed -n 's/.*\[\s*\([0-9]*[KMG]\?\).*/\1/p')
            if [[ "$size_str" =~ ^([0-9]+)G$ ]]; then
                total_kb=$(( total_kb + BASH_REMATCH[1] * 1048576 ))
            elif [[ "$size_str" =~ ^([0-9]+)M$ ]]; then
                total_kb=$(( total_kb + BASH_REMATCH[1] * 1024 ))
            elif [[ "$size_str" =~ ^([0-9]+)K$ ]]; then
                total_kb=$(( total_kb + BASH_REMATCH[1] ))
            elif [[ "$size_str" =~ ^([0-9]+)$ ]]; then
                total_kb=$(( total_kb + BASH_REMATCH[1] / 1024 ))
            fi
        done <<< "$ioacc_lines"
    fi

    echo "IOAccelerator regions: $region_count, total virtual: ${total_kb}K" >> "$OUTPUT_FILE"

    # Physical footprint
    echo "--- vmmap Physical footprint ---" >> "$OUTPUT_FILE"
    vmmap "$PID" 2>&1 | grep "Physical footprint" >> "$OUTPUT_FILE" 2>/dev/null || true
    echo "" >> "$OUTPUT_FILE"

    # RSS
    local rss
    rss=$(ps -o rss= -p "$PID" | tr -d ' ')
    echo "RSS: ${rss}K" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # Print summary to terminal
    echo "$label: IOAccelerator=${total_kb}K (${region_count} regions), RSS=${rss}K"
}

echo "Profiling MLX Metal memory for PID $PID ($NUM_CALLS calls)"
echo "Output: $OUTPUT_FILE"
echo ""

# Header
echo "MLX Metal Memory Profile - $(date)" > "$OUTPUT_FILE"
echo "PID: $PID" >> "$OUTPUT_FILE"
echo "Calls: $NUM_CALLS" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Baseline
measure "BASELINE (before any TTS)"

# Sequential TTS calls
for i in $(seq 1 "$NUM_CALLS"); do
    echo ""
    echo "--- Triggering TTS call $i/$NUM_CALLS ---"

    # Use a short test sentence to minimize synthesis time
    curl -s -X POST http://localhost:8780/tts/test \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"Test sentence number $i for memory profiling.\"}" > /dev/null 2>&1

    # Wait for synthesis to complete (watch logs or just wait)
    echo "Waiting for synthesis to complete..."
    sleep 8

    measure "AFTER CALL $i"
done

echo ""
echo "=== SUMMARY ===" | tee -a "$OUTPUT_FILE"
echo "Profile complete. See $OUTPUT_FILE for details."
