# ast-grep for Rust

AST-aware code search and structural rewriting for Rust codebases. Unlike regex, ast-grep understands Rust syntax — it matches on the abstract syntax tree, not text patterns.

## Installation

```bash
cargo install ast-grep
# or via npm
npm install -g @ast-grep/cli
```

## Core Concepts

### Pattern Syntax

ast-grep patterns use **metavariables** to match AST nodes:

| Metavariable | Matches                               |
| ------------ | ------------------------------------- |
| `$X`         | Any single AST node                   |
| `$$$X`       | Zero or more AST nodes (variadic)     |
| `$_`         | Any single node (unnamed, no capture) |

### Language Flag

Always specify `--lang rust` (or `-l rust`) — ast-grep supports multiple languages and needs to know the parser.

## Common Rust Patterns

### Error Handling

```bash
# Find all .unwrap() calls
ast-grep -p '$X.unwrap()' -l rust

# Find all .expect() calls
ast-grep -p '$X.expect($MSG)' -l rust

# Replace unwrap with expect
ast-grep -p '$X.unwrap()' -r '$X.expect("TODO: handle error")' -l rust

# Find unwrap_or with expensive default (should be unwrap_or_else)
ast-grep -p '$X.unwrap_or($DEFAULT)' -l rust
```

### Unsafe Code

```bash
# Find all unsafe blocks
ast-grep -p 'unsafe { $$$BODY }' -l rust

# Find unsafe fn declarations
ast-grep -p 'unsafe fn $NAME($$$ARGS) $BODY' -l rust

# Find unsafe impl blocks
ast-grep -p 'unsafe impl $TRAIT for $TYPE { $$$BODY }' -l rust
```

### Pattern Matching Refactors

```bash
# Convert single-arm match to if-let
ast-grep -p 'match $X { $P => $E, _ => () }' -r 'if let $P = $X { $E }' -l rust

# Find match with single arm (potential if-let candidate)
ast-grep -p 'match $X { $P => $E, _ => $F }' -l rust
```

### Deprecated API Migration

```bash
# Replace deprecated try! with ?
ast-grep -p 'try!($X)' -r '$X?' -l rust

# Find manual Result handling (potential ? candidate)
ast-grep -p 'match $X { Ok($V) => $V, Err($E) => return Err($E) }' -l rust
```

### Clone and Copy Patterns

```bash
# Find .clone() calls (potential unnecessary allocations)
ast-grep -p '$X.clone()' -l rust

# Find .to_string() on string literals
ast-grep -p '"$S".to_string()' -l rust

# Find String::from on literals (prefer .to_string() or .into())
ast-grep -p 'String::from("$S")' -l rust
```

## YAML Rule Files

For complex multi-rule transforms, create YAML rule files:

```yaml
# rules/unwrap-to-expect.yml
id: unwrap-to-expect
language: rust
rule:
  pattern: $X.unwrap()
  not:
    inside:
      kind: test  # Skip test functions
fix: $X.expect("TODO: handle None/Err")
message: "Replace .unwrap() with .expect() for better panic messages"
severity: warning
```

```bash
# Run rules
ast-grep scan --rule rules/unwrap-to-expect.yml

# Run all rules in a directory
ast-grep scan --rule rules/
```

### Rule Composition

```yaml
# rules/clippy-style.yml
id: manual-map
language: rust
rule:
  pattern: |
    match $X {
      Some($V) => Some($E),
      None => None,
    }
fix: $X.map(|$V| $E)
message: "Use .map() instead of match on Option"
```

## Interactive Mode

```bash
# Interactive search with preview
ast-grep -p '$PATTERN' -l rust --interactive

# JSON output for scripting
ast-grep -p '$X.unwrap()' -l rust --json
```

## Integration with CI

```yaml
# .github/workflows/ast-grep.yml
- name: ast-grep lint
  run: |
    cargo install ast-grep
    ast-grep scan --rule rules/ --error  # Non-zero exit on findings
```

## Configuration File

Create `sgconfig.yml` at project root:

```yaml
ruleDirs:
  - rules/
testConfigs:
  - testDir: rules/tests/
```

## Tips

- **Whitespace insensitive**: ast-grep ignores formatting differences
- **Comment aware**: Patterns skip comments in the AST
- **Nested matching**: `$$$BODY` captures entire blocks including nested structures
- **Debugging patterns**: Use `ast-grep parse <file> --lang rust` to see the AST
- **Performance**: ast-grep is very fast — it uses tree-sitter parsing, not compilation

## Comparison with Other Tools

| Tool        | AST-Aware         | Rust-Specific  | Rewrite               | Speed               |
| ----------- | ----------------- | -------------- | --------------------- | ------------------- |
| ast-grep    | Yes (tree-sitter) | Multi-language | Yes                   | Very fast           |
| `clippy`    | Yes (rustc)       | Yes            | Limited (suggestions) | Slow (full compile) |
| `semgrep`   | Yes               | Multi-language | Yes                   | Fast                |
| `grep`/`rg` | No                | No             | No                    | Fastest             |

ast-grep fills the gap between fast-but-dumb text search and slow-but-smart full compilation.
