← [Back to plugin CLAUDE.md](../CLAUDE.md)

# Solar canvas + segment styling levers

SSoT for the 2026-06-11 styling arc: the solar-elevation canvas color ramp
(`CanvasColorMode`) and the hairline segment border (`BorderStyle`).

## Solar canvas (`CanvasColorMode`, 2026-06-11)

"Colorful, not transparent": the COMPACT modes' background derives from the
CONTINUOUS solar elevation at the user's real location — authoritative
ephemeris math, nothing scheduled by clock hours.

- `Sources/data/SolarEvents.m` gained `FCSolarElevationDegrees` (SunCalc/
  Meeus sun position; same lineage as the event calculator so glyph and
  canvas can never disagree). Locality = the CoreLocation fix cached by
  `FCLocationProvider` (same `Latitude`/`Longitude` defaults the sky glyph
  reads); pre-fix fallback = coarse local-hour sinusoid.
- `Sources/core/SolarSkyColorRamp.{h,m}`: OKLab ramp keyed to international
  twilight standards (−18/−12/−6/−4/0/+6/+20/+50°). Two styles (locked by
  test_levers): `solar-vivid` (DEFAULT — LCh polar interpolation, constant
  chroma; day-side hue arc runs UP through green/cyan 440→605 because the
  descending arc retraced magenta and made mid-morning purple — preview-
  validated with an ANSI swatch harness) and `solar-atmospheric` (Cartesian
  Lab interpolation — warm→blue crossfades desaturate through neutral like
  the real sky). Menu: Display → Canvas Color; registered default
  solar-vivid; threaded through all 8 starter profiles.
- Painting: the ROUNDED contentView layer, NOT the window background (the
  window rect extends past the corner radius — square patches, user-caught).
  Three-segment + theme paths clear the layer fill/border so nothing leaks
  across mode switches. 1Hz evolution in tick, 8-bit-quantized.
- Text: `Sources/rendering/SolarOutlinedTextRenderingView.{h,m}` — Core
  Text, white fill + ROUND-JOIN black outline (2.2pt), replaces `_label`
  while solar is active (`_label` stays populated for sizeToFit). Rejected on
  the way (all user-caught on-screen): negative NSStrokeWidth eats the fill
  from inside; positive-stroke underlay field has NO join control → miter
  spikes on descenders; CTLineDraw fills with the RUN color (black) unless
  `kCTForegroundColorFromContextAttributeName` opts into context colors.
  Optical alignment user-tuned: lift 1.5pt, left-shift 2.0pt.
- Location staleness bug (found during this work): `FCLocationProvider
kickoff` ran only at launch and `requestLocation` failures are silent →
  coords stranded on a 7-week-old fix from another city. Fixed: hourly
  re-kick from tick (self-gates on the 24h freshness check). NOTE: changing
  the code-signing identity RESETS TCC grants — Location (and Bluetooth)
  each need one re-Allow after the stable-identity migration (see
  [signing-and-tcc.md](./signing-and-tcc.md)).

## Hairline segment border (`BorderStyle`, 2026-06-11)

The audio bar's edge recipe promoted to the clock pills. Catalog dispatcher
`Sources/core/SegmentBorderSpec.{h,m}` (locked by test_levers), applied in
BOTH layout families via `FCApplyBorderToLayer` (FloatingClockPanel+Layout.m):
the three-segment pills AND the compact local-only/single-market modes, where
the window contentView IS the pill (first ship missed those — user caught the
bare double-click-shrunk view; three-segment clears the contentView border so
mode switches never leak a stale frame). Color is luminance-adaptive per
segment theme bg: white @ alpha on dark fills, black @ alpha+0.08 on light.
Menu: context menu → Display → Border. Presets: `none` / `hairline` (1pt @
0.22, DEFAULT — registered in clock.m, threaded through all 8 starter
profiles; Minimalist=none, Auction Watcher=frame) / `frame` (1.5pt @ 0.35).
