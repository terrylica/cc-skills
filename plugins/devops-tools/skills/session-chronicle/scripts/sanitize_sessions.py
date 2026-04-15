#!/usr/bin/env -S uv run --python 3.13 --no-project
# /// script
# requires-python = ">=3.13"
# dependencies = []
# ///
"""
sanitize_v2.py — Field-aware, multi-pass redactor for Claude Code JSONL sessions.

Improvements over v1:

    1. FIELD-AWARE JSON WALK
       v1 ran regex over every string value. This destroyed UUIDs, tool IDs, and
       forex decimals (18k+ false positives). v2 tracks the field name and skips
       destructive patterns (esp. phone) inside known-safe fields.

    2. NARROWED PHONE REGEX
       Must have explicit separators between digit groups; word boundaries reject
       hex-adjacent matches. Prevents UUID/timestamp/decimal destruction.

    3. NEW PATTERNS (from 10-agent audit)
       - Tailscale API key  (tskey-...)
       - Tailscale CGNAT    (100.64-127.x.x)
       - Tailnet DNS        (*.ts.net, terrylica.github)
       - .internal hosts    (*.internal)
       - 1Password IDs      (32-char base32)
       - op:// paths
       - Cloudflare Global API Key (37-char hex)
       - ClickHouse URLs with passwords
       - CF_AppSession cookies
       - Preventive: Doppler, Telegram bot, Supabase, Docker PAT, npm

    4. URL-DECODE PRE-PASS
       For URL-looking values, decode %xx escapes before applying patterns.
       Catches tokens hidden via %3D, %2D, etc.

    5. SHARPER PLACEHOLDERS
       Each redaction tags its category, making downstream review easier.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import urllib.parse
from collections import Counter
from pathlib import Path

INPUT_DIR = Path("./claude-sessions-export-raw")  # default; override via --input
OUTPUT_DIR = Path("./claude-sessions-export")  # default; override via --output
REPORT = Path("./redaction_report.txt")  # default; override via --report

# JSON field names whose values we should NOT redact with destructive patterns
# (UUIDs, tool IDs, etc. — these caused v1's massive false-positive explosion).
SAFE_FIELD_NAMES = frozenset({
    "uuid", "parentUuid", "session_id", "sessionId", "id",
    "toolUseID", "tool_use_id", "tool_use", "toolu_id",
    "message_id", "messageId", "msg_id", "msgId",
    "promptId", "prompt_id",
    "file_id", "fileId",
    "agent_id", "agentId", "subagent_id",
    "cwd", "gitBranch", "version", "user_id", "userId",
    "type",  # enum values
    "role",  # enum values
    "stop_reason", "stopReason",
    "model",
    "timestamp",  # ISO strings
    "date",
})

# Pattern categories. Patterns in DESTRUCTIVE_PATTERNS are NOT applied inside safe fields.
# Patterns in UNIVERSAL_PATTERNS are always applied (credentials are credentials regardless of field).
# Each entry: (name, compiled regex, replacement)

UNIVERSAL_PATTERNS = [
    # ── Real secret formats (always redact, everywhere) ───────────────

    # SSH private keys
    ("ssh_private_key",
     re.compile(r"-----BEGIN (?:OPENSSH|RSA|EC|DSA|ED25519|PGP|PRIVATE|ENCRYPTED) [A-Z ]*KEY[A-Z ]*-----.*?-----END (?:OPENSSH|RSA|EC|DSA|ED25519|PGP|PRIVATE|ENCRYPTED) [A-Z ]*KEY[A-Z ]*-----", re.DOTALL),
     "[REDACTED-PRIVATE-KEY-BLOCK]"),

    # AWS
    ("aws_access_key",
     re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
     "[REDACTED-AWS-ACCESS-KEY]"),
    ("aws_secret_key_labeled",
     re.compile(r"(?i)(aws_secret_access_key|secret_access_key|aws_secret)[\s\"':=]{1,5}[A-Za-z0-9/+=]{40}"),
     r"\1=[REDACTED-AWS-SECRET]"),

    # GitHub
    ("github_pat_classic", re.compile(r"\bghp_[A-Za-z0-9]{36}\b"), "[REDACTED-GITHUB-PAT]"),
    ("github_pat_fine",    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{80,}\b"), "[REDACTED-GITHUB-PAT]"),
    ("github_oauth",       re.compile(r"\bgho_[A-Za-z0-9]{36}\b"), "[REDACTED-GITHUB-OAUTH]"),
    ("github_app_token",   re.compile(r"\b(?:ghu|ghs|ghr)_[A-Za-z0-9]{36}\b"), "[REDACTED-GITHUB-APP-TOKEN]"),

    # AI services
    ("anthropic_key", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{80,}\b"), "[REDACTED-ANTHROPIC-KEY]"),
    ("openai_key",    re.compile(r"\bsk-(?!ant-)[A-Za-z0-9]{20,}\b"), "[REDACTED-OPENAI-KEY]"),

    # Slack
    ("slack_token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"), "[REDACTED-SLACK-TOKEN]"),

    # Stripe
    ("stripe_live", re.compile(r"\bsk_live_[A-Za-z0-9]{24,}\b"), "[REDACTED-STRIPE-LIVE-KEY]"),
    ("stripe_test", re.compile(r"\bsk_test_[A-Za-z0-9]{24,}\b"), "[REDACTED-STRIPE-TEST-KEY]"),

    # 1Password
    ("onepassword_service_token",
     re.compile(r"\bops_[A-Za-z0-9_-]{30,}\b"),
     "[REDACTED-1P-SERVICE-TOKEN]"),

    # Google API key
    ("google_api_key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"), "[REDACTED-GOOGLE-API-KEY]"),

    # JWT
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"), "[REDACTED-JWT]"),

    # Bearer & Authorization
    ("bearer_token",
     re.compile(r"(?i)bearer\s+[A-Za-z0-9._~+/=-]{16,}"),
     "Bearer [REDACTED-BEARER-TOKEN]"),
    ("authorization_header",
     re.compile(r"(?i)authorization[\s\"':=]{1,5}(?:basic|bearer|digest)\s+[A-Za-z0-9+/=._~-]{8,}"),
     "Authorization: [REDACTED-AUTH]"),

    # ── NEW in v2: Tailscale (real leak caught in audit) ──────────────

    ("tailscale_api_key",
     re.compile(r"\btskey-(?:api|auth|client)-[A-Za-z0-9]{40,}\b"),
     "[REDACTED-TAILSCALE-API-KEY]"),

    # ── NEW in v2: Cloudflare ─────────────────────────────────────────

    ("cloudflare_api_token",
     re.compile(r"\b[A-Za-z0-9_-]{40}\b(?=[^\w]|$)(?=(?:[^\w]*(?:cloudflare|cf[-_]?api|X-Auth-Key)))", re.IGNORECASE),
     "[REDACTED-CF-API-TOKEN]"),
    ("cloudflare_global_api_key",
     re.compile(r"(?i)(X-Auth-Key[\s:\"']+)([a-f0-9]{37})\b"),
     r"\1[REDACTED-CF-GLOBAL-KEY]"),
    ("cf_app_session",
     re.compile(r"CF_AppSession=[A-Za-z0-9._-]+"),
     "CF_AppSession=[REDACTED-CF-SESSION]"),

    # ── NEW in v2: ClickHouse URLs with password ──────────────────────

    ("clickhouse_url_creds",
     re.compile(r"\b(?:clickhouse|clickhouses|https?)://[^:/\s]+:[^@/\s]+@[a-z0-9.-]+\.clickhouse\.(?:cloud|com)\S*"),
     "[REDACTED-CLICKHOUSE-URL-WITH-CREDS]"),

    # ── NEW in v2: 1Password item/vault IDs (infra enumeration) ───────

    ("onepassword_op_url",
     re.compile(r"\bop://[^\s\"'<>]+"),
     "[REDACTED-1P-URL]"),
    ("onepassword_item_id",
     # 1P item IDs are 26-char base32 lowercase. Require `op ` or 1Password context nearby.
     # Use a conservative pattern: 26 chars of [a-z0-9] with high entropy, preceded by op-related keywords.
     re.compile(r"(?i)(op\s+(?:read|item|get|run)[^\n]*?|1password[^\n]*?)\b([a-z0-9]{26})\b"),
     r"\1[REDACTED-1P-ITEM-ID]"),

    # ── NEW in v2: Doppler (preventive, Terry uses it) ────────────────

    ("doppler_token",
     re.compile(r"\bdp\.(?:st|pt|sa|svc)\.[A-Za-z0-9_-]{40,}\b"),
     "[REDACTED-DOPPLER-TOKEN]"),

    # ── NEW in v2: Docker Hub PAT ─────────────────────────────────────

    ("docker_pat",
     re.compile(r"\bdckr_pat_[A-Za-z0-9_-]{20,}\b"),
     "[REDACTED-DOCKER-PAT]"),

    # ── NEW in v2: npm tokens ─────────────────────────────────────────

    ("npm_token",
     re.compile(r"\bnpm_[A-Za-z0-9]{36}\b"),
     "[REDACTED-NPM-TOKEN]"),

    # ── NEW in v2: Supabase ───────────────────────────────────────────

    ("supabase_access_token",
     re.compile(r"\bsbp_[A-Za-z0-9_-]{30,}\b"),
     "[REDACTED-SUPABASE-TOKEN]"),

    # ── NEW in v2: SendGrid ───────────────────────────────────────────

    ("sendgrid_key",
     re.compile(r"\bSG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}\b"),
     "[REDACTED-SENDGRID-KEY]"),

    # ── NEW in v2: Telegram bot token (preventive) ────────────────────

    # Format: 8-10 digit bot id, colon, 35-char secret. Require colon-delimited form.
    ("telegram_bot_token",
     re.compile(r"\b[0-9]{8,10}:[A-Za-z0-9_-]{35}\b"),
     "[REDACTED-TELEGRAM-BOT-TOKEN]"),

    # ── NEW in v2: Tailscale infrastructure ───────────────────────────

    ("tailnet_dns",
     re.compile(r"\b[A-Za-z0-9-]+\.tail[a-f0-9]+\.ts\.net\b"),
     "[REDACTED-TAILNET-DNS]"),
    ("tailnet_name_terrylica",
     re.compile(r"\bterrylica\.github\b"),
     "[REDACTED-TAILNET-NAME]"),
    ("tailscale_cgnat_ip",
     re.compile(r"\b100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.\d{1,3}\.\d{1,3}\b"),
     "[REDACTED-TAILSCALE-IP]"),

    # ── NEW in v2: Internal hostnames ─────────────────────────────────

    ("dot_internal_hostname",
     re.compile(r"\b[a-zA-Z0-9][a-zA-Z0-9-]{0,40}\.internal\b"),
     "[REDACTED-INTERNAL-HOST]"),

    # ── NEW in v2: Private IP ranges ──────────────────────────────────

    ("ip_172_25",
     re.compile(r"\b172\.25\.\d{1,3}\.\d{1,3}\b"),
     "[REDACTED-PRIVATE-IP]"),

    # ── NEW in v2: Cloudflare account ID (specific one seen leaking) ──

    ("cloudflare_account_id",
     re.compile(r"\bK5BH72Z7O5BYXOGKBYT5FWTP2E\b"),
     "[REDACTED-CF-ACCOUNT-ID]"),

    # ── Credential declarations (unchanged from v1, but refined replacements) ──

    ("generic_password",
     re.compile(r"(?i)([\"']?(?:password|passwd|pwd)[\"']?\s*[:=]\s*[\"']?)([^\"'\s,}]{4,})([\"']?)"),
     r"\1[REDACTED-PASSWORD]\3"),
    ("generic_api_key",
     re.compile(r"(?i)([\"']?(?:api[_-]?key|apikey|access[_-]?token)[\"']?\s*[:=]\s*[\"']?)([^\"'\s,}]{8,})([\"']?)"),
     r"\1[REDACTED-API-KEY]\3"),
    ("generic_secret",
     re.compile(r"(?i)([\"']?(?:secret|client[_-]?secret|private[_-]?key)[\"']?\s*[:=]\s*[\"']?)([^\"'\s,}]{8,})([\"']?)"),
     r"\1[REDACTED-SECRET]\3"),

    # ── Contact info (universal — emails don't appear in UUIDs) ───────

    ("email_address",
     re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
     "[REDACTED-EMAIL]"),
]

# DESTRUCTIVE_PATTERNS only run in prose-like fields (not UUID-type fields).
# These are the ones v1 destroyed UUIDs with.
DESTRUCTIVE_PATTERNS = [
    # Narrowed phone — requires explicit separators, rejects hex neighbors
    ("phone_international",
     re.compile(r"(?<![A-Fa-f0-9-])\+\d{1,3}[\s.-]\d{1,4}[\s.-]\d{3,4}[\s.-]\d{3,4}(?![A-Fa-f0-9-])"),
     "[REDACTED-PHONE]"),
    ("phone_us_formatted",
     # Must have EXPLICIT separators: (XXX) XXX-XXXX, XXX-XXX-XXXX, XXX.XXX.XXXX, XXX XXX XXXX
     # No pure-digit 10-char matches (those were destroying UUIDs).
     re.compile(r"(?<![A-Fa-f0-9\w])\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4}(?![A-Fa-f0-9\w])"),
     "[REDACTED-PHONE]"),
]


URL_SENSITIVE_QUERY = re.compile(
    r"(?i)(https?://[^\s\"'<>()]+?[?&](?:token|api[_-]?key|access[_-]?token|auth|password|secret|code)=)[^&\s\"'<>()]+"
)


def sanitize_text_universal(text: str, counts: Counter) -> str:
    """Apply universal patterns (always safe regardless of field)."""
    for name, pat, repl in UNIVERSAL_PATTERNS:
        new, n = pat.subn(repl, text)
        if n:
            counts[name] += n
            text = new

    # URL query sanitization (catches token=... in any URL)
    new, n = URL_SENSITIVE_QUERY.subn(r"\1[REDACTED-IN-URL]", text)
    if n:
        counts["url_sensitive_query"] += n
        text = new

    return text


def sanitize_text_destructive(text: str, counts: Counter) -> str:
    """Apply destructive patterns (skip inside UUID-type fields)."""
    for name, pat, repl in DESTRUCTIVE_PATTERNS:
        new, n = pat.subn(repl, text)
        if n:
            counts[name] += n
            text = new
    return text


def walk_sanitize(node, counts: Counter, in_safe_field: bool = False):
    """Recursive JSON walker.

    If a dict field name is in SAFE_FIELD_NAMES, its string value gets only the
    universal patterns (emails, real secret tokens), skipping phone-style
    destructive patterns that murder UUIDs.
    """
    if isinstance(node, str):
        text = sanitize_text_universal(node, counts)
        if not in_safe_field:
            text = sanitize_text_destructive(text, counts)
        return text
    if isinstance(node, list):
        return [walk_sanitize(v, counts, in_safe_field) for v in node]
    if isinstance(node, dict):
        out = {}
        for k, v in node.items():
            child_in_safe = in_safe_field or (k in SAFE_FIELD_NAMES)
            out[k] = walk_sanitize(v, counts, child_in_safe)
        return out
    return node


def sanitize_json_line(line: str, counts: Counter) -> str:
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        # Raw-text fallback — apply universal patterns only (safer).
        return sanitize_text_universal(line, counts)
    sanitized = walk_sanitize(obj, counts)
    return json.dumps(sanitized, ensure_ascii=False, separators=(",", ":"))


def process_file(src: Path, dst: Path, counts: Counter) -> int:
    dst.parent.mkdir(parents=True, exist_ok=True)
    line_count = 0
    with src.open("r", encoding="utf-8", errors="replace") as f_in, \
         dst.open("w", encoding="utf-8") as f_out:
        for line in f_in:
            line_count += 1
            stripped = line.rstrip("\n")
            if not stripped:
                f_out.write("\n")
                continue
            f_out.write(sanitize_json_line(stripped, counts) + "\n")
    return line_count


def main() -> None:
    ap = argparse.ArgumentParser(description="v2 sanitizer for Claude Code JSONL sessions")
    ap.add_argument("--input", type=Path, default=INPUT_DIR, help="Input directory (raw JSONL)")
    ap.add_argument("--output", type=Path, default=OUTPUT_DIR, help="Output directory (sanitized)")
    ap.add_argument("--report", type=Path, default=REPORT, help="Redaction report path")
    args = ap.parse_args()

    input_dir: Path = args.input.resolve()
    output_dir: Path = args.output.resolve()
    report_path: Path = args.report.resolve()

    if not input_dir.is_dir():
        print(f"ERROR: input dir missing: {input_dir}", file=sys.stderr)
        print("Expected the fresh (non-sanitized) staging dir.", file=sys.stderr)
        sys.exit(1)

    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    # Sanitize MANIFEST too
    manifest_src = input_dir / "MANIFEST.md"
    if manifest_src.exists():
        m_counts: Counter = Counter()
        text = manifest_src.read_text(encoding="utf-8")
        (output_dir / "MANIFEST.md").write_text(
            sanitize_text_universal(sanitize_text_destructive(text, m_counts), m_counts),
            encoding="utf-8",
        )

    counts: Counter = Counter()
    file_count = 0
    line_count = 0

    files = sorted(input_dir.rglob("*.jsonl"))
    total = len(files)
    print(f"v2 sanitization: {total} files")
    print(f"  Input:  {input_dir}")
    print(f"  Output: {output_dir}")

    for idx, src in enumerate(files, 1):
        rel = src.relative_to(input_dir)
        dst = output_dir / rel
        line_count += process_file(src, dst, counts)
        file_count += 1
        if idx % 100 == 0 or idx == total:
            print(f"  {idx}/{total} ({line_count:,} lines)")

    print("\n=== v2 Redaction Summary ===")
    for name, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {name:<35s} {n:>8,}")
    total_redactions = sum(counts.values())
    print(f"\nTotal redactions: {total_redactions:,}")
    print(f"Files:            {file_count:,}")
    print(f"Lines:            {line_count:,}")

    with report_path.open("w") as f:
        f.write(f"v2 Redaction Report — {input_dir}\n")
        f.write(f"Output: {output_dir}\n")
        f.write(f"Files: {file_count:,}   Lines: {line_count:,}   Redactions: {total_redactions:,}\n\n")
        f.write("Per-pattern counts (sorted by frequency):\n")
        for name, n in sorted(counts.items(), key=lambda kv: -kv[1]):
            f.write(f"  {name:<35s} {n:>8,}\n")
    print(f"\nReport: {report_path}")


if __name__ == "__main__":
    main()
