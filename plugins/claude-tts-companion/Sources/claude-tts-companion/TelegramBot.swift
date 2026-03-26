import Foundation
import Logging
import SwiftTelegramBot

/// Telegram bot using swift-telegram-sdk long polling.
/// Wraps TGBot actor and provides command handlers + message sending.
final class TelegramBot: @unchecked Sendable {
    private let logger = Logger(label: "telegram-bot")
    private var bot: TGBot?
    private let botToken: String
    private let chatId: Int64
    private var isWatching: Bool = true
    private let startTime: Date = Date()

    // Subsystem references for session notifications (BOT-03, BOT-04)
    private let summaryEngine: SummaryEngine
    private let ttsEngine: TTSEngine
    private let subtitlePanel: SubtitlePanel  // @MainActor -- access must dispatch to main

    // Prompt execution (BOT-05, BOT-06)
    private let promptExecutor = PromptExecutor()

    init(botToken: String, chatId: Int64, summaryEngine: SummaryEngine, ttsEngine: TTSEngine, subtitlePanel: SubtitlePanel) {
        self.botToken = botToken
        self.chatId = chatId
        self.summaryEngine = summaryEngine
        self.ttsEngine = ttsEngine
        self.subtitlePanel = subtitlePanel
    }

    // MARK: - Public API

    /// Whether the bot is currently monitoring sessions.
    var watching: Bool { isWatching }

    /// Send a notification message via Telegram (HTML parse mode).
    func sendNotification(_ text: String) async {
        await sendMessage(text, parseMode: .html)
    }

    // MARK: - Session Notifications (BOT-03, BOT-04, FMT-01, FMT-02, FMT-03)

    /// Send session-end notification with rich HTML header, Arc Summary as main message,
    /// Tail Brief as separate silent message, then dispatch TTS.
    /// Called by file watcher (Phase 7) when a session ends.
    func sendSessionNotification(
        sessionId: String,
        turns: [ConversationTurn],
        cwd: String?,
        gitBranch: String?,
        startTime: Date?,
        lastActivity: Date?
    ) async {
        guard isWatching else {
            logger.info("Skipping notification -- bot not watching")
            return
        }

        // Generate both summaries concurrently
        async let arcResult = summaryEngine.arcSummary(turns: turns, cwd: cwd)
        async let tailResult = summaryEngine.tailBrief(turns: turns, cwd: cwd)

        let arc = await arcResult
        let tail = await tailResult

        // Extract last user prompt from turns (FMT-02)
        let lastPrompt = turns.last(where: { !$0.prompt.isEmpty })?.prompt

        // Build SessionNotificationData for rich HTML rendering (FMT-01)
        let notifData = SessionNotificationData(
            sessionId: sessionId,
            cwd: cwd ?? "unknown",
            gitBranch: gitBranch,
            startTime: startTime ?? turns.first?.timestamp,
            lastActivity: lastActivity ?? Date(),
            turnCount: turns.count,
            lastUserPrompt: lastPrompt,
            aiNarrative: arc.narrative != "Session completed." ? arc.narrative : nil,
            promptSummary: arc.promptSummary
        )

        // Render rich HTML notification with metadata header
        let message = TelegramFormatter.renderSessionNotification(notifData)

        // If rendering produced nothing useful, send minimal fallback
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await sendMessage("<b>Session Complete</b>\n\n<i>Summary generation failed or was skipped.</i>")
        } else {
            await sendMessage(message)
        }

        // Send Tail Brief as separate silent message (FMT-03)
        if !tail.narrative.isEmpty {
            let tbrMessage = "<b>Tail Brief</b>:\n\(TelegramFormatter.escapeHtml(tail.narrative))"
            await sendSilentMessage(tbrMessage)
        }

        // Dispatch TTS for Tail Brief with karaoke subtitles (BOT-04)
        if !tail.narrative.isEmpty {
            await dispatchTTS(text: tail.narrative, greeting: arc.ttsGreeting)
        }
    }

    /// Send a silent HTML message (no push notification). Used for Tail Brief (FMT-03).
    func sendSilentMessage(_ text: String) async {
        guard let bot = bot else {
            logger.warning("Cannot send silent message: bot not started")
            return
        }
        let chunks = TelegramFormatter.chunkTelegramHtml(text)
        for chunk in chunks {
            do {
                let params = TGSendMessageParams(
                    chatId: .chat(chatId),
                    text: chunk,
                    parseMode: .html,
                    linkPreviewOptions: TGLinkPreviewOptions(isDisabled: true),
                    disableNotification: true
                )
                try await bot.sendMessage(params: params)
            } catch {
                logger.warning("Failed to send silent HTML, retrying plain: \(error)")
                do {
                    let plainParams = TGSendMessageParams(
                        chatId: .chat(chatId),
                        text: TelegramFormatter.stripHtmlTags(chunk),
                        disableNotification: true
                    )
                    try await bot.sendMessage(params: plainParams)
                } catch {
                    logger.error("Failed to send silent plain text: \(error)")
                }
            }
        }
    }

    /// Synthesize text and play with synchronized karaoke subtitles.
    private func dispatchTTS(text: String, greeting: String?) async {
        // Build full TTS text with optional greeting
        let fullText: String
        if let greeting = greeting, !greeting.isEmpty {
            fullText = "\(greeting) \(text)"
        } else {
            fullText = text
        }

        logger.info("Dispatching TTS: \(fullText.count) chars")

        ttsEngine.synthesizeWithTimestamps(text: fullText) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let ttsResult):
                self.logger.info("TTS synthesis complete: \(String(format: "%.2f", ttsResult.audioDuration))s")

                // Show karaoke subtitles on main thread (SubtitlePanel is @MainActor)
                DispatchQueue.main.async {
                    self.subtitlePanel.showUtterance(ttsResult.text, wordTimings: ttsResult.wordTimings)
                }

                // Play audio concurrently with subtitle display
                self.ttsEngine.play(wavPath: ttsResult.wavPath) {
                    self.logger.info("TTS playback complete")
                }

            case .failure(let error):
                self.logger.error("TTS dispatch failed: \(error)")
            }
        }
    }

    // MARK: - Boot Sequence

    /// Start the bot: connect via long polling, register commands, begin receiving updates.
    func start() async throws {
        let client = TGClientDefault()
        let tgBot = try await TGBot(
            connectionType: .longpolling(limit: 100, timeout: 30, allowedUpdates: [.message]),
            tgClient: client,
            botId: botToken
        )
        self.bot = tgBot

        // Create and register dispatcher with command handlers
        let dispatcher = BotDispatcher(bot: tgBot, telegramBot: self, logger: logger)
        try await tgBot.add(dispatcher: dispatcher)

        // Register command menu with Telegram
        let commands: [TGBotCommand] = [
            TGBotCommand(command: "start", description: "Start monitoring sessions"),
            TGBotCommand(command: "stop", description: "Stop monitoring"),
            TGBotCommand(command: "status", description: "View bot status"),
            TGBotCommand(command: "health", description: "Check connectivity"),
            TGBotCommand(command: "sessions", description: "List recent sessions"),
            TGBotCommand(command: "prompt", description: "Send prompt to Claude CLI"),
            TGBotCommand(command: "done", description: "Detach from session"),
            TGBotCommand(command: "commands", description: "Show available commands"),
        ]
        try await tgBot.setMyCommands(params: TGSetMyCommandsParams(commands: commands))

        // Start long polling
        try await tgBot.start()
        logger.info("Telegram bot started (long polling)")
    }

    /// Stop the bot gracefully.
    func stop() async {
        guard let bot = bot else { return }
        do {
            try await bot.stop()
            logger.info("Telegram bot stopped")
        } catch {
            logger.error("Error stopping Telegram bot: \(error)")
        }
    }

    // MARK: - Message Sending

    /// Send an HTML message, chunking if needed. On failure, retries with plain text.
    func sendMessage(_ text: String, parseMode: TGParseMode = .html) async {
        guard let bot = bot else {
            logger.warning("Cannot send message: bot not started")
            return
        }

        let chunks: [String]
        if parseMode == .html {
            chunks = TelegramFormatter.chunkTelegramHtml(text)
        } else {
            // For non-HTML, simple character-based chunking
            if text.count <= TelegramFormatter.telegramMaxLength {
                chunks = [text]
            } else {
                var result: [String] = []
                var remaining = text
                while remaining.count > TelegramFormatter.telegramMaxLength {
                    let idx = remaining.index(remaining.startIndex, offsetBy: TelegramFormatter.telegramMaxLength)
                    result.append(String(remaining[..<idx]))
                    remaining = String(remaining[idx...])
                }
                if !remaining.isEmpty { result.append(remaining) }
                chunks = result
            }
        }

        for chunk in chunks {
            do {
                let params = TGSendMessageParams(
                    chatId: .chat(chatId),
                    text: chunk,
                    parseMode: parseMode,
                    linkPreviewOptions: TGLinkPreviewOptions(isDisabled: true)
                )
                try await bot.sendMessage(params: params)
            } catch {
                logger.warning("Failed to send HTML message, retrying as plain text: \(error)")
                // Retry with stripped HTML as plain text fallback
                do {
                    let plainText = TelegramFormatter.stripHtmlTags(chunk)
                    let fallbackParams = TGSendMessageParams(
                        chatId: .chat(chatId),
                        text: plainText
                    )
                    try await bot.sendMessage(params: fallbackParams)
                } catch {
                    logger.error("Failed to send plain text fallback: \(error)")
                }
            }
        }
    }

    /// Send a message and return its message_id for later editing (edit-in-place pattern).
    func sendMessageReturningId(_ text: String) async -> Int? {
        guard let bot = bot else {
            logger.warning("Cannot send message: bot not started")
            return nil
        }
        do {
            let params = TGSendMessageParams(
                chatId: .chat(chatId),
                text: text,
                parseMode: .html,
                linkPreviewOptions: TGLinkPreviewOptions(isDisabled: true)
            )
            let msg = try await bot.sendMessage(params: params)
            return msg.messageId
        } catch {
            logger.error("Failed to send message for edit-in-place: \(error)")
            return nil
        }
    }

    /// Edit an existing message by ID. Retries with plain text on HTML parse error.
    func editMessage(messageId: Int, text: String) async {
        guard let bot = bot else { return }
        do {
            let params = TGEditMessageTextParams(
                chatId: .chat(chatId),
                messageId: messageId,
                text: text,
                parseMode: .html,
                linkPreviewOptions: TGLinkPreviewOptions(isDisabled: true)
            )
            try await bot.editMessageText(params: params)
        } catch {
            // Retry with plain text on HTML parse error
            do {
                let plainParams = TGEditMessageTextParams(
                    chatId: .chat(chatId),
                    messageId: messageId,
                    text: TelegramFormatter.stripHtmlTags(text)
                )
                try await bot.editMessageText(params: plainParams)
            } catch {
                logger.warning("Failed to edit message \(messageId): \(error)")
            }
        }
    }

    // MARK: - Command Handlers

    /// Reply to a specific chat (used by command handlers to reply to the sender).
    private func replyToChat(_ chatId: Int64, text: String) async {
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
        let ttsStatus = "Available (Kokoro int8)"
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

    private func formatUptime(since date: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(date))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Bot Dispatcher

/// Custom dispatcher that registers all 7 command handlers.
private final class BotDispatcher: TGDefaultDispatcher {
    unowned let telegramBot: TelegramBot

    init(bot: TGBot, telegramBot: TelegramBot, logger: Logger) {
        self.telegramBot = telegramBot
        super.init(bot: bot, logger: logger)
    }

    override func handle() async {
        await add(TGCommandHandler(commands: ["start"]) { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handleStart(update: update)
        })

        await add(TGCommandHandler(commands: ["stop"]) { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handleStop(update: update)
        })

        await add(TGCommandHandler(commands: ["status"]) { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handleStatus(update: update)
        })

        await add(TGCommandHandler(commands: ["health"]) { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handleHealth(update: update)
        })

        await add(TGCommandHandler(commands: ["sessions"]) { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handleSessions(update: update)
        })

        await add(TGCommandHandler(commands: ["prompt"]) { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handlePrompt(update: update)
        })

        await add(TGCommandHandler(commands: ["done"]) { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handleDone(update: update)
        })

        await add(TGCommandHandler(commands: ["commands"]) { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handleCommands(update: update)
        })
    }
}
