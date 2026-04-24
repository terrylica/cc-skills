---
archetype: Novice User
iter: 18
topic: fresh-install first-30-seconds
timestamp: 2026-04-23T00:00:00Z
verdict: flag
severity: medium
---

## What I evaluated

I just installed floating-clock expecting a simple, elegant clock widget for my Mac. When I launch it, I see a dark floating panel with three distinct sections. The left shows "22:08:17" in large white numbers. The middle has a bunch of ticker symbols I don't recognize (TOK, TSE, HKG, SHA, SEO, KRX, MUM) with green bars and times. The right says "NEXT TO OPEN" with stock exchanges (LSE, EUX, XETR) and countdown timers. My first thought: "What... is all this?" I installed a clock, not a trading dashboard.

## Findings

- **Clock is buried in ambiguity** — The local time (22:08:17) is clear and readable, but there's zero visual hierarchy. The three segments are crammed into one dark panel with no dividers, labels, or color separation. A novice sees "market data" immediately and questions whether this is even a clock app.

- **Market data unexplained** — TOK, TSE, HKG, SHA, SEO, KRX, MUM are all ticker codes. I don't know what these are or why they're important to me. The green bars suggest "status" but status of what? Are these price movements? Open/close indicators? The "1h21m" durations next to them — are those trading hours remaining? Time until open?

- **Right segment label is jargon** — "NEXT TO OPEN" makes sense if you trade forex, but I'm a casual user. I don't immediately grasp that this is showing me _when_ markets I apparently care about will open. No context about why _these_ markets specifically. Are they suggested? Did I choose them? Should I be able to change them?

- **No visual separation or affordance** — Three columns are packed together with minimal spacing. No subtle background color differences, no vertical dividers, no section headers like "Local Time | Active Markets | Upcoming Openings". They blur together visually. This is not immediately recognizable as a multi-purpose widget.

- **No hint to customize** — There's zero indication I can right-click to change settings. No question mark icon, no "?" on hover, no tiny help text. If I wanted to remove the markets and see only the clock, I'd have to discover the context menu by accident.

- **Colors are monochrome** — Everything is dark gray/black with bright green text. The green is used for the status indicator dots and bars, but there's no other visual language to differentiate the three segments. The layout feels utilitarian rather than elegant.

- **Delight: The clock itself is crisp** — When I focus on the left side, 22:08:17 in large white monospace is genuinely beautiful and easy to read at a glance. This is what I expected when I installed the app.

## Recommended fixes (prioritized)

1. **Add subtle visual separators and section headers** — Use faint vertical dividers or slightly different background shades (e.g., three shades of dark gray) and place tiny, muted labels above each section: "LOCAL TIME", "ACTIVE MARKETS", "NEXT TO OPEN". This immediately clarifies what the user is looking at.

2. **Add a tooltip or "?" icon** — A small help icon on first launch or visible somewhere in the panel that explains: "Right-click to customize markets" or "Click the gear icon for settings." Novices should not have to discover features by accident.

3. **Simplify or contextualize market data** — For a fresh install, show only the clock by default, or provide an onboarding flow that asks "Which markets interest you?" before populating the widget. Alternatively, add a one-sentence label explaining why these markets are shown (e.g., "Your tracked exchanges").

4. **Increase visual hierarchy** — Make the clock larger or give it more breathing room. The market data should feel supplementary, not co-equal in prominence. Consider font size, spacing, or opacity to reinforce that this is primarily a clock.

5. **Color code the segments** — Use three distinct (but harmonious) color schemes: cool tones for the clock, warm tones for active markets, neutral for upcoming. This makes the three-part layout instantly recognizable.

## Specific evidence

The screenshot shows the three segments crammed into a 1000px-wide panel with no spacing or hierarchy. The local time is clear, but adjacent market tickers in the same typeface and size make it feel like one jumbled information wall. A novice's brain has to work to parse "oh, there are three _different_ things here" rather than having that structure immediately evident.

The absence of any text label above or within each section is the critical issue. "LOCAL TIME | ACTIVE MARKETS | NEXT TO OPEN" would transform user comprehension from "What is this?" to "Oh, I see" in under one second.
