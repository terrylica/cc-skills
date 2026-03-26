---
phase: quick
plan: 260326-fvh
type: execute
wave: 1
depends_on: []
files_modified:
  - plugins/claude-tts-companion/launchd/com.terryli.claude-tts-companion.plist
autonomous: false
must_haves:
  truths:
    - "Old services (telegram-bot, kokoro-tts-server) are stopped but plists preserved"
    - "Kokoro model files exist at ~/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0/"
    - "claude-tts-companion binary installed at /usr/local/bin/claude-tts-companion"
    - "New service running under launchd with correct secrets"
    - "Health endpoint responds at localhost:8780/health"
  artifacts:
    - path: "/usr/local/bin/claude-tts-companion"
      provides: "Release binary (stripped)"
    - path: "/Users/terryli/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0/model.int8.onnx"
      provides: "Kokoro TTS model at canonical path"
    - path: "/Users/terryli/Library/LaunchAgents/com.terryli.claude-tts-companion.plist"
      provides: "Launchd plist with real secrets"
  key_links:
    - from: "com.terryli.claude-tts-companion service"
      to: "localhost:8780/health"
      via: "HTTP server startup on launch"
      pattern: "curl.*localhost:8780/health"
---

<objective>
Deploy claude-tts-companion as a unified launchd service replacing three separate processes.

Purpose: Consolidate telegram-bot + kokoro-tts-server + subtitle overlay into one binary running as a single launchd service.
Output: Running service at com.terryli.claude-tts-companion with health endpoint at localhost:8780.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@plugins/claude-tts-companion/scripts/install.sh
@plugins/claude-tts-companion/scripts/rollback.sh
@plugins/claude-tts-companion/launchd/com.terryli.claude-tts-companion.plist
@plugins/claude-tts-companion/Sources/claude-tts-companion/Config.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Populate plist secrets, copy model, build and install</name>
  <files>plugins/claude-tts-companion/launchd/com.terryli.claude-tts-companion.plist</files>
  <action>
  Three pre-flight steps before running install.sh:

1. **Populate plist with real secrets**: Read secrets from ~/.claude/.secrets/ccterrybot-telegram (MINIMAX_API_KEY, TELEGRAM_BOT_TOKEN=8527677636:AAGEg1RQ269rcXP_kj2eSF9FwrvINcN0ecg, TELEGRAM_CHAT_ID=90417581). Edit the plist file at plugins/claude-tts-companion/launchd/com.terryli.claude-tts-companion.plist to fill in the three empty string values. DO NOT commit this file with secrets — it will be used locally only and must be reverted after install.

2. **Copy model to canonical path**: The model lives at /Users/terryli/tmp/subtitle-spikes-7aqa/03-textream/models-int8/kokoro-int8-multi-lang-v1_0/. Copy the entire directory to the canonical path:

   ```
   mkdir -p ~/.local/share/kokoro/models/
   cp -R /Users/terryli/tmp/subtitle-spikes-7aqa/03-textream/models-int8/kokoro-int8-multi-lang-v1_0 ~/.local/share/kokoro/models/
   ```

   Verify model.int8.onnx exists at the destination.

3. **Run install.sh**: Execute the existing install script from plugins/claude-tts-companion/:

   ```
   cd plugins/claude-tts-companion && bash scripts/install.sh
   ```

   This script handles: swift build -c release, strip binary, copy to /usr/local/bin/, create log dir, copy plist, stop old services (bootout), bootstrap new service.

4. **Revert plist secrets**: After install completes, restore the plist to have empty secret strings so secrets are never committed to git:

   ```
   git checkout plugins/claude-tts-companion/launchd/com.terryli.claude-tts-companion.plist
   ```

  </action>
  <verify>
    <automated>launchctl print gui/501/com.terryli.claude-tts-companion 2>&1 | head -5 && curl -sf http://localhost:8780/health</automated>
  </verify>
  <done>
  - Binary at /usr/local/bin/claude-tts-companion (stripped, ~18MB)
  - Model at ~/.local/share/kokoro/models/kokoro-int8-multi-lang-v1_0/model.int8.onnx
  - Service running (launchctl print shows active)
  - Old services stopped (launchctl print for telegram-bot and kokoro-tts-server returns error)
  - Old plists preserved at ~/Library/LaunchAgents/ (NOT deleted)
  - Plist in repo reverted to empty secrets (git clean)
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <what-built>
  Deployed claude-tts-companion as unified launchd service. Old telegram-bot and kokoro-tts-server services stopped (plists preserved). New service running with health endpoint.
  </what-built>
  <how-to-verify>
  1. Check health endpoint: `curl http://localhost:8780/health` -- should return JSON with service status
  2. Check service is running: `launchctl print gui/501/com.terryli.claude-tts-companion | head -10`
  3. Verify old services are stopped: `launchctl print gui/501/com.terryli.telegram-bot` should fail
  4. Send a test message to the Telegram bot to verify it responds
  5. Check logs for any errors: `tail -20 ~/.local/state/launchd-logs/claude-tts-companion/stderr.log`
  6. If anything is wrong, rollback is available: `cd plugins/claude-tts-companion && bash scripts/rollback.sh`
  </how-to-verify>
  <resume-signal>Type "approved" or describe issues</resume-signal>
</task>

</tasks>

<verification>
- `curl -sf http://localhost:8780/health` returns 200
- `launchctl print gui/501/com.terryli.claude-tts-companion` shows active service
- `launchctl print gui/501/com.terryli.telegram-bot` returns error (stopped)
- `launchctl print gui/501/com.terryli.kokoro-tts-server` returns error (stopped)
- Old plists still exist: `ls ~/Library/LaunchAgents/com.terryli.telegram-bot.plist ~/Library/LaunchAgents/com.terryli.kokoro-tts-server.plist`
- `git diff plugins/claude-tts-companion/launchd/` shows no changes (secrets reverted)
</verification>

<success_criteria>
Health endpoint at localhost:8780/health responds with 200. Service running under launchd. Old services stopped but plists preserved. No secrets committed to git.
</success_criteria>

<output>
After completion, create `.planning/quick/260326-fvh-deploy-tts-companion/260326-fvh-SUMMARY.md`
</output>
