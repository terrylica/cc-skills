# CI Detection Enforcement

The canonical publish script (`scripts/publish-to-pypi.sh`) includes CI detection guards to prevent accidental execution in CI/CD pipelines.

## Environment Variables Checked

- `$CI` - Generic CI indicator
- `$GITHUB_ACTIONS` - GitHub Actions
- `$GITLAB_CI` - GitLab CI
- `$JENKINS_URL` - Jenkins
- `$CIRCLECI` - CircleCI

## Behavior

**If any CI variable detected**, script exits with error:

```
❌ ERROR: This script must ONLY be run on your LOCAL machine

   Detected CI environment variables:
   - CI: true
   - GITHUB_ACTIONS: <not set>
   ...

   This project enforces LOCAL-ONLY PyPI publishing for:
   - Security: No long-lived PyPI tokens in GitHub secrets
   - Speed: 30 seconds locally vs 3-5 minutes in CI
   - Control: Manual approval step before production release

   See: docs/development/PUBLISHING.md (ADR-0027)
```

## Testing CI Detection

```bash
# This should FAIL with error message
CI=true ./scripts/publish-to-pypi.sh

# Expected: ❌ ERROR: This script must ONLY be run on your LOCAL machine
```
