# ssh-tunnel-companion

System-wide SSH tunnel persistence for macOS. Keeps the ClickHouse tunnel to **bigblack** alive across sleep/wake, network changes, and reboots — without autossh.

## 3-Layer Resilience System

| Layer | What              | Where                                                           | Role                                                    |
| ----- | ----------------- | --------------------------------------------------------------- | ------------------------------------------------------- |
| 1     | SSH keepalive     | `~/.ssh/config` (Host bigblack)                                 | Detects dead connections (90s), SSH exits cleanly       |
| 2     | launchd KeepAlive | `~/Library/LaunchAgents/com.terryli.ssh-tunnel-companion.plist` | Restarts SSH on exit — replaces autossh                 |
| 3     | sleepwatcher      | `~/.wakeup` hook                                                | Kills stale SSH immediately on wake — instant reconnect |

**Control plane**: SwiftBar plugin (`ssh-tunnel.5s.sh`) — menu bar status + start/stop/restart actions.

## Files

```
ssh-tunnel-companion/
├── CLAUDE.md                  ← You are here
├── Makefile                   ← install/uninstall/start/stop/restart/status/logs/zt-probe
├── launchd/
│   └── com.terryli.ssh-tunnel-companion.plist   ← Layer 2
├── swiftbar/
│   └── ssh-tunnel.5s.sh       ← Menu bar plugin (symlinked to SwiftBar plugins dir)
└── scripts/
    ├── install.sh             ← Deploy all 3 layers
    ├── uninstall.sh           ← Remove all 3 layers (preserves SSH config + sleepwatcher daemon)
    ├── wakeup.sh              ← Layer 3 source (appended to ~/.wakeup)
    └── zt-probe.sh            ← ZeroTier health probe (sudo required)
```

## Ports Forwarded

| Local             | Remote          | Service         |
| ----------------- | --------------- | --------------- |
| `localhost:18123` | `bigblack:8123` | ClickHouse HTTP |
| `localhost:18081` | `bigblack:8081` | SSE sidecar     |

## Commands

```bash
make install     # Deploy everything, start tunnel
make uninstall   # Remove everything, stop tunnel
make start       # Load launchd agent
make stop        # Unload launchd agent
make restart     # Kill SSH → launchd restarts it
make status      # Show all 3 layers + ClickHouse connectivity
make logs        # Tail /tmp/ssh-tunnel-companion.log
make zt-probe    # ZeroTier diagnostics (requires sudo)
```

## Consumers

- **flowsurface** — `mise run preflight` checks `localhost:18123` connectivity. Tunnel lifecycle is NOT managed by flowsurface (was migrated out of `.mise/tasks/infra.toml`).
- Any tool needing ClickHouse on bigblack via `localhost:18123`.

## Self-Referencing Convention

Every file in this system contains a header block listing all companion files with full paths. Finding any one file leads to all others. This prevents orphaned configuration when troubleshooting.

---

## Research: Landscape of SSH Tunnel Persistence on macOS

_Conducted 2026-04-02. Covers all viable FOSS options for persistent SSH tunnels that survive macOS sleep/wake._

### Why This Matters

macOS aggressively kills TCP connections during sleep. An SSH tunnel that was alive before your laptop lid closed will be dead when you open it — but the process may still exist as a zombie, holding the port. The tunnel doesn't recover until: (a) SSH keepalive detects the dead connection (30-90s), (b) the SSH process exits, and (c) something restarts it. Without intervention, users see "Fetch error: POST <http://localhost:18123>" in apps like flowsurface.

### Options Evaluated

#### 1. autossh (what we dropped)

- **What**: Wrapper around SSH that monitors and restarts the connection on death
- **Status**: Unmaintained since 2019 (v1.4g). Available via `brew install autossh`
- **How it works**: Spawns SSH as a child process, optionally opens a monitoring port (`-M port`) to send test data through the tunnel. If the test fails, kills and restarts SSH
- **Key insight**: With `-M 0` (monitor port disabled — the common modern config), autossh does exactly one thing: restart SSH when it exits. launchd `KeepAlive=true` does this identically, natively, with zero dependencies
- **Sleep/wake**: No macOS awareness. Waits for SSH keepalive timeout to detect death (~90s)
- **Verdict**: Unnecessary middleware. Replaced by pure SSH + launchd

#### 2. Pure OpenSSH + launchd (what we use — Layer 1+2)

- **What**: `ssh -N` with `ServerAliveInterval=30`, `ServerAliveCountMax=3`, `ExitOnForwardFailure=yes`, managed by launchd `KeepAlive=true`
- **Status**: Always current — ships with macOS
- **How it works**: SSH sends keepalive probes every 30s. After 3 missed responses (90s), SSH exits cleanly. launchd detects the exit and restarts SSH within `ThrottleInterval` (10s). `ExitOnForwardFailure=yes` ensures SSH exits if port forwarding fails (e.g., port already in use)
- **Sleep/wake**: Reconnects after keepalive timeout + throttle (~100s worst case). sleepwatcher (Layer 3) eliminates this delay
- **Verdict**: The correct approach. Zero dependencies beyond macOS itself

#### 3. sleepwatcher (Layer 3 — instant wake recovery)

- **What**: C daemon that runs user scripts on macOS sleep/wake/idle events
- **Author**: Bernhard Baehr. GPL-3.0. ~200 lines of C using IOKit `IORegisterForSystemPower`
- **Status**: Last release 2.2.1 (2011). Unmaintained but stable — the IOKit API hasn't changed. Available via `brew install sleepwatcher`
- **Source**: [bernhard-baehr.de/sleepwatcher_2.2.1.tgz](https://www.bernhard-baehr.de/sleepwatcher_2.2.1.tgz) (tarball, not on GitHub). Unofficial mirrors: [OpenFibers/sleepwatcher](https://github.com/OpenFibers/sleepwatcher), [qiuosier/SleepTight](https://github.com/qiuosier/SleepTight)
- **How it works**: Registers IOKit power callbacks. On wake, runs `~/.wakeup`. Our hook kills the stale SSH process on port 18123, and launchd restarts it fresh
- **Risk**: 15-year-old unmaintained C binary. If Apple changes IOKit power notifications or removes the API, sleepwatcher breaks silently (no crash — just stops receiving events)
- **Verdict**: Works today. Should be replaced with a native solution when time permits (see Roadmap)

#### 4. Dedicated tunnel managers (server-side required — rejected)

| Tool            | Stars | Requires server daemon | Port forwarding | Why rejected                                             |
| --------------- | ----- | ---------------------- | --------------- | -------------------------------------------------------- |
| **chisel**      | 12k+  | Yes (chisel server)    | Yes, arbitrary  | Adds server-side complexity. SSH is already there        |
| **rathole**     | 10k+  | Yes (rathole server)   | Yes             | Rust. Config-file driven. Overkill for one tunnel        |
| **frp**         | 90k+  | Yes (frpd)             | Yes             | Most popular but massive overkill. Client+server model   |
| **bore**        | 9k+   | Yes (bore server)      | Single port     | Designed for exposing local services, not our use case   |
| **sshuttle**    | -     | No                     | Full subnet     | VPN-over-SSH. Wrong abstraction — we need specific ports |
| **cloudflared** | -     | Cloudflare account     | Yes             | Excellent reconnection but requires external service     |

**Common problem**: All require installing and maintaining a server-side daemon on bigblack. SSH is already running there. Adding another daemon just for tunneling is unnecessary complexity.

#### 5. macOS GUI apps (not FOSS or abandoned)

| App                    | Type             | Status           | Sleep/wake   | Notes                                                                                     |
| ---------------------- | ---------------- | ---------------- | ------------ | ----------------------------------------------------------------------------------------- |
| **Core Tunnel**        | Native macOS     | Active, $10/yr   | Yes, native  | Best UX. Closed-source, paid. [codinn.com/tunnel](https://codinn.com/tunnel/)             |
| **Tunneler**           | Menu bar (Swift) | Stale            | Unknown      | [jonashoechst/Tunneler](https://github.com/jonashoechst/Tunneler). Parses `~/.ssh/config` |
| **SSH Tunnel Manager** | macOS app        | Sporadic updates | Inconsistent | [tynsoe.org/stm](https://www.tynsoe.org/stm/)                                             |
| **Secure Pipes**       | macOS app        | Stalled          | Unknown      | Closed-source                                                                             |

**Verdict**: Core Tunnel is the only polished option but fails the FOSS requirement. The open-source macOS apps are all effectively abandoned.

#### 6. xbar/SwiftBar SSH plugins (reference only)

- **xbar ssh-tunnel.1s.sh**: Basic start/stop from menu bar. Parses `~/.ssh/config`. No keepalive, no reconnection logic. [xbarapp.com](https://xbarapp.com/docs/plugins/Network/ssh-tunnel.1s.sh.html)
- **SwiftBar**: We use this as the control plane — our `ssh-tunnel.5s.sh` is custom

### Decision Matrix

| Criterion        | autossh       | SSH+launchd    | sleepwatcher     | chisel/frp | Core Tunnel |
| ---------------- | ------------- | -------------- | ---------------- | ---------- | ----------- |
| FOSS             | Yes           | Yes (built-in) | Yes (GPL-3)      | Yes        | No          |
| No server daemon | Yes           | Yes            | Yes              | **No**     | Yes         |
| Sleep/wake aware | No            | No             | **Yes**          | N/A        | **Yes**     |
| Maintained       | **No** (2019) | Always         | **No** (2011)    | Yes        | Yes         |
| Dependencies     | 1 (autossh)   | **0**          | 1 (sleepwatcher) | 1 (binary) | 1 (app)     |
| macOS native     | No            | **Yes**        | Mostly (IOKit)   | No         | **Yes**     |

### Conclusion

**Current stack (SSH + launchd + sleepwatcher) is the simplest viable solution.** The only concern is sleepwatcher's age and maintenance status. The roadmap below addresses this.

---

## Roadmap: Native Swift Wake Detector

**Goal**: Replace sleepwatcher (Layer 3) with a purpose-built, minimal Swift binary that uses native macOS APIs for wake detection. This eliminates the last unmaintained dependency.

### Why Swift (not C, not Go, not Rust)

- **NSWorkspace notifications** (`didWakeNotification`, `willSleepNotification`) are first-class Swift/ObjC APIs — no IOKit low-level work needed
- **Compile once, run forever** — Swift binary with no runtime dependencies on macOS
- **~30 lines of code** — register for notification, kill tunnel process, exit (or stay resident)
- **Same toolchain** as claude-tts-companion — no new build chain to maintain

### Two approaches

#### A. Minimal wake-hook binary (recommended first step)

A ~50-line Swift CLI that registers `NSWorkspace.didWakeNotification`, kills the tunnel process, and stays resident. Replaces sleepwatcher entirely for our use case.

```
Sources/
  ssh-tunnel-wake/
    main.swift     # ~50 lines: NSWorkspace.didWakeNotification → kill tunnel
```

**Pros**: Minimal, single-purpose, easy to audit
**Cons**: Only handles our tunnel — not a general-purpose sleepwatcher replacement

#### B. General-purpose sleep/wake runner (future, if needed)

A configurable tool that reads `~/.sleep` and `~/.wakeup` scripts (sleepwatcher-compatible) but uses Swift/AppKit instead of IOKit C. Could replace sleepwatcher system-wide.

**Pros**: Drop-in sleepwatcher replacement, benefits all hooks
**Cons**: More scope, more maintenance surface

### Implementation plan (when triggered)

1. Add `Package.swift` with a single executable target
2. Write `main.swift` using `NSWorkspace.shared.notificationCenter` for `didWakeNotification`
3. Create `launchd/com.terryli.ssh-tunnel-wake.plist` (or merge into existing plist as an additional `WatchPaths` trigger)
4. Update `scripts/install.sh` to build + deploy the Swift binary
5. Remove sleepwatcher dependency from install script
6. Update all self-referencing headers

### Trigger condition

Replace sleepwatcher when any of:

- sleepwatcher breaks on a future macOS version
- `brew services start sleepwatcher` fails after a macOS upgrade
- We want to add sleep-time behavior (e.g., log tunnel uptime before sleep)
- General cleanup / dependency reduction effort
