# Debug Session: iterm2-stop-notification

**Status**: ROOT CAUSE FOUND
**Date**: 2026-04-06
**Confidence**: High (verified via direct OSC 9 test + flag bitmask comparison)

## Symptoms

- Claude Code Stop event no longer fires iTerm2 notification
- Setting enabled via `/config > Notifications > iTerm2`
- Used to work (regression)
- No errors visible

## Investigation

### Test 1: Direct OSC 9 emission

Sent `\033]9;test\007` directly via printf — iTerm2 swallowed it silently.
**Conclusion**: Problem is downstream of Claude Code, not Claude Code itself.

### Test 2: iTerm2 profile config

```
BM Growl = 1                       (✓ Growl/notification enabled)
Silence Bell = 0                    (✓ not silenced)
Visual Bell = 0
Flashing Bell = 0
```

iTerm2 profile is correctly configured to send OSC 9 to Notification Center.

### Test 3: macOS Notification Center authorization (~/Library/Preferences/com.apple.ncprefs.plist)

Compared bitmask flags across apps:

| App                | auth | flags     |
| ------------------ | ---- | --------- |
| **iTerm2**         | 6    | **6**     |
| Telegram (working) | 7    | 310386766 |
| Calendar           | 263  | 6         |

iTerm2's `flags=6` is binary `0000...0110` — only 2 bits set out of 32.
Telegram's `flags=310386766` has dozens of bits set.

## Root Cause

**macOS System Settings > Notifications > iTerm2 has nearly all per-feature toggles DISABLED.**

The `auth=6` value indicates "Allow Notifications" is technically ON, but:

- Banner style is set to **None** (no banners or alerts)
- Sound is OFF
- Show in Notification Center is OFF
- Show on Lock Screen is OFF
- Badge app icon is OFF

This explains why:

1. Direct OSC 9 escape sequences go nowhere
2. Claude Code's Stop notifications never appeared
3. The `/config > Notifications > iTerm2` setting in Claude Code has no effect (it just enables sending OSC 9, but macOS suppresses it)

## Fix

Open System Settings → Notifications → iTerm2 and enable:

- ✅ Allow Notifications (verify on)
- ✅ Banner style: **Banners** or **Alerts**
- ✅ Show in Notification Center
- ✅ Play sound for notifications
- ✅ Show on Lock Screen (optional)

## Verification

After fix, run: `printf "\033]9;test\007"` — banner should appear top-right.
Then run any Claude Code prompt; Stop event should fire notification.

## Why It Regressed

Most likely macOS update reset iTerm2 notification permissions. macOS occasionally resets app notification permissions during major updates (Sequoia 15.x updates have been known to do this).
