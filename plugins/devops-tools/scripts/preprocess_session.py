#!/usr/bin/env python3
# /// script
# requires-python = ">=3.13"
# dependencies = ["claude-code-log"]
# ///
"""Preprocess a Claude Code session JSONL using claude-code-log's library.

Outputs NDJSON (one JSON object per line) to stdout. Each object mirrors
the RawTurn interface in session-debrief.ts, enriched with fields that
the TypeScript JSONL parser cannot extract:

  thinkingLen      — total chars of extended thinking in this turn
  thinkingSnippet  — first 200 chars of thinking
  tokenUsage       — "In: X | Out: Y | CC: Z | CR: W" (cache-aware)
  hookErrors       — list of hook error strings from adjacent system messages
  systemWarnings   — list of system warning texts
  isSubagent       — true when this turn originates from a spawned Task agent

Usage:
  uv run --python 3.13 preprocess_session.py <session.jsonl>
"""

import json
import sys
from pathlib import Path
from typing import Optional


# Regex-free noise stripping: handled by TypeScript's stripNoise().
# Python only strips the raw metadata injected by claude-code-log load itself.

META_TOOL_NAMES = {
    "AskUserQuestion", "Skill", "ExitPlanMode", "EnterPlanMode",
    "EnterWorktree", "ExitWorktree", "TaskCreate", "TaskUpdate",
    "TaskGet", "TaskList", "TaskOutput", "TaskStop",
}


def extract_text_from_content(items) -> tuple[str, list[str], list[str], list[str], list[str]]:
    """Extract (text, tool_calls, tool_results, files, errors) from a content list."""
    text_parts: list[str] = []
    tool_calls: list[str] = []
    tool_results: list[str] = []
    files: list[str] = []
    errors: list[str] = []

    from claude_code_log.models import (
        TextContent, ToolUseContent, ToolResultContent, ImageContent,
        ThinkingContent, BashInput, ReadInput, WriteInput, EditInput,
        MultiEditInput, TaskInput,
    )

    # Track meta-tool IDs to skip their results
    meta_ids: set[str] = set()

    for item in items:
        if isinstance(item, ThinkingContent):
            # Handled separately in caller — skip here
            continue
        elif isinstance(item, TextContent):
            if item.text:
                text_parts.append(item.text)
        elif isinstance(item, ToolUseContent):
            if item.name in META_TOOL_NAMES:
                meta_ids.add(item.id)
                continue
            input_str = json.dumps(item.input) if item.input else "{}"
            tool_calls.append(f"{item.name}({input_str})")
            # Extract file paths
            inp = item.input
            if isinstance(inp, dict):
                fp = inp.get("file_path") or inp.get("path")
                if fp and isinstance(fp, str) and (fp.startswith("/") or fp.startswith("~/")):
                    files.append(fp)
        elif isinstance(item, ToolResultContent):
            if item.tool_use_id in meta_ids:
                continue
            result_text = ""
            if isinstance(item.content, str):
                result_text = item.content
            elif isinstance(item.content, list):
                result_text = " ".join(
                    b.get("text", "") if isinstance(b, dict) else str(b)
                    for b in item.content
                )
            tool_results.append(result_text)
            if item.is_error or (result_text and "error" in result_text.lower()[:500]):
                errors.append(f"{item.tool_use_id}: {result_text[:300]}")
        elif isinstance(item, ImageContent):
            data_len = len(item.source.data) if item.source and item.source.data else 0
            text_parts.append(f"[image: {getattr(item.source, 'media_type', 'unknown')}, {data_len // 1024}KB]")

    return "\n".join(text_parts), tool_calls, tool_results, list(dict.fromkeys(files)), errors


def format_token_usage(usage) -> str:
    if not usage:
        return ""
    parts: list[str] = []
    if usage.input_tokens:
        parts.append(f"In: {usage.input_tokens}")
    if usage.output_tokens:
        parts.append(f"Out: {usage.output_tokens}")
    if usage.cache_creation_input_tokens:
        parts.append(f"CC: {usage.cache_creation_input_tokens}")
    if usage.cache_read_input_tokens:
        parts.append(f"CR: {usage.cache_read_input_tokens}")
    return " | ".join(parts)


def extract_thinking(content_items) -> tuple[int, str]:
    """Return (total_thinking_len, first_200_char_snippet)."""
    from claude_code_log.models import ThinkingContent
    total = 0
    snippet = ""
    for item in content_items:
        if isinstance(item, ThinkingContent) and item.thinking:
            total += len(item.thinking)
            if not snippet:
                snippet = item.thinking[:200]
    return total, snippet


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: preprocess_session.py <session.jsonl>", file=sys.stderr)
        sys.exit(1)

    jsonl_path = Path(sys.argv[1])
    if not jsonl_path.exists():
        print(f"Error: File not found: {jsonl_path}", file=sys.stderr)
        sys.exit(1)

    from claude_code_log.converter import load_transcript
    from claude_code_log.models import (
        AssistantTranscriptEntry, UserTranscriptEntry,
        SystemTranscriptEntry, QueueOperationTranscriptEntry,
        SummaryTranscriptEntry,
        ThinkingContent,
    )

    entries = load_transcript(jsonl_path, silent=True)

    session_label = jsonl_path.stem[:8]
    turn_n = 0

    # Pending system messages to attach to the next real turn
    pending_hook_errors: list[str] = []
    pending_warnings: list[str] = []

    for entry in entries:
        # Accumulate system messages — attach to next real turn
        if isinstance(entry, SystemTranscriptEntry):
            level = getattr(entry, "level", None) or "info"
            content = getattr(entry, "content", None) or ""
            hook_errors = getattr(entry, "hookErrors", None) or []
            subtype = getattr(entry, "subtype", None) or ""

            if hook_errors:
                pending_hook_errors.extend(hook_errors)
            elif level in ("error", "warning"):
                if content:
                    pending_warnings.append(f"[{level.upper()}] {content[:300]}")
            continue

        # Queue-operation "remove": steering inputs shown to agent while working
        if isinstance(entry, QueueOperationTranscriptEntry):
            if entry.operation == "remove" and entry.content:
                content_text = entry.content if isinstance(entry.content, str) else ""
                if content_text and len(content_text) > 10:
                    turn_n += 1
                    _emit(turn_n, session_label, "user",
                          f"[steering] {content_text}",
                          [], [], [], [],
                          entry.timestamp,
                          0, "", "", pending_hook_errors, pending_warnings,
                          is_subagent=entry.isSidechain)
                    pending_hook_errors = []
                    pending_warnings = []
            continue

        # Summary entries — skip (already included as compaction context in user turns)
        if isinstance(entry, SummaryTranscriptEntry):
            continue

        if not isinstance(entry, (AssistantTranscriptEntry, UserTranscriptEntry)):
            continue

        msg = entry.message
        if not msg:
            continue

        role = msg.role  # "user" or "assistant"

        # Extract thinking blocks (assistant only)
        thinking_len = 0
        thinking_snippet = ""
        token_usage = ""

        if isinstance(entry, AssistantTranscriptEntry):
            thinking_len, thinking_snippet = extract_thinking(msg.content)
            token_usage = format_token_usage(msg.usage)

        # Extract main content
        text, tool_calls, tool_results, files, errors = extract_text_from_content(msg.content)

        # Skip empty turns
        if not text and not tool_calls:
            continue

        turn_n += 1
        _emit(
            turn_n, session_label, role, text,
            tool_calls, tool_results, files, errors,
            entry.timestamp,
            thinking_len, thinking_snippet, token_usage,
            pending_hook_errors, pending_warnings,
            is_subagent=entry.isSidechain,
        )

        # Reset pending after attachment
        pending_hook_errors = []
        pending_warnings = []


def _emit(
    n: int,
    session: str,
    role: str,
    text: str,
    tool_calls: list[str],
    tool_results: list[str],
    files: list[str],
    errors: list[str],
    timestamp: Optional[str],
    thinking_len: int,
    thinking_snippet: str,
    token_usage: str,
    hook_errors: list[str],
    system_warnings: list[str],
    is_subagent: bool = False,
) -> None:
    obj = {
        "n": n,
        "session": session,
        "role": role,
        "userText": text,
        "toolCalls": tool_calls,
        "toolResults": tool_results,
        "files": files,
        "errors": errors,
        "timestamp": timestamp,
        "thinkingLen": thinking_len,
        "thinkingSnippet": thinking_snippet,
        "tokenUsage": token_usage,
        "hookErrors": hook_errors,
        "systemWarnings": system_warnings,
        "isSubagent": is_subagent,
    }
    print(json.dumps(obj, ensure_ascii=False))


if __name__ == "__main__":
    main()
