# Tool Selection Rationale

## Evaluation Summary

Evaluated 6 ASCII/text chart tools for rendering financial line charts in GitHub Flavored Markdown. The primary use case is triple barrier diagrams, price paths with barriers/thresholds, and range bar visualizations.

## Tools Evaluated

| Tool         | Type           | Output          | Install       |
| ------------ | -------------- | --------------- | ------------- |
| asciichartpy | Python library | Plain ASCII     | `pip`         |
| plotille     | Python library | Braille Unicode | `pip`         |
| plotext      | Python library | Configurable    | `pip`         |
| svgbob       | Rust CLI       | SVG             | `cargo`       |
| GoAT         | Go CLI         | SVG             | `go install`  |
| Ascidia      | Python CLI     | PNG/SVG         | `pip + cairo` |

## Detailed Comparison

### asciichartpy

- **Output**: Plain ASCII box-drawing characters (`╭╮│╯╰`)
- **Diagonals**: Staircase only — slopes rendered as vertical steps
- **GitHub**: Renders correctly (pure ASCII)
- **Verdict**: No true diagonals, no x-axis labels, no title support
- **Rating**: 2/5

### plotille

- **Output**: Braille Unicode dots (U+2800-U+28FF)
- **Diagonals**: True smooth slopes via 2x4 Braille sub-pixels
- **GitHub**: Misaligned — Braille characters render at wrong width in GitHub's font
- **Verdict**: Font-dependent, Y-axis labels have too many decimals
- **Rating**: 4/5 (terminal), 2/5 (GitHub)

### plotext (SELECTED)

- **Output**: Configurable — dot, HD blocks, Braille, FHD
- **Diagonals**: Depends on marker mode
- **GitHub**: Dot and HD markers align correctly; Braille and FHD do not
- **Verdict**: Best overall — matplotlib-like API, all features needed
- **Rating**: 5/5

**Marker mode evaluation within plotext:**

| Marker    | Resolution | GitHub Aligned | Font Dependent      |
| --------- | ---------- | -------------- | ------------------- |
| `dot` (•) | 1x1        | Yes            | No                  |
| `hd` (▞)  | 2x2        | Yes            | No                  |
| `braille` | 4x2        | No             | Yes                 |
| `fhd`     | 3x2        | No             | Yes (Unicode 13.0+) |

**Selected**: `dot` marker — universal alignment, zero font dependencies.

### svgbob (Rust CLI)

- **Output**: SVG vector graphics from ASCII input
- **Diagonals**: True smooth SVG lines
- **GitHub**: SVG not embeddable in markdown code blocks
- **Verdict**: Excellent for SVG documents, not for inline markdown
- **Parentheses issue**: Renders `()` as SVG arcs
- **Rating**: 5/5 (SVG), 0/5 (markdown code blocks)

### GoAT (Go CLI)

- **Output**: SVG vector graphics from ASCII input
- **Diagonals**: True smooth SVG polylines
- **GitHub**: SVG not embeddable in markdown code blocks
- **Verdict**: Better than svgbob (handles parentheses correctly, dark mode)
- **Rating**: 5/5 (SVG), 0/5 (markdown code blocks)

### Ascidia (Python CLI)

- **Output**: PNG/SVG from ASCII input
- **Dependencies**: Requires system cairo library (`brew install cairo`)
- **Diagonals**: True image lines with dashed diagonal support
- **GitHub**: Image output, not text
- **Verdict**: Heavy dependencies, less maintained
- **Rating**: 3/5

## Font Compatibility Research

### The Braille Problem

Braille Unicode characters (U+2800-U+28FF) require fonts with native monospace Braille glyphs. When a font lacks these, the OS falls back to a different font with different glyph metrics, causing horizontal misalignment.

**Fonts with native Braille support:**

- DejaVu Sans Mono
- Iosevka Term
- Hack
- Menlo (macOS, based on DejaVu)

**Fonts lacking Braille:**

- JetBrains Mono (open issue #630)
- Fira Code (partial, relies on fallback)

**GitHub's font stack**: `ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas, Liberation Mono, monospace`

GitHub uses SF Mono / Menlo on macOS, which has Braille support, but alignment still varies across platforms and browsers. The dot marker (`•`) avoids this problem entirely.

### Why Dot Marker Wins

The bullet character `•` (U+2022) is:

1. Present in every monospace font
2. Rendered at correct character cell width universally
3. Not affected by font fallback mechanisms
4. Visually distinct as a data point

Trade-off: Lower resolution (1x1 per cell vs 4x2 for Braille), but universal alignment is more important for documentation.

## Decision

**Tool**: plotext
**Marker**: `dot` (•)
**Rationale**: Best API (matplotlib-like), all chart features needed (title, axes, hlines, legend), universal GitHub alignment with dot marker, no font dependencies.
