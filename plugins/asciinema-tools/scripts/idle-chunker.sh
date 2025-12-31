#!/usr/bin/env bash
# idle-chunker.sh - Monitor recording and push chunks on idle
#
# This script monitors a .cast file and pushes chunks to GitHub
# when idle time exceeds the threshold.
#
# Usage: ./idle-chunker.sh <cast_file> <local_repo> [idle_threshold] [zstd_level]
#
# Arguments:
#   cast_file       - Path to the active .cast recording
#   local_repo      - Path to local orphan branch clone
#   idle_threshold  - Seconds of idle before pushing chunk (default: 30)
#   zstd_level      - zstd compression level 1-19 (default: 3)

set -euo pipefail

CAST_FILE="${1:?Usage: $0 <cast_file> <local_repo> [idle_threshold] [zstd_level]}"
LOCAL_REPO="${2:?Usage: $0 <cast_file> <local_repo> [idle_threshold] [zstd_level]}"
IDLE_THRESHOLD="${3:-30}"
ZSTD_LEVEL="${4:-3}"

# Validate inputs
if [[ ! -f "$CAST_FILE" ]]; then
  echo "ERROR: Cast file not found: $CAST_FILE"
  exit 1
fi

if [[ ! -d "$LOCAL_REPO/.git" ]]; then
  echo "ERROR: Local repo not a git directory: $LOCAL_REPO"
  exit 1
fi

echo "=== idle-chunker started ==="
echo "Monitoring: $CAST_FILE"
echo "Pushing to: $LOCAL_REPO"
echo "Idle threshold: ${IDLE_THRESHOLD}s"
echo "Compression: zstd-${ZSTD_LEVEL}"
echo ""

cd "$LOCAL_REPO"
mkdir -p chunks

last_pos=0
chunk_count=0

while true; do
  # Check if recording still exists
  if [[ ! -f "$CAST_FILE" ]]; then
    echo "[$(date +%H:%M:%S)] Recording ended, exiting..."
    break
  fi

  # Get file modification time and size (cross-platform)
  if [[ "$(uname)" == "Darwin" ]]; then
    mtime=$(stat -f%m "$CAST_FILE" 2>/dev/null || echo 0)
    size=$(stat -f%z "$CAST_FILE" 2>/dev/null || echo 0)
  else
    mtime=$(stat -c%Y "$CAST_FILE" 2>/dev/null || echo 0)
    size=$(stat -c%s "$CAST_FILE" 2>/dev/null || echo 0)
  fi

  now=$(date +%s)
  idle=$((now - mtime))

  # Check if idle and new data available
  if (( idle >= IDLE_THRESHOLD && size > last_pos )); then
    chunk_count=$((chunk_count + 1))
    chunk_name="chunk_$(date +%Y%m%d_%H%M%S).cast"
    chunk_path="chunks/$chunk_name"

    echo "[$(date +%H:%M:%S)] Idle detected (${idle}s), creating chunk #${chunk_count}..."

    # Extract new data since last position
    bytes_new=$((size - last_pos))
    tail -c +"$((last_pos + 1))" "$CAST_FILE" > "$chunk_path"

    # Compress with zstd
    if ! zstd -"${ZSTD_LEVEL}" --rm "$chunk_path" 2>&1; then
      echo "[$(date +%H:%M:%S)] ERROR: zstd compression failed for $chunk_path" >&2
    fi
    compressed_size=$(stat -f%z "${chunk_path}.zst" 2>/dev/null || stat -c%s "${chunk_path}.zst" 2>/dev/null)

    # Commit and push
    git add chunks/
    git commit -m "chunk #${chunk_count} ($(numfmt --to=iec "$bytes_new" 2>/dev/null || echo "${bytes_new}B"))"

    push_output=$(git push 2>&1)
    push_status=$?
    if [[ $push_status -eq 0 ]]; then
      echo "[$(date +%H:%M:%S)] Pushed: ${chunk_name}.zst ($(numfmt --to=iec "$compressed_size" 2>/dev/null || echo "${compressed_size}B"))"
    else
      echo "[$(date +%H:%M:%S)] Push failed (exit $push_status): $push_output" >&2
      echo "[$(date +%H:%M:%S)] Will retry on next idle..."
    fi

    last_pos=$size
  fi

  # Check every 5 seconds
  sleep 5
done

# Final chunk on exit
if (( $(stat -f%z "$CAST_FILE" 2>/dev/null || stat -c%s "$CAST_FILE" 2>/dev/null || echo 0) > last_pos )); then
  echo "[$(date +%H:%M:%S)] Creating final chunk..."
  final_chunk="chunks/final_$(date +%Y%m%d_%H%M%S).cast"
  tail -c +"$((last_pos + 1))" "$CAST_FILE" > "$final_chunk"
  if ! zstd -"${ZSTD_LEVEL}" --rm "$final_chunk" 2>&1; then
    echo "[$(date +%H:%M:%S)] ERROR: zstd compression failed for final chunk" >&2
  fi
  git add chunks/
  git commit -m "final chunk"
  final_push_output=$(git push 2>&1)
  final_push_status=$?
  if [[ $final_push_status -eq 0 ]]; then
    echo "[$(date +%H:%M:%S)] Final chunk pushed"
  else
    echo "[$(date +%H:%M:%S)] Final push failed (exit $final_push_status): $final_push_output" >&2
  fi
fi

echo "=== idle-chunker stopped ==="
