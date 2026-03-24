---
name: mql5:headless-mt5-remote
description: >
  Deploy and manage MetaTrader 5 on headless Linux (Ubuntu) via Wine with remote desktop
  access from macOS. Covers the complete stack: Wine 10 installation, Xvfb virtual display,
  XFCE desktop, x11vnc with TigerVNC viewer, SSH tunnel security, clipboard sync via SSH
  side-channel, Spotlight app launcher, and systemd services. Includes all proven patterns,
  anti-patterns (noMachine, KasmVNC, macOS Screen Sharing clipboard issues), and the exact
  scripts that work in production. Use whenever setting up MT5 on Linux, troubleshooting
  VNC/Wine issues, or configuring remote desktop for headless trading servers.
  TRIGGERS: headless MT5, MT5 on Linux, Wine MT5, MT5 VNC, remote MT5, headless Wine,
  MT5 Ubuntu, gpu-host MT5, VNC clipboard, x11vnc setup, Xvfb MT5, headless trading.
---

# Headless MT5 Remote Desktop — Production Setup Guide

Deploy MetaTrader 5 on a headless Linux server via Wine, with crisp remote desktop access
from macOS. This skill captures every pattern and anti-pattern discovered through extensive
testing — use it to avoid weeks of debugging.

## Architecture

```
macOS (dev machine)
  └─ Spotlight app "MT5 gpu-host"
       ├─ SSH tunnel (port 5900)
       ├─ TigerVNC viewer (no auth, clipboard flags)
       └─ SSH clipboard sync daemon (pbpaste → xclip)

gpu-host (Ubuntu 24.04, headless)
  ├─ Xvfb :99 (1680x1050x24 virtual display)
  ├─ XFCE desktop (taskbar, file manager, right-click menu)
  ├─ x11vnc (-repeat -xkb -nopw -noncache)
  ├─ autocutsel (CLIPBOARD + PRIMARY bridge)
  ├─ Wine 10.0 stable (pinned, Win64 prefix)
  └─ MT5 terminal64.exe /portable
       ├─ TickCollector EA (Parquet via tick_writer.dll)
       └─ FXView broker connection
```

## Proven Stack (What Works)

### Wine Version

- **Wine 10.0 stable** from WineHQ repos — confirmed working with MT5 build 5699
- Pin with `apt-mark hold` to prevent upgrade
- Wine prefix: `~/.mt5` with `WINEARCH=win64`

### Virtual Display

- **Xvfb** at 1680x1050x24 — matches standard 16:10 resolution
- Larger is fine; smaller causes MT5 window clipping

### Desktop Environment

- **XFCE** — lightweight, full desktop with taskbar and file manager
- Without XFCE: closing MT5 leaves a black screen with no way to relaunch
- Disable lock screen: `sudo apt remove light-locker xfce4-screensaver`
- Disable PolicyKit prompts for NetworkManager (headless servers have no Wi-Fi)

### VNC Server

- **x11vnc** with flags: `-repeat -xkb -nopw -noncache -localhost`
- `-repeat`: enables key auto-repeat (without this, holding Delete doesn't work)
- `-xkb`: fixes clipboard direction issues
- `-noncache`: prevents ncache pixel buffer that causes bottom-of-screen clipping
- `-nopw`: no password (SSH tunnel provides security)
- `-localhost`: only accept connections from localhost (forces SSH tunnel)

### VNC Viewer (macOS)

- **TigerVNC** (`brew install --cask tigervnc-viewer`)
- Launch with: `-SecurityTypes None localhost:5900` (single-dash flags, not double-dash)
- Grant **Accessibility** permission in System Settings for key repeat to work

### Clipboard Sync

- VNC clipboard protocol is **broken** on this stack (libvncserver 0.9.14 bug on Ubuntu 24.04)
- Solution: **SSH side-channel** — a background script polls `pbpaste` on macOS and pushes
  changes to Linux via `ssh gpu-host "DISPLAY=:99 xclip -selection clipboard"`
- Also run `autocutsel` on the server to bridge X11 CLIPBOARD and PRIMARY selections
- See `scripts/clipboard-sync.sh`

### SSH Tunnel

- `ssh -f -N -L 5900:localhost:5900 tca@gpu-host`
- All VNC traffic encrypted through SSH — no need for VNC-level authentication

### macOS Spotlight Launcher

- Create an `.app` bundle in `/Applications/` with Info.plist + shell script
- Spotlight indexes it automatically — `Cmd+Space → "MT5"` to launch
- Script: kill old tunnel → create new tunnel → start clipboard sync → launch TigerVNC
- See `scripts/MT5gpu-host` for the launcher script

## Anti-Patterns (What Does NOT Work)

### noMachine

- **Rejected**: Requires login authentication that can't be bypassed, installs many
  background services and launchd plists, heavy footprint
- The X11 vector mode is theoretically fastest for 2D but macOS client quality is poor
- Full removal: `brew uninstall --cask nomachine` + clean `~/.nx`, preferences, launchd

### KasmVNC

- **Rejected**: Browser-only client, WebSocket overhead, no performance advantage for
  this use case. User prioritizes performance over browser convenience.

### macOS Screen Sharing (built-in VNC)

- **Rejected**: Always requires password even with `-nopw` server. No way to bypass.
- Clipboard works well but the auth requirement is a dealbreaker.

### Wine 11.0

- **Broken**: "Debugger has been found" error on both macOS CrossOver and Linux.
- Wine 10.0 stable works. Wine 11.2 devel reportedly works on Linux but not tested.

### Wine Virtual Desktop (`explorer /desktop=`)

- Creates a Wine-managed window container. MT5 still maximizes to fill it.
- Adds complexity without solving the display sizing problem.

### x11vnc `-ncache`

- Default in some builds. Appends a huge scratch area below the framebuffer.
- Causes bottom-of-screen clipping in VNC viewers. Always use `-noncache`.

### x11vnc `-clipboard` flag

- Crashes x11vnc on Ubuntu 24.04. Use `autocutsel` daemon instead.

### `--SecurityTypes=None` (double-dash)

- TigerVNC uses single-dash flags. `--SecurityTypes=None` silently fails.
- Correct: `-SecurityTypes None` (space-separated, single dash)

### Docker for MT5

- User rejected for performance concerns (container networking/filesystem overhead).
- Native Wine on Linux preferred.

### SPICE / Xspice

- Not applicable without a VM. Known slow 2D primitives. Immature macOS client.

### Xpra

- Per-window encoding is theoretically optimal but has variable latency in practice.
- More complex setup than VNC for this use case.

## Server Setup (One-Time)

Read `references/server-setup.md` for the complete step-by-step installation guide.

## Scripts

All scripts are in the `scripts/` directory:

| Script              | Purpose                                                   |
| ------------------- | --------------------------------------------------------- |
| `server-start.sh`   | Start Xvfb + XFCE + x11vnc + autocutsel + MT5 on gpu-host |
| `clipboard-sync.sh` | macOS → Linux clipboard sync via SSH (runs alongside VNC) |
| `MT5gpu-host`       | macOS Spotlight app launcher script                       |

## Troubleshooting

Read `references/troubleshooting.md` for common issues and fixes.

## Key Decisions Log

| Decision     | Chosen                           | Rejected                           | Why                                          |
| ------------ | -------------------------------- | ---------------------------------- | -------------------------------------------- |
| VNC viewer   | TigerVNC                         | noMachine, Screen Sharing, KasmVNC | No auth prompt, native app, good performance |
| Clipboard    | SSH side-channel                 | VNC protocol, autocutsel alone     | VNC clipboard broken on Ubuntu 24.04         |
| Wine version | 10.0 stable                      | 11.0, staging                      | Debugger detection in newer versions         |
| Desktop      | XFCE                             | None (bare Xvfb)                   | Need taskbar/file manager for usability      |
| Display      | Xvfb 1680x1050                   | 1280x720, 1920x1080                | Fits Mac Retina at 1:1 without clipping      |
| Key repeat   | x11vnc `-repeat` + `xset r rate` | Default                            | Holding keys didn't auto-repeat              |
| Lock screen  | Removed entirely                 | Disabled config                    | XFCE lock screen kept reappearing            |
| Auth         | SSH tunnel only                  | VNC password, noMachine login      | Simplest, most secure, zero prompts          |
