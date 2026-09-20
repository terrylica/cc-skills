# Display blackout, 2026-09-19 — forensic finding

**Verdict: caused by agent-orchestration load, not by the brightness code.** The XDR/gamma work is exonerated by evidence, not by assertion. What actually happened is a sustained trust/policy daemon storm that starved WindowServer until the panel went dark and could not be revived.

Recorded because the conclusion changes how this repo's display work should be developed, and because the failure class is already documented in the operator's `CLAUDE.md` and was walked into anyway.

## What the operator observed

Screen went totally black, nothing could resume it, no recourse but a forced reboot. Two reboots are recorded, at 22:16 and 22:20 (`last reboot`).

## Timeline

| Time               | Event                                                                                                                                                                                                                                                                                        |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 20:30, 21:00       | Unified-log rate: **1 line/minute**. Machine essentially silent.                                                                                                                                                                                                                             |
| 21:15:49           | An 11-agent research workflow is launched (`wf_6c8ae578-456`; dir ctime and first agent meta both 21:15:49).                                                                                                                                                                                 |
| 21:15              | Log rate: **191,431 lines/minute** — a ~191,000× step change in the same minute.                                                                                                                                                                                                             |
| 21:18–21:24        | Six subagent probe binaries crash in `/private/tmp/*/`: `cdprobe`, `cd1` (SIGSEGV in `CoreDisplay::Display::IsHDR10()` via `CoreDisplay_Display_GetDisplayBrightnessInNits`), `final` ×2, `one` (SIGBUS in `DisplayServicesAmbientLightCompensationEnabled`), `raw` (SIGSEGV in `mach_msg`). |
| ~21:18–21:30       | The four operator-facing display programs (`edrtest`, `calibrate`, `calibrate2`, `abdemo`) run and **exit cleanly**, restoring gamma.                                                                                                                                                        |
| 21:54:00           | Last workflow agent finishes. Log rate still 126,937/min.                                                                                                                                                                                                                                    |
| 22:00–22:10        | Storm decays slowly: 106,048 → 83,580 → 53,513 lines/min. Daemon backlog, not new work.                                                                                                                                                                                                      |
| 22:06:32           | `powerd`: `caffeinate.26216 ClientDied PreventUserIdleSystemSleep` — sleep-prevention assertion released.                                                                                                                                                                                    |
| 22:08:49           | `corebrightnessd`: `keyboard backlight dimmed 1`, then a 34% → 15% PWM ramp. Standard macOS idle sequence.                                                                                                                                                                                   |
| 22:11:57, 22:12:41 | `bluetoothd`: `io_pm_assertion_create failed with error 0xe00002c1` (twice). Power assertions beginning to fail.                                                                                                                                                                             |
| 22:13:05.252       | **Last WindowServer[176] log line.**                                                                                                                                                                                                                                                         |
| 22:15              | Log rate: 1 line/minute. Machine unusable.                                                                                                                                                                                                                                                   |
| 22:16              | Forced reboot (WindowServer returns as PID 175 at 22:16:38).                                                                                                                                                                                                                                 |

## Evidence that it was starvation, not a crash

- **No kernel panic.** No `*.panic` reports exist at all.
- **No WindowServer crash report.** WindowServer did not die — it stopped being scheduled.
- **No jetsam kill and no memory-pressure events** in 21:00–22:17. This was not OOM.
- **No display sleep or wake transition was ever logged.** The panel did not fail to wake from a sleep it entered; it went dark while nominally awake.
- **35,717 error/fault messages in the 7.5 minutes 22:09–22:16:30** (~80/second).
- Top log producers in the final 3.5 minutes: `trustd` 81,060 · `runningboardd` 47,672 · `tccd` 43,509 · `locationd` 38,809 · `accessoryupdaterd` 32,319. Roughly 2,400 lines/second.
- `syspolicyd` looping on `Unable to initialize qtn_proc: 3` and `dispatch_mig_server returned 268435459` — the quarantine/Gatekeeper subsystem exhausted.
- Kernel sandbox violations dominated by `syscall-mach-denied` (388) and cascading `mach-lookup com.apple.contactsd.persistence` denials as `contactsd` fell over, which then fail-looped `imagent`, `searchpartyuseragent` and `fontd`.

## Mechanism

Every `exec` of an unsigned binary drives Gatekeeper assessment and certificate-trust evaluation through `syspolicyd` and `trustd`. Those are serialised, IPC-heavy, single-instance daemons. Eleven concurrent agents, each compiling and running probe binaries against live system frameworks and making network calls, drove them into sustained saturation.

WindowServer is an ordinary client of those same daemons — the log shows it making a `TCCAccessRequest()` IPC round trip several times per second in normal operation. When they saturate, WindowServer blocks in IPC. The kernel stays healthy, nothing crashes, and the display simply stops being composited. No input can revive it because the process that would handle the input is the one that is blocked.

## Why the brightness code is ruled out

1. All four display programs exited ~40 minutes before the failure.
2. A `CGSetDisplayTransferByTable` override is owned per-process and reverts automatically on process death — verified in this session under both `exit()` and `SIGKILL`.
3. The EDR trigger window was torn down with its owning process; headroom decays to 1.0 on its own within ~16 s.
4. The display never logged a sleep/wake transition, which is the failure mode a stuck gamma or EDR state would produce.
5. The storm began at 21:15:49 — **before** the first display program was written, let alone run.

The six subagent probe crashes are a separate, real hazard worth naming: they called `CoreDisplay_*` and `DisplayServicesAmbientLightCompensationEnabled` with guessed signatures and died inside Apple's frameworks. They did not cause this outage, but probing undocumented private APIs with unverified ABIs on a live machine is not something to repeat casually.

## Consequences for this repo

- **Do not develop display features under multi-agent fan-out on this machine.** The bound that matters is concurrency, not wall-clock duration — this is exactly what `CLAUDE.md` § "Process Storm Prevention" already says, and it was not followed.
- Compile-and-execute steps belong in the main session, serially, where their rate is naturally bounded.
- If a workflow is genuinely warranted, agents must not compile and execute binaries. Reading and reasoning are cheap; `exec` of unsigned code is not.

## Prior art in this operator's own notes

`reference_shutdown_stall_forensic_2026_07_29.md` records the same shape from a different resource: WindowServer blocked in `mach_msg_trap` waiting on page-faulted clients, 27 Claude sessions + 43 iTerm panes consuming 27 of 36 GB, resolved only by forced reboot. Different exhausted resource, identical symptom and identical remedy.

## Method notes for whoever re-runs this

- `log` is shadowed by a shell function in this environment; the first three query attempts returned zero rows and looked like log rotation had eaten the window. Use `/usr/bin/log` explicitly.
- The shell is zsh, so `set -- $var` does not word-split. Bash-style split loops fail with `parameter not set` under `set -u`.
- `.ips` crash reports are a JSON header line followed by a JSON body; parse with `head -1 | jq` and `tail -n +2 | jq`.
