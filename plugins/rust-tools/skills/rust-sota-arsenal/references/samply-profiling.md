# samply: Interactive Rust Profiling

Interactive profiler that opens results in the Firefox Profiler UI. Supports macOS (dtrace), Linux (perf), and Windows (ETW).

## Installation

```bash
cargo install samply
```

## Why samply

| Feature     | samply                     | `cargo-instruments` | `perf` + flamegraph |
| ----------- | -------------------------- | ------------------- | ------------------- |
| UI          | Firefox Profiler (web)     | Instruments.app     | Static SVG          |
| Interactive | Yes (zoom, filter, search) | Yes                 | No                  |
| macOS       | Yes (dtrace)               | Yes (native)        | No                  |
| Linux       | Yes (perf)                 | No                  | Yes                 |
| Windows     | Yes (ETW)                  | No                  | No                  |
| Call trees  | Yes                        | Yes                 | Flamegraph only     |
| Timeline    | Yes                        | Yes                 | No                  |

## Basic Workflow

### Step 1: Build with Debug Info

```bash
# Release build with debug info (fast + symbols)
cargo build --release

# Or set in Cargo.toml:
[profile.release]
debug = true  # Full debug info
# debug = "line-tables-only"  # Smaller, still useful
```

### Step 2: Profile

```bash
# Profile a binary
samply record ./target/release/my-binary

# Profile with arguments
samply record ./target/release/my-binary --arg1 value1 < input.txt

# Profile for specific duration
samply record --duration 10 ./target/release/my-binary

# Profile an already-running process (by PID)
samply record --pid 12345
```

### Step 3: Analyze

samply automatically opens the Firefox Profiler UI in your browser. The UI provides:

- **Call tree**: Hierarchical function call breakdown
- **Flame graph**: Visual representation of call stacks
- **Timeline**: CPU activity over time
- **Source view**: Line-level timing (with debug info)
- **Marker chart**: Custom markers and events

## macOS Setup

### SIP (System Integrity Protection) Considerations

On macOS, samply uses dtrace which may need elevated permissions:

```bash
# Option 1: Run with sudo (simplest)
sudo samply record ./target/release/my-binary

# Option 2: Sign the binary for dtrace (no sudo needed)
codesign -s - -f --entitlements entitlements.plist ./target/release/my-binary
```

Entitlements plist for dtrace:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.get-task-allow</key>
    <true/>
</dict>
</plist>
```

### Apple Silicon Notes

- samply works on Apple Silicon (M1/M2/M3/M4)
- ARM PMU counters may be limited without SIP modifications
- CPU frequency scaling is less of an issue than on Intel

## Reading the Firefox Profiler UI

### Call Tree Tab

- **Self time**: Time spent in the function itself (not callees)
- **Total time**: Self time + time in all callees
- **Sort by self time** to find hotspots

### Flame Graph Tab

- Width = time spent
- Bottom = entry points (main, thread start)
- Top = leaf functions (actual work)
- **Look for wide bars** — those are your hotspots
- Click to zoom into a subtree

### Timeline Tab

- Shows CPU activity over the profiling duration
- Select a time range to focus the call tree on that window
- Useful for finding startup vs steady-state performance

### Filtering

- **Search box**: Filter by function name
- **Call tree filter**: Show only paths matching a pattern
- **Invert call tree**: Bottom-up view (start from hotspots)

## Advanced Usage

### Profile Cargo Tests

```bash
# Build test binary, then profile it
cargo test --no-run --release
samply record ./target/release/deps/my_test-<hash>
```

### Profile Benchmarks

```bash
# Build benchmark binary
cargo bench --no-run
samply record ./target/release/deps/my_bench-<hash> --bench
```

### Compare Profiles

1. Save profile: Firefox Profiler → Share → Save to file
2. Load two profiles in separate tabs
3. Compare call trees side by side

### Markers (Custom Events)

samply supports recording custom markers for event-based profiling:

```bash
# With environment variable markers
SAMPLY_MARKERS=1 samply record ./target/release/my-binary
```

## Integration with Other Tools

### With cargo-pgo

```bash
# Profile first to understand hotspots
samply record ./target/release/my-binary

# Then PGO to optimize the hot paths
cargo pgo build
./target/release/my-binary < workload.txt
cargo pgo optimize
```

### With cargo-wizard

```bash
# Set up profiling-friendly profile
[profile.profiling]
inherits = "release"
debug = true
strip = false

cargo build --profile profiling
samply record ./target/profiling/my-binary
```

## Tips

- **Always use release builds**: Debug builds are too slow for meaningful profiling
- **Keep debug info**: `debug = true` or `debug = "line-tables-only"` in release profile
- **Don't strip symbols**: `strip = false` when profiling
- **Representative workload**: Profile real usage patterns, not synthetic benchmarks
- **Warm up**: Run the workload once before profiling to avoid measuring startup/cache effects
- **Multiple runs**: Profile several times to check consistency
- **Firefox Profiler**: Works in any browser, not just Firefox
- **Sharing**: The Firefox Profiler can generate shareable links
