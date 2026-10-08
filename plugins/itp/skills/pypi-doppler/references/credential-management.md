# Credential Management

## Doppler Configuration

**Project**: `private-config` **Configs**: `prd` (production), `dev` (development) **Secret Name**: `PYPI_TOKEN`

## Token Format

Valid PyPI token format:

- Starts with: `pypi-AgEIcHlwaS5vcmc`
- Length: ~180 characters
- Example: `pypi-AgEIcHlwaS5vcmcCJGI4YmNhMDA5LTg...`

## Token Permissions

**Account-wide token** (recommended):

- Can publish to all projects under your account
- Simpler management
- One token for all repositories

**Project-scoped token**:

- Can only publish to specific project
- More restrictive
- Separate token per project needed

## Token Rotation

```bash
# 1. Create new token on PyPI
# Visit: https://pypi.org/manage/account/token/

# 2. Update Doppler
doppler secrets set PYPI_TOKEN='new-token' \
  --project private-config \
  --config prd

# 3. Verify new token works
doppler secrets get PYPI_TOKEN \
  --project private-config \
  --config prd \
  --plain

# 4. Test publish (dry-run not available, use TestPyPI)
# See: TestPyPI Testing reference
```
