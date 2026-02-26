---
name: graph-easy
description: Create ASCII diagrams for markdown using graph-easy. TRIGGERS - ASCII diagram, graph-easy, architecture diagram, markdown diagram.
allowed-tools: Bash, Read, Write, Edit
---

# Graph-Easy Diagram Skill

Create ASCII architecture diagrams for any GitHub Flavored Markdown file using graph-easy. Pure text output with automatic layout - no image rendering required.

## When to Use This Skill

- Adding diagrams to README files
- Design specification documentation
- Any GFM markdown file needing architecture visualization
- Creating flowcharts, pipelines, or system diagrams
- User mentions "diagram", "ASCII diagram", "graph-easy", or "architecture chart"

**NOT for ADRs** - Use `adr-graph-easy-architect` for Architecture Decision Records (includes ADR-specific patterns like 2-diagram requirement and before/after templates).

## Preflight Check

Ensure graph-easy is installed and functional before rendering. See [Preflight Check](./references/preflight-check.md) for the full layered installation guide (mise-first approach, macOS + Linux).

**Quick verify:**

```bash
echo "[Test] -> [OK]" | graph-easy &>/dev/null && echo "✓ graph-easy ready"
```

---

## DSL Quick Reference

Full syntax reference: [DSL Syntax](./references/dsl-syntax.md)

### Essentials

```
[Node] -> [Node]              # Basic edge
[A] -- label --> [B]          # Labeled edge
[A] <-> [B]                   # Bidirectional
( Group: [Node A] [Node B] )  # Container
[n] { label: "Display Name"; }  # Custom label
```

### Mandatory Graph Attributes

```
graph { label: "Title"; flow: south; }   # Top-to-bottom
graph { label: "Title"; flow: east; }    # Left-to-right
```

- **Every diagram MUST have** `label:` with semantic emoji + title
- **Every diagram MUST have** explicit `flow:` direction

### Character Safety

| Location     | Graphical Emojis | Unicode Symbols | ASCII Markers |
| ------------ | ---------------- | --------------- | ------------- |
| Inside nodes | NEVER            | OK              | ALWAYS safe   |
| Graph label  | SAFE             | OK              | OK            |

ASCII markers: `[x]` `[+]` `[!]` `[OK]` `[>]` `[*]` `[~]` `[?]` `[=]`

### Node & Edge Styling

| Style         | Syntax                | Use For               |
| ------------- | --------------------- | --------------------- |
| Rounded       | `{ shape: rounded; }` | Start/end nodes       |
| Double border | `{ border: double; }` | Critical/emphasis     |
| Bold border   | `{ border: bold; }`   | Important nodes       |
| Dotted border | `{ border: dotted; }` | Optional (GH caution) |
| Solid arrow   | `->` / `<->`          | Normal/happy path     |
| Dotted arrow  | `..>`                 | Conditional/alternate |
| Bold arrow    | `==>`                 | Critical path         |

---

## Common Patterns

See [Diagram Patterns](./references/diagram-patterns.md) for full examples (pipeline, multi-component, decision, grouped, bidirectional, layered architecture).

**Quick templates:**

```
# Pipeline (left-to-right)
graph { label: "Pipeline"; flow: east; }
[Input] -> [Process] -> [Output]

# Multi-component (top-down)
graph { label: "System"; flow: south; }
[Gateway] -> [Service A]
[Gateway] -> [Service B]
[Service A] -> [Database]
[Service B] -> [Database]
```

---

## Rendering

### Command (Platform-Aware)

```bash
# For GitHub markdown (RECOMMENDED) - renders as solid lines
graph-easy --as=ascii << 'EOF'
graph { flow: south; }
[A] -> [B] -> [C]
EOF

# For terminal/local viewing - prettier Unicode lines
graph-easy --as=boxart << 'EOF'
graph { flow: south; }
[A] -> [B] -> [C]
EOF
```

### Output Modes

| Mode     | Command       | When to Use                                                     |
| -------- | ------------- | --------------------------------------------------------------- |
| `ascii`  | `--as=ascii`  | **GitHub markdown** - `+--+` renders as solid lines everywhere  |
| `boxart` | `--as=boxart` | **Terminal only** - `┌──┐` looks nice locally, dotted on GitHub |

**Why ASCII for GitHub?** GitHub renders Unicode box-drawing characters (`┌─┐│└─┘`) as dotted lines. Pure ASCII (`+---+`, `|`) renders correctly everywhere.

### Post-Generation Alignment Validation (Recommended)

After embedding, validate with: `Skill(doc-tools:ascii-diagram-validator)`

- Catches copy-paste alignment drift and font rendering issues
- Skip if diagram was just generated and not manually edited

---

## Embedding in Markdown

Full guide with GFM collapsible section syntax: [Embedding Guide](./references/embedding-guide.md)

**CRITICAL: Every diagram MUST include a `<details>` source block.** This is non-negotiable.

````markdown
## Architecture

```
+----------+     +----------+     +----------+
|  Input   | --> | Process  | --> |  Output  |
+----------+     +----------+     +----------+
```

<details>
<summary>graph-easy source</summary>

```
graph { flow: east; }
[Input] -> [Process] -> [Output]
```

</details>
````

---

## Monospace-Safe Symbols

Full reference: [Monospace Symbols](./references/monospace-symbols.md)

Key markers: `[+]` Added | `[x]` Removed | `[*]` Changed | `[!]` Warning | `[>]` Active

---

## Graph Label (MANDATORY: EVERY diagram MUST have emoji + title)

**WARNING**: This is the most commonly forgotten requirement. Diagrams without labels are invalid.

### Correct Example

```
graph { label: "Deployment Pipeline"; flow: east; }
[Build] -> [Test] -> [Deploy]
```

### Anti-Pattern (INVALID - DO NOT DO THIS)

```
graph { flow: east; }
[Build] -> [Test] -> [Deploy]
```

**Why this is wrong**: Missing `label:` with emoji. Every diagram needs context at a glance.

---

## Mandatory Checklist (Before Rendering)

### Graph-Level (MUST have)

- [ ] **`graph { label: "Title"; }`** - semantic emoji + title (MOST FORGOTTEN - check first!)
- [ ] `graph { flow: south; }` or `graph { flow: east; }` - explicit direction
- [ ] Command uses `--as=ascii` for GitHub markdown (or `--as=boxart` for terminal only)

### Embedding (MUST have - non-negotiable)

- [ ] **`<details>` block with source** - EVERY diagram MUST have collapsible source code block
- [ ] Never commit a diagram without its reproducible source

### Post-Embedding Validation (Recommended)

- [ ] Run `ascii-diagram-validator` on the file after embedding diagram
- [ ] Especially important if diagram was manually edited after generation

### Node & Edge Styling

- [ ] Start/end: `{ shape: rounded; }` | Critical: `{ border: double; }` | Optional: `{ border: dotted; }`
- [ ] Main path: `->` | Conditional: `..>` | Critical: `==>` | Labels: 1-3 words
- [ ] NO graphical emojis inside nodes; emojis ONLY in `graph { label: "..."; }`

### Structure

- [ ] Groups `( Name: ... )` for 4+ related nodes
- [ ] Node IDs short, labels descriptive: `[db] { label: "PostgreSQL"; }`
- [ ] Max 7-10 nodes per diagram (split if larger)

## Success Criteria

### Correctness

1. **Parses without error** - graph-easy accepts the DSL
2. **Renders cleanly** - no misaligned boxes or broken lines
3. **Matches content** - all key elements from description represented
4. **Source preserved (MANDATORY)** - EVERY diagram MUST have `<details>` block with graph-easy DSL source

### Aesthetics

1. **Platform-appropriate output** - `--as=ascii` for GitHub, `--as=boxart` for terminal
2. **Readable labels** - multiline with `\n`, no truncation
3. **Clear flow** - direction matches natural reading (top-down or left-right)
4. **Consistent styling** - same border style = same semantic meaning throughout

### Comprehensiveness

1. **Edge semantics** - solid=normal, dotted=conditional, bold=critical
2. **Logical grouping** - related nodes in `( Group: ... )` containers

## Troubleshooting

| Issue               | Cause                    | Solution                                               |
| ------------------- | ------------------------ | ------------------------------------------------------ |
| `command not found` | graph-easy not installed | Run [preflight check](./references/preflight-check.md) |
| Dotted lines on GH  | Used `--as=boxart`       | Use `--as=ascii` for GitHub markdown                   |
| Box border broken   | Graphical emoji in node  | Remove emojis, use ASCII markers [x][+]                |
| Nodes overlap       | Too complex              | Split into multiple diagrams (max 7-10 nodes)          |
| Edge labels cut off | Label too long           | Shorten to 1-3 words                                   |
| No title showing    | Wrong syntax             | Use `graph { label: "Title"; flow: south; }`           |
| Weird layout        | No flow direction        | Add `graph { flow: south; }` or `flow: east`           |
| Parse error         | Special chars in node    | Escape or simplify node names                          |

## Resources

- [Graph::Easy on CPAN](https://metacpan.org/dist/Graph-Easy)
- [Graph::Easy Manual](http://bloodgate.com/perl/graph/manual/)
- [Graph::Easy GitHub](https://github.com/ironcamel/Graph-Easy)
