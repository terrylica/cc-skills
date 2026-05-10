# Evolution Log

Reverse chronological - newest on top.

## 2026-05-09 — pueue hook conflict with heredocs containing spaced paths

**Trigger**: Drilldown bash blocks for `~/Library/Application Support/...` failed with `parse error near TASK_ID=$(pueue add ...` and `(eval):X: unmatched '` after the pueue interception hook tried to wrap them.

**Root cause**: When a `Bash` tool call is intercepted by a pueue submission hook, the hook re-parses the command string. Heredocs that contain `${var}/Path With Spaces/*` or backslash-escaped spaces inside variable expansions break the hook's quoting layer, even though the bash itself is well-formed.

**Fix**: For multi-line drilldowns, write the script to `/tmp/<name>.sh` with the `Write` tool, then invoke as `bash /tmp/<name>.sh`. This bypasses the inline heredoc → hook re-quote path entirely. Single-line `du -sh "$VAR"/path/*` style commands still work fine.

**Evidence**: 2026-05-09 disk audit on terryli's MBP — Chrome / Claude / MacWhisper drilldowns failed twice via heredoc, succeeded immediately when scripted via `/tmp/disk-hygiene-scan.sh`. Reclaim totals were unaffected; 40GB freed across both passes (caches 19GB + selected items 20GB physical).

**Action taken**: Added "pueue hook + heredoc with spaced paths" row to Troubleshooting table in SKILL.md, plus a "Hook-safe multi-line scripts" note in Phase 2.

## 2026-02-08 - Initial creation

- Created skill from real disk audit session
- Benchmarked dust (20.4s), gdu (28.8s), dua-cli (37.1s), ncdu (96.6s) on ~632GB home dir
- Documented cache cleanup workflow: uv (10.8GB), brew (9.4GB), pip (837MB), npm (1.1GB) = ~22GB reclaimed
- Added forgotten file detection patterns (ISOs, video exports, old recordings)
- Added Downloads triage workflow with AskUserQuestion multi-select pattern
- Covers 10 cache types: uv, brew, pip, npm, cargo, rustup, Docker, Playwright, sccache, huggingface
