---
name: link-validation
description: Offline markdown link validation with lychee (tasks/link-check.sh, moon run repo:link-check). Detect broken internal links and anchors on demand.
allowed-tools: Bash, Read, Glob
triggers:
  - link validation
  - broken links
  - lychee
  - check links
  - markdown links
---

# Link Validation Skill

Validates markdown links in your workspace using [lychee](https://github.com/lycheeverse/lychee).

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## When to Use This Skill

Use this skill when:

- Checking for broken links in markdown files
- Validating link paths before committing documentation
- Proving a doc change left no dangling internal link

## How to Run It

The working path is the offline lychee check in `tasks/link-check.sh`. Inside the cc-skills repository it is part of the quality gate:

```bash
moon run repo:link-check     # this check alone
moon run repo:check          # the whole gate, link-check included
bash tasks/link-check.sh     # the same script without moon
```

In any other workspace, run the same lychee command from the repository root:

```bash
lychee --offline --no-progress --root-dir "$(git rev-parse --show-toplevel)" './**/*.md'
```

Add `--config lychee.toml` when the repository has one; lychee also loads `./lychee.toml` by itself.

## What the Check Does

`tasks/link-check.sh`:

1. `cd`s to the working-tree root (`git rev-parse --show-toplevel`, so it is correct inside a worktree too)
2. Runs `bunx lychee --config lychee.toml --offline --no-progress --root-dir <repo root> './**/*.md'`
3. Excludes `plugins/statusline-tools/tests/fixtures`, whose links are broken on purpose
4. Prints lychee's summary line, then `✓ every internal link resolves` or `✗ broken internal links found (lychee exit N)`, and exits with lychee's exit code

It checks relative links, root-relative links (`/docs/adr/x.md`, resolved through `--root-dir`) and `#anchor` fragments. It is offline by design: external URL liveness depends on the network and on other sites' uptime, so it is not checked. Nothing is written to disk except lychee's own `.lycheecache`; the result is the terminal output and the exit code.

A path that exists on one machine only (`~/...`, another repository) cannot pass. Write it as inline code instead of a link.

## Requirements

- [lychee](https://github.com/lycheeverse/lychee): `tasks/link-check.sh` runs it through `bunx`, so Bun is enough there; elsewhere install it (`brew install lychee`)

## Configuration

cc-skills keeps one lychee config, `lychee.toml` at the repository root. It holds the path and URL exclusions and `include_fragments = "anchor-only"` (lychee 0.24 rejects the old boolean `true`). The statusline-tools Stop hook reads the same file when it exists.

## Related Checks

- Link portability in skills (absolute repo paths that break once installed): the [link-validator](../link-validator/SKILL.md) skill
- Path policy at session end: the statusline-tools Stop hook runs `lint-relative-paths` and lychee, and writes `.lychee-results.json` for the status line

## History

This skill used to describe a Stop hook, `hooks/stop-link-check.py`, that wrote `.link-check-results.md`. link-tools never had a `hooks.json`, so the hook never ran; it was deleted in issue #33.

## References

- [ADR: Link Checker Plugin Extraction](../../../../docs/adr/2025-12-11-link-checker-plugin-extraction.md)
- [lychee Documentation](https://github.com/lycheeverse/lychee)

---

## Troubleshooting

| Issue                         | Cause                           | Solution                                                        |
| ----------------------------- | ------------------------------- | --------------------------------------------------------------- |
| lychee not found              | Not installed                   | `brew install lychee`, or run through `bunx lychee`             |
| Config fails to load          | `include_fragments = true`      | Use `include_fragments = "anchor-only"` (lychee 0.24 and later) |
| Every `/docs/...` link fails  | No `--root-dir`                 | Pass `--root-dir` with the absolute repository root             |
| A link to `~/...` fails       | Path exists on one machine only | Write it as inline code, not a link                             |
| A fixture's broken link fails | Fixture not excluded            | Add it to `--exclude-path` or the config's `exclude_path`       |

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If the underlying tool's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
