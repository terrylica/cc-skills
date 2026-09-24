# Troubleshooting

## Issue: "PYPI_TOKEN not found in Doppler"

**Symptom**: Script fails at Step 0

**Fix**:

```bash
# Verify token exists
doppler secrets --project claude-config --config prd | grep PYPI_TOKEN

# If missing, get new token from PyPI
# Visit: https://pypi.org/manage/account/token/
# Create token with scope: "Entire account" or specific project

# Store in Doppler
doppler secrets set PYPI_TOKEN='your-token' \
  --project claude-config \
  --config prd
```

## Issue: "403 Forbidden from PyPI"

**Symptom**: Script fails at Step 4 with authentication error

**Root Cause**: Token expired or invalid (PyPI requires 2FA since 2024)

**Fix**:

1. Verify 2FA enabled on PyPI account
2. Create new token: <https://pypi.org/manage/account/token/>
3. Update Doppler: `doppler secrets set PYPI_TOKEN='new-token' --project claude-config --config prd`
4. Retry publish

## Issue: "Script blocked with CI detection error"

**Symptom**:

```
❌ ERROR: This script must ONLY be run on your LOCAL machine
Detected CI environment variables:
- CI: true
```

**Root Cause**: Running in CI environment OR `CI` variable set locally

**Fix**:

```bash
# Check if CI variable set in your shell
env | grep CI

# If set, unset it
unset CI
unset GITHUB_ACTIONS

# Retry publish
./scripts/publish-to-pypi.sh
```

**Expected behavior**: This is INTENTIONAL - script should ONLY run locally.

## Issue: "Version not updated in pyproject.toml"

**Symptom**: Local publish uses old version number

**Root Cause**: Didn't pull latest release commit from GitHub

**Fix**:

```bash
# Always pull before publishing
git pull origin main

# Verify version updated
grep '^version = ' pyproject.toml

# Retry publish
./scripts/publish-to-pypi.sh
```

## Issue: "uv package manager not found"

**Symptom**: Script fails at startup before any steps

**Root Cause**: uv not installed or not discoverable

**How the script discovers uv** (in priority order):

1. Already in PATH (Homebrew, direct install, shell configured)
2. Common direct install locations (`~/.local/bin/uv`, `~/.cargo/bin/uv`, `/opt/homebrew/bin/uv`, the proto shim `~/.proto/shims/uv`)
3. asdf as fallback

**Fix**: Install uv using any method:

```bash
# Official installer (recommended)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Homebrew
brew install uv

# Cargo
cargo install uv

# proto
proto install uv --pin global
```

The script doesn't force any particular installation method.

## Issue: Script Hangs with No Output

**Symptom**: Script starts but produces no output, eventually times out

**Root Cause**: Script sources `~/.zshrc` or `~/.bashrc` which waits for interactive input

**Fix**: Never source shell config files in scripts. The bundled script uses:

```bash
# PROCESS-STORM-OK
/usr/bin/env bash << 'SHIMS_EOF'
# CORRECT - safe for non-interactive shells: put proto shims on PATH explicitly
export PATH="$HOME/.proto/shims:$HOME/.proto/bin:$PATH"

# WRONG - hangs in non-interactive shells
source ~/.zshrc
SHIMS_EOF
```
