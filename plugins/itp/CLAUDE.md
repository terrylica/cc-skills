# itp Plugin

> Implement-The-Plan workflow: ADR-driven 4-phase development with preflight, implementation, formatting, and release automation.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md)

**Keep the acronym neutral**: "ITP" avoids the action inference that caused Claude to skip preflight. Do not rename it to a verb.

## 4-Phase Workflow

```
Preflight (ADR + Spec) → Phase 1 (Implement) → Phase 2 (Format) → Phase 3 (Release)
```

1. **Preflight**: Creates ADR (MADR 4.0) and design spec
2. **Phase 1**: Implement from design spec with TodoWrite tracking
3. **Phase 2**: Format with Prettier, push to GitHub
4. **Phase 3**: Release via the repo's mise release pipeline (main/master only)

## Plan Mode Bridge

Two paths from Plan Mode to `/itp:go`:

| Path                              | Steps          | Interface                               |
| --------------------------------- | -------------- | --------------------------------------- |
| **A**: Type in rejection feedback | Fewer (direct) | Plain text field                        |
| **B**: Defer to command prompt    | Extra step     | Native slash commands with autocomplete |

## Skills

- [adr-code-traceability](./skills/adr-code-traceability/SKILL.md)
- [bootstrap-monorepo](./skills/bootstrap-monorepo/SKILL.md)
- [code-hardcode-audit](./skills/code-hardcode-audit/SKILL.md)
- [go](./skills/go/SKILL.md)
- [impl-standards](./skills/impl-standards/SKILL.md)
- [implement-plan-preflight](./skills/implement-plan-preflight/SKILL.md)
- [mise-configuration](./skills/mise-configuration/SKILL.md)
- [mise-tasks](./skills/mise-tasks/SKILL.md)
- [pypi-doppler](./skills/pypi-doppler/SKILL.md)
- [setup](./skills/setup/SKILL.md)

## Commands

| Command      | Purpose                                        |
| ------------ | ---------------------------------------------- |
| `/itp:go`    | Execute 4-phase workflow                       |
| `/itp:setup` | Install dependencies and configure environment |

For release, use the repo's mise pipeline directly: `/mise:run-full-release`.

**`/itp:tether` was retired (issue #127)**: it drove `scripts/manage-hooks.sh`, which injected itp-hooks entries into `~/.claude/settings.json` back when Claude Code did not load a plugin's own `hooks/hooks.json`. It does now — `plugins/itp-hooks/hooks/hooks.json` registers `posttooluse-reminder.ts` itself, so the injection would have fired the hook twice per matching event. The installer had also been inert since `posttooluse-reminder.sh` was renamed to `.ts`, and its second entry (`pretooluse-fake-data-guard.mjs`) was deliberately unregistered in `e6c665a9` for blocking legitimate writes; re-enabling that guard is a `hooks.json` edit, never a settings.json injection.

## Dependencies

| Tool     | Install               | Notes                              |
| -------- | --------------------- | ---------------------------------- |
| uv       | `mise install uv`     | Or `brew install uv`               |
| gh       | `brew install gh`     | **NEVER use mise** (iTerm2 issues) |
| prettier | `bun add -g prettier` | Bun-first policy                   |
