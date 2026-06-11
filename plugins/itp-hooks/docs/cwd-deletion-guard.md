# CWD Deletion Guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — moved verbatim from the hub 2026-06-11 (CLAUDE.md size-guard refactor: hub was 112k chars, limit 40k).

## CWD Deletion Guard

The `pretooluse-cwd-deletion-guard.ts` hook prevents commands that would delete the current working directory. When CWD is deleted, the shell becomes permanently broken — every subsequent command (including `cd`) fails with exit code 1.

### Two Lessons Encoded

| Lesson              | Problem                                   | Solution                                                |
| ------------------- | ----------------------------------------- | ------------------------------------------------------- |
| Never delete CWD    | Shell unrecoverable after `rm -rf $(pwd)` | `cd /tmp && rm -rf <target>`                            |
| Don't rm + re-clone | Wasteful and breaks CWD                   | `git remote set-url` + `git fetch` + `git reset --hard` |

### Detection Patterns

| Pattern          | Example                                               |
| ---------------- | ----------------------------------------------------- |
| Exact path match | `rm -rf /path/to/cwd` where path = CWD                |
| Parent deletion  | `rm -rf ~/fork-tools` when CWD is `~/fork-tools/repo` |
| Relative CWD     | `rm -rf .` or `rm -rf ./`                             |
| Shell expansion  | `rm -rf $(pwd)` or `rm -rf $PWD`                      |
| Tilde expansion  | `rm -rf ~/project` matching CWD                       |

### Git-Aware Guidance

When the command includes `git clone` or `gh repo clone` (rm-before-reclone pattern), the denial message suggests `git remote set-url` instead:

```bash
# Instead of: rm -rf ~/fork-tools/repo && git clone <new-url> ~/fork-tools/repo
# Do:
git remote set-url origin <new-url>
git fetch origin
git reset --hard origin/main
```

### Escape Hatch

Add `# CWD-DELETE-OK` comment to bypass:

```bash
rm -rf ~/fork-tools/repo  # CWD-DELETE-OK
```

