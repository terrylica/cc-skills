# DSL Syntax Reference

## Basic Elements

```
# Nodes (square brackets)
[Node Name]

# Edges (arrows)
[A] -> [B]

# Labeled edges
[A] -- label --> [B]

# Bidirectional
[A] <-> [B]

# Chain
[A] -> [B] -> [C]
```

## Groups (Containers)

```
# Named group with dashed border
( Group Name:
  [Node A]
  [Node B]
)

# Nested connections
( Frontend:
  [React App]
  [API Client]
)
( Backend:
  [API Server]
  [Database]
)
[API Client] -> [API Server]
```

## Node Labels

```
# Custom label (different from ID)
[db] { label: "PostgreSQL Database"; }

# ASCII markers for visual distinction INSIDE boxes
# (emojis break box alignment - use ASCII markers instead)
[deleted] { label: "[x] Old Component"; }
[added] { label: "[+] New Component"; }
[warning] { label: "[!] Deprecated"; }
[success] { label: "[OK] Passed"; }
```

**Character rules for nodes:**

- Graphical emojis (rocket, bulb, checkmark) - NEVER (double-width breaks box alignment)
- Unicode symbols (check, cross, arrow) - OK (single-width, safe)
- ASCII markers ([x] [+] [!] :) ) - ALWAYS safe (monospace)

Use `graph { label: "..."; }` for graphical emojis in title/legend.

**Example: Emoji breaks alignment (DON'T DO THIS)**

```
# BAD - emoji inside node
[rocket] { label: "Launch"; }
```

Renders broken:

```
+----------------+
| Launch         |   <-- box edge misaligned due to double-width emoji
+----------------+
```

**Example: ASCII marker preserves alignment (DO THIS)**

```
# GOOD - ASCII marker inside node
[rocket] { label: "[>] Launch"; }
```

Renders correctly:

```
+--------------+
| [>] Launch   |
+--------------+
```

## Flow Direction (MANDATORY: Always specify)

```
# MANDATORY: Always specify flow direction explicitly
graph { flow: south; }   # Top-to-bottom (architecture, decisions)
graph { flow: east; }    # Left-to-right (pipelines, sequences)
```

Never rely on default flow - explicit is clearer.

## Graph Title and Legend (Outside Boxes - Emojis Safe Here)

Emojis break alignment INSIDE boxes but are SAFE in graph titles/legends.

**Emoji Selection Guide** - Choose emoji that matches diagram purpose:

| Diagram Type             | Emoji  | Example Title           |
| ------------------------ | ------ | ----------------------- |
| Migration/Change         | swap   | `"Database Migration"`  |
| Deployment/Release       | rocket | `"Deployment Pipeline"` |
| Data Flow                | chart  | `"Data Ingestion Flow"` |
| Security/Auth            | lock   | `"Authentication Flow"` |
| Error/Failure            | warn   | `"Error Handling"`      |
| Decision/Branch          | split  | `"Routing Decision"`    |
| Architecture             | build  | `"System Architecture"` |
| Network/API              | globe  | `"API Integration"`     |
| Storage/Database         | disk   | `"Storage Layer"`       |
| Monitoring/Observability | signal | `"Monitoring Stack"`    |

```
# Title with semantic emoji
graph { label: "Deployment Pipeline"; flow: east; }

# Title with legend (multiline using \n)
graph { label: "Hook Flow\n----------\nAllow  Deny  Warn"; flow: south; }
```

## Node Styling (Best Practices)

```
# Rounded corners for start/end nodes
[ Start ] { shape: rounded; }
[ End ] { shape: rounded; }

# Double border for emphasis
[ Critical Step ] { border: double; }

# Bold border for important nodes
[ Key Decision ] { border: bold; }

# Dotted border for optional/skippable
[ Optional ] { border: dotted; }

# Multiline labels with \n
[ Hook Input\n(stdin JSON) ]
```

**Rendered examples:**

```
+----------+              +---------+
| Rounded  |              | Default |
+----------+              +---------+

+==========+              +=========+
| Double   |              |  Bold   |
+==========+              +=========+
```

> **Note:** Dotted borders (`{ border: dotted; }`) use special characters that render inconsistently on GitHub. Use sparingly.

## Edge Styles

```
[ A ] -> [ B ]      # Solid arrow (default)
[ A ] ..> [ B ]     # Dotted arrow
[ A ] ==> [ B ]     # Bold/double arrow
[ A ] - -> [ B ]    # Dashed arrow
[ A ] -- label --> [ B ]  # Labeled edge
```
