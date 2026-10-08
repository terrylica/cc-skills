# ssh-tunnel-companion

System-wide SSH tunnel persistence for macOS. Keeps the ClickHouse tunnel to your configured host alive across sleep/wake, network changes, and reboots — without autossh.

## Network Access Path (2026-04-12)

**Primary: Tailscale** — `ssh <host>` resolves to `<host>.<your-tailnet>.ts.net` via MagicDNS, works from LAN, coffee shops, cellular, anywhere. Pre-auth keys never expire. Substitute your own tailnet name (`tailscale status --json | jq -r .MagicDNSSuffix`); this plugin never hardcodes one.

**Fallback: Cloudflare Access SSH** — `ssh <host>-cf` via your own Access-protected SSH hostname through `cloudflared access ssh`, protected by GitHub SSO → ssh-operators group → short-lived SSH cert (4min validity, regenerated per connection via `Match host exec cloudflared access ssh-gen`).

**Legacy paths (removed)**: mDNS (`<host>.local`, LAN-only, unreliable off-LAN); ZeroTier (removed 2026-04-06 due to macOS kernel-extension fragility).

The launchd tunnel host alias in `~/.ssh/config` resolves to the Tailscale FQDN — launchd-managed SSH tunnels now traverse Tailscale, so they work from any network without wrapper scripts.

## 3-Layer Resilience System

| Layer | What              | Where                                                             | Role                                                    |
| ----- | ----------------- | ----------------------------------------------------------------- | ------------------------------------------------------- |
| 1     | SSH keepalive     | `~/.ssh/config` (Host $TUNNEL_HOST)                               | Detects dead connections (90s), SSH exits cleanly       |
| 2     | launchd KeepAlive | `~/Library/LaunchAgents/com.cc-skills.ssh-tunnel-companion.plist` | Restarts SSH on exit — replaces autossh                 |
| 3     | sleepwatcher      | `~/.wakeup` hook                                                  | Kills stale SSH immediately on wake — instant reconnect |

**Control plane**: SwiftBar plugin (`ssh-tunnel.5s.sh`) — menu bar status + start/stop/restart actions.

## Files

```
ssh-tunnel-companion/
├── CLAUDE.md                  ← You are here
├── Makefile                   ← install/uninstall/start/stop/restart/status/logs/ping
├── launchd/
│   └── com.cc-skills.ssh-tunnel-companion.plist   ← Layer 2
├── swiftbar/
│   └── ssh-tunnel.5s.sh       ← Menu bar plugin (symlinked to SwiftBar plugins dir)
└── scripts/
    ├── install.sh             ← Deploy all 3 layers
    ├── uninstall.sh           ← Remove all 3 layers (preserves SSH config + sleepwatcher daemon)
    └── wakeup.sh              ← Layer 3 source (appended to ~/.wakeup)
```

## Ports Forwarded

| Local             | Remote              | Service                            |
| ----------------- | ------------------- | ---------------------------------- |
| `localhost:18123` | `$TUNNEL_HOST:8123` | ClickHouse HTTP                    |
| `localhost:18081` | `$TUNNEL_HOST:8081` | SSE sidecar — crypto ODB live bars |

**SSoT is `libexec/ssh-tunnel-companion-runner`; this table is a copy.** When they disagree, the runner wins. The tunnel is load-bearing: a stale port listed here once made it look dead and nearly got it removed (2026-09-01). The machine is alive; only a former tenancy on it ended (2026-07-28), so scope any claim to the tenant.

## Commands

```bash
make install     # Deploy everything, start tunnel
make uninstall   # Remove everything, stop tunnel
make start       # Load launchd agent
make stop        # Unload launchd agent
make restart     # Kill SSH → launchd restarts it
make status      # Show all 3 layers + ClickHouse connectivity
make logs        # Tail /tmp/ssh-tunnel-companion.log
make ping        # Tailscale connectivity check to the configured host
```

## Consumers

- **flowsurface** — its own `preflight` task checks `localhost:18123` connectivity (`curl -sf -m 3 http://localhost:18123/ -d 'SELECT 1'`). Tunnel lifecycle is NOT managed by flowsurface.
- Any tool needing ClickHouse on the tunnel host via `localhost:18123`.

## Self-Referencing Convention

Every file in this system contains a header block listing all companion files with full paths. Finding any one file leads to all others. This prevents orphaned configuration when troubleshooting.

---

## Research and roadmap

The 2026-04-02 survey of tunnel-persistence options (autossh, pure OpenSSH + launchd, sleepwatcher, server-side managers, GUI apps), its decision matrix, and the native Swift wake-detector roadmap with its trigger condition: [docs/research-and-roadmap.md](./docs/research-and-roadmap.md).
