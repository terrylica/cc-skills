**Skill**: [semantic-release](../SKILL.md)

## Troubleshooting

### No Release Created

**Symptom**: GitHub Actions succeeds but no git tag or release created.

**Diagnosis**:

- Check commit messages follow Conventional Commits format
- Verify commits since last release contain `feat:` or `fix:` types
- Confirm branch name matches configuration (default: `main`)

**Solution**: Add qualifying commit (e.g., `feat: trigger release`) and push.

### Permission Denied Errors

**Symptom**: GitHub Actions fails with "Resource not accessible by integration" error.

**Diagnosis**: Missing GitHub Actions permissions.

**Solution**: Repository Settings → Actions → General → Workflow permissions → Enable "Read and write permissions".

### Node.js Version Mismatch

**Symptom**: Installation fails with "engine node is incompatible" error.

**Diagnosis**: Node.js version below 24.10.0.

**Solution**:

```bash
# Install Node.js 24 LTS (using mise)
mise install node@24
mise use node@24
```

Update `.github/workflows/release.yml`:

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: "24"
```

### macOS Gatekeeper Blocks .node Files

**Symptom**: macOS shows dialog "Apple could not verify .node is free of malware" when running `npx semantic-release`. Multiple dialogs appear for different `.node` files.

**Diagnosis**: macOS Gatekeeper quarantines unsigned native Node.js modules downloaded via npm/npx. Each `npx` invocation re-downloads packages, triggering new quarantine flags.

**Root cause**: Native `.node` modules (compiled C++ addons) are not code-signed by npm package authors. macOS Sequoia and later are stricter about unsigned binaries.

**Solution (Recommended): Install globally instead of using npx**

```bash
# One-time setup: Install semantic-release globally
npm install -g semantic-release @semantic-release/changelog @semantic-release/git @semantic-release/github @semantic-release/exec

# Clear quarantine from global node_modules (one-time after install or node upgrade)
xattr -r -d com.apple.quarantine ~/.local/share/mise/installs/node/

# Use semantic-release directly (not npx)
/usr/bin/env bash -c 'GITHUB_TOKEN=$(gh auth token) semantic-release --no-ci'
```

**Why this works**: Global install downloads packages once. Clearing quarantine once is sufficient until Node.js is upgraded.

**Alternative: Clear quarantine from npm cache**

If you must use `npx`, clear quarantine from npm cache locations:

```bash
xattr -r -d com.apple.quarantine ~/.npm/
xattr -r -d com.apple.quarantine ~/.local/share/mise/installs/node/
```

**For project-local installs**: Add postinstall script to `package.json`:

```json
{
  "scripts": {
    "postinstall": "xattr -r -d com.apple.quarantine ./node_modules 2>/dev/null || true"
  }
}
```

**References**:

- [Der Flounder - Clearing quarantine attribute](https://derflounder.wordpress.com/2012/11/20/clearing-the-quarantine-extended-attribute-from-downloaded-applications/)
- [Homebrew/brew#17979 - xattr quarantine on Apple Silicon](https://github.com/Homebrew/brew/issues/17979)
