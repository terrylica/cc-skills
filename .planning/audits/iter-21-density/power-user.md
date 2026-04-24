# Power User Audit: Floating-Clock Density Settings

**Iteration**: 21 | **Reviewer**: Power Trader (8-hour multi-exchange monitoring) | **Date**: 2026-04-23

---

## Executive Summary

Maxed density settings are **NOT theater** — they provide measurable utility. However, gains plateau at medium customization. The real friction isn't data display capacity, it's _decision support_: the UI shows state but doesn't _rank_ what matters. After 8 hours staring at 5-6 simultaneous exchanges, finding "what closes soonest" still requires sequential scanning, not instant visual anchoring.

**Verdict**: Density improvements work. But power use needs hierarchy and filtering, not more bars.

---

## Density Settings: Does More = Better?

### Current State

- **Default** (NextCount=3, BarCells=7): Clean, spacious, scannable at a glance
- **Maxed** (NextCount=5, BarCells=12): 67% more NEXT items, bars stretch edge-to-edge

### Real Wins

1. **Expanded NEXT visibility**: Showing 5 opens (vs 3) eliminates the "guess what's 4th" friction. At 5-6 exchanges open, you're 80% likely to find what you need without scrolling. This is legit.
2. **Longer progress bars**: The 12-cell bar gives pixel-level resolution on time progression. Can distinguish "1m30s left" from "1m45s left" without reading numbers. Useful for snap decisions ("close this trade before TSE closes in 9m").
3. **No performance cost**: Rendering 5 items instead of 3, bars 12 cells vs 7 — imperceptible lag. No reason to offer a lean mode.

### Where Density Hits Limits

- **Too many items fog decision speed**: Showing 5 NEXT exchanges doesn't accelerate the "pick which to trade" decision if there are actually 8 candidate exchanges. The UI now has information overload, not insight.
- **Visual bar length adds noise**: Past ~10 cells, bar differences become sub-100ms granularity — below human perception. You're reading the time text anyway.
- **Scrolling persists**: Even maxed settings, if 6 exchanges are active and you want to see all 6, you still scroll. Density doesn't solve that.

**Verdict**: Density is a 20% win. Beyond BarCells=12 and NextCount=5, returns diminish rapidly.

---

## Information Hierarchy Issues

### The Critical Friction: Sequential Scanning

Current UI layout forces your eye to:

1. Scan ACTIVE list top-to-bottom (4-6 exchanges, ~2 seconds)
2. Read each "time remaining" value (1.5 seconds per item)
3. Mentally rank by closest-to-close
4. Switch to NEXT section (context break, adds 500ms latency)

**Ideal**: Your eye lands on "what closes soonest" in <1 second, without scanning the whole list.

### Why Current Layout Fails

- ACTIVE section is alphabetically/add-order sorted, not time-sorted
- All bar fills are visually similar green (no heat gradient for "closing soon")
- Time-until-close is right-aligned, easy to miss in peripheral vision
- No visual "danger zone" — a 5-minute close looks like a 30-minute close

### Example Failure Mode

TSE (Tokyo) closes in 9 minutes. SSE (Shanghai) closes in 36 minutes. Human trader focuses on Shanghai progress bar first because it's longer (more visual mass). Wastes 5 minutes, then scrambles. Should have been: **TSE at 1.5x visual weight**, color-coded red, sorted to top.

---

## 8-Hour Fatigue Factors

### Fatigue #1: The "Hunting" Game

Staring for 4+ hours, your brain stops pattern-matching the layout and treats each item as a new puzzle. The exchange name (TOK, HKG, SHA) and time-until (9m, 1h39m, 36m) aren't spatially consistent, so you can't build muscle memory. You have to consciously read every row.

**Exposure**: This gets worse as more exchanges activate (5-6 active means more visual searching).

### Fatigue #2: Bar Fills as False Precision

Green bars normalize at visual attention — they're all "full" until they're "empty." The jump from 11 cells green to 10 cells green is hard to track. After 3 hours, you're ignoring bars and reading timestamps.

### Fatigue #3: Color Monotony

All green (open), all green (open), all green (open). Context switches to NEXT and you see gray circles (unopened). No intermediate state (e.g., "closing in <15m" → yellow/orange). The UI feels binary, not graduated.

### Fatigue #4: NEXT Section Anchoring Drift

The NEXT section starts out "informative" but by hour 6, you realize you're not using it. You're re-reading the same 3 exchanges that were listed at hour 1. The section feels stale; you have to consciously remember it updates.

---

## Power Use Feature Requests (Prioritized)

### 1. **Time-Based Sorting + Color Gradient (CRITICAL)**

Sort ACTIVE by time-until-close ascending (closest first). Color gradient: >30m = dim green, 15-30m = bright green, 5-15m = yellow, <5m = red. Reduces scanning from 2s to 0.3s. This is the biggest lever.

### 2. **"Pinned" Exchange Slots (HIGH)**

Allow user to pin 2-3 exchanges to the top (e.g., "I always care about TSE and EUX first"). Pinned items always appear first, others sort by time. Eliminates mental re-sorting.

### 3. **Numeric Time Remaining + Bar Cell Count in Seconds (HIGH)**

Display time as "9m 30s" (vs "9m"), and scale BarCells so each cell = 5 seconds (not whatever variable scale exists now). Removes ambiguity on sub-minute closes and makes bar micro-movements meaningful.

### 4. **Exchange Visibility Toggle (MEDIUM)**

Hide specific exchanges from ACTIVE view (e.g., "I don't trade LSE right now"). Reduces visual clutter and scanning surface area. NEXT still shows them, but they're deprioritized.

### 5. **Volume/Tick Density Indicator (MEDIUM)**

Add a micro-badge next to exchange names: "HIGH VOL" if liquidity is high, "LOW VOL" if tight spreads. Helps triage which exchanges are worth trading into during crush hours. One-character visual cue (e.g., "📊" or a small histogram).

---

## Conclusion

**Density settings work and should stay at max (BarCells=12, NextCount=5).** But the next 5x efficiency gain comes from _information ranking_, not _display capacity_. The power user doesn't want "more stuff on screen" — they want "the right stuff in the right order, color-coded by urgency."

Current design serves casual monitoring. Power use needs time-as-sort-key, color-as-risk-signal, and control over visual focus.
