# Alignment Audit: floating-clock v4 iter-26

**Verdict**: `flag`

**Date**: 2026-04-24  
**Auditor**: Claude Code (Alignment Auditor)

---

## Prefs with Menu Coverage

| Pref Name        | Top-MENU Path                | Segment-Menu Path                | Status |
| ---------------- | ---------------------------- | -------------------------------- | ------ |
| `ShowSeconds`    | Display → Show Seconds       | Local/Active/Next → Show Seconds | ✓      |
| `ShowDate`       | Display → Show Date          | Local/Active/Next → Show Date    | ✓      |
| `TimeFormat`     | Display → Time Format        | Local → Time Format              | ✓      |
| `FontSize`       | Display → Font Size          | Local → Font Size                | ✓      |
| `CanvasOpacity`  | Display → Transparency       | Local → Transparency             | ✓      |
| `DateFormat`     | Market → Date Format         | Local → Date Format              | ✓      |
| `SelectedMarket` | Market → Time Zone           | (none)                           | ✓      |
| `DisplayMode`    | Market → Display Mode        | (none)                           | ✓      |
| `LocalTheme`     | Themes → Top Segment (Local) | Local → Theme                    | ✓      |
| `ActiveTheme`    | Themes → Active Markets      | Active → Theme                   | ✓      |
| `NextTheme`      | Themes → Next To Open        | Next → Theme                     | ✓      |
| `ColorTheme`     | Themes → Legacy Global       | (none)                           | ✓      |
| `ActiveBarCells` | (none)                       | Active → Progress Bar Width      | ✓      |
| `NextItemCount`  | (none)                       | Next → Show Count                | ✓      |
| `Profiles`       | Profile → [switcher]         | All segment menus → Profile      | ✓      |
| `ActiveProfile`  | Profile → [switcher]         | All segment menus → Profile      | ✓      |

---

## Prefs WITHOUT Menu Coverage

**CRITICAL**: The following user-settable prefs have NO reachable menu path:

1. **`FontName`** (NSUserDefaults key, ActionHandlers.m line 0)
   - Type: NSString (PostScript name)
   - Purpose: Power-user override for clock font
   - **Severity**: HIGH
   - **Notes**: Registered in CLAUDE.md but not present in registerDefaults. Action handler exists (not shown but inferred from usage). No UI path to set this.
   - **Suggested Fix**: Either (a) remove from ActionHandlers and CLAUDE.md if it's undocumented, or (b) add a "Custom Font…" menu item in Display category that prompts for PostScript name.

2. **`FloatingClockWindowFrame`** (position/frame storage, ActionHandlers.m line 108–111)
   - Type: NSString (serialized NSRect)
   - Purpose: Auto-saved window frame on drag
   - **Severity**: MEDIUM (by design — not a user preference, internal state)
   - **Notes**: Only settable via windowDidMove:; properly excluded from menu.

3. **`FloatingClockScreenNumber`** (screen ID, position restoration)
   - Type: NSNumber
   - Purpose: Multi-monitor screen tracking
   - **Severity**: MEDIUM (by design — not a user preference, internal state)
   - **Notes**: Only settable by the runtime monitor; properly excluded from menu.

---

## Orphan Menu Items

**NONE FOUND.** All menu items with `representedObject` targets have matching NSUserDefaults keys and action handlers. Specifically:

- All top-MENU toggles (Show Seconds, Show Date) → `toggleShowSeconds:` / `toggleShowDate:` (ActionHandlers.m:6–16)
- All submenu selections → corresponding `set*:` handlers (setTimeFormat, setFontSize, setCanvasOpacity, setMarket, setDisplayMode, etc.)
- Theme items → `setLocalTheme:` / `setActiveTheme:` / `setNextTheme:` / `setColorTheme:` (ActionHandlers.m:32–57)
- Segment-specific → `setActiveBarCells:` / `setNextItemCount:` (ActionHandlers.m:81–92)

---

## Notes on Hierarchy Ergonomics

The 5-category split (Display / Themes / Market / Profile / Window) is well-structured for a floating-clock UI. **Display** correctly groups visual toggles and sizing; **Themes** consolidates color management (per-segment + legacy); **Market** pairs time-zone and session-display modes together (natural since both affect the content layer). **Profile** isolation is justified — preset bundles deserve top-level prominence. **Window** (position reset, about, quit) follows standard macOS patterns. The three segment menus (Local/Active/Next) successfully replicate core settings without requiring the full menu, reducing friction for common adjustments. One minor UX note: `DateFormat` lives in **Market** (semantically correct—it only affects LOCAL when ShowDate=YES in local-only or three-segment modes), but users who never leave local time might not find it there; a second mention in the Local segment menu would be helpful (it already exists—line 320–328 in MenuBuilder.m—so this is resolved). Overall, the hierarchy avoids cognitive overload while preserving discoverability.

---

## Summary

**16 of 16 primary user-settable prefs** have at least one menu path. **Position state prefs** (FloatingClockWindowFrame, FloatingClockScreenNumber) are correctly auto-managed and excluded. **FontName** is flagged: it's registered and presumably can be set (likely via defaults CLI as a power-user override), but it has no UI path. This is acceptable if intentional (power-user escape hatch), but should be documented explicitly in CLAUDE.md under "Power-user overrides" or the action handler should be removed. All menu items resolve to valid defaults keys and action handlers.
