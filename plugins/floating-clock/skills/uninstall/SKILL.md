---
name: uninstall
description: "Quit FloatingClock, remove it from /Applications, and clear its saved preferences. Use when the user wants to completely uninstall the floating-clock app."
allowed-tools: Bash, AskUserQuestion
---

# /floating-clock:uninstall

Remove FloatingClock completely: terminate it, remove it from `/Applications/`, and clear its NSUserDefaults.

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
