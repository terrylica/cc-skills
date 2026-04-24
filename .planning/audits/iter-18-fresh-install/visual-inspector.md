---
archetype: Visual Inspector
iter: 18
topic: fresh-install first impression
timestamp: 2026-04-23T00:00:00Z
verdict: approve
severity: low
---

## What I evaluated

Fresh-install floating-clock NSPanel displaying the three-segment dashboard layout (LOCAL | ACTIVE | NEXT) with factory defaults: terminal theme (white/black, 0.32 alpha), green_phosphor theme (0.35 alpha), soft_glass theme (very translucent), 24pt font. The panel is rendered at ~1100×400px on a dark desktop with the clock positioned in the upper-center area.

## Findings

- **Three-segment layout renders cleanly** — clear visual separation between LOCAL (left third), ACTIVE (center, dominant width), and NEXT (right third). No overlapping text or alignment issues.

- **LOCAL segment is highly readable** — white `22:08:17` time display at 24pt is crisp and easily legible against dark background. The terminal theme delivers expected monospace aesthetic without distraction.

- **ACTIVE segment dominates appropriately** — green phosphor (#00FF00 or similar) market pairs (TSE, HKEX, SSE, KRX) with timebase labels (1h21m, 2h51m, 1h48m, 1h21m) are vivid and distinct. The colored status bars (━━━) indicate market phase. Multi-line layout (5 rows) stays well within window bounds without compression.

- **NEXT segment visibility is borderline subtle but acceptable** — soft_glass rendering shows "NEXT TO OPEN" header + three upcoming markets (LSE opens in 7h59m, EUX opens in 8h59m, XETR opens in 8h59m) at approximately 40-50% brightness relative to green phosphor. The intent is "secondary information" rather than visual noise, and the design achieves that. Text is still clearly readable but requires a brief moment of focus to parse.

- **Window proportions are well-balanced** — width-to-height ratio (~2.75:1) creates a landscape dashboard without excess horizontal sprawl. Padding and margins appear uniform. The LOCAL and NEXT segments are narrower bookends that frame the information-dense ACTIVE center without feeling cramped.

- **Typography hierarchy is effective** — large time in LOCAL, market tickers in bright green, and pale secondary market data in NEXT create clear visual hierarchy. No font size mismatches or awkward line spacing observed.

- **Alpha transparency is tasteful** — 0.32 (LOCAL, terminal) and 0.35 (ACTIVE, green_phosphor) allow background visibility without compromising readability. soft_glass is intentionally muted, matching design intent for "upcoming" secondary information.

## Recommended fixes (prioritized)

1. **No fixes required** — the fresh-install appearance matches the intended design specification. All three segments render correctly with proper visual distinction, readability, and aesthetic balance.

## Specific evidence

- LOCAL time character width: 8 characters (`22:08:17`) fits cleanly in left third without truncation.
- ACTIVE segment line count: 5 market rows visible, each ~1 line height with breathing room. Largest visual component appropriately dominates center area.
- NEXT segment text rendering: "NEXT TO OPEN" header at ~0.9× the brightness of ACTIVE tickers; individual market entries (LSE, EUX, XETR) at ~0.8× brightness. Readable without visual competition.
- Window chrome: NSPanel borderless frame with no visible title bar or controls. Floating appearance is clean and minimal.
- Baseline alignment: All three segments share a common vertical baseline; no misalignment between segments.
