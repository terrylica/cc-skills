<!-- # SSoT-OK -->

# Phase 29: Telegram Bot Activation - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase)

<domain>
## Phase Boundary

Wire Telegram bot credentials into claude-tts-companion launchd plist so the bot connects and delivers session notifications. Currently "Bot: unknown" because TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID are not in the plist's EnvironmentVariables.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

- Read credentials from ~/.claude/.secrets/ccterrybot-telegram (format: KEY=VALUE lines)
- Add TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID to ~/Library/LaunchAgents/com.terryli.claude-tts-companion.plist EnvironmentVariables
- Also need MINIMAX_API_KEY for AI summaries (check if it's in the secrets file or elsewhere)
- Restart service after plist update to pick up new env vars
- Verify bot connects by checking /health endpoint bot subsystem status

</decisions>

<canonical_refs>

## Canonical References

- `~/Library/LaunchAgents/com.terryli.claude-tts-companion.plist` — Launchd plist to modify
- `~/.claude/.secrets/ccterrybot-telegram` — Credentials source
- `plugins/claude-tts-companion/Sources/CompanionCore/Config.swift` — Env var names
- `plugins/claude-tts-companion/Sources/CompanionCore/TelegramBot.swift` — Bot connection logic
- `.planning/REQUIREMENTS.md` — BOT-10, BOT-11, BOT-12

</canonical_refs>

<code_context>

## Existing Code Insights

- CompanionApp.swift reads Config.telegramBotToken and Config.telegramChatId from env vars
- If either is missing, bot is not created (graceful fallback, logs warning)
- Bot uses swift-telegram-sdk long polling — connects automatically when token is valid
- Session notifications already implemented in TelegramBot.sendSessionNotification()

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond ROADMAP success criteria.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

_Phase: 29-telegram-bot-activation_
_Context gathered: 2026-03-28 via auto mode_
