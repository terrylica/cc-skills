# Provenance — `<CAMPAIGN_SLUG>`

> **Purpose**: this file is the human-and-AI-readable index of who-what-when-why for this loop. Append-mostly; one line per ownership transition. The contract frontmatter mirrors registry state for offline lookup; this file records the *narrative* of who has held the loop over time.

## Identity

- **Loop ID**: `<LOOP_ID>` (sha256(realpath(CONTRACT.md))[:12])
- **Campaign slug**: `<CAMPAIGN_SLUG>`
- **Short hash**: `<SHORT_HASH>` (6 hex; differentiates concurrent campaigns with the same slug)
- **Created**: `<CREATED_AT_UTC>` in session `<CREATED_IN_SESSION>`
- **Project cwd**: `<PROJECT_CWD>`
- **Originating branch / commit**: `<GIT_BRANCH>` @ `<GIT_COMMIT>`

## Layout

```
<PROJECT_CWD>/.autoloop/<CAMPAIGN_SLUG>--<SHORT_HASH>/
├── CONTRACT.md              ← live contract (the /loop prompt)
├── PROVENANCE.md            ← this file
└── state/
    ├── heartbeat.json
    └── revision-log/<session_id>.jsonl
```

Registry entry: `jq '.loops[] | select(.loop_id == "<LOOP_ID>")' ~/.claude/loops/registry.json`

## Ownership history (append-only)

<!-- One line per transition. Format:
ISO_8601_UTC | event | session_id | pid | gen | reason
events: created, bound, heartbeat, reclaim, paused, resumed, completed, migrated_to:<id>, migrated_from:<id> -->

- `<CREATED_AT_UTC>` | created | `<CREATED_IN_SESSION>` | — | 0 | scaffolded by /autoloop:start
