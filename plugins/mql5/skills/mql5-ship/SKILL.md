---
name: mql5-ship
description: Ship MQL5 code from macOS to the gpu-host Linux MT5 production environment. Handles the full pipeline in one command — git commit, push to GitHub, pull on gpu-host, copy to Wine MT5 directories, compile via MetaEditor CLI, cross-compile Rust DLL via cargo-xwin, deploy DLL, and validate everything works. Use whenever the user says ship, deploy, publish EA, push to gpu-host, compile on Linux, deploy tick collector, update production, sync to gpu-host, or mql5 ship. Also use after any MQL5 or Rust tick-writer code changes that need to reach the production MT5 on gpu-host.
allowed-tools: Read, Bash, Glob, Grep, Write, Edit, AskUserQuestion
argument-hint: "[--dry] [--dll-only] [--ea-only] [--validate]"
---

# /mql5:mql5-ship

Ship MQL5 EA code and Rust DLL from macOS development to gpu-host Linux production.
One command to go from local edit to running in production MT5.

## Architecture

```
macOS (development)                    gpu-host (production)
┌─────────────────────┐                ┌──────────────────────────┐
│ ~/eon/mql5/          │   git push    │ ~/eon/mql5/              │
│ ├─ mql5_ea/*.mq5    │ ──────────► │ ├─ mql5_ea/*.mq5        │
│ ├─ crates/tick-writer│   git pull    │ ├─ crates/tick-writer   │
│ └─ target/...dll     │              │ └─ (not built here)     │
└─────────────────────┘                └──────────┬───────────────┘
                                                   │ copy + compile
                                       ┌──────────▼───────────────┐
                                       │ ~/.mt5/.../MetaTrader 5/  │
                                       │ ├─ MQL5/Experts/*.ex5    │
                                       │ ├─ MQL5/Libraries/*.dll  │
                                       │ └─ tick_data/ → ODB cache│
                                       └──────────────────────────┘
```

## Flags

| Flag         | Effect                                               |
| ------------ | ---------------------------------------------------- |
| `--dry`      | Show what would be done without executing            |
| `--dll-only` | Only cross-compile and deploy the Rust DLL (skip EA) |
| `--ea-only`  | Only sync and compile MQL5 EAs (skip DLL)            |
| `--validate` | Run post-deploy validation only                      |

## Ship Pipeline

### Phase 1: Pre-Flight

Check working directory, commit pending changes, push to GitHub.

```bash
cd ~/eon/mql5

# 1. Check for uncommitted changes
git status --porcelain

# 2. If dirty: commit with conventional commit message
git add -A && git commit -m "feat/fix/chore: <description>"

# 3. Push to GitHub
git push origin main
```

**Gotcha**: Never skip pre-commit hooks. If hooks fail, fix the issue first.

### Phase 2: Pull on gpu-host

```bash
ssh gpu-host 'cd ~/eon/mql5 && git pull origin main'
```

### Phase 3: Cross-Compile Rust DLL (if tick-writer changed)

Only needed when `crates/tick-writer/` has changes. Run on **macOS** (cross-compile):

```bash
# Cross-compile from macOS to Windows x64
RUSTC_WRAPPER="" CARGO_BUILD_RUSTFLAGS="" \
RUSTFLAGS="-C opt-level=3 -C strip=symbols" \
CFLAGS="-O2 -mtune=generic" \
cargo xwin build --manifest-path crates/tick-writer/Cargo.toml \
  --target x86_64-pc-windows-msvc --release

# Deploy DLL to gpu-host
scp target/x86_64-pc-windows-msvc/release/tick_writer.dll \
  gpu-host:~/.mt5/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Libraries/
```

**Critical gotchas:**

- `RUSTC_WRAPPER=""` bypasses sccache (breaks cross-compile with target-cpu=native)
- `CFLAGS="-O2 -mtune=generic"` prevents zstd-sys from using apple-m3 CPU target
- DLL goes to `MQL5/Libraries/` (not Experts or Files)
- After DLL update, EA must be removed and re-attached in MT5

### Phase 4: Compile MQL5 EA on gpu-host

```bash
ssh gpu-host 'export WINEPREFIX=~/.mt5 WINEDEBUG=-all DISPLAY=:99 && \
  cd "$HOME/.mt5/drive_c/Program Files/MetaTrader 5" && \
  wine metaeditor64.exe /compile:"MQL5\Experts\TickCollector.mq5" \
    /log:"MQL5\Files\compile.log" 2>/dev/null; \
  iconv -f UTF-16LE -t UTF-8 \
    "$HOME/.mt5/drive_c/Program Files/MetaTrader 5/MQL5/Files/compile.log" \
    2>/dev/null | grep "Result:"'
```

**Expected**: `Result: 0 errors, 0 warnings`

**Gotchas:**

- MetaEditor returns exit code 1 even on success under Wine — check the log
- Compile log is UTF-16LE encoded — use `iconv` to read
- `DISPLAY=:99` required (Xvfb must be running)
- Wine prefix is `~/.mt5` (not `~/.wine`)

### Phase 5: Copy Updated Files to MT5 Directories

MQL5 source files live in the git repo but MT5 reads from its own directories:

```bash
ssh gpu-host '
MT5="$HOME/.mt5/drive_c/Program Files/MetaTrader 5"
REPO="$HOME/eon/mql5"

# Copy EAs
cp "$REPO/mql5_ea/TickCollector.mq5" "$MT5/MQL5/Experts/"

# Copy any new scripts
for f in "$REPO"/mql5_ea/Scripts/*.mq5; do
  [ -f "$f" ] && cp "$f" "$MT5/MQL5/Scripts/"
done
'
```

### Phase 6: Validate

```bash
ssh gpu-host '
echo "=== Validation ==="
MT5="$HOME/.mt5/drive_c/Program Files/MetaTrader 5"

# 1. EA compiled (.ex5 newer than .mq5)
EA_MQ5=$(stat -c %Y "$MT5/MQL5/Experts/TickCollector.mq5")
EA_EX5=$(stat -c %Y "$MT5/MQL5/Experts/TickCollector.ex5")
[ "$EA_EX5" -ge "$EA_MQ5" ] && echo "EA: compiled ✓" || echo "EA: STALE — recompile needed"

# 2. DLL present
ls "$MT5/MQL5/Libraries/tick_writer.dll" >/dev/null 2>&1 && echo "DLL: present ✓" || echo "DLL: MISSING"

# 3. MT5 running
pgrep -f terminal64.exe >/dev/null && echo "MT5: running ✓" || echo "MT5: NOT RUNNING"

# 4. Xvfb running
pgrep -f Xvfb >/dev/null && echo "Xvfb: running ✓" || echo "Xvfb: NOT RUNNING"

# 5. x11vnc running
pgrep -f x11vnc >/dev/null && echo "VNC: running ✓" || echo "VNC: NOT RUNNING"

# 6. Parquet data accessible
find -L "$MT5/tick_data/EURUSD" -name "*.parquet" 2>/dev/null | wc -l | xargs -I{} echo "Parquet EURUSD: {} files ✓"

# 7. Git in sync
cd ~/eon/mql5 && LOCAL=$(git rev-parse HEAD) && REMOTE=$(git rev-parse origin/main)
[ "$LOCAL" == "$REMOTE" ] && echo "Git: in sync ✓" || echo "Git: OUT OF SYNC — pull needed"
'
```

### Phase 7: Reload EA (if needed)

After deploying changes, the running EA uses the old .ex5 binary. To pick up changes:

1. Connect via VNC: `Cmd+Space → "MT5"`
2. Right-click EURUSD chart → Expert Advisors → Remove
3. Re-attach TickCollector from Navigator → Expert Advisors
4. Check Experts tab for `RESUME: watermark=...`

**Important**: This is a manual step. MT5 does not auto-reload EAs when .ex5 changes on disk.

## Quick Reference

```bash
# Full ship (commit + push + pull + compile + validate)
/mql5:mql5-ship

# DLL only (after Rust tick-writer changes)
/mql5:mql5-ship --dll-only

# EA only (after MQL5 code changes)
/mql5:mql5-ship --ea-only

# Just validate current state
/mql5:mql5-ship --validate
```

## File Locations on gpu-host

| Resource       | Path                                                                             |
| -------------- | -------------------------------------------------------------------------------- |
| Git repo       | `~/eon/mql5/`                                                                    |
| Wine prefix    | `~/.mt5/`                                                                        |
| MT5 install    | `~/.mt5/drive_c/Program Files/MetaTrader 5/`                                     |
| EA source      | `~/.mt5/.../MQL5/Experts/TickCollector.mq5`                                      |
| EA compiled    | `~/.mt5/.../MQL5/Experts/TickCollector.ex5`                                      |
| DLL            | `~/.mt5/.../MQL5/Libraries/tick_writer.dll`                                      |
| Parquet data   | `~/.mt5/.../tick_data/` → symlink to `~/.cache/opendeviationbar/ticks/FXVIEW_*/` |
| Compile script | `~/eon/mql5/scripts/compile-gpu-host.sh`                                         |
