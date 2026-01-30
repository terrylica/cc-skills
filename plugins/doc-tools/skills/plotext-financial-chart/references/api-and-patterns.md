# Plotext Financial Chart — API and Patterns Reference

## Core API

```python
import re
import plotext as plt

# Data
x = list(range(20))
y = [100, 101, 102, 101, 100, 99, 98, 99, 100, 101, 102, 103, 102, 101, 100, 99, 100, 101, 102, 101]

# Setup
plt.clear_figure()
plt.plot(x, y, marker="dot", label="Price path")
plt.title("Chart Title")
plt.xlabel("Time (bars)")
plt.ylabel("Price")
plt.plotsize(65, 22)         # Width x Height in characters
plt.theme("clear")

# Horizontal reference lines (barriers, thresholds)
plt.hline(103)               # Upper barrier
plt.hline(97)                # Lower barrier
plt.hline(100)               # Entry price

# Build and strip ANSI
output = re.sub(r'\x1b\[[0-9;]*m', '', plt.build())
print(output)
```

## Key Functions

| Function             | Purpose                        | Example                              |
| -------------------- | ------------------------------ | ------------------------------------ |
| `plt.plot(x, y)`     | Plot a line series             | `plt.plot(x, y, marker="dot")`       |
| `plt.hline(value)`   | Horizontal reference line      | `plt.hline(103)` for upper barrier   |
| `plt.title(text)`    | Chart title                    | `plt.title("Triple Barrier Method")` |
| `plt.xlabel(text)`   | X-axis label                   | `plt.xlabel("Time (bars)")`          |
| `plt.ylabel(text)`   | Y-axis label                   | `plt.ylabel("Price")`                |
| `plt.plotsize(w, h)` | Chart dimensions in characters | `plt.plotsize(65, 22)`               |
| `plt.theme("clear")` | Strip color/formatting         | Always use for markdown output       |
| `plt.clear_figure()` | Reset state before new chart   | Call before every chart              |
| `plt.build()`        | Return chart as string         | Use instead of `plt.show()`          |

## Chart Patterns

### Triple Barrier Method

```python
import re
import plotext as plt

x = list(range(20))
y = [97, 98, 100, 101, 100, 98, 100, 101, 102, 101, 100, 98, 100, 101, 102, 103, 102, 101, 100, 100]

plt.clear_figure()
plt.plot(x, y, marker="dot", label="Price path")
plt.hline(103)    # Upper barrier (+pt x sigma)
plt.hline(97)     # Lower barrier (-sl x sigma)
plt.hline(100)    # Entry price
plt.title("Triple Barrier Method")
plt.xlabel("Time (bars)")
plt.ylabel("Price")
plt.plotsize(65, 22)
plt.theme("clear")
output = re.sub(r'\x1b\[[0-9;]*m', '', plt.build())
```

### Price Path with Moving Average

```python
import re
import plotext as plt

x = list(range(30))
price = [100, 101, 103, 102, 104, 103, 105, 104, 106, 105,
         107, 106, 105, 104, 103, 102, 101, 100, 99, 98,
         97, 98, 99, 100, 101, 102, 103, 104, 105, 106]
# Simple moving average (window=5)
ma = [None]*4 + [sum(price[i-4:i+1])/5 for i in range(4, 30)]

plt.clear_figure()
plt.plot(x, price, marker="dot", label="Price")
plt.plot(x[4:], ma[4:], marker="dot", label="SMA(5)")
plt.title("Price with Moving Average")
plt.xlabel("Time")
plt.ylabel("Price")
plt.plotsize(65, 18)
plt.theme("clear")
output = re.sub(r'\x1b\[[0-9;]*m', '', plt.build())
```

### Range Bar Threshold Visualization

```python
import re
import plotext as plt

x = list(range(15))
price = [100, 100.5, 101, 101.5, 102, 102.5, 102, 101.5, 101, 100.5, 100, 99.5, 99, 99.5, 100]

plt.clear_figure()
plt.plot(x, price, marker="dot", label="Price")
plt.hline(102.5)
plt.hline(97.5)
plt.title("Range Bar Threshold (250 dbps)")
plt.xlabel("Ticks")
plt.ylabel("Price")
plt.plotsize(50, 15)
plt.theme("clear")
output = re.sub(r'\x1b\[[0-9;]*m', '', plt.build())
```

## Size Guidelines

| Context              | plotsize   | Notes                              |
| -------------------- | ---------- | ---------------------------------- |
| Inline in markdown   | `(65, 22)` | Standard — fits 80-col code blocks |
| Wide markdown        | `(80, 22)` | For repos with wide code blocks    |
| Compact / sidebar    | `(40, 15)` | Smaller illustrations              |
| Detailed / full page | `(80, 30)` | Maximum detail for complex charts  |

## Embedding in Markdown

### Template (MANDATORY: Source Immediately After Chart)

Every rendered chart MUST be followed **immediately** by a collapsible `<details>` block containing the Python source code. This is non-negotiable for:

- **Reproducibility**: Future maintainers can regenerate the chart
- **Editability**: Data or styling can be modified and re-rendered
- **Auditability**: Changes to charts are trackable in git diffs

### Ordering Convention (CRITICAL)

The `<details>` block MUST be **immediately adjacent** to the chart — no explanatory text between them:

```
✅ CORRECT ORDER:
   1. Chart (code block)
   2. <details> with source (immediately after)
   3. Explanatory text (after <details>)

❌ WRONG ORDER:
   1. Chart (code block)
   2. Explanatory text
   3. <details> with source
```

**Why**: The source code is part of the chart artifact. When explanatory text is inserted between chart and source, future edits risk separating or losing the reproducibility information. Keeping them adjacent ensures the chart + source travel together through document edits.

### Complete Example

````markdown
## Triple Barrier Method

```
                        Triple Barrier Method
   ┌────────────────────────────────────────────────────────────┐
103├ •• Price path ────────────────────────────────•────────────┤
   │                                              • •           │
   ...
 97├•───────────────────────────────────────────────────────────┤
   └┬──────────────┬──────────────┬─────────────┬──────────────┬┘
   0.0            4.8            9.5          14.2          19.0
Price                        Time (bars)
```

<details>
<summary>plotext source</summary>

```python
import re
import plotext as plt

x = list(range(20))
y = [97, 98, 100, 101, 100, 98, 100, 101, 102, 101,
     100, 98, 100, 101, 102, 103, 102, 101, 100, 100]

plt.clear_figure()
plt.plot(x, y, marker="dot", label="Price path")
plt.hline(103)
plt.hline(97)
plt.hline(100)
plt.title("Triple Barrier Method")
plt.xlabel("Time (bars)")
plt.ylabel("Price")
plt.plotsize(65, 22)
plt.theme("clear")
print(re.sub(r'\x1b\[[0-9;]*m', '', plt.build()))
```

</details>

The triple barrier method (de Prado, AFML Ch. 3) uses three barriers:

- **Upper barrier**: Take-profit level at +pt × σ
- **Lower barrier**: Stop-loss level at -sl × σ
- **Vertical barrier**: Maximum holding period of h bars

This chart shows a price path that experiences drawdown (MAE) before
recovering to hit the upper barrier (MFE).
````

**The `<details>` block is MANDATORY and must be immediately after the chart** — never insert explanatory text between them.

### GFM Collapsible Section Rules

1. **Blank lines required** — Must have empty line after `<summary>` and before `</details>` for Markdown to render
2. **No indentation** — `<details>` and `<summary>` must be at column 0
3. **Summary text** — Always use `plotext source` for consistency

## Success Criteria

### Correctness

1. **Renders without error** — Python script runs cleanly
2. **Data accurate** — All data points and reference lines visible
3. **No ANSI codes** — Output is pure text (no color escapes)
4. **Source preserved (MANDATORY)** — `<details>` block with runnable Python source

### Aesthetics

1. **Dot marker only** — `•` characters render at correct width on GitHub
2. **Readable labels** — Title, axis labels, legend visible
3. **Appropriate size** — Chart fits code block without horizontal scroll
4. **Clean diagonals** — Dot marker produces recognizable slope patterns

### Portability

1. **GitHub rendering** — Correct alignment in GitHub markdown preview
2. **Terminal rendering** — Correct in iTerm2, Kitty, VS Code terminal
3. **Editor rendering** — Correct in VS Code, vim, any monospace editor
4. **No font dependencies** — Dot marker works in any monospace font
