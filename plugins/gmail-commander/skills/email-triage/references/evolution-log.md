# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-09-26: Scheduled digest moved out; triage skill documents `/digest`

**Trigger**: The skill described `scripts/digest.ts` running every 6 hours via launchd with a Kokoro voice briefing. The launchd job was retired on 2026-09-24, the scheduled digest now runs in a private deployment with its own implementation, and `scripts/digest.ts` plus `scripts/lib/tts-client.ts` were removed on 2026-09-26 once nothing imported them. The References section linked two files that never existed.

**Fix**: The skill now separates the on-demand `/digest [hours]` bot command (this plugin's `lib/triage.ts` pipeline) from the scheduled digest (the deployment's own code), documents the pipeline step by step, and replaces the missing references with a source map.

**Files**: `SKILL.md`

---

## 2026-02-26: Initial Evolution Log

**Status**: Skill is in use and maintained. Track improvements here.

### Purpose

This evolution log tracks updates to the skill. Each entry should note:

- What changed (content, structure, tooling)
- Why it changed (bug fix, feature request, best practice)
- Files affected

### How to Use

1. When updating SKILL.md or references, add an entry here with the date
2. Keep entries reverse-chronological (newest first)
3. Link to ADRs or GitHub issues when relevant
4. Reference specific line changes when helpful

---
