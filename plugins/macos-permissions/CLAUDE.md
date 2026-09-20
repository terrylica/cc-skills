# macos-permissions — privacy grants and persistence on macOS

Two skills for the same underlying job: knowing, and controlling, what software on a Mac can **see**, **drive** and **outlive a reboot**.

| Skill                                                    | Use it for                                                                                                                                         |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`tcc-grant-audit`](skills/tcc-grant-audit/SKILL.md)     | TCC privacy grants across all ~40 services and all three stores; clearing grants stranded by uninstalled apps                                      |
| [`persistence-audit`](skills/persistence-audit/SKILL.md) | everything that auto-starts: launchd, BTM, system extensions, audio HAL plug-ins, login-chain plugins, helpers, kexts, profiles, sockets, firewall |

## Why this plugin exists

It was written after a cleanup that went well and still missed most of the problem. The failures were not exotic; they repeat:

- **The UI framed the investigation.** Accessibility and Screen Recording got all the attention because they have System Settings panes. Camera, Microphone and Full Disk Access grants to uninstalled software sat untouched — the large majority of the orphaned grants were in the services nobody looked at.
- **Tools reported success while doing nothing.** Apple's `tccutil` prints `Successfully reset` and exits `0` on a no-op. So does a third-party `TCC.db` writer when SIP refuses the write. So does a heuristic uninstaller that "found" hundreds of orphans, dozens of which were live launchd jobs.
- **Name-based searching cannot find the unknown.** Grepping for five vendor names missed a root daemon that was running the whole time.
- **Guessed names produce confident false negatives.** Checking for `pam_tid.so` when the file is `pam_tid.so.2`, `Foo.app` when the bundle is `Foo Helper.app`, a space-delimited list that is newline-delimited, a plist keyed by identifier when you grepped for paths. Five separate times in one session.

Every rule in these skills is something that was measured, usually after being wrong first.

## The three principles

1. **Enumerate, never grep.** Listing what exists answers a question searching cannot.
2. **Verify against the data store, never a tool's exit code.** `SELECT COUNT(*)` after the write.
3. **Privilege is per-store, and both directions of the mistake are silent.** A user-store operation under `sudo` edits root's copy and reports success; a system-store operation without it edits nothing and reports success.

## Honesty about value

Clearing orphaned TCC rows is mostly **housekeeping**. Each row's `csreq` pins the original developer's signing identity, so a renamed binary inherits nothing; the genuine exposure is narrow (reinstalling the same-signed app skips the consent prompt). Say that plainly rather than reporting a row count as a security win — and point instead at what is live: current grants, services bound to `*:`, and whether the application firewall is on.

## Related

- Apple-native tooling worth knowing: `eslogger` (104 Endpoint Security event types incl. `tcc_modify`, `btm_launch_item_add`, `screensharing_attach`), `/usr/bin/csreq`, `sfltool dumpbtm`, `log show --predicate 'subsystem == "com.apple.TCC"'`, `launchctl print-disabled`, `NSWorkspace` via `osascript -l JavaScript`. All ship with macOS.
- `lsappinfo` is **not** a bundle-id resolver — it only knows about running applications.
