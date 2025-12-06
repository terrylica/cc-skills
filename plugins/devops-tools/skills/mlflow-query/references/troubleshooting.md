**Skill**: [MLflow Query Skill](../SKILL.md)

## 🛠️ Troubleshooting Common Issues

### Issue 1: Connection Refused

**Error:**

```
ConnectionRefusedError: [Errno 61] Connection refused
```

**Diagnosis:**

1. Is MLflow server running?
   ```bash
   curl http://mlflow.example.com:5000/health
   ```
1. Is tracking URI correct?
   ```bash
   echo $MLFLOW_TRACKING_URI
   ```
1. Firewall blocking port?

**Fix:**

- Verify server is running: `mlflow server --host 0.0.0.0 --port 5000`
- Check network connectivity
- Verify credentials if using auth

### Issue 2: Authentication Failed

**Error:**

```
HTTPError: 401 Client Error: Unauthorized
```

**Diagnosis:**

1. Are credentials correct?
   ```bash
   doppler secrets --project claude-config --config dev | grep MLFLOW
   ```
1. Is URI formatted correctly?
   ```bash
   # Should be: http://USERNAME:PASSWORD@HOST:PORT
   echo $MLFLOW_TRACKING_URI
   ```

**Fix:**

- Update Doppler secrets if password changed
- Verify URI format includes credentials
- Test with curl:
  ```bash
  curl -u user:password http://mlflow.example.com:5000/api/2.0/mlflow/experiments/list
  ```

### Issue 3: Filter String Invalid

**Error:**

```
MlflowException: Invalid filter string
```

**Common mistakes:**

1. **Using OR** (not supported)

   - ❌ `"param = 'A' OR param = 'B'"`
   - ✅ Run two queries and merge

1. **Unquoted parameter values**

   - ❌ `"params.learning_rate = 0.001"` (number, but params are strings!)
   - ✅ `"params.learning_rate = '0.001'"` (quoted)

1. **Invalid operators**

   - ❌ `"metrics.accuracy BETWEEN 0.8 AND 0.9"`
   - ✅ `"metrics.accuracy > 0.8 AND metrics.accuracy < 0.9"`

**Fix:**

- Use AND-only filters
- Always quote parameter values
- Use valid operators: `=`, `!=`, `>`, `<`, `>=`, `<=`, `LIKE`, `ILIKE`

### Issue 4: No Results Found

**Issue:**

```bash
mlflow runs list --experiment-id 999
# Returns empty (no error)
```

**Diagnosis:**

1. Does experiment exist?
   ```bash
   mlflow experiments search | grep 999
   ```
1. Are there runs in this experiment?
   ```bash
   mlflow runs list --experiment-id 999 | wc -l
   ```

**Fix:**

- List all experiments: `mlflow experiments search`
- Verify experiment ID
- Check if runs exist with different status: `mlflow runs list --experiment-id 1 --view all`

### Issue 5: Doppler Secrets Not Loading

**Error:**

```
Error: unknown command "list" for "doppler projects"
```

**Diagnosis:**

1. Is Doppler CLI installed?
   ```bash
   doppler --version
   ```
1. Check authentication status:
   ```bash
   doppler whoami
   ```

**Fix:**

- Install: `brew install dopplerhq/cli/doppler`
- Login: `doppler login`
- Verify project: `doppler projects`

