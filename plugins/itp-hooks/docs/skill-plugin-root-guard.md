# skill-plugin-root guard

> Blocks skill markdown from referencing `CLAUDE_PLUGIN_ROOT` in a shape the runtime cannot honor. Subhook of the PreToolUse Write|Edit orchestrator. Escape hatch: `SKILL-PLUGIN-ROOT-OK`.

**Hub**: [itp-hooks CLAUDE.md](../CLAUDE.md) | **Sibling**: [pretooluse-write-edit-orchestrator.md](./pretooluse-write-edit-orchestrator.md)

## The incident that produced it (2026-08-05)

`/notes-commander:draft-hold`, invoked from an unrelated repo, died with:

```
Error: Exit code 127
(eval):1: no such file or directory: /skills/draft-hold/draft-hold.sh
```

Its SKILL.md said `DH="$CLAUDE_PLUGIN_ROOT/skills/draft-hold/draft-hold.sh"`. The variable was unset, zsh expanded it to the empty string, and the result was an absolute-looking `/skills/…` path — which reads like a missing **file** rather than a missing **variable**. The recovery was also wrong: globbing the version cache and taking the highest semver picked `23.4.1`, a directory marked `.orphaned_at`, while the live version was `23.5.0`.

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

The `:-` idiom deserves emphasis: it _looks_ defensive, and 51 call sites in this marketplace used it. Because it never substitutes, every one of them silently ran the **Layer-2 marketplace clone** rather than the installed version. It worked, but not for the reason its authors believed.

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

`FILE_WIDE` semantics: one marker anywhere in the file exempts the whole file, because the files that legitimately contain these patterns are documentation _about_ the variable. On Edit/MultiEdit the marker is honored from the on-disk copy too (the iter-15 pattern), so an edit to an unrelated region of a marked file is not blocked.

Currently marked: `plugin-dev`'s `path-patterns.md` / `advanced-topics.md` / `evolution-log.md`, `itp-hooks`'s `lifecycle-reference.md` / `hook-templates.md`, the `gh-tools` and `productivity-tools` `tether` skills, and the two SKILL.mds whose prose explains the rule.

## Implementation

- Classifier: `classifySkillPluginRootGuardForOrchestrator` in [`../hooks/pretooluse-skill-plugin-root-guard.ts`](../hooks/pretooluse-skill-plugin-root-guard.ts)
- Registered as a subhook in the PreToolUse Write|Edit orchestrator, positioned early: an O(1) path filter (`/skills/` substring + `.md` suffix) then an O(1) content sentinel; the single disk read is deferred until a real candidate violation exists.
- Tests: 18 in [`../hooks/pretooluse-skill-plugin-root-guard.test.ts`](../hooks/pretooluse-skill-plugin-root-guard.test.ts).
- Marker registered in the iter-111 canonical registry.

## Relationship to the retired iter-78 guard

This guard **replaces** `pretooluse-iter78-layer3-stripped-path-edit-time-guard.ts`, which was unregistered the same day. Iter-78 policed the _opposite_ concern — which subtrees survive the Layer-2 to Layer-3 cache promotion — on a premise that no longer holds: a `diff -rq` of the L2 mirror against the live L3 cache for four plugins returns exactly one difference each (the `.in_use` marker Claude Code adds), and `scripts/` is present in the latest cached version of all 27 cc-skills plugins that ship one. With a false premise it produced only false positives; it fired three times in one session on documentation and test fixtures that merely mentioned a path. See that file's retirement header for the full evidence.
