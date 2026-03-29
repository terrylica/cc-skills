import Foundation
import Logging
import SwiftTelegramBot

/// Telegram bot using swift-telegram-sdk long polling.
/// Wraps TGBot actor and provides command handlers + message sending.
///
/// Extensions:
/// - `TelegramBotCommands.swift`      -- /start, /stop, /status, /health, etc.
/// - `TelegramBotNotifications.swift`  -- session notification dispatch + TTS
/// - `TelegramBotCallbacks.swift`      -- inline button callbacks + BotDispatcher
public final class TelegramBot: @unchecked Sendable {
    let logger = Logger(label: "telegram-bot")
    private(set) var bot: TGBot?
    private let botToken: String
    let chatId: Int64
    var isWatching: Bool = true
    let startTime: Date = Date()

    // Subsystem references for session notifications (BOT-03, BOT-04)
    let summaryEngine: SummaryEngine
    private let playbackManager: PlaybackManager
    private let ttsEngine: TTSEngine
    let subtitlePanel: SubtitlePanel  // @MainActor -- access must dispatch to main
    private let pipelineCoordinator: TTSPipelineCoordinator
    let ttsQueue: TTSQueue

    // Prompt execution (BOT-05, BOT-06)
    let promptExecutor = PromptExecutor()

    // Inline button state manager (BTN-01, BTN-02, BTN-03)
    let inlineButtonManager = InlineButtonManager()

    init(botToken: String, chatId: Int64, summaryEngine: SummaryEngine, playbackManager: PlaybackManager, ttsEngine: TTSEngine, subtitlePanel: SubtitlePanel, pipelineCoordinator: TTSPipelineCoordinator, ttsQueue: TTSQueue) {
        self.botToken = botToken
        self.chatId = chatId
        self.summaryEngine = summaryEngine
        self.playbackManager = playbackManager
        self.ttsEngine = ttsEngine
        self.subtitlePanel = subtitlePanel
        self.pipelineCoordinator = pipelineCoordinator
        self.ttsQueue = ttsQueue
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
            connectionType: .longpolling(limit: 100, timeout: 30, allowedUpdates: [.message, .callbackQuery]),
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

    // MARK: - Inline Keyboard (BTN-01, BTN-02, BTN-03)

    /// Send an HTML message with an inline keyboard. Returns the message ID on success.
    func sendMessageWithKeyboard(_ text: String, keyboard: TGInlineKeyboardMarkup, silent: Bool = false) async -> Int? {
        guard let bot = bot else {
            logger.warning("Cannot send message with keyboard: bot not started")
            return nil
        }
        do {
            let params = TGSendMessageParams(
                chatId: .chat(chatId),
                text: text,
                parseMode: .html,
                linkPreviewOptions: TGLinkPreviewOptions(isDisabled: true),
                disableNotification: silent,
                replyMarkup: .inlineKeyboardMarkup(keyboard)
            )
            let msg = try await bot.sendMessage(params: params)
            return msg.messageId
        } catch {
            logger.warning("Failed to send HTML with keyboard, retrying plain without keyboard: \(error)")
            // Fallback: plain text without keyboard (matching legacy pattern)
            do {
                let plainParams = TGSendMessageParams(
                    chatId: .chat(chatId),
                    text: TelegramFormatter.stripHtmlTags(text),
                    disableNotification: silent
                )
                let msg = try await bot.sendMessage(params: plainParams)
                return msg.messageId
            } catch {
                logger.error("Failed to send plain text fallback: \(error)")
                return nil
            }
        }
    }

    /// Remove inline keyboard from a message (for Focus Tab dedup).
    func removeInlineKeyboard(chatId: Int64, messageId: Int) async {
        guard let bot = bot else { return }
        do {
            try await bot.editMessageReplyMarkup(params: TGEditMessageReplyMarkupParams(
                chatId: .chat(chatId),
                messageId: messageId,
                replyMarkup: nil
            ))
        } catch {
            // Silently ignore -- message may be too old or already edited
            logger.debug("Could not remove keyboard from message \(messageId): \(error)")
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
}
