#!/usr/bin/env bash
# bundle.sh — Phase 1 of the chronicle-share pipeline.
#
# Enumerate Claude Code session JSONL files for a project, copy them into a
# staging directory, and write a manifest.json describing the bundle.
#
# The manifest is the single evolving record that downstream phases mutate:
#   Phase 2 (sanitize) flips `sanitized: false -> true` and adds redaction metadata.
#   Phase 3 (archive)  flips `archived: false  -> true` and adds archive metadata.
#   Phase 4 (upload)   adds presigned URL + object key.
#
# Usage:
#   bundle.sh [--project PATH] [--out DIR] [--limit N]
#   bundle.sh --help
#
# Stdout: staging directory path (one line) on success.
# Stderr: all human-readable logs and errors.
#
# Exit codes:
#   0  bundle created
#   1  usage or validation error
#   2  no sessions found for the requested project

set -euo pipefail

# --- defaults ---------------------------------------------------------------
PROJECT="$PWD"
OUT_DIR=""
LIMIT=0   # 0 = no limit

# --- helpers ----------------------------------------------------------------
log() { printf '[bundle] %s\n' "$*" >&2; }
err() { printf '[bundle] ERROR: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: bundle.sh [OPTIONS]

Enumerate Claude Code session JSONL files for a project and stage them for
the rest of the chronicle-share pipeline.

Options:
  --project PATH   Project whose sessions to bundle (default: $PWD).
                   Encoded via Claude Code's scheme: strip leading '/',
                   replace '/' and '.' with '-', prepend '-'.
  --out DIR        Staging directory to create. Must not exist yet.
                   Default: $TMPDIR/chronicle-share-<UTC-timestamp>
  --limit N        Bundle only the N newest sessions (by mtime). 0 = all.
  --help, -h       Show this help.

Staging layout:
  <OUT_DIR>/
  ├── manifest.json
  └── sessions/
      └── <session-id>.jsonl

On success, the staging directory path is printed to stdout; logs go to stderr.
EOF
}

# --- arg parse --------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?--project requires a path}"; shift 2 ;;
    --out)     OUT_DIR="${2:?--out requires a path}";     shift 2 ;;
    --limit)   LIMIT="${2:?--limit requires a number}";   shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) err "unknown arg: $1"; usage >&2; exit 1 ;;
  esac
done

# --- validate ---------------------------------------------------------------
if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
  err "--limit must be a non-negative integer (got: $LIMIT)"
  exit 1
fi

if [[ ! -d "$PROJECT" ]]; then
  err "project path is not a directory: $PROJECT"
  exit 1
fi

for bin in jq shasum stat find; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    err "required tool not on PATH: $bin"
    exit 1
  fi
done

PROJECT="$(cd "$PROJECT" && pwd)"   # normalize to absolute

# Encode project path per Claude Code's scheme.
encoded="-$(printf '%s' "$PROJECT" | sed 's|^/||' | tr '/.' '--')"
session_dir="$HOME/.claude/projects/$encoded"

if [[ ! -d "$session_dir" ]]; then
  err "no Claude Code session directory for this project"
  err "  project : $PROJECT"
  err "  encoded : $encoded"
  err "  looked  : $session_dir"
  exit 2
fi

if [[ -z "$OUT_DIR" ]]; then
  tmp="${TMPDIR:-/tmp}"
  OUT_DIR="${tmp%/}/chronicle-share-$(date -u +%Y%m%dT%H%M%SZ)"
fi

if [[ -e "$OUT_DIR" ]]; then
  err "out dir already exists: $OUT_DIR"
  err "  refusing to overwrite; pick a different --out or remove it first"
  exit 1
fi

# --- enumerate sessions (sorted newest-first) -------------------------------
declare -a all_sessions=()
while IFS= read -r path; do
  [[ -n "$path" ]] && all_sessions+=("$path")
done < <(
  find "$session_dir" -maxdepth 1 -type f -name '*.jsonl' -print0 \
    | xargs -0 stat -f '%m %N' 2>/dev/null \
    | sort -rn \
    | awk '{ $1=""; sub(/^ /,""); print }'
)

if [[ ${#all_sessions[@]} -eq 0 ]]; then
  err "no *.jsonl sessions in: $session_dir"
  exit 2
fi

declare -a sessions=()
if [[ "$LIMIT" -gt 0 ]]; then
  for ((i=0; i<LIMIT && i<${#all_sessions[@]}; i++)); do
    sessions+=("${all_sessions[$i]}")
  done
else
  sessions=("${all_sessions[@]}")
fi

log "project  : $PROJECT"
log "encoded  : $encoded"
log "found    : ${#all_sessions[@]} session(s); bundling ${#sessions[@]}"
log "out dir  : $OUT_DIR"

# --- stage files + build manifest entries -----------------------------------
mkdir -p "$OUT_DIR/sessions"

manifest_entries="$(mktemp)"
trap 'rm -f "$manifest_entries"' EXIT

total_bytes=0
for src in "${sessions[@]}"; do
  filename="$(basename "$src")"
  session_id="${filename%.jsonl}"
  dst="$OUT_DIR/sessions/$filename"

  cp "$src" "$dst"

  size_bytes=$(stat -f %z "$src")
  line_count=$(awk 'END{print NR}' "$src")
  mtime_epoch=$(stat -f %m "$src")
  mtime_utc=$(date -u -r "$mtime_epoch" +%Y-%m-%dT%H:%M:%SZ)
  sha=$(shasum -a 256 "$src" | awk '{print $1}')

  total_bytes=$(( total_bytes + size_bytes ))

  jq -nc \
    --arg sid  "$session_id" \
    --arg fn   "$filename" \
    --argjson sz "$size_bytes" \
    --argjson lc "$line_count" \
    --arg mt   "$mtime_utc" \
    --arg sh   "$sha" \
    '{session_id:$sid, filename:$fn, size_bytes:$sz, line_count:$lc, mtime_utc:$mt, sha256:$sh}' \
    >> "$manifest_entries"
done

# --- assemble manifest ------------------------------------------------------
now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
host_val="$(hostname -s 2>/dev/null || hostname)"
user_val="$(whoami)"

jq -s \
  --arg gen_at "$now_utc" \
  --arg gen_by "chronicle-share/bundle.sh" \
  --arg proj   "$PROJECT" \
  --arg enc    "$encoded" \
  --arg host   "$host_val" \
  --arg user   "$user_val" \
  --argjson total_sz "$total_bytes" \
  '{
    manifest_version: 1,
    generated_at_utc: $gen_at,
    generated_by:     $gen_by,
    source: {
      project_path:    $proj,
      project_encoded: $enc,
      host:            $host,
      claude_user:     $user
    },
    sessions: .,
    totals: {
      session_count:    (. | length),
      total_size_bytes: $total_sz
    },
    sanitized: false,
    archived:  false
  }' \
  "$manifest_entries" \
  > "$OUT_DIR/manifest.json"

log "manifest : $OUT_DIR/manifest.json"
log "total    : ${#sessions[@]} session(s), $total_bytes bytes"
log "done"

printf '%s\n' "$OUT_DIR"
