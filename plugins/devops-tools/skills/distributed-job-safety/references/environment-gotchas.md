# Environment Gotchas

Host-specific pitfalls encountered during remote deployments. Each gotcha includes the symptom, root cause, and fix.

---

## G-1: PEP 668 Externally-Managed-Environment

**Symptom**: `pip install mypkg` fails with "externally managed environment" on Python 3.12+.

**Root cause**: PEP 668 (Python 3.12+) blocks pip in system-managed environments to prevent breakage.

**Fix**: Use uv instead of pip:

```bash
# WRONG
pip install mypkg

# RIGHT
uv pip install --python .venv/bin/python mypkg
```

**Affected hosts**: Any host with Python 3.12+ managed by system package manager.

---

## G-2: ClickHouse Docker Auth Failure

**Symptom**: `Authentication failed for user 'default'` with local Docker ClickHouse.

**Root cause**: ClickHouse Docker image requires explicit password configuration, even if empty.

**Fix**:

```bash
docker run -e CLICKHOUSE_PASSWORD= clickhouse/clickhouse-server
```

---

## G-3: `uv run` Editable vs. Wheel Confusion

**Symptom**: Installed new wheel version via pip, but `uv run` still executes old code.

**Root cause**: `uv.lock` defines `source = { editable = "." }`. When running `uv run python script.py` inside the project directory, uv reads Python files directly from the git working tree, NOT from the installed wheel.

**Implications**:

- `git pull` on remote host updates the code that `uv run` uses
- `pip install` only matters for standalone venvs outside the project
- Version shown by `import pkg; pkg.__version__` may differ from actual source code behavior

**Decision tree**:

```
Is the remote host's project directory a git checkout?
|-- YES -> git pull updates the code uv run uses
|          pip install is irrelevant for uv run
|-- NO  -> pip install / uv pip install is required
```

---

## G-4: Pueue Daemon Not Running

**Symptom**: `pueue add` fails with "Connection refused" or hangs.

**Root cause**: Pueue daemon (`pueued`) not started on the host.

**Fix**:

```bash
# Start daemon (persists across SSH disconnects)
pueued -d

# Verify
pueue status
```

**Auto-start on Linux** (systemd):

```bash
systemctl --user enable --now pueued
```

---

## G-5: Pueue Groups Paused After Kill

**Symptom**: After `pueue kill --all`, new jobs stay in `Queued` state forever.

**Root cause**: `pueue kill` pauses all affected groups as a safety measure.

**Fix**: Unpause groups after kill:

```bash
pueue start --all
```

---

## G-6: Pandas 3.0 Datetime Resolution

**Symptom**: Timestamps are off by factor of 1000 (seconds instead of milliseconds).

**Root cause**: Pandas 3.0 defaults to `datetime64[us]` (microsecond). `.astype("int64")` returns microseconds, not nanoseconds. So `// 10**6` produces seconds instead of milliseconds.

**Fix**: Use explicit unit conversion:

```python
# WRONG (breaks on pandas 3.0):
df["timestamp_ms"] = df["timestamp"].astype("int64") // 10**6

# RIGHT (works on pandas 2.x and 3.0):
df["timestamp_ms"] = df["timestamp"].dt.as_unit("ms").astype("int64")
```

**Defensive guard**: Add a scale check before database writes:

```python
def _guard_timestamp_ms_scale(df):
    """Reject writes where timestamps are seconds instead of milliseconds."""
    if df["timestamp_ms"].min() < 1_000_000_000_000:
        raise ValueError("timestamp_ms appears to be seconds, not milliseconds")
```

---

## G-7: SSH Key Not Available on Remote Host

**Symptom**: `git clone git@github.com:...` fails with "Permission denied (publickey)".

**Root cause**: Remote host doesn't have SSH key configured for GitHub.

**Fix**: Use HTTPS with token instead:

```bash
git remote set-url origin https://github.com/owner/repo.git
# Token is provided via GH_TOKEN env var from mise
```

Or use `git init` + fetch pattern:

```bash
cd ~/project
git init
git remote add origin https://github.com/owner/repo.git
git fetch origin main
git reset --hard origin/main
```

---

## G-8: `mise trust` Required on Fresh Checkout

**Symptom**: `mise run <task>` fails with "Config files are not trusted".

**Root cause**: mise requires explicit trust for config files to prevent supply-chain attacks from untrusted repos.

**Fix**: Run once per checkout:

```bash
cd ~/project && mise trust
```

---

## G-9: PyPI Propagation Delay

**Symptom**: `uv pip install pkg==X.Y.Z` fails immediately after publishing.

**Root cause**: PyPI CDN propagation takes 30-120 seconds globally.

**Fixes** (in order of preference):

```bash
# 1. Bust uv's index cache
uv pip install --refresh pkg==X.Y.Z

# 2. Force primary index
uv pip install --refresh --index-url https://pypi.org/simple/ pkg==X.Y.Z

# 3. Wait and retry
sleep 60 && uv pip install pkg==X.Y.Z
```

---

## G-10: MemoryMax Without MemorySwapMax=0

**Symptom**: `systemd-run --scope -p MemoryMax=256M` doesn't prevent allocation beyond 256 MB.

**Root cause**: Linux memory overcommit + swap. Without `MemorySwapMax=0`, the cgroup can spill into swap, effectively making `MemoryMax` a soft limit.

**Fix**: Always pair `MemoryMax` with `MemorySwapMax=0`:

```bash
# WRONG: Process escapes into swap
systemd-run --user --scope -p MemoryMax=2G <command>

# RIGHT: Hard memory limit, no swap escape
systemd-run --user --scope -p MemoryMax=2G -p MemorySwapMax=0 <command>
```

**Verification**:

```bash
SCOPE=$(pueue log <id> | grep "Running as unit" | grep -o "run-r[a-z0-9]*.scope")
CGROUP=$(find /sys/fs/cgroup/user.slice -name "$SCOPE" -type d | head -1)
cat $CGROUP/memory.swap.max   # Must be 0
```

**When OOM-killed**: Exit code 137 (SIGKILL). Pueue marks the job as Failed.

---

## G-11: Rust Not in PATH via `uv run` on Remote Hosts

**Symptom**: `maturin develop --uv` fails with "rustc not installed or not in PATH".

**Root cause**: `uv run` inherits a minimal PATH that doesn't include `~/.cargo/bin`.

**Fix**: Prepend cargo bin to PATH:

```bash
# Interactive
PATH="$HOME/.cargo/bin:$PATH" uv run maturin develop --uv

# In pueue jobs
pueue add -- env PATH="/home/user/.cargo/bin:$PATH" uv run maturin develop --uv
```

---

## G-12: Pueue `add` Inherits SSH cwd, Not Project Directory

**Symptom**: Pueue job fails instantly with `No such file or directory` for a relative script path.

**Root cause**: When running `ssh host "pueue add -- cmd"`, pueue records the working directory as the SSH session's cwd (typically `$HOME`). Relative paths in the command resolve against `$HOME`, not the project root.

**Fix**: Always `cd` to the project directory in the same shell command:

```bash
# WRONG
ssh host "pueue add -- uv run python scripts/process.py"
# Job runs in $HOME, fails to find scripts/process.py

# RIGHT
ssh host "cd ~/project && pueue add -- uv run python scripts/process.py"
# Job runs in ~/project, relative paths work correctly
```

**Verify**: Check the Path column in `pueue status` output — it should show the project directory.

---

## G-13: SIGPIPE (Exit 141) Under set -euo pipefail

**Symptom**: Bash script exits with code 141 on `ls | head`, `cat | head`, or similar pipe-to-head patterns.

**Root cause**: Under `set -o pipefail`, when `head` closes its stdin after reading N lines, the upstream command receives SIGPIPE (signal 13). Exit code = 128 + 13 = 141.

**Fix**: Avoid piping to `head`/`tail -n` in strict-mode scripts. Write to temp file first:

```bash
# WRONG (exit 141 under set -euo pipefail)
ls /tmp/gen600_sql/2down/*.sql | head -10

# RIGHT
find /tmp/gen600_sql/2down/ -name '*.sql' -print0 | head -z -n 10

# RIGHT (temp file approach)
ls /tmp/gen600_sql/2down/*.sql > /tmp/filelist.txt
head -10 /tmp/filelist.txt
```

---

## G-14: Pipe Subshell Data Loss in While Loops

**Symptom**: `while read ... done > $TMPOUT` produces empty or truncated output when the input comes from a pipe.

**Root cause**: `echo "$OUTPUT" | while read ...; do ...; done > file` runs the while loop in a **subshell** (because it's the right side of a pipe). Variables set inside the loop are lost when the subshell exits. More critically, output redirection may not flush correctly under concurrent execution.

**Fix**: Use process substitution to keep the while loop in the main shell:

```bash
# WRONG (subshell, data loss risk)
echo "$OUTPUT" | while IFS=$'\t' read -r col1 col2 col3; do
    echo "processed: $col1"
done > "$TMPOUT"

# RIGHT (process substitution, main shell)
while IFS=$'\t' read -r col1 col2 col3; do
    echo "processed: $col1"
done < <(echo "$OUTPUT" | tail -n +2) > "$TMPOUT"
```

**Affected**: Any bash script that parses multi-line command output (ClickHouse TSV, CSV, etc.) into a while-read loop.

---

## G-15: Pueue Jobs Cannot See mise `[env]` Variables

**Symptom**: Pueue job fails with empty env vars (e.g., `MissingSchema: Invalid URL ''`) even though `mise env` shows them in your interactive shell.

**Root cause**: Pueue jobs run in a **clean shell** — no `.bashrc`, no `.zshrc`, no mise activation. Variables defined in `mise.toml [env]` are only available in shells that have run mise activation or `eval "$(mise env)"`. # PROCESS-STORM-OK (documentation only)

**Fix**: For Python applications, use `python-dotenv` + `.env` file in the project root. The pueue job only needs `cd $PROJECT_DIR` — dotenv auto-loads `.env` from cwd at runtime:

```bash
# WRONG (pueue can't see mise [env] vars)
pueue add -- uv run python my_script.py  # POLYGON_RPC="" → crash

# WRONG (mise env works but requires trust + version compat)
pueue add -- bash -c 'export MISE_YES=1 && cd ~/project && eval "$(mise env)" && uv run python my_script.py'  # PROCESS-STORM-OK

# RIGHT (python-dotenv loads .env from cwd — zero binary dependencies)
pueue add -- bash -c 'cd ~/project && uv run python my_script.py'
# Requires: load_dotenv() in your Python entry point + .env file in project root
```

**Architecture**: Use `mise.toml` for task definitions only, `.env` for secrets (gitignored, loaded by `python-dotenv` at runtime). This is the most portable pattern across macOS/Linux, interactive/daemon shells, and local/remote execution.

**Affected**: Any pueue/cron/systemd job running Python code that expects mise-managed env vars.

---

## G-16: mise Trust Errors Over SSH (\_\_MISE_DIFF Leakage)

**Symptom**: Every SSH command to a remote host fails with `mise ERROR: Config files not trusted`, even with `mise trust` run on the remote.

**Root cause**: The local machine's `__MISE_DIFF` environment variable (set by mise shell activation) propagates through SSH sessions. The remote mise sees this variable, interprets it as a stale diff, and triggers trust validation against remote configs — which fails because the serialized diff references local paths.

**Fix**: Either unset the variable locally before SSH, or set `MISE_YES=1` on the remote:

```bash
# Option 1: Unset locally before SSH (per-command)
unset __MISE_DIFF && ssh host 'cd ~/project && mise env'

# Option 2: Set MISE_YES=1 in remote's .bashrc/.profile
# This auto-trusts all configs (OK for single-user servers)
echo 'export MISE_YES=1' >> ~/.bashrc

# Option 3: Trust the specific config on both sides
mise trust .               # On local machine
ssh host 'mise trust .'    # On remote machine
```

**Affected**: Any workflow where a macOS dev machine SSHes into Linux servers that also have mise installed. Most common with `rsync + ssh` or `pueue` remote orchestration.

---

## G-17: Cursor/Checkpoint File Deletion Destroys Incremental Resume

**Symptom**: An indexer or ETL job runs successfully, but the next invocation does a full re-run instead of resuming from where it left off.

**Root cause**: The job deletes its cursor/checkpoint/offset file on completion (e.g., `CURSOR_FILE.unlink()` after the final batch). This was likely added to "clean up" but destroys the state needed for incremental runs.

**Fix**: Never delete checkpoint files on success. The checkpoint IS the proof of completion — it tells the next run "start from here":

```python
# WRONG (deletes proof of progress)
def run(self):
    while has_more_data():
        batch = fetch_next_batch()
        save_batch(batch)
        CURSOR_FILE.write_text(str(batch.last_id))
    CURSOR_FILE.unlink()  # ← BUG: next run starts from scratch

# RIGHT (preserve checkpoint for incremental resume)
def run(self):
    while has_more_data():
        batch = fetch_next_batch()
        save_batch(batch)
        CURSOR_FILE.write_text(str(batch.last_id))
    # Done — cursor stays. Next run reads it and finds nothing new.
```

**Bonus**: Add a filename-based fallback for recovery if the cursor file is lost:

```python
# Derive progress from output files (e.g., trades_100_200.parquet → resume from 200)
import re
pattern = re.compile(r"output_(\d+)_(\d+)\.parquet")
max_id = max(int(m.group(2)) for f in DATA_DIR.glob("output_*.parquet") if (m := pattern.match(f.name)))
```

**Affected**: Any ETL pipeline, web scraper, or blockchain indexer with resumable backfilling.

---

## Quick Reference Table

| Gotcha | Symptom                   | One-Line Fix                                  |
| ------ | ------------------------- | --------------------------------------------- |
| G-1    | Externally managed        | `uv pip install` instead of `pip install`     |
| G-2    | Auth failure              | `-e CLICKHOUSE_PASSWORD=` in docker run       |
| G-3    | Old code after upgrade    | `git pull` updates editable source            |
| G-4    | Pueue won't add           | `pueued -d` to start daemon                   |
| G-5    | Jobs stuck queued         | `pueue start --all` to unpause                |
| G-6    | Timestamps off by 1000x   | `.dt.as_unit("ms").astype("int64")`           |
| G-7    | Git SSH denied            | Use HTTPS + token                             |
| G-8    | Config not trusted        | `mise trust`                                  |
| G-9    | Version not found         | `--refresh` flag on uv pip install            |
| G-10   | MemoryMax not enforced    | Add `-p MemorySwapMax=0` to systemd-run       |
| G-11   | rustc not in PATH         | `PATH="$HOME/.cargo/bin:$PATH"` before uv run |
| G-12   | Script not found          | `cd ~/project &&` before `pueue add`          |
| G-13   | Exit 141 on pipe+head     | Write to temp file, then `head` on file       |
| G-14   | While-read output empty   | Process substitution: `< <(echo "$OUT")`      |
| G-15   | Pueue job env vars empty  | `python-dotenv` + `.env` + `cd $PROJECT_DIR`  |
| G-16   | mise trust errors via SSH | `unset __MISE_DIFF` or `MISE_YES=1` on remote |
| G-17   | Full re-run after success | Never delete cursor/checkpoint files          |
