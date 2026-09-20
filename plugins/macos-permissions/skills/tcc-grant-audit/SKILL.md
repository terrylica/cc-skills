---
name: tcc-grant-audit
description: Audit and clean macOS TCC privacy grants (Accessibility, Screen Recording, Camera, Microphone, Full Disk Access, AppleEvents, folder access) across ALL ~40 services and all three permission stores — not just the two System Settings shows. Clears grants stranded by uninstalled apps, which Apple's tccutil cannot reach and macOS never garbage-collects. Use when auditing privacy permissions, removing remote-access or spyware-adjacent software, investigating what can see the screen or drive the keyboard, or when tccutil fails with -10814 kLSApplicationNotFoundErr. TRIGGERS - TCC, tccutil, privacy permissions, Accessibility permission, Screen Recording permission, Full Disk Access, orphaned permission, -10814, kLSApplicationNotFoundErr, revoke permission, TCC.db, permission audit, what can record my screen, remove remote access software.
allowed-tools: Bash, Read
---

# tcc-grant-audit — macOS privacy grants, all stores

> **Self-Evolving skill** — every rule below was MEASURED, not inferred. If a macOS release changes one, fix this file and the scripts; see Post-Execution Reflection.

Resolve the scripts against the version Claude Code actually loaded:

```bash
SKILL="$(cc-plugin-root macos-permissions)/skills/tcc-grant-audit"
```

## Start here, always

```bash
bash "$SKILL/tcc-audit.sh" all        # READ-ONLY. Changes nothing.
```

## 🔴 The seven things that will bite you

**1. `tccutil` is not the only tool, and is the wrong one for half the job.** Reach for the whole set:

| Need                                    | Tool                                                   |
| --------------------------------------- | ------------------------------------------------------ |
| Query any grant, any service, any store | `sqlite3 -readonly` on `TCC.db`                        |
| Is this bundle id still installed?      | `NSWorkspace` via `osascript -l JavaScript` (one line) |
| What does a grant actually pin?         | `/usr/bin/csreq -r- -t`                                |
| Watch grants change live                | `sudo eslogger tcc_modify`                             |
| Ground truth on whether a write landed  | `log show --predicate 'subsystem == "com.apple.TCC"'`  |
| Reset a grant for an INSTALLED app      | `/usr/bin/tccutil reset <Service> <id>`                |
| Clear a grant for an UNINSTALLED app    | `tcc-clear-orphans.sh` (stub technique)                |
| Remove a `client_type=1` path row       | a direct DB writer, user store only                    |

**2. Order is load-bearing: reset the grant BEFORE deleting the app.** `tccutil` resolves the identifier through LaunchServices first. Delete the app and every reset fails `-10814` forever.

**3. `tccutil` reports success on a no-op.** It prints `Successfully reset` and exits `0` while deleting nothing. **Verify every change with `SELECT COUNT(*)` against the database.** Third-party tools do this too — a direct DB writer exits 0 when the write was refused.

**3b. Verifying immediately is not verifying.** A daemon that owns a file holds it in memory and flushes over your edit **minutes later**. Measured: a `PlistBuddy` prune of the Sequoia store verified clean, and roughly eight minutes later `replayd` rewrote every deleted entry back from its cached dictionary. The first verification passed only because it read the file before the flush.

So, for any store owned by a live daemon:

```bash
killall replayd            # launchd restarts it on demand, re-reading from disk
sleep 2
# ...make the edit...
sleep 20                   # then RE-verify; an immediate read proves only that
                           # the write landed, not that it survived
```

Generalise the rule: **verify the authority, not the artifact, and verify after it has had a chance to disagree with you.**

**4. There are THREE stores, with decreasing visibility.**

| Store   | Path                                                                              | Privilege    | Holds                                                                      |
| ------- | --------------------------------------------------------------------------------- | ------------ | -------------------------------------------------------------------------- |
| system  | `/Library/Application Support/com.apple.TCC/TCC.db`                               | root         | Accessibility, ScreenCapture, SystemPolicyAllFiles, ListenEvent, PostEvent |
| user    | `~/Library/Application Support/com.apple.TCC/TCC.db`                              | console user | Camera, Microphone, AppleEvents, folder access, Photos                     |
| Sequoia | `~/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist` | console user | screen-capture approvals; **no CLI, no UI, `tccutil` cannot address it**   |

Running a user-store operation under `sudo` targets **root's** store and reports success. Both directions of this mistake are silent.

**5. Do not let System Settings frame the audit.** Accessibility and Screen Recording have visible panes; Camera, Microphone and Full Disk Access do not surface orphans at all. In a real cleanup only 2 of ~40 services were addressed, and **the large majority of orphaned grants remained** — including Camera and Microphone still granted to uninstalled remote-access tools, and several orphaned Full Disk Access grants. Enumerate from the database.

**6. `csreq` pins the SIGNING IDENTITY, not the bundle name.** Decode it and see:

```bash
sqlite3 -readonly "/Library/Application Support/com.apple.TCC/TCC.db" \
  "SELECT hex(csreq) FROM access WHERE client='com.example.app' LIMIT 1;" | xxd -r -p | /usr/bin/csreq -r- -t
```

So malware renaming itself to an orphaned identifier inherits **nothing**. State this accurately: orphaned rows are **inert**; the real (narrow) exposure is that reinstalling the genuine, same-signed app silently regains the grant with no prompt. Do not oversell the threat — and note that **live grants carry identical exposure and usually outnumber the dead ones**.

**7. `com.apple.*` entries are resolver false positives.** They are XPC services, not apps, so `NSWorkspace` cannot find them and they look orphaned — typically dozens per user store. **Never clear them**; you can break iCloud, Reminders, Passwords or Find My.

## Clearing orphans

```bash
bash      "$SKILL/tcc-clear-orphans.sh" preview user
bash      "$SKILL/tcc-clear-orphans.sh" preview system
bash      "$SKILL/tcc-clear-orphans.sh" user          # NOT sudo
sudo bash "$SKILL/tcc-clear-orphans.sh" system        # sudo
```

The mechanism: stage one throwaway `.app` in `/Applications` carrying the orphaned identifier, register it, `tccutil reset All <id>`, unregister, delete.

🔴 **The stub MUST be in `/Applications`.** Measured with all other variables held constant: a stub in `/private/tmp` **is** registered (it appears in `lsregister -dump`) and `tccutil` still returns `-10814` — with a 0-byte executable, a real Mach-O, or ad-hoc signed. `tccutil` does not read the registration database; it calls an application-lookup API that only returns bundles from standard application directories. **Registration is not resolvability.**

## Path-type rows (`client_type=1`)

`tccutil` accepts identifiers only, so these are unreachable by it at any scope. A direct `TCC.db` writer (e.g. `jacobsalmela/tccutil`, GPL-2.0) handles them — but **the SIP boundary is per-database, measured**: writes **succeed** against the user store with SIP enabled and are **refused** by the system store (`"you probably need to disable SIP"`). Do not disable SIP to delete inert rows.

⚠️ If you install that tool via Homebrew it lands as `tccutil` and **shadows `/usr/bin/tccutil`**, silently changing the meaning of every `tccutil` in your scripts. Keep it `brew unlink`ed, expose it under a distinct name, and always call Apple's by absolute path `/usr/bin/tccutil`.

## Before you delete an application

1. Reset its TCC grants **now**, while the bundle still resolves.
2. Check launchd persistence **by the Label inside the plist**, never the filename.
3. Then remove files.

## Reporting results

State separately: what was cleared, what was **deliberately** skipped and why (`com.apple.*`, path rows, live apps), and what the change is actually worth. If the honest answer is "housekeeping, not a security improvement," say so — then point at where the real surface is (live grants, listening sockets, the firewall).

## Post-Execution Reflection

1. **Did a verification disagree with a tool's exit code?** That is the normal case — make sure the script reported the database, not the tool.
2. **Did a resolver call return NOT_INSTALLED for something that exists?** Find the class (non-app bundle, helper outside `/Applications`) and add it to rule 7.
3. **Did a macOS update move a store or change `tccutil`'s surface?** Update the store table.
4. **Did you clear rows whose real-world benefit was nil?** Record that honestly rather than reporting a count as an achievement.
