# chrome-debug-port-guard

**Hook:** `hooks/pretooluse-chrome-debug-port-guard.ts` · **Event:** PreToolUse · **Matcher:** `Bash` · **Escape:** `CHROME-DEBUG-PORT-OK: <≥10-char reason>`

Blocks browser launches that **provably cannot work**, plus one launch shape that is a genuine security hole. It has no opinion about whether you should be driving a browser at all — that is a judgement call and is not decidable from a command string.

## Why this is a hard block and not a doc entry

Since **Chrome 136**, `--remote-debugging-port` and `--remote-debugging-pipe` are refused when the browser uses its **default user-data directory**. That was deliberate hardening: a non-default directory gets a different encryption key, so malware attaching over CDP cannot decrypt the real profile's cookies and passwords. Upstream announcement: <https://developer.chrome.com/blog/remote-debugging-port>.

The reason it earns a block is the **failure mode**, which does not look like a flag error. You get either `DevTools remote debugging requires a non-default data directory`, or — for an automation client — a browser that starts, reports healthy, and hangs on a blank page while the client waits for a port that was never opened. A confident wrong answer is this repo's standing bar for blocking, the same bar `headless-claude-p-guard` was built to.

## The three violations

| #   | Shape                                                      | Why it is blocked                                                               |
| --- | ---------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 1   | remote-debugging switch, **no** `--user-data-dir`          | Dead on Chrome ≥ 136; the port never opens                                      |
| 2   | `--user-data-dir` **is** the platform default profile root | Fails identically to #1, but reads as compliant so it is harder to spot         |
| 3   | `--remote-debugging-address` bound **off loopback**        | Hands full browser control — drive any page, read every cookie — to the network |

Default profile roots recognised for #2: macOS `Library/Application Support/Google/Chrome`, Linux `.config/google-chrome`, Windows `AppData\Local\Google\Chrome\User Data`, plus the Chromium variants. A **subdirectory** of one of those is deliberately NOT matched — it is a genuinely different directory, so Chrome accepts it and remote debugging works.

## What it deliberately does not touch

A guard on a flag that commonly appears in `pkill` and `grep` commands is one false positive away from being switched off, so the check requires a **positive browser-launch signal** and vetoes entirely on inspector/terminator verbs. These are allowed with no marker:

```bash
pkill -f "remote-debugging-port=9222"          # terminating a debug browser
ps aux | grep -i remote-debugging-port         # inspecting
curl -s http://127.0.0.1:9222/json/version     # probing the endpoint
echo --remote-debugging-port=9222 >> notes.txt # merely writing the flag down
```

If you find yourself reaching for the escape marker to unblock one of those, the guard has a bug — the fix is a test, not an opt-out.

## The launch shape it wants instead

```bash
osascript -e 'quit app "Google Chrome"'   # MUST fully quit — relaunching while an instance is alive
                                          # just opens a tab in it and silently drops every flag
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --remote-debugging-port=9222 \
  --user-data-dir="$HOME/.chrome-debug" &
curl -s http://127.0.0.1:9222/json/version   # JSON with webSocketDebuggerUrl == live
```

That is a **fresh profile**: no cookies, no logins, no extensions. Sign in once by hand in that window, or copy `Local State` plus the single profile directory you need with Chrome fully quit. **Close the port when done** (`pkill -f "remote-debugging-port=9222"`) — an open 9222 lets any local process drive the browser and read every cookie in that profile, which is the attack Chrome 136 hardened against in the first place.

## Escape hatch

`CHROME-DEBUG-PORT-OK:` followed by at least 10 characters of reason, anywhere in the command. A bare marker with no reason does **not** suppress. Legitimate uses are narrow: pinning an old Chrome (<136) where the default profile still works, driving a non-Chromium binary that merely shares the flag spelling, or a fixture in this guard's own test suite.

## Behaviour notes

- Fails **open**: any throw in its own logic is tracked and the command is allowed. A guard that blocks work when its own logic breaks is worse than the bug it prevents.
- Uses the ordinary single-signal deny (stdout JSON, exit 0, nothing on stderr). The belt-and-suspenders stdout+stderr+exit-2 form exists only for `Write|Edit`, where deny was reported ignored on some versions.
- Tests spawn the real hook and speak the real protocol, rather than re-asserting the hook's own regexes. One boundary bug was caught that way during development: the original `(?!\S)` terminator never matched a **quoted** default path, and those paths always contain a space (`Application Support`) so they are effectively always quoted — the check for violation #2 could never have fired.
