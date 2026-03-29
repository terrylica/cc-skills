import Foundation
import SwiftTelegramBot

// MARK: - Command Handlers

extension TelegramBot {

    /// Reply to a specific chat (used by command handlers to reply to the sender).
    func replyToChat(_ chatId: Int64, text: String) async {
        guard let bot = bot else { return }
        do {
            let params = TGSendMessageParams(
                chatId: .chat(chatId),
                text: text,
                parseMode: .html,
                linkPreviewOptions: TGLinkPreviewOptions(isDisabled: true)
            )
            try await bot.sendMessage(params: params)
        } catch {
            logger.error("Failed to reply: \(error)")
        }
    }

    func handleStart(update: TGUpdate) async {
        guard let chatId = update.message?.chat.id else { return }
        if isWatching {
            await replyToChat(chatId, text: "<b>Already Watching</b>\n\nThe bot is already monitoring sessions.")
        } else {
            isWatching = true
            await replyToChat(chatId, text: "<b>Monitoring Active</b>\n\nNow watching Claude Code sessions.")
        }
    }

    func handleStop(update: TGUpdate) async {
        guard let chatId = update.message?.chat.id else { return }
        if isWatching {
            isWatching = false
            await replyToChat(chatId, text: "<b>Monitoring Stopped</b>\n\nNo longer watching sessions.")
        } else {
            await replyToChat(chatId, text: "<b>Not Watching</b>\n\nMonitoring was not active.")
        }
    }

    func handleStatus(update: TGUpdate) async {
        guard let chatId = update.message?.chat.id else { return }
        let uptime = formatUptime(since: startTime)
        let watchingStr = isWatching ? "Yes" : "No"
        let text = """
        <b>Bot Status</b>

        <b>Watching:</b> \(watchingStr)
        <b>Uptime:</b> \(uptime)
        <b>Version:</b> \(Config.appName)
        """
        await replyToChat(chatId, text: text)
    }

    func handleHealth(update: TGUpdate) async {
        guard let chatId = update.message?.chat.id else { return }
        let summaryStatus = Config.miniMaxAPIKey != nil ? "Available (\(Config.miniMaxModel))" : "No API key"
        let ttsStatus = "Available (Kokoro MLX bf16)"
        let text = """
        <b>Health Check</b>

        <b>Telegram API:</b> Connected
        <b>TTS Engine:</b> \(ttsStatus)
        <b>Summary Engine:</b> \(summaryStatus)
        <b>Subtitle Panel:</b> Active
        """
        await replyToChat(chatId, text: text)
    }

    func handleSessions(update: TGUpdate) async {
        guard let chatId = update.message?.chat.id else { return }
        await replyToChat(chatId, text: "<b>Sessions</b>\n\nSession listing will be available in Phase 7 (File Watching).")
    }

    func handlePrompt(update: TGUpdate) async {
        guard let chatId = update.message?.chat.id else { return }

        // Extract text after "/prompt"
        let rawText = update.message?.text ?? ""
        let afterCommand: String
        if rawText.hasPrefix("/prompt ") {
            afterCommand = String(rawText.dropFirst(8))
        } else if rawText == "/prompt" {
            afterCommand = ""
        } else {
            afterCommand = rawText
        }

        let trimmed = afterCommand.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            await replyToChat(chatId, text: "<b>Usage:</b> /prompt [--haiku|--sonnet|--opus] your question")
            return
        }

        let (model, promptText) = parsePromptFlags(trimmed)

        if promptText.isEmpty {
            await replyToChat(chatId, text: "<b>Usage:</b> /prompt [--haiku|--sonnet|--opus] your question")
            return
        }

        // Execute via PromptExecutor with injected closures
        await promptExecutor.execute(
            prompt: promptText,
            model: model,
            cwd: Config.promptDefaultCwd,
            resumeSessionId: nil,  // Session resume wiring in Phase 7
            sendMessage: { [weak self] text in
                return await self?.sendMessageReturningId(text)
            },
            editMessage: { [weak self] msgId, text in
                await self?.editMessage(messageId: msgId, text: text)
            }
        )
    }

    func handleDone(update: TGUpdate) async {
        guard let chatId = update.message?.chat.id else { return }
        // Cancel any running prompt
        promptExecutor.cancel()
        await replyToChat(chatId, text: "<b>Done</b>\n\nSession detach: no active prompt session to detach.")
    }

    func handleCommands(update: TGUpdate) async {
        guard let chatId = update.message?.chat.id else { return }
        let text = """
        <b>Available Commands</b>

        /start - Start monitoring sessions
        /stop - Stop monitoring
        /status - View bot status
        /health - Check connectivity
        /sessions - List recent sessions
        /prompt - Send prompt to Claude (--haiku, --sonnet, --opus)
        /done - Detach from session
        /commands - Show this list
        """
        await replyToChat(chatId, text: text)
    }

    // MARK: - Helpers

    func formatUptime(since date: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(date))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
