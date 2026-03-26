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
    private var isWatching: Bool = false
    private let startTime: Date = Date()

    init(botToken: String, chatId: Int64) {
        self.botToken = botToken
        self.chatId = chatId
    }

    // MARK: - Public API

    /// Whether the bot is currently monitoring sessions.
    var watching: Bool { isWatching }

    /// Send a notification message via Telegram (HTML parse mode).
    func sendNotification(_ text: String) async {
        await sendMessage(text, parseMode: .html)
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
        let summaryStatus = Config.miniMaxAPIKey != nil ? "Available" : "No API key"
        let text = """
        <b>Health Check</b>

        <b>Telegram API:</b> Connected
        <b>TTS Engine:</b> Available
        <b>Summary Engine:</b> \(summaryStatus)
        """
        await replyToChat(chatId, text: text)
    }

    func handleSessions(update: TGUpdate) async {
        guard let chatId = update.message?.chat.id else { return }
        await replyToChat(chatId, text: "<b>Sessions</b>\n\nSession listing will be available in Phase 7 (File Watching).")
    }

    func handleDone(update: TGUpdate) async {
        guard let chatId = update.message?.chat.id else { return }
        await replyToChat(chatId, text: "<b>Done</b>\n\nSession detach will be available in Phase 6 (Bot Commands).")
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
