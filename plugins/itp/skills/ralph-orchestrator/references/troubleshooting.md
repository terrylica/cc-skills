# Troubleshooting

Common issues and solutions when using Ralph Orchestrator.

## Quick Diagnostic

Run this to check your environment:

```bash
# Check available agents
which claude && echo "Claude: OK" || echo "Claude: NOT FOUND"
which gemini && echo "Gemini: OK" || echo "Gemini: NOT FOUND"
which q && echo "Q Chat: OK" || echo "Q Chat: NOT FOUND"

# Check Ralph status
ralph status

# View recent errors
cat .agent/metrics/state_*.json | jq '.errors' 2>/dev/null | tail -20
```

---

## Installation Issues

### Agent Not Found

**Symptom**: `ralph: command 'claude' not found`

**Cause**: AI agent CLI not installed or not in PATH.

**Solutions**:

```bash
# Verify installation
which claude
which gemini
which q

# Install missing agents
# Claude (via npm)
npm install -g @anthropic-ai/claude-code

# Gemini
npm install -g @google/gemini-cli

# Add to PATH if installed but not found
export PATH=$PATH:/usr/local/bin
export PATH=$PATH:$HOME/.npm/bin
```

### Permission Denied

**Symptom**: `Permission denied: './ralph'`

**Solution**:

```bash
chmod +x ralph ralph_orchestrator.py
```

### Python Version Mismatch

**Symptom**: `SyntaxError` or `ModuleNotFoundError`

**Cause**: Wrong Python version (Ralph requires 3.11+)

**Solution**:

```bash
# Check version
python --version

# Use specific version
python3.11 -m ralph_orchestrator

# Or use uv
uv run ralph
```

---

## Execution Issues

### Task Not Completing

**Symptom**: Ralph runs to max iterations without finishing.

**Causes**:

- Unclear requirements
- Too ambitious scope
- Agent not understanding the task

**Solutions**:

1. **Check progress**:

   ```bash
   ralph status
   cat .agent/metrics/state_latest.json | jq '.iteration_count, .errors'
   ```

2. **Simplify the task**:

   ```markdown
   # Instead of:

   Build a complete e-commerce platform

   # Try:

   Build a Flask app with one endpoint that returns product list as JSON
   ```

3. **Add explicit success criteria**:

   ```markdown
   ## Success Criteria

   - [ ] File `app.py` exists
   - [ ] Running `python app.py` starts server on port 5000
   - [ ] GET /products returns JSON array
   ```

4. **Try different agent**:

   ```bash
   ralph run -a gemini  # Larger context window
   ralph run -a claude  # Better reasoning
   ```

### Circular Corrections

**Symptom**: Agent makes a change, then reverts it, repeatedly.

**Cause**: Contradictory requirements or unclear spec.

**Solutions**:

1. Review PROMPT.md for contradictions
2. Add explicit constraints:

   ```markdown
   ## Constraints

   - Do NOT modify existing function signatures
   - Keep backward compatibility
   ```

3. Clear state and restart:

   ```bash
   ralph clean
   ralph run
   ```

### Agent Timeout

**Symptom**: `Agent execution timed out`

**Causes**:

- Complex task taking too long
- Agent stuck in loop
- Network issues

**Solutions**:

```bash
# Increase timeout in ralph.yml
adapters:
  claude:
    timeout: 600  # 10 minutes

# Or via command line
ralph run --max-runtime 7200  # 2 hours total
```

### Repeated Errors

**Symptom**: Same error occurs in multiple iterations.

**Diagnosis**:

```bash
# Check error pattern
cat .agent/metrics/state_*.json | jq '.errors[-5:]'
```

**Solutions**:

1. Add error context to PROMPT.md:

   ```markdown
   ## Known Issues

   The agent may encounter "ImportError: No module named X".
   Install missing modules with: pip install X
   ```

2. Clean and restart:

   ```bash
   ralph clean
   ralph run
   ```

3. Manual intervention - fix the issue, then continue:

   ```bash
   # Fix the problem manually
   pip install missing-module

   # Resume
   ralph run
   ```

---

## Context and Memory Issues

### Context Window Exceeded

**Symptom**:

- Agent forgets earlier instructions
- Incomplete responses
- `Context window limit exceeded` error

**Causes**:

- Large files in workspace
- Long iteration history
- Complex prompt

**Solutions**:

1. **Use agent with larger context**:

   ```bash
   ralph run -a gemini  # 2M token context
   ```

2. **Reduce prompt size**:
   - Remove unnecessary context
   - Use references instead of inline content
   - Focus on current task only

3. **Clear iteration history**:

   ```bash
   rm .agent/prompts/prompt_*.md
   ```

4. **Split into phases**:

   ```bash
   # Phase 1: Research
   ralph run --max-iterations 10 -p "Analyze the codebase structure"

   # Phase 2: Implementation (fresh context)
   ralph clean
   ralph run --max-iterations 50 -p "Implement feature X based on analysis"
   ```

### Agent Loses Track

**Symptom**: Agent starts working on unrelated tasks.

**Solutions**:

1. Add explicit focus in prompt:

   ```markdown
   ## Current Focus

   ONLY work on implementing the login endpoint.
   Do NOT modify any other files.
   ```

2. Use progress tracking:

   ```markdown
   ## Progress

   - [x] Database models created
   - [ ] Login endpoint (CURRENT)
   - [ ] Tests
   ```

---

## Git Issues

### Checkpoint Failed

**Symptom**: `Failed to create checkpoint`

**Causes**:

- No Git repo initialized
- Git user not configured
- Permission issues

**Solutions**:

```bash
# Initialize Git
git init
git add .
git commit -m "Initial commit"

# Configure Git user
git config user.email "you@example.com"
git config user.name "Your Name"

# Check permissions
ls -la .git
```

### Uncommitted Changes Warning

**Symptom**: `Uncommitted changes detected`

**Solutions**:

```bash
# Commit changes
git add .
git commit -m "Save current state"

# Or stash
git stash
ralph run
git stash pop

# Or disable Git
ralph run --no-git
```

### Reset to Checkpoint

**Need**: Recover from bad iteration.

```bash
# List checkpoints
git log --oneline | grep -i "ralph\|checkpoint"

# Reset to specific checkpoint
git reset --hard <commit-hash>

# Resume
ralph run
```

---

## Cost and Resource Issues

### Unexpected High Costs

**Symptom**: API costs higher than expected.

**Diagnosis**:

```bash
# Check token usage
cat .agent/metrics/state_*.json | jq '.total_tokens, .total_cost'
```

**Prevention**:

```bash
# Set strict limits
ralph run --max-cost 10.0 --max-tokens 100000

# Use cheaper agents for testing
ralph run -a q --max-cost 2.0

# Dry run first
ralph run --dry-run
```

### High Memory Usage

**Symptom**: System slows down, OOM errors.

**Solutions**:

```bash
# Clean old state files
find .agent -name "*.json" -mtime +7 -delete

# Reduce checkpoint frequency
ralph run --checkpoint-interval 10

# Restart Ralph
pkill -f ralph_orchestrator
ralph run
```

### Rate Limiting

**Symptom**: `Rate limit exceeded` errors.

**Solutions**:

1. Add delay between iterations:

   ```bash
   ralph run --retry-delay 5
   ```

2. Switch to different agent temporarily:

   ```bash
   ralph run -a gemini  # Different rate limits
   ```

3. Wait and resume:

   ```bash
   sleep 60
   ralph run
   ```

---

## Agent-Specific Issues

### Claude Errors

**"Invalid API key"**

```bash
# Check Claude configuration
claude --version
claude auth status

# Re-authenticate
claude auth login
```

**"Rate limit exceeded"**

- Wait 60 seconds and retry
- Upgrade API plan if frequent
- Use `--retry-delay 5` flag

### Gemini Errors

**"Quota exceeded"**

- Wait for quota reset (usually daily)
- Check usage in Google Cloud Console
- Upgrade plan if needed

**"Model not available"**

```bash
# Update Gemini CLI
npm update -g @google/gemini-cli

# Check available models
gemini models list
```

### Q Chat Errors

**"Connection refused"**

```bash
# Check Q service status
q status

# Restart Q service
q restart
```

---

## Recovery Procedures

### From Failed State

```bash
# 1. Save current state
cp -r .agent .agent.backup

# 2. Analyze failure
tail -n 100 .agent/logs/ralph.log 2>/dev/null
cat .agent/metrics/state_latest.json | jq '.errors[-3:]'

# 3. Fix the issue
# (Edit PROMPT.md, fix code, etc.)

# 4. Resume or restart
ralph run        # Continue from current state
# OR
ralph clean && ralph run  # Start fresh
```

### From Git Checkpoint

```bash
# List available checkpoints
git log --oneline | head -20

# Find last good state
git log --oneline | grep "checkpoint"

# Reset to checkpoint
git reset --hard <commit-hash>

# Clear Ralph state
rm -rf .agent/metrics/*.json

# Resume
ralph run
```

### Complete Reset

```bash
# Nuclear option: start completely fresh
ralph clean
rm -rf .agent
git reset --hard HEAD~10  # Reset to 10 commits ago
ralph init
ralph run
```

---

## Debug Mode

### Enable Verbose Logging

```bash
# Maximum verbosity
ralph run --verbose

# With debug environment
DEBUG=1 ralph run

# Save logs to file
ralph run --verbose 2>&1 | tee debug.log
```

### Inspect Execution

Add debug markers to PROMPT.md:

```markdown
## Debug Points

After each major step, output:
DEBUG: Step N complete - [description]
```

### Profile Execution

```bash
# Trace system calls
strace -o trace.log ralph run

# Profile Python execution
python -m cProfile -o profile.stats -m ralph_orchestrator run
```

---

## Common Error Codes

| Exit Code | Meaning              | Solution                 |
| --------- | -------------------- | ------------------------ |
| 0         | Success              | None needed              |
| 1         | General failure      | Check logs for details   |
| 130       | Interrupted (Ctrl+C) | Normal user interruption |
| 137       | Killed (OOM)         | Increase memory limits   |
| 124       | Timeout              | Increase timeout value   |

---

## Getting Help

### Self-Diagnosis Script

```bash
#!/bin/bash
echo "Ralph Orchestrator Diagnostic"
echo "============================="

echo -e "\n1. Environment:"
python --version
which ralph && ralph --version 2>/dev/null

echo -e "\n2. Agents:"
which claude && echo "  Claude: $(claude --version 2>/dev/null || echo 'installed')" || echo "  Claude: NOT FOUND"
which gemini && echo "  Gemini: installed" || echo "  Gemini: NOT FOUND"
which q && echo "  Q Chat: installed" || echo "  Q Chat: NOT FOUND"

echo -e "\n3. Git Status:"
git status --short 2>/dev/null || echo "  Not a git repository"

echo -e "\n4. Ralph Status:"
ralph status 2>/dev/null || echo "  Ralph not initialized"

echo -e "\n5. Recent Errors:"
cat .agent/metrics/state_*.json 2>/dev/null | jq '.errors[-3:]' || echo "  No state files found"
```

### Community Resources

- **GitHub Issues**: [Report bugs](https://github.com/mikeyobrien/ralph-orchestrator/issues)
- **Discussions**: [Ask questions](https://github.com/mikeyobrien/ralph-orchestrator/discussions)
- **Full Documentation**: [Online docs](https://mikeyobrien.github.io/ralph-orchestrator/)

### Bug Reports Should Include

1. Ralph version: `ralph --version`
2. Agent versions
3. Full error message
4. PROMPT.md content (redacted if sensitive)
5. Diagnostic output (script above)
6. Steps to reproduce
