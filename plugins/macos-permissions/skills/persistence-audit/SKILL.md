---
name: persistence-audit
description: Enumerate everything that persists or auto-starts on a Mac — launchd daemons and agents, Background Task Management items, system extensions, audio HAL plug-ins, SecurityAgentPlugins in the login chain, privileged helpers, kernel extensions, configuration profiles, login hooks, cron, listening sockets and firewall state. Enumerates rather than greps, so it finds what you did not think to search for. Use before uninstalling software, when hunting remote-access tools or unwanted background services, or when auditing what starts at boot or login. TRIGGERS - persistence, what starts at boot, launchd audit, LaunchDaemon, LaunchAgent, login items, background services, remove remote access, what is running in the background, audio HAL plugin, SecurityAgentPlugin, listening ports, what can connect to my Mac, uninstall leftovers.
allowed-tools: Bash, Read
---

# persistence-audit — enumerate what persists, don't grep for it

> **Self-Evolving skill** — if a macOS release adds or moves a persistence mechanism, add a section and record it here.

```bash
SKILL="$(cc-plugin-root macos-permissions)/skills/persistence-audit"
bash      "$SKILL/persistence-inventory.sh"      # everything readable as you
sudo bash "$SKILL/persistence-inventory.sh"      # adds root-only sections
```

Read-only. It deletes nothing.

## 🔴 Why enumerate instead of search

Grepping for product names answers _"is X here?"_ and can never answer _"what is here?"_. In a real cleanup that searched for a handful of vendor names, a **root LaunchDaemon was running the entire time** and was missed — nobody typed its name. The same run also checked for `/Applications/<Vendor>.app` when the bundle was actually named `<Vendor> Helper.app` — a confident false negative.

**Checking for a name you guessed at is not a test.** List what exists, then classify.

## 🔴 launchd addresses jobs by the Label INSIDE the plist, never the filename

A vendor plist named `com.vendor.vendor_service.plist` can carry `Label com.vendor.service`. So:

```bash
launchctl bootout system/com.vendor.vendor_service    # ESRCH -> "not loaded"
```

…looks like the job is already gone, and you then delete a root binary out from under a **live `KeepAlive` job**. Always:

```bash
label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist")"
[ -n "$label" ] || { echo "no Label key — refusing to guess a target"; exit 1; }
launchctl bootout "system/$label"
```

Section 1 of the inventory flags every `LABEL!=FILENAME` mismatch for you.

## Mechanisms people forget

| Mechanism                                             | Why it hides                                             |
| ----------------------------------------------------- | -------------------------------------------------------- |
| Audio HAL plug-ins (`/Library/Audio/Plug-Ins/HAL`)    | load into `coreaudiod`; appear in **no** launchd listing |
| SecurityAgentPlugins + `system.login.console`         | wired into the authorization chain, not a process list   |
| Background Task Management (`sfltool dumpbtm`)        | the modern login-item registry; not a plist you can `ls` |
| `launchctl print-disabled`                            | remembers labels of long-uninstalled software forever    |
| System extensions / DriverKit                         | `systemextensionsctl list`, separate from launchd        |
| Privileged helpers (`/Library/PrivilegedHelperTools`) | installed by SMJobBless, survive app deletion            |

## 🔴 Editing the login chain can lock you out

`system.login.console` is what authenticates you at the login window. Before touching it: keep a terminal open, verify an SSH route in (`ssh` from another machine, confirmed working), and know the recovery command `security authorizationdb reset <UUID>`. Verify afterwards by **rebooting and locking/unlocking the screen with a terminal still open**.

## Listening sockets and the firewall belong in the same audit

A service bound to `*:` accepts connections from **every** interface. If the application firewall is disabled, those are reachable from the LAN and from any VPN/mesh network. That is live surface — unlike a dormant permission grant — and it is routinely overlooked while attention goes to uninstalling apps.

Verify reachability **from another host**, never from the machine itself: connecting to your own address routes over loopback and never crosses the filter, so a self-test proves nothing.

## Uninstall order that avoids the traps

1. **TCC grants first**, while the bundle still resolves (see the `tcc-grant-audit` skill).
2. Enumerate persistence; resolve each launchd Label from inside its plist.
3. `launchctl bootout` by Label; assert nothing remains loaded.
4. Only then delete files — previewing every path, never globbing wider than what the vendor created.
5. Re-run the inventory and diff.

## A warning about heuristic uninstallers

Tools that "find orphaned files" infer from whether a file maps to a known `.app`. On a machine with hand-written launchd runners in `~/.local/bin`, `~/.claude/tools` or a project `libexec`, that inference is catastrophically wrong — one popular uninstaller flagged **dozens of LaunchAgent plists, most of them live loaded jobs**, plus support files for several installed, running applications. Always use such a tool's _list_ mode, verify against `launchctl list`, and never its bulk _remove_ mode.

## Post-Execution Reflection

1. **Did something turn up that no section covers?** Add a section.
2. **Did a Label mismatch appear?** Confirm the flag fired; if not, fix section 1.
3. **Did you find something by grepping that enumeration missed?** That is a gap in the script, not a win for grep.
4. **Was a finding a false negative from a guessed name or path?** Record the class so the next run enumerates instead.
