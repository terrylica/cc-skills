---
name: telemetry-terminology-similarity
description: Detect similar/duplicate field names in telemetry, logging, and observability schemas. TRIGGERS - field name collision, terminology overlap, schema dedup, naming inconsistency, telemetry naming, log field similarity.
allowed-tools: Read, Bash, Grep, Edit, Write
---

# Telemetry Terminology Similarity

Detect when different telemetry field names mean the same thing — preventing terminology collisions that cause silent data misinterpretation in observability pipelines.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## When to Use This Skill

Use this skill when:

- Auditing a telemetry/logging schema for naming collisions
- Comparing two JSONL log schemas for field overlap
- Reviewing OTel semantic convention compliance
- Detecting `trace_id` vs `traceId` vs `request_id` vs `correlation_id` style problems
- Validating field naming consistency before shipping telemetry changes

## Architecture

3-layer pipeline — each layer catches what the others miss:

```
┌─────────────────────────────────────────────────────────┐
│  Layer 1: NORMALIZE                                     │
│  camelCase/snake_case split + abbreviation expansion    │
│  wordninja for concatenated words                       │
│  "traceId" → "trace id", "ts" → "timestamp"            │
├─────────────────────────────────────────────────────────┤
│  Layer 2: SYNTACTIC (RapidFuzz)                         │
│  token_set_ratio on normalized forms                    │
│  Catches: trace_id ↔ traceId, level ↔ log_level        │
├─────────────────────────────────────────────────────────┤
│  Layer 3: SEMANTIC (sentence-transformers)              │
│  Cosine similarity via all-MiniLM-L6-v2 embeddings     │
│  Catches: error ↔ exception, user_id ↔ account_id      │
├─────────────────────────────────────────────────────────┤
│  Output: Union-find clusters + ranked match pairs       │
└─────────────────────────────────────────────────────────┘
```

## Dependencies

All installed via `uv run` (PEP 723 inline metadata — no global install needed):

| Package                 | Purpose                          | Size    |
| ----------------------- | -------------------------------- | ------- |
| `sentence-transformers` | Semantic embeddings (MiniLM-L6)  | ~80 MB  |
| `rapidfuzz`             | Fast fuzzy string matching (C++) | ~1.3 MB |
| `wordninja`             | Probabilistic word splitting     | ~0.5 MB |
| `orjson`                | Fast JSON serialization          | ~0.3 MB |

First run downloads the `all-MiniLM-L6-v2` model (~80 MB). Subsequent runs use cache.

## Script Location

The analysis script lives in this skill's `references/` directory. Resolve the path before use:

```bash
# SSoT-OK: marketplace path resolution for cross-repo invocation
SCRIPT_DIR="$(dirname "$(find ~/.claude/plugins -path '*/telemetry-terminology-similarity/references/term_similarity.py' -print -quit 2>/dev/null)")"
SCRIPT="$SCRIPT_DIR/term_similarity.py"
```

All examples below assume `$SCRIPT` is set. When invoking from the cc-skills repo itself, use the relative path directly: `plugins/quality-tools/skills/telemetry-terminology-similarity/references/term_similarity.py`.

## Usage

### Analyze field names directly

```bash
# SSoT-OK: uv run handles PEP 723 inline deps
uv run --python 3.13 "$SCRIPT" \
  trace_id traceId request_id correlation_id \
  level severity log_level priority \
  timestamp created_at time ts \
  error exception fault \
  duration_ms latency response_time
```

### Extract fields from a Python codebase

Use Python regex extraction (macOS lacks `grep -P`):

```bash
python3 -c "
import re, glob, sys
fields = set()
for f in glob.glob('**/*.py', recursive=True):
    text = open(f).read()
    for m in re.finditer(r'\"([a-z][a-z0-9_]*?)\":', text):
        fields.add(m.group(1))
for f in sorted(fields):
    print(f)
" | uv run --python 3.13 "$SCRIPT"
```

### Analyze from stdin (pipe from jq, grep, etc.)

```bash
# Extract field names from JSONL and pipe
head -1 telemetry.jsonl | jq -r 'keys[]' | \
  uv run --python 3.13 "$SCRIPT"
```

### Analyze a JSONL file's fields (including nested)

```bash
uv run --python 3.13 "$SCRIPT" --jsonl /path/to/telemetry.jsonl
```

### Compare two JSON schemas

```bash
uv run --python 3.13 "$SCRIPT" \
  --schema-a schema_v1.json --schema-b schema_v2.json
```

### JSON output (for programmatic consumption)

```bash
uv run --python 3.13 "$SCRIPT" --json \
  trace_id request_id correlation_id level severity
```

### Custom thresholds

```bash
# Tighter thresholds (fewer false positives)
uv run --python 3.13 "$SCRIPT" \
  --syntactic-threshold 75 --semantic-threshold 0.65 \
  trace_id traceId level severity

# Looser thresholds (catch more borderline cases)
uv run --python 3.13 "$SCRIPT" \
  --syntactic-threshold 55 --semantic-threshold 0.45 \
  trace_id traceId level severity
```

## Parameters

| Parameter               | Default | Range   | Description                                        |
| ----------------------- | ------- | ------- | -------------------------------------------------- |
| `--syntactic-threshold` | 65      | 0-100   | RapidFuzz token_set_ratio cutoff                   |
| `--semantic-threshold`  | 0.55    | 0.0-1.0 | Cosine similarity cutoff for sentence-transformers |
| `--jsonl`               | —       | path    | Extract fields from a JSONL file (all unique keys) |
| `--schema-a` / `-b`     | —       | path    | Cross-schema comparison (two JSON schema files)    |
| `--json`                | false   | flag    | Output as structured JSON instead of text          |

## Output Format

### Text output (default)

```
Fields analyzed: 24
Unique after normalization: 21

=== EXACT DUPLICATES (after normalization) ===
  trace_id  ==  traceId
  timestamp  ==  ts
  user_id  ==  uid

=== SIMILARITY CLUSTERS ===
  [exact+semantic] correlation_id
               ~ trace_id
               ~ request_id
  [both]       level
               ~ log_level
  [semantic]   error
               ~ exception

=== ALL MATCHES (sorted by combined score) ===
  syn=100.0  sem=0.560  [both     ]  level         <-> log_level
  syn= 28.6  sem=0.700  [semantic ]  error         <-> exception
```

### JSON output (`--json`)

Structured JSON with `similarity_matches` and `clusters` arrays. Useful for CI integration or downstream analysis.

## Abbreviation Dictionary

The normalizer expands common telemetry abbreviations:

| Abbreviation | Expansion      | Abbreviation | Expansion     |
| ------------ | -------------- | ------------ | ------------- |
| `ts`         | timestamp      | `uid`        | user id       |
| `req`        | request        | `resp`       | response      |
| `err`        | error          | `msg`        | message       |
| `dur`        | duration       | `ms`         | milliseconds  |
| `svc`        | service        | `env`        | environment   |
| `op`         | operation      | `lvl`        | level         |
| `evt`        | event          | `attr`       | attribute     |
| `ctx`        | context        | `lat`        | latency       |
| `acct`       | account        | `cfg`        | configuration |
| `auth`       | authentication | `conn`       | connection    |

Add domain-specific abbreviations by editing `ABBREVIATIONS` in `term_similarity.py`.

## How Each Layer Contributes

| Scenario                         | Layer 1 (Normalize) | Layer 2 (Syntactic) | Layer 3 (Semantic) |
| -------------------------------- | ------------------- | ------------------- | ------------------ |
| `trace_id` vs `traceId`          | exact match         | 100                 | 1.000              |
| `timestamp` vs `ts`              | exact (abbrev)      | 100                 | 1.000              |
| `level` vs `log_level`           | different           | 100 (subset)        | 0.560              |
| `error` vs `exception`           | different           | 28.6                | 0.700              |
| `user_id` vs `account_id`        | different           | 47.1                | 0.792              |
| `duration_ms` vs `response_time` | different           | 35.3                | 0.456              |

## Known Limitations

1. **Semantic model biases**: `all-MiniLM-L6-v2` trained on general English — may miss domain-specific equivalences (e.g., `severity` ↔ `level` scores ~0.38, below default threshold)
2. **Abbreviation dictionary is static**: Novel abbreviations require manual addition
3. **No value-based matching**: Only compares field names, not field values (use Valentine for value-distribution-based matching)
4. **First-run latency**: ~5s to download and load the model on first invocation

## Complementary Tools

| Tool             | When to Use Instead                                      |
| ---------------- | -------------------------------------------------------- |
| **OTel Weaver**  | Validate against OTel semantic conventions (CI linting)  |
| **Valentine**    | Schema matching using both names AND value distributions |
| **SemHash**      | Fast bulk dedup (>10k fields) with Model2Vec embeddings  |
| **Vector + VRL** | Runtime field renaming in observability pipelines        |

## Troubleshooting

| Issue                            | Cause                         | Solution                                           |
| -------------------------------- | ----------------------------- | -------------------------------------------------- |
| `ModuleNotFoundError`            | Missing deps                  | Use `uv run` (PEP 723 resolves deps automatically) |
| Model download slow              | First run                     | Model cached after first download (~80 MB)         |
| Too many false positives         | Thresholds too low            | Raise `--semantic-threshold` to 0.65+              |
| Mega-clusters (60+ fields)       | Generic English words cluster | Raise `--semantic-threshold` to 0.65+              |
| Missing known equivalences       | Thresholds too high           | Lower `--semantic-threshold` to 0.45               |
| Abbreviation not expanded        | Not in dictionary             | Add to `ABBREVIATIONS` in `term_similarity.py`     |
| `severity` ↔ `level` not caught  | Model limitation              | Lower threshold or add to abbreviation dict        |
| Script not found from other repo | Path not resolved             | Set `$SCRIPT` per Script Location section above    |
| `grep: invalid option -- P`      | macOS lacks PCRE              | Use `python3 -c "import re..."` pattern instead    |

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If the underlying tool's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
