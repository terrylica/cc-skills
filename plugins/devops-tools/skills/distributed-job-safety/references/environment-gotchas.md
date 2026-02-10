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

## Quick Reference Table

| Gotcha | Symptom                 | One-Line Fix                                  |
| ------ | ----------------------- | --------------------------------------------- |
| G-1    | Externally managed      | `uv pip install` instead of `pip install`     |
| G-2    | Auth failure            | `-e CLICKHOUSE_PASSWORD=` in docker run       |
| G-3    | Old code after upgrade  | `git pull` updates editable source            |
| G-4    | Pueue won't add         | `pueued -d` to start daemon                   |
| G-5    | Jobs stuck queued       | `pueue start --all` to unpause                |
| G-6    | Timestamps off by 1000x | `.dt.as_unit("ms").astype("int64")`           |
| G-7    | Git SSH denied          | Use HTTPS + token                             |
| G-8    | Config not trusted      | `mise trust`                                  |
| G-9    | Version not found       | `--refresh` flag on uv pip install            |
| G-10   | MemoryMax not enforced  | Add `-p MemorySwapMax=0` to systemd-run       |
| G-11   | rustc not in PATH       | `PATH="$HOME/.cargo/bin:$PATH"` before uv run |
