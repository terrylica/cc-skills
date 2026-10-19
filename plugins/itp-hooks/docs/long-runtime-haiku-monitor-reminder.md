# long-runtime-haiku-monitor-reminder

**Hook:** `hooks/pretooluse-long-runtime-haiku-monitor-reminder.ts` · **Event:** PreToolUse (Bash orchestrator) · **Kind:** soft reminder, never denies · **Escape:** `HAIKU-MONITOR-SKIP`

When a Bash call looks likely to run past 5 minutes, this hook adds a reminder to the model's context: do not wait blind. Start a background monitor with the Agent tool and `model: "haiku"`, and let it check on the run every few minutes.

## Why

On 2026-10-18 a gate that normally takes 7 to 9 minutes had been running for 77 minutes, hung, before anyone looked. The operator then had to ask by hand for "intermittent monitoring with haiku 5.5 agent for healthy progress". This hook makes that the default for every long run, without anyone having to ask.

## Always the newest Haiku

The reminder tells the model to write the bare alias `haiku`, never a dated or numbered id such as `claude-haiku-4-5-…` or "haiku 5.5". Claude Code resolves the Agent tool's `haiku` alias to the newest Haiku release when the agent starts. So the monitor follows each new Haiku release without anyone editing this hook, and nothing in the hook pins a version. A pinned id is right on the day it is written and stale from the next release on.

## When it fires

| Bash call                                                                        | Fires                   |
| -------------------------------------------------------------------------------- | ----------------------- |
| `run_in_background: true`                                                        | yes                     |
| `timeout` above 300000 ms                                                        | yes                     |
| `timeout` of 300000 ms or less, no other signal                                  | no                      |
| `pueue add …` at a command position (after `;`, `&&`, `\|`, `(`, or a full path) | yes                     |
| `pueue status`, `echo 'pueue add'`, `grep 'pueue add' notes.md`                  | no                      |
| any command containing `HAIKU-MONITOR-SKIP`                                      | no                      |
| any tool other than Bash                                                         | no                      |
| a second long call in the same session within 20 minutes                         | no (cooldown)           |
| no session id, or a session id containing a path separator                       | yes (no cooldown kept)  |
| malformed hook input                                                             | no; allows (fails open) |

## What the reminder asks for

- A monitor started with the Agent tool, `model: "haiku"`, `run_in_background: true`.
- Inputs for the monitor: the PID or pueue task id, the log path, the expected duration, and what healthy and stalled look like.
- A check about every 4 minutes (`sleep 240`), which keeps the parent's prompt cache within its 5-minute window.
- The monitor ends, with its report as its final answer, only on a stall, a failure, an overrun of about twice the expected duration, or completion. The final answer reaches the main session as a completion notification. SendMessage to `main` is not used: measured 2026-10-19, a monitor started from the main session reported "this session is not a background subagent" and returned its report as its result instead.
- The monitor observes and reports only. It never kills or restarts anything; the main session decides.

## Cooldown and portability

The cooldown stamp is `<os.tmpdir()>/.claude-haiku-monitor-reminder-<uid>/<session>.last`. `os.tmpdir()` honours `TMPDIR`, which is the per-user `/var/folders/…/T/` on macOS and usually `/tmp` on Linux. The `<uid>` suffix keeps accounts apart on shared hosts such as el02. The hook uses only `node:fs`, `node:os` and `node:path` under bun, with no shell-outs and no network calls, so it behaves the same on macOS and Linux. An unreadable or corrupt stamp, or an unwritable temp directory, still lets the reminder through: a repeated reminder costs less than a missed one.

## Validation

- `pretooluse-long-runtime-haiku-monitor-reminder.test.ts` is the **hermetic** suite. Each test runs in a fresh temp directory, and each subprocess run gets an environment of only `PATH`, `HOME` and `TMPDIR`, with both directories inside that temp directory. It covers detection boundaries, cooldown timing, the reminder text, end-to-end subprocess runs (including a macOS-style `TMPDIR` with a space and a trailing slash), and a run through the real orchestrator.
- `pretooluse-long-runtime-haiku-monitor-reminder.mutation.test.ts` is the **mutation** suite. It applies 32 single-site defects to the hook: boundary shifts, dropped checks, a pinned model id, a deny, a monitor allowed to kill, and others. It runs the hermetic suite against each mutant in its own temp directory, at most 4 at a time, and fails if any mutant survives. A control run on the unmutated hook must pass first. Each mutant's search string must match exactly once, so editing the hook without updating its mutants fails loudly.
- Measured 2026-10-19: all 32 mutants killed on el02 (Linux, bun 1.3.14) and on the MacBook Pro (macOS 15.8.1 arm64, bun 1.4.3). The first run had one survivor, `minutes-floor`, because the only minutes case was exactly 10 minutes. A 5.5-minute case was added to kill it.

## Escape

Put `HAIKU-MONITOR-SKIP` anywhere in the command when the run is known to be short or something else already watches it.
