# Troubleshooting — Headless MT5 Remote

## "Debugger has been found" error

- **Cause:** Wine 11.0+ triggers MT5's anti-debug protection
- **Fix:** Downgrade to Wine 10.0 stable: `sudo apt install --allow-downgrades winehq-stable=10.0.0.0~noble-1 wine-stable=10.0.0.0~noble-1 wine-stable-amd64=10.0.0.0~noble-1 wine-stable-i386=10.0.0.0~noble-1`
- On macOS CrossOver: create a Windows 11 bottle (not Windows 10)

## Black screen after connecting VNC

- **Cause:** XFCE session not running, or MT5 was closed
- **Fix:** Restart the full stack: `./scripts/server-start.sh`

## Bottom of screen trimmed/clipped

- **Cause:** x11vnc `-ncache` or display too tall for VNC viewer window
- **Fix:** Use `-noncache` flag, set Xvfb to 1680x1050

## Key repeat not working (holding Delete doesn't auto-repeat)

- **Cause:** x11vnc default disables autorepeat; TigerVNC 1.16.0 macOS bug
- **Fix:** `x11vnc -repeat` + `xset r rate 200 30` on server
- Also grant TigerVNC **Accessibility** permission on macOS

## Clipboard not transferring from macOS

- **Cause:** libvncserver 0.9.14 clipboard bug on Ubuntu 24.04
- **Fix:** Use SSH side-channel clipboard sync (see `scripts/clipboard-sync.sh`)
- NOT fixable via VNC protocol alone on this stack

## XFCE lock screen appears

- **Cause:** `light-locker` package auto-installed with XFCE
- **Fix:** `sudo apt remove -y light-locker xfce4-screensaver`

## PolicyKit "System policy prevents Wi-Fi scans" dialog

- **Cause:** NetworkManager asks for auth on headless server
- **Fix:** Add PolicyKit rules (see server-setup.md)

## TigerVNC `--SecurityTypes=None` does nothing

- **Cause:** TigerVNC uses single-dash flags
- **Fix:** `-SecurityTypes None` (single dash, space not equals)

## x11vnc crashes with `-clipboard` flag

- **Cause:** Bug in x11vnc on Ubuntu 24.04
- **Fix:** Don't use `-clipboard`. Use `autocutsel` daemon instead.

## Spotlight app doesn't appear

- **Cause:** macOS hasn't indexed the .app bundle yet
- **Fix:** `mdimport "/Applications/MT5 gpu-host.app"`

## MT5 auto-update breaks Wine compatibility

- **Cause:** MT5 auto-updates can't be disabled
- **Mitigation:** Block update server: `sudo iptables -A OUTPUT -d 78.140.180.45 -j DROP`
- Back up executables weekly: `cp terminal64.exe terminal64.exe.bak`
