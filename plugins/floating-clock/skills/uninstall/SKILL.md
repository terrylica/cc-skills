---
name: uninstall
description: Quit FloatingClock, remove it from /Applications, and clear its saved preferences. Use when the user wants to completely uninstall the.
allowed-tools: Bash, AskUserQuestion
---

# /floating-clock:uninstall

Remove FloatingClock completely: terminate it, remove it from `/Applications/`, and clear its NSUserDefaults.

> **Self-Evolving Skill**: This skill improves through use. If the uninstall step misses a path (new pref domain, new auxiliary file) — fix this file immediately, don't defer. Only update for real, reproducible issues.

## Steps

1. Confirm with the user first — uninstall is destructive:

   ```
   AskUserQuestion(
     header: "Uninstall",
     question: "Remove FloatingClock from /Applications/ and clear all saved settings?",
     options: [
       { label: "Yes, uninstall", description: "Quits app, removes bundle, clears preferences" },
       { label: "Cancel", description: "Do nothing" }
     ],
     multiSelect: false
   )
   ```

2. If cancelled, print `Uninstall cancelled.` and exit.

3. If confirmed:

   ```bash
   pkill -f "FloatingClock.app/Contents/MacOS/floating-clock" 2>/dev/null || true
   rm -rf /Applications/FloatingClock.app
   defaults delete com.terryli.floating-clock 2>/dev/null || true
   echo "FloatingClock uninstalled. (The plugin itself remains — remove it separately via 'claude plugin marketplace remove' if desired.)"
   ```

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the pref domain delete succeed?** — If `defaults` returned an error other than "not found", investigate.
2. **Are there any auxiliary files left behind?** — Check `~/Library/Saved Application State/`, log files, etc., and add to the cleanup if so.
3. **Did the AskUserQuestion confirmation flow work as expected?** — If the user wanted finer control (e.g., keep prefs), add an option.

Only update if the issue is real and reproducible — not speculative.
