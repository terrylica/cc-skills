# skill-plugin-root guard

> Blocks skill markdown from referencing `CLAUDE_PLUGIN_ROOT` in a shape the runtime cannot honor. Subhook of the PreToolUse Write|Edit orchestrator. Escape hatch: `SKILL-PLUGIN-ROOT-OK`.

**Hub**: [itp-hooks CLAUDE.md](../CLAUDE.md) | **Sibling**: [pretooluse-write-edit-orchestrator.md](./pretooluse-write-edit-orchestrator.md)

## The symptom it prevents

A skill whose SKILL.md runs `"$CLAUDE_PLUGIN_ROOT/skills/x/run.sh"` fails with something like:

```
(eval):1: no such file or directory: /skills/x/run.sh
```

The variable is unset in the Bash tool, zsh expands it to the empty string, and the result is an absolute-looking `/skills/…` path that reads like a missing **file** rather than a missing **variable**. Recovering by globbing the version cache for the highest semver is also wrong (see below).

## What is actually true about `CLAUDE_PLUGIN_ROOT`

Verified by disassembling the shipping Claude Code binary plus a live skill-invocation probe.

Claude Code does exactly two things with it:

1. **Text-substitutes the exact literal `${CLAUDE_PLUGIN_ROOT}`** inside plugin _manifests_ — `hooks/hooks.json`, `.mcp.json`, `.lsp.json`, monitor commands. The bundled helper is literally `e.replace(/\$\{CLAUDE_PLUGIN_ROOT\}/g, pluginPath)`.
2. **Injects `CLAUDE_PLUGIN_ROOT` into the environment** of the hook and MCP/LSP subprocesses it spawns.

It is never exported into the Bash tool's environment. And a SKILL.md body is served to the model **verbatim** on the Skill-tool path — a live probe of `doc-tools:markdown-table-validator` returned the body byte-identical to the file on disk, with no substitution and no "Base directory for this skill:" prefix.

| Context                                            | Works? | Why                                                          |
| -------------------------------------------------- | ------ | ------------------------------------------------------------ |
| A plugin's own `hooks/hooks.json`                  | YES    | Substituted at load; also injected into the hook's env       |
| `.mcp.json` / `.lsp.json` / monitor commands       | YES    | Same substitution pass; also set in the subprocess env       |
| Hook command copied into `~/.claude/settings.json` | NO     | Not plugin-associated — nothing substitutes, no env var      |
| A `SKILL.md` body (Bash the model runs)            | NO     | Served verbatim on the Skill-tool path; not in the shell env |

## The three deniable shapes

| Kind                       | Pattern                                 | Why it is broken                                                                                                                   |
| -------------------------- | --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `BARE_SPELLING`            | `$CLAUDE_PLUGIN_ROOT`                   | No braces, so the substitution regex cannot match it **anywhere** — broken in skills _and_ in manifests                            |
| `NON_SUBSTITUTING_DEFAULT` | `${CLAUDE_PLUGIN_ROOT:-fallback}`       | The regex needs the closing brace right after the name, so this is never substituted either; it silently always takes the fallback |
| `BRACED_IN_SHELL_CONTEXT`  | `${CLAUDE_PLUGIN_ROOT}` on a shell line | Correct in a manifest snippet, not in a shell command a skill tells the model to run                                               |

The `:-` idiom deserves emphasis: it _looks_ defensive, but because it never substitutes, a fallback such as the **Layer-2 marketplace clone** path is always the one used, never the installed version. It can appear to work, but not for the reason its author believed.

## Scope and exemptions

- **In scope**: any `.md` whose path contains `/skills/` — SKILL.md bodies and their on-demand `references/`.
- **Out of scope**: manifests, `.ts`/`.sh`/`.py` scripts (which may legitimately read the env var when run as a hook child), and non-skill markdown.
- **Manifest-snippet exemption**: a braced reference on a JSON-shaped line — a `"key": value` pair or a bare `"array element"` — is allowed, because pasting it into `hooks.json` is the correct thing to do. A **bare** reference is still denied there, since bare never substitutes even in a manifest.

## The remediation it steers to

```bash
SCRIPT="$(cc-plugin-root <plugin-name>)/skills/<skill>/run.sh"
```

`cc-plugin-root` ([`scripts/cc-plugin-root`](../../../scripts/cc-plugin-root), symlinked into `~/.local/bin/`) reads `~/.claude/plugins/installed_plugins.json` and prints the **live** install path, so it always matches the version Claude Code actually loaded. `<plugin-name>` is the directory under `plugins/`, not the skill name.

Do **not** glob `~/.claude/plugins/cache/<mp>/<plugin>/*` for the highest version — that directory retains every previously-installed version, and the highest is routinely orphaned.

## Escape hatch

```
SKILL-PLUGIN-ROOT-OK: <reason at least 10 characters>
```

`FILE_WIDE` semantics: one marker anywhere in the file exempts the whole file, because the files that legitimately contain these patterns are documentation _about_ the variable. On Edit the marker is honored from the on-disk copy too, so an edit to an unrelated region of a marked file is not blocked.

Currently marked: `plugin-dev`'s `path-patterns.md` / `advanced-topics.md` / `evolution-log.md`, `itp-hooks`'s `lifecycle-reference.md` / `hook-templates.md`, and the two SKILL.mds whose prose explains the rule (`notes-commander`'s `draft-park` and `macos-font-defaults`).

## Implementation

- Classifier: `classifySkillPluginRootGuardForOrchestrator` in [`../hooks/pretooluse-skill-plugin-root-guard.ts`](../hooks/pretooluse-skill-plugin-root-guard.ts)
- Registered as a subhook in the PreToolUse Write|Edit orchestrator, positioned early: an O(1) path filter (`/skills/` substring + `.md` suffix) then an O(1) content sentinel; the single disk read is deferred until a real candidate violation exists.
- Tests: [`../hooks/pretooluse-skill-plugin-root-guard.test.ts`](../hooks/pretooluse-skill-plugin-root-guard.test.ts).
- Marker registered in the canonical marker registry, [`lib/escape-hatch-marker-registry-iter111.ts`](../hooks/lib/escape-hatch-marker-registry-iter111.ts).

## What it does not police

This guard is only about how a skill resolves its own path. It does not restrict which subtrees a skill may reference: the plugin cache copies a plugin's whole tree (a `diff -rq` of the marketplace clone against the installed cache differs only by the `.in_use` marker Claude Code adds), so `scripts/` and other non-skill directories are present in an installed plugin. A guard that once assumed otherwise was removed for producing only false positives; see `docs/LESSONS.md` (2026-08-05).
