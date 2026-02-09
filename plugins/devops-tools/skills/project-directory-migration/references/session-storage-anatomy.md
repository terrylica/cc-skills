# Claude Code Session Storage Anatomy

How Claude Code stores project data, empirically validated during the CKVD package rename.

## Path Encoding

Claude Code encodes absolute directory paths by replacing `/` with `-`:

```
/Users/alice/projects/my-app  →  -Users-alice-projects-my-app
```

This encoded string becomes the directory name under `~/.claude/projects/`.

## Storage Layout

```
~/.claude/
├── projects/
│   └── {encoded-path}/
│       ├── *.jsonl              ← Session conversation files
│       ├── sessions-index.json  ← Session registry with path references
│       ├── memory/
│       │   └── MEMORY.md        ← Auto-memory (persistent across sessions)
│       └── {session-uuid}/      ← Per-session subdirectories
│           ├── subagents/       ← Subagent transcripts
│           └── tool-results/    ← Tool output cache
└── history.jsonl                ← Global conversation history
```

## What Contains Path References

| File                   | Fields with paths                                             | Needs rewriting? |
| ---------------------- | ------------------------------------------------------------- | ---------------- |
| `sessions-index.json`  | `originalPath`, `entries[].projectPath`, `entries[].fullPath` | **Yes**          |
| `history.jsonl`        | `project` field per entry                                     | **Yes**          |
| Session `.jsonl` files | None                                                          | No               |
| `MEMORY.md`            | None (content only)                                           | No               |

## sessions-index.json Structure

```json
{
  "originalPath": "/Users/alice/projects/my-app",
  "projectPath": "/Users/alice/projects/my-app",
  "entries": [
    {
      "sessionId": "abc-123-def",
      "projectPath": "/Users/alice/projects/my-app",
      "fullPath": "/Users/alice/.claude/projects/-Users-alice-projects-my-app/abc-123-def.jsonl",
      "createdAt": "2026-01-15T10:00:00.000Z",
      "lastAccessedAt": "2026-01-15T12:00:00.000Z"
    }
  ]
}
```

**Fields requiring update on rename:**

- `originalPath` (top-level) — absolute path to project
- `projectPath` (top-level and per-entry) — absolute path to project
- `fullPath` (per-entry) — contains encoded path in the file path

## history.jsonl Structure

Each line is a JSON object with a `project` field:

```json
{
  "project": "/Users/alice/projects/my-app",
  "sessionId": "abc-123",
  "lastAccessedAt": "2026-01-15T12:00:00.000Z"
}
```

Only the `project` field needs updating — exact string match on the old path.

## Key Insight

Session `.jsonl` files (the actual conversation transcripts) do **not** contain the directory path internally. This means the migration only needs to:

1. Move the project directory (rename encoded folder)
2. Rewrite `sessions-index.json` (3 field types)
3. Rewrite `history.jsonl` (1 field per entry)

No session content is modified, preserving full conversation integrity.
