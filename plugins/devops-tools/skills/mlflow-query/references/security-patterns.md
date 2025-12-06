**Skill**: [MLflow Query Skill](../SKILL.md)

## 🔐 Security & Credential Patterns

### Pattern 1: Doppler Atomic Secrets (Recommended)

**Why atomic secrets?**

- Rotation flexibility (change password without changing host)
- Audit trail per secret
- Multi-environment support (dev/staging/prod)

**Setup:**

```bash
# Store secrets atomically (zero-exposure)
echo 'mlflow.example.com' | doppler secrets set MLFLOW_HOST -p private-config -c dev --silent
echo '5000' | doppler secrets set MLFLOW_PORT -p private-config -c dev --silent
echo 'example-org' | doppler secrets set MLFLOW_USERNAME -p private-config -c dev --silent
echo 'password' | doppler secrets set MLFLOW_PASSWORD -p private-config -c dev --silent
```

**Usage (One-Liner):**

```bash
doppler run --project private-config --config dev -- bash -c \
  'export MLFLOW_TRACKING_URI="http://$MLFLOW_USERNAME:$MLFLOW_PASSWORD@$MLFLOW_HOST:$MLFLOW_PORT" && \
   uvx mlflow <command>'
```

**Usage (Session-based):**

```bash
# Set environment for entire session
eval "$(doppler secrets download --project private-config --config dev --format env-no-quotes --no-file | \
        grep -E '^(MLFLOW_HOST|MLFLOW_PORT|MLFLOW_USERNAME|MLFLOW_PASSWORD)=')"

export MLFLOW_TRACKING_URI="http://$MLFLOW_USERNAME:$MLFLOW_PASSWORD@$MLFLOW_HOST:$MLFLOW_PORT"

# Now run commands normally
uvx mlflow experiments search
uvx mlflow runs list --experiment-id 1
```

### Pattern 2: Environment Variable (Simple)

**For local/dev only:**

```bash
export MLFLOW_TRACKING_URI="http://localhost:5000"
uvx mlflow experiments search
```

**For remote with basic auth:**

```bash
export MLFLOW_TRACKING_URI="http://user:password@mlflow.example.com:5000"
uvx mlflow runs list --experiment-id 1
```

**⚠️ Security Warning**: Credentials visible in shell history and process list. Use Doppler for production.

