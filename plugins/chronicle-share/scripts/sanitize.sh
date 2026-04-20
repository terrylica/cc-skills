#!/usr/bin/env bash
# sanitize.sh — Phase 2 of the chronicle-share pipeline.
#
# Invoke the upstream field-aware sanitizer over the raw sessions produced by
# bundle.sh, then mutate manifest.json in place to record what happened.
#
# Never re-implements redaction logic. The upstream script at
#   ~/.claude/plugins/marketplaces/cc-skills/plugins/devops-tools/
#     skills/session-chronicle/scripts/sanitize_sessions.py
# is the single source of truth; its SHA-256 is recorded in the manifest so
# downstream consumers can detect drift.
#
# Usage:
#   sanitize.sh [--sanitizer PATH] STAGING_DIR
#   sanitize.sh --help
#
# Output on stdout: the same STAGING_DIR (so the pipeline can be chained).
# Logs go to stderr.
#
# Exit codes:
#   0  sanitization complete
#   1  usage / validation error (missing staging, missing manifest, already sanitized, etc.)
#   2  sanitizer invocation failed

set -euo pipefail

SANITIZER_EXPLICIT=""
STAGING=""

# Candidate paths for the upstream sanitizer (first match wins).
CANDIDATES=(
  "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/devops-tools/skills/session-chronicle/scripts/sanitize_sessions.py"
  "$HOME/eon/cc-skills/plugins/devops-tools/skills/session-chronicle/scripts/sanitize_sessions.py"
)

log() { printf '[sanitize] %s\n' "$*" >&2; }
err() { printf '[sanitize] ERROR: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: sanitize.sh [OPTIONS] STAGING_DIR

Sanitize the sessions produced by bundle.sh (Phase 1) and update the manifest.
STAGING_DIR must be the path previously returned by bundle.sh on stdout.

Options:
  --sanitizer PATH   Use this sanitize_sessions.py instead of auto-discovery.
  --help, -h         Show this help.

After success, STAGING_DIR contains:
  manifest.json          (mutated: sanitized=true, sanitization.*, redactions.*,
                          per-session sanitized_sha256/size/line_count)
  sessions/              (unchanged — raw, for forensic audit)
  sessions-sanitized/    (new — upstream sanitizer output)
  redaction_report.txt   (new — upstream sanitizer report)

Idempotency: refuses to run if manifest.sanitized is already true. Bundle a
fresh staging dir to sanitize again.
EOF
}

# --- arg parse --------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sanitizer) SANITIZER_EXPLICIT="${2:?--sanitizer requires a path}"; shift 2 ;;
    --help|-h)   usage; exit 0 ;;
    --*)         err "unknown arg: $1"; usage >&2; exit 1 ;;
    *)
      if [[ -n "$STAGING" ]]; then
        err "only one STAGING_DIR allowed (got '$STAGING' and '$1')"
        exit 1
      fi
      STAGING="$1"; shift ;;
  esac
done

if [[ -z "$STAGING" ]]; then
  err "STAGING_DIR required"
  usage >&2
  exit 1
fi

# --- validate deps ----------------------------------------------------------
for bin in jq shasum awk stat; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    err "required tool not on PATH: $bin"
    exit 1
  fi
done

# --- validate staging -------------------------------------------------------
if [[ ! -d "$STAGING" ]]; then
  err "staging dir not found: $STAGING"
  exit 1
fi

STAGING="$(cd "$STAGING" && pwd)"   # normalize to absolute
manifest="$STAGING/manifest.json"
sessions_dir="$STAGING/sessions"

if [[ ! -f "$manifest" ]]; then
  err "manifest.json not found: $manifest"
  exit 1
fi

if [[ ! -d "$sessions_dir" ]]; then
  err "sessions/ dir not found: $sessions_dir"
  exit 1
fi

if ! jq -e . "$manifest" >/dev/null 2>&1; then
  err "manifest.json is not valid JSON: $manifest"
  exit 1
fi

already_sanitized="$(jq -r '.sanitized // false' "$manifest")"
if [[ "$already_sanitized" == "true" ]]; then
  err "manifest.sanitized is already true — refusing to re-sanitize"
  err "  bundle a fresh staging dir if you need to re-run"
  exit 1
fi

session_count_expected="$(jq -r '.totals.session_count' "$manifest")"
input_jsonl_count="$(find "$sessions_dir" -maxdepth 1 -type f -name '*.jsonl' | wc -l | awk '{print $1}')"
if [[ "$session_count_expected" != "$input_jsonl_count" ]]; then
  err "manifest claims $session_count_expected sessions but sessions/ has $input_jsonl_count *.jsonl"
  exit 1
fi

# --- locate sanitizer -------------------------------------------------------
SANITIZER=""
if [[ -n "$SANITIZER_EXPLICIT" ]]; then
  if [[ ! -f "$SANITIZER_EXPLICIT" ]]; then
    err "--sanitizer path does not exist: $SANITIZER_EXPLICIT"
    exit 1
  fi
  SANITIZER="$SANITIZER_EXPLICIT"
else
  for c in "${CANDIDATES[@]}"; do
    if [[ -f "$c" ]]; then
      SANITIZER="$c"
      break
    fi
  done
fi

if [[ -z "$SANITIZER" ]]; then
  err "could not locate upstream sanitize_sessions.py; searched:"
  for c in "${CANDIDATES[@]}"; do err "  $c"; done
  err "install Terry's devops-tools plugin or pass --sanitizer PATH"
  exit 1
fi

# The upstream sanitizer's shebang uses uv — require it.
if ! command -v uv >/dev/null 2>&1; then
  err "uv is required to run the upstream sanitizer (its shebang: 'uv run --python 3.13')"
  err "install with: brew install uv"
  exit 1
fi

sanitizer_sha="$(shasum -a 256 "$SANITIZER" | awk '{print $1}')"
out_dir="$STAGING/sessions-sanitized"
report="$STAGING/redaction_report.txt"

log "staging   : $STAGING"
log "sanitizer : $SANITIZER"
log "sha256    : $sanitizer_sha"
log "sessions  : $input_jsonl_count file(s)"

# --- invoke sanitizer -------------------------------------------------------
# The sanitizer rmtrees $out_dir if it exists, so safe to re-invoke.
if ! "$SANITIZER" --input "$sessions_dir" --output "$out_dir" --report "$report" >&2; then
  err "sanitizer invocation failed"
  exit 2
fi

if [[ ! -d "$out_dir" ]]; then
  err "sanitizer did not create output dir: $out_dir"
  exit 2
fi

if [[ ! -f "$report" ]]; then
  err "sanitizer did not write report: $report"
  exit 2
fi

# Verify every input session has a corresponding output file.
output_count=$(find "$out_dir" -maxdepth 1 -type f -name '*.jsonl' | wc -l | awk '{print $1}')
if [[ "$output_count" != "$input_jsonl_count" ]]; then
  err "sanitizer output count mismatch: input=$input_jsonl_count, output=$output_count"
  exit 2
fi

# --- parse report into JSON -------------------------------------------------
# Report format:
#   v2 Redaction Report — <input>
#   Output: <output>
#   Files: X,XXX   Lines: X,XXX   Redactions: X,XXX
#
#   Per-pattern counts (sorted by frequency):
#     pattern_name                  count
#     ...

total_redactions="$(
  awk '/^Files:/ {
    for(i=1;i<=NF;i++) if($i=="Redactions:") {
      v=$(i+1); gsub(",","",v); print v; exit
    }
  }' "$report"
)"
: "${total_redactions:=0}"

by_pattern_json="$(
  awk 'BEGIN{printf "{"}
       /^Per-pattern counts/ { flag=1; next }
       flag && NF==2 {
         v=$2; gsub(",","",v)
         if (v+0 > 0) {
           printf "%s\"%s\":%d", (first?",":""), $1, v
           first=1
         }
       }
       END { printf "}" }' "$report"
)"

# Validate it parses as JSON
if ! printf '%s' "$by_pattern_json" | jq -e . >/dev/null 2>&1; then
  err "failed to parse redaction report into JSON (got: $by_pattern_json)"
  by_pattern_json='{}'
fi

# --- enrich per-session manifest entries ------------------------------------
entries_tmp="$(mktemp)"
trap 'rm -f "$entries_tmp"' EXIT

jq -c '.sessions[]' "$manifest" | while IFS= read -r entry; do
  fn="$(printf '%s' "$entry" | jq -r '.filename')"
  sanitized_path="$out_dir/$fn"
  if [[ ! -f "$sanitized_path" ]]; then
    err "sanitizer did not produce expected output: $sanitized_path"
    exit 2
  fi
  ssz="$(stat -f %z "$sanitized_path")"
  slc="$(awk 'END{print NR}' "$sanitized_path")"
  ssh="$(shasum -a 256 "$sanitized_path" | awk '{print $1}')"
  printf '%s' "$entry" | jq -c \
    --argjson ssz "$ssz" \
    --argjson slc "$slc" \
    --arg     ssh "$ssh" \
    '. + {sanitized_size_bytes: $ssz, sanitized_line_count: $slc, sanitized_sha256: $ssh}' \
    >> "$entries_tmp"
done

# --- mutate manifest in place -----------------------------------------------
now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

new_manifest="$manifest.new.$$"
jq \
  --slurpfile enriched "$entries_tmp" \
  --arg     sat_at      "$now_utc" \
  --arg     san_sha     "$sanitizer_sha" \
  --arg     san_path    "$SANITIZER" \
  --arg     report_path "$report" \
  --argjson by_pattern  "$by_pattern_json" \
  --argjson total       "$total_redactions" \
  '. + {
    sanitized: true,
    sessions:  $enriched,
    sanitization: {
      sanitized_at_utc: $sat_at,
      sanitizer_path:   $san_path,
      sanitizer_sha256: $san_sha,
      report_path:      $report_path
    },
    redactions: {
      total:      $total,
      by_pattern: $by_pattern
    }
  }' "$manifest" > "$new_manifest"

mv "$new_manifest" "$manifest"

log "manifest  : updated (sanitized=true, $total_redactions redactions)"
log "done"
printf '%s\n' "$STAGING"
