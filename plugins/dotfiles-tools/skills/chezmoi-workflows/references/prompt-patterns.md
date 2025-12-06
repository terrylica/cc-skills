**Skill**: [Chezmoi Workflows](../SKILL.md)

## Prompt Pattern 1: Track Changes

**User says**: "I edited [file]. Track the changes."

**Workflow**:

1. **Verify drift**

   ```bash
   chezmoi status
   ```

   Expected: Shows modified file(s) with 'M' indicator

2. **Show changes**

   ```bash
   chezmoi diff [file]
   ```

   Expected: Displays unified diff of changes

3. **Add to source state** (auto-commits)

   ```bash
   chezmoi add [file]
   ```

   Expected: File added to source directory, git commit created automatically
   Note: `autocommit = true` in chezmoi.toml triggers automatic commit

4. **Verify commit**

   ```bash
   cd ~/.local/share/chezmoi && git log -1 --oneline
   ```

   Expected: Shows new commit with timestamp

5. **Push to remote**

   ```bash
   cd ~/.local/share/chezmoi && git push
   ```

   Expected: Successfully pushed to remote

6. **Confirm to user**
   - Show commit message
   - Show files changed
   - Confirm push success

---

## Prompt Pattern 2: Sync from Remote

**User says**: "Sync my dotfiles from remote."

**Workflow**:

1. **Pull and apply**

   ```bash
   chezmoi update
   ```

   Expected: Pulls from GitHub, applies changes to home directory
   Note: Equivalent to `git pull` + `chezmoi apply`

2. **Show what changed**

   ```bash
   chezmoi status
   ```

   Expected: Should show empty (no drift after sync)

3. **Verify SLOs**

   ```bash
   chezmoi verify
   ```

   Expected: Exit code 0 (all files match source state)

4. **Confirm to user**
   - Show files updated
   - Confirm no errors
   - Report SLO status

---

## Prompt Pattern 3: Push to Remote

**User says**: "Push my dotfile changes to GitHub."

**Workflow**:

1. **Check drift**

   ```bash
   chezmoi status
   ```

   Expected: Shows any untracked modifications

2. **Re-add all modified tracked files**

   ```bash
   chezmoi re-add
   ```

   Expected: Updates source state for all managed files, creates commit

3. **Show commit log**

   ```bash
   cd ~/.local/share/chezmoi && git log --oneline -3
   ```

   Expected: Shows recent commits including new auto-commit

4. **Push to remote**

   ```bash
   cd ~/.local/share/chezmoi && git push
   ```

   Expected: Successfully pushed to origin/main

5. **Confirm to user**
   - Show commit count pushed
   - Show commit messages
   - Confirm push success

---

## Prompt Pattern 4: Check Status

**User says**: "Check my dotfile status."

**Workflow**:

1. **Check drift**

   ```bash
   chezmoi status
   ```

   Expected: Lists modified/added/deleted files with indicators (M/A/D)

2. **List managed files**

   ```bash
   chezmoi managed
   ```

   Expected: Shows all files tracked by chezmoi

3. **Explain drift**
   - If drift detected: Explain which files differ
   - If no drift: Confirm everything synchronized
   - Suggest next action (track changes, sync, push, etc.)

---

## Prompt Pattern 5: Track New File

**User says**: "Track [file path] with chezmoi."

**Workflow**:

1. **Add file**

   ```bash
   chezmoi add [file]
   ```

   Expected: File added to source directory, commit created

2. **Verify in managed list**

   ```bash
   chezmoi managed | grep [filename]
   ```

   Expected: File appears in managed list

3. **Push to remote**

   ```bash
   cd ~/.local/share/chezmoi && git push
   ```

   Expected: Successfully pushed

4. **Confirm to user**
   - Show file now tracked
   - Confirm pushed to remote

---

## Prompt Pattern 6: Resolve Conflicts

**User says**: "I have merge conflicts. Help resolve them."

**Workflow**:

1. **Check git status**

   ```bash
   cd ~/.local/share/chezmoi && git status
   ```

   Expected: Shows conflicted files

2. **Show conflicted files**
   - List each file with conflict markers
   - Explain the conflict (local vs. remote changes)

3. **Guide resolution**
   - Ask user which version to keep (local/remote/manual merge)
   - For manual merge: show conflict markers and guide editing

4. **Complete merge**

   ```bash
   cd ~/.local/share/chezmoi
   git add [resolved-files]
   git commit -m "Resolve merge conflict in [files]"
   ```

5. **Apply to home directory**

   ```bash
   chezmoi apply
   ```

   Expected: Resolved changes applied to home directory

6. **Push to remote**

   ```bash
   cd ~/.local/share/chezmoi && git push
   ```

7. **Verify SLOs**

   ```bash
   chezmoi verify
   ```
