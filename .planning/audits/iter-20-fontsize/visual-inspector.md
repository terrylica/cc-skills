# Visual Inspector Report: Floating-Clock v3 Font Size Audit

**Archetype**: Visual Inspector | **Iteration**: 20 | **Date**: 2026-04-23

---

## Executive Summary

The floating-clock scales gracefully across all 6 font sizes (10pt–64pt), with no layout breakage or critical readability issues. However, the lower and upper extremes expose a design imbalance that suggests narrowing the usable range to 14pt–48pt.

---

## Detailed Findings

### LOCAL Time Legibility

**At 10pt** (size-10.png): The LOCAL time is problematic. At 22:57:25 in a 495×300 window, the LOCAL segment appears cramped and dwarfed by the 11pt ACTIVE/NEXT sections. While readable on a sunny display, it requires eyeball focus and doesn't command attention in its own interface. This size feels mismatched to the clock's purpose as a _primary_ display.

**At 16pt** (size-16.png): Legible but still undersized relative to ACTIVE/NEXT. The LOCAL time (22:57:27) is present but not the visual anchor of the layout. Window width grows modestly to 524px.

**At 24pt** (size-24.png): The design sweet spot. LOCAL time (22:57:30) is clear, prominent, and properly weighted against the trading data. Window is 563px—compact but spacious. This is the default and it shows.

**At 36pt** (size-36.png): Strong legibility. LOCAL time (22:57:32) dominates the left third in large, confident strokes. No readability issues; window grows to 620px. Still feels intentional.

**At 48pt** (size-48.png): LOCAL time (22:57:34) is nearly 4× the height of ACTIVE/NEXT labels. Visually impressive but beginning to feel like a single-purpose display: "this is a clock first, trading data second." Window is 678px—noticeably wider but not excessive.

**At 64pt** (size-64.png): The LOCAL time (22:57:37) consumes 2 character-widths of height. This is dramatic—more display device than information hierarchy. The ACTIVE/NEXT sections are now relegated to detail status. Window reaches 755px, the point at which you're operating a dedicated clock appliance, not an integrated cockpit display.

---

## Proportion & Visual Balance

### 10pt–24pt (Ascending Imbalance Phase)

The fundamental asymmetry is visible: ACTIVE/NEXT freeze at 11pt while LOCAL varies. At 10pt, LOCAL undershoots the fixed 11pt labels by 1 point—a 9% deficit. Users who prefer smaller clocks end up with an inverted visual hierarchy where the secondary data is actually larger. This feels like a bug.

### 36pt–48pt (Intentional Dominance)

By 36pt, LOCAL has grown 3.6× larger than the 11pt labels. This reads as _intentional design_—the clock is meant to dominate. Whether this is desired depends on use case: a wall-mounted airport display? Yes. A corner tool in a multi-purpose cockpit? Questionable.

### 64pt (Appliance Mode)

At 64pt, the scaling feels exhausted. The LOCAL time fills so much vertical space (≈500px would be the implied 11-column mono cell height) that the sidebar becomes secondary. The window geometry also becomes inconvenient: 755px width is approaching laptop-screen-share territory.

---

## Window Growth Trajectory

The horizontal scaling is **smooth and linear**:

- 10pt: 495px
- 16pt: 524px (+29px / +6.7pt)
- 24pt: 563px (+39px / +8pt)
- 36pt: 620px (+57px / +12pt)
- 48pt: 678px (+58px / +12pt)
- 64pt: 755px (+77px / +16pt)

No layout breaks observed. Padding and margins scale consistently. The right-aligned NEXT TO OPEN section stays visible and readable throughout. Grid alignment is clean at all sizes.

---

## Recommendations

### 1. Minimum Usable Size: Raise to 14pt

At 10pt and 16pt, the LOCAL segment undercuts ACTIVE/NEXT (11pt). Enforce a 14pt floor to ensure LOCAL never visually loses to its own details.

### 2. Maximum Practical Size: Cap at 48pt

At 64pt, the clock transitions from "integrated display" to "dedicated appliance." If the user wants a full-screen clock, redirect them to a native macOS clock app. Keep floating-clock in the 14pt–48pt sweet spot where it functions as a cockpit instrument.

### 3. Default Remains 24pt

The 24pt default is well-chosen: proportionally balanced, window size is practical (563px), and LOCAL time is clearly the primary element without drowning out context data.

### 4. Consider a "Proportional Sync" Mode (Future)

If you retain the full 10pt–64pt range, expose a toggle: when ON, ACTIVE/NEXT scale with LOCAL to maintain visual hierarchy. When OFF, keep the current fixed-11pt behavior. This resolves the 10pt imbalance for users who want smaller clocks.

---

## Verdict

✓ **No critical flaws**. Layout is robust, scaling is linear, no content clipping or overflow.

⚠ **Design imbalance at extremes**. 10pt–16pt creates an inversion where secondary data outweighs primary; 64pt converts the tool into a single-purpose display.

**Recommended action**: Constrain the UI to 14pt–48pt. If broader range is needed later, implement proportional scaling to keep hierarchy consistent across all sizes.

---

**Inspector**: Visual Inspector  
**Archetype**: Audit—Visual Analysis  
**Scope**: Font size extremes, proportion, layout robustness  
**Status**: Ready for design review
