# Link Validation Hook Test - Meta-Prompt

**Version**: 8.1.8+
**Purpose**: Test lychee-stop-hook in non-marketplace repositories

Copy this prompt to Claude Code when working in a **non-marketplace repo** (e.g., `~/eon/alpha-forge`):

---

## Meta-Prompt for Testing Link Validation Hook

````
I need you to test the lychee-stop-hook link validation. Create a test file with intentional path violations:

### Step 1: Create Test File with Path Violations

Create this file in the `docs/` directory (NOT in `tmp/` which is excluded):

```bash
cat > docs/TEST-LINK-ERRORS.md << 'EOF'
# Test File for Link Validation Hook

This file intentionally contains link errors to test lychee-stop-hook.

## Relative Path Violations (should trigger lint-relative-paths)

These links use relative paths instead of repo-root paths:

- [Wrong: Relative to parent](../README.md)
- [Wrong: Relative without leading slash](adr/some-file.md)
- [Wrong: Dot-relative link](./design/spec.md)

## Correct Links (should NOT trigger errors)

- [Correct: Repo-root path](/docs/README.md)
- [Correct: External URL](https://github.com)

## DELETE THIS FILE AFTER TESTING
EOF
```

### Step 2: Trigger the Stop Hook

Try to exit the session by typing `/exit` or pressing Escape.

### Expected Behavior

The lychee-stop-hook should:
1. Detect 3 path violations in `docs/TEST-LINK-ERRORS.md`
2. Output `{"decision": "block", "reason": "...violations..."}`
3. Block stopping and inject the violations into Claude's context
4. Claude should then see and offer to fix the violations

### Step 3: Verify Claude Sees Violations

After the stop is blocked, Claude should:
- See the violation details in its context
- Offer to fix the relative paths to repo-root format
- Convert `../README.md` to `/README.md`
- Convert `adr/some-file.md` to `/docs/adr/some-file.md`
- Convert `./design/spec.md` to `/docs/design/spec.md`

### Step 4: Clean Up

After testing, delete the test file:

```bash
rm docs/TEST-LINK-ERRORS.md
```

---

## Troubleshooting

If the hook doesn't trigger:

1. **Check hook is installed**:
   ```bash
   jq '.hooks.Stop' ~/.claude/settings.json | grep -i lychee
   ```

2. **Check hook script exists**:
   ```bash
   ls -la ~/.claude/plugins/marketplaces/cc-skills/plugins/statusline-tools/hooks/lychee-stop-hook.sh
   ```

3. **Run lint-relative-paths manually**:
   ```bash
   ~/.claude/plugins/marketplaces/cc-skills/plugins/statusline-tools/scripts/lint-relative-paths $(pwd)
   ```

4. **Restart Claude Code** - hooks are loaded at session start

## Note on Marketplace Repos

This test will NOT work in marketplace repos (like cc-skills) because:
- Marketplace plugins use relative paths correctly
- lint-relative-paths auto-detects and skips marketplace repos

Test in regular repos like alpha-forge, or any repo without `.claude-plugin/marketplace.json`.
````

---

## Quick Test Commands (Copy-Paste Ready)

```bash
# 1. Verify not a marketplace repo
ls .claude-plugin/marketplace.json 2>/dev/null && echo "MARKETPLACE - test elsewhere" || echo "OK - can test here"

# 2. Create test file
mkdir -p docs && cat > docs/TEST-LINK-ERRORS.md << 'EOF'
# Test Link Errors
- [Wrong](../README.md)
- [Wrong](./foo.md)
- [Wrong](bar/baz.md)
EOF

# 3. Verify lint-relative-paths detects it
~/.claude/plugins/marketplaces/cc-skills/plugins/statusline-tools/scripts/lint-relative-paths $(pwd)

# 4. Clean up after testing
rm docs/TEST-LINK-ERRORS.md
```
