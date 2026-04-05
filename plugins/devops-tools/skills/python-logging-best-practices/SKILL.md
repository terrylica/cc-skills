---
name: python-logging-best-practices
description: Python logging with loguru, structlog, and orjson. TRIGGERS - loguru, structlog, structured logging, JSONL logs, log rotation, secret redaction, OTel logging.
allowed-tools: Read, Bash, Grep, Edit, Write
---

# Python Logging Best Practices

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## When to Use This Skill

Use this skill when:

- Setting up Python logging with loguru or structlog
- Configuring structured JSONL logging for analysis
- Implementing log rotation
- Choosing between loguru, structlog, and stdlib logging
- Adding logging to containerized vs local applications

## Overview

Unified reference for Python logging patterns optimized for machine readability (Claude Code analysis) and operational reliability.

## MANDATORY Best Practices

### 1. Log Rotation (ALWAYS CONFIGURE for local/CLI apps)

Prevent unbounded log growth — configure rotation for ALL file-based log sinks:

```python
# Loguru pattern (recommended for CLI tools and scripts)
from loguru import logger

logger.add(
    log_path,
    rotation="10 MB",      # Rotate at 10MB
    retention="7 days",    # Keep 7 days
    compression="gz"       # Compress old logs
)

# RotatingFileHandler pattern (stdlib-only)
from logging.handlers import RotatingFileHandler

handler = RotatingFileHandler(
    log_path,
    maxBytes=100 * 1024 * 1024,  # 100MB
    backupCount=5                 # Keep 5 backups (~500MB max)
)
```

> **Container/serverless apps**: Skip file rotation entirely. Log to **stdout/stderr as JSON**. Let the container runtime (Docker log driver, k8s fluentbit/fluentd) handle collection and rotation.

### 2. JSONL Format (Machine-Readable)

Use JSONL (`.jsonl`) for logs that Claude Code or other tools will analyze:

```python
# One JSON object per line - jq-parseable
{"timestamp": "2026-01-14T12:45:23.456Z", "level": "info", "message": "..."}
{"timestamp": "2026-01-14T12:45:24.789Z", "level": "error", "message": "..."}
```

**File extension**: Always use `.jsonl` (not `.json` or `.log`)

**Validation**: `cat file.jsonl | jq -c .`

**Terminology**: JSONL is canonical. Equivalent terms: NDJSON, JSON Lines.

**Performance**: For high-volume logging (>10k records/sec), use `orjson` instead of `json.dumps()`:

```python
import orjson

def json_formatter(record) -> str:
    """JSONL formatter — orjson is 2-10x faster than stdlib json."""
    log_entry = { ... }
    return orjson.dumps(log_entry).decode()  # orjson returns bytes
```

### 3. Security — Never Log Secrets

**Rule**: Redact secrets at the log filter level, not after the fact.

```python
import re

REDACT_PATTERNS = [
    (re.compile(r'AKIA[0-9A-Z]{16}'), '[REDACTED_AWS_KEY]'),
    (re.compile(r'sk-[a-zA-Z0-9]{48}'), '[REDACTED_API_KEY]'),
    (re.compile(r'(?i)bearer\s+[a-zA-Z0-9._~+/=-]+'), '[REDACTED_BEARER]'),
    (re.compile(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'), '[REDACTED_EMAIL]'),
]

def redact_filter(record):
    """Loguru filter that scrubs secrets from log messages."""
    for pattern, replacement in REDACT_PATTERNS:
        record["message"] = pattern.sub(replacement, record["message"])
    return True

logger.add(sink, filter=redact_filter)
```

For compliance-heavy contexts, consider [`pii-redactor`](https://pypi.org/project/pii-redactor/) for broader PII detection (emails, phones, SSNs, credit cards). Note: regex-based detection produces false positives — use as a safety net, not primary defense. **Best practice: don't log PII at all.**

### 4. Shutdown — Always Flush Enqueued Messages

When using `enqueue=True`, call `logger.complete()` before exit to flush pending messages:

```python
import asyncio
from loguru import logger

async def main():
    logger.add("app.jsonl", enqueue=True)
    # ... application logic ...
    await logger.complete()  # Flush all enqueued messages

asyncio.run(main())

# Sync equivalent:
logger.remove()  # Implicitly flushes and closes all sinks
```

Omitting this = **silent log loss** on shutdown.

## When to Use Which Approach

| Approach    | Use Case                              | Pros                                       | Cons                                     |
| ----------- | ------------------------------------- | ------------------------------------------ | ---------------------------------------- |
| `loguru`    | CLI tools, scripts, local services    | Zero-config, built-in rotation, great DX   | External dep, not truly schema-enforced  |
| `structlog` | Production services, OTel integration | ContextVars, processor chains, OTel-native | Steeper learning curve                   |
| `stdlib`    | LaunchAgent daemons, zero-dep         | No dependencies, Python 3.13 `merge_extra` | More boilerplate, no structured defaults |
| `Logfire`   | AI/LLM observability, Pydantic apps   | Built on OTel, token/cost tracking, SQL    | SaaS dependency, newer ecosystem         |

**Decision heuristic**:

- CLI script or local tool → **loguru**
- Production service with tracing → **structlog** + OTel
- AI/LLM app with Pydantic → **Pydantic Logfire**
- Stdlib-only constraint → **RotatingFileHandler**
- Container/serverless → stdout JSON (any library), no file rotation

## Complete Loguru + JSONL Pattern

Cross-platform structured logging with rotation and security:

```python
#!/usr/bin/env python3
# /// script
# requires-python = ">=3.13"
# dependencies = ["loguru", "orjson"]
# ///

import re
import sys
from pathlib import Path
from uuid import uuid4

import orjson
from loguru import logger

REDACT_PATTERNS = [
    (re.compile(r'AKIA[0-9A-Z]{16}'), '[REDACTED_AWS_KEY]'),
    (re.compile(r'sk-[a-zA-Z0-9]{48}'), '[REDACTED_API_KEY]'),
]


def json_formatter(record) -> str:
    """JSONL formatter for Claude Code analysis. Uses orjson for speed."""
    log_entry = {
        "timestamp": record["time"].strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
        "level": record["level"].name.lower(),
        "component": record["function"],
        "operation": record["extra"].get("operation", "unknown"),
        "operation_status": record["extra"].get("status", None),
        "trace_id": record["extra"].get("trace_id"),
        "message": record["message"],
        "context": {k: v for k, v in record["extra"].items()
                   if k not in ("operation", "status", "trace_id", "metrics")},
        "metrics": record["extra"].get("metrics", {}),
        "error": None
    }

    if record["exception"]:
        exc_type, exc_value, _ = record["exception"]
        log_entry["error"] = {
            "type": exc_type.__name__ if exc_type else "Unknown",
            "message": str(exc_value) if exc_value else "Unknown error",
        }

    return orjson.dumps(log_entry).decode()


def redact_filter(record):
    for pattern, replacement in REDACT_PATTERNS:
        record["message"] = pattern.sub(replacement, record["message"])
    return True


def setup_logger(app_name: str, log_dir: Path | None = None):
    """Configure Loguru for machine-readable JSONL output.

    Args:
        app_name: Application name for log file naming.
        log_dir: Directory for log files. If None, logs only to stderr.
    """
    logger.remove()

    # Console output (JSONL to stderr)
    logger.add(sys.stderr, format=json_formatter, filter=redact_filter, level="INFO")

    # File output with rotation (if log_dir provided)
    if log_dir is not None:
        log_dir.mkdir(parents=True, exist_ok=True)
        logger.add(
            str(log_dir / f"{app_name}.jsonl"),
            format=json_formatter,
            filter=redact_filter,
            rotation="10 MB",
            retention="7 days",
            compression="gz",
            level="DEBUG"
        )

    return logger


# Usage
setup_logger("my-app", log_dir=Path.home() / ".local" / "log" / "my-app")
trace_id = str(uuid4())

logger.info(
    "Operation started",
    operation="my_operation",
    status="started",
    trace_id=trace_id
)

logger.info(
    "Operation complete",
    operation="my_operation",
    status="success",
    trace_id=trace_id,
    metrics={"duration_ms": 150, "items_processed": 42}
)
```

## Semantic Fields Reference

| Field              | Type            | Purpose                                                   |
| ------------------ | --------------- | --------------------------------------------------------- |
| `timestamp`        | ISO 8601 with Z | Event ordering (millisecond precision minimum)            |
| `level`            | string          | debug/info/warning/error/critical                         |
| `component`        | string          | Module/function name                                      |
| `operation`        | string          | What action is being performed                            |
| `operation_status` | string          | started/success/failed/skipped                            |
| `trace_id`         | UUID4 or OTel   | Correlation ID. Use OTel trace ID for production services |
| `message`          | string          | Human-readable description                                |
| `context`          | object          | Operation-specific metadata                               |
| `metrics`          | object          | Quantitative data (counts, durations)                     |
| `error`            | object/null     | Exception details if failed                               |

> **OTel note**: For production services instrumented with OpenTelemetry, replace `uuid4()` trace IDs with OTel-propagated trace IDs. Set `OTEL_PYTHON_LOG_CORRELATION=true` to auto-inject `trace_id`/`span_id` into stdlib `LogRecord`. structlog processor chains can inject OTel context natively.

## Related Resources

- [Python logging.handlers](https://docs.python.org/3/library/logging.handlers.html#rotatingfilehandler) - RotatingFileHandler for log rotation
- [loguru patterns](./references/loguru-patterns.md) - Advanced loguru configuration
- [logging architecture](./references/logging-architecture.md) - Decision tree and comparison
- [migration guide](./references/migration-guide.md) - From print() to structured logging
- [structlog docs](https://www.structlog.org/) - Structured logging for production services
- [Pydantic Logfire](https://pydantic.dev/logfire) - AI/LLM observability built on OTel
- [orjson](https://github.com/ijl/orjson) - Fast JSON serialization (Rust-backed)

## Anti-Patterns to Avoid

1. **Unbounded logs** - Always configure rotation (local) or stdout (container)
2. **print() for logging** - Use structured logger
3. **Bare except** - Catch specific exceptions, log them
4. **Silent failures** - Log errors before suppressing
5. **Logging secrets** - Use redaction filters, never log PII/tokens/keys
6. **`enqueue=True` without `logger.complete()`** - Causes silent log loss on shutdown
7. **`enqueue=True` with slow sinks** - Unbounded memory growth ([loguru#1419](https://github.com/Delgan/loguru/issues/1419)). Monitor RSS or use structlog for high-throughput
8. **`json.dumps()` at high volume** - Use orjson for 2-10x speedup
9. **UUID4 trace IDs in OTel services** - Use OTel-propagated trace IDs instead

---

## Troubleshooting

| Issue                    | Cause                     | Solution                                                           |
| ------------------------ | ------------------------- | ------------------------------------------------------------------ |
| loguru not found         | Not installed             | Run `uv add loguru`                                                |
| Logs not appearing       | Wrong log level           | Set level to DEBUG for troubleshooting                             |
| Log rotation not working | Missing rotation config   | Add rotation param to logger.add()                                 |
| JSONL parse errors       | Malformed log line        | Check for unescaped special characters                             |
| OOM with enqueue=True    | Unbounded internal queue  | Monitor RSS; use structlog for high-throughput or avoid slow sinks |
| Lost logs on shutdown    | Missing logger.complete() | Call `await logger.complete()` or `logger.remove()` before exit    |
| Slow JSONL serialization | Using stdlib json         | Switch to `orjson.dumps().decode()`                                |
| Secrets in logs          | No redaction filter       | Add `redact_filter` to all sinks                                   |

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If the underlying tool's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
