import Foundation
import Logging
import SwiftTelegramBot

// MARK: - Bot Dispatcher (command wiring + callback query handlers)

/// Custom dispatcher that registers all command handlers and callback query handlers.
final class BotDispatcher: TGDefaultDispatcher {
    unowned let telegramBot: TelegramBot

    init(bot: TGBot, telegramBot: TelegramBot, logger: Logger) {
        self.telegramBot = telegramBot
        super.init(bot: bot, logger: logger)
    }

    override func handle() async {
        // MARK: Command Handlers

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

        // MARK: Callback Query Handlers (BTN-01, BTN-02, BTN-03)

        // Focus Tab: switch iTerm2 to the session's tab
        await add(TGCallbackQueryHandler(name: "focusTab", pattern: "^iterm:") { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handleFocusTabCallback(update: update, bot: self.bot)
        })

        // Ask About This: show session CWD info for follow-up Q&A
        await add(TGCallbackQueryHandler(name: "followUp", pattern: "^fu:") { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handleFollowUpCallback(update: update, bot: self.bot)
        })

        // Transcript: show parsed transcript overview
        await add(TGCallbackQueryHandler(name: "transcript", pattern: "^tx:") { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handleTranscriptCallback(update: update, bot: self.bot)
        })

        // Transcript pagination: navigate pages
        await add(TGCallbackQueryHandler(name: "transcriptPage", pattern: "^txp:") { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handleTranscriptPageCallback(update: update, bot: self.bot)
        })

        // MARK: Text Message Handler — MiniMax Q&A for free-text messages
        await add(TGMessageHandler(name: "textQA") { [weak self] update in
            guard let self = self else { return }
            await self.telegramBot.handleTextMessage(update: update, bot: self.bot)
        })
    }
}

// MARK: - Callback Handler Methods

extension TelegramBot {

    /// Handle Focus Tab callback: switch iTerm2 to the session's tab via AppleScript.
    func handleFocusTabCallback(update: TGUpdate, bot: TGBot) async {
        guard let query = update.callbackQuery, let data = query.data else { return }

        let uuid = String(data.dropFirst(6)) // drop "iterm:"
        // Validate UUID-like format (hex chars and dashes, 8-36 chars)
        let uuidChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        guard uuid.count >= 8, uuid.count <= 36,
              uuid.unicodeScalars.allSatisfy({ uuidChars.contains($0) }) else {
            try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                callbackQueryId: query.id, text: "Invalid session ID"))
            return
        }

        // Run AppleScript to switch iTerm2 tab
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if unique ID of s ends with "\(uuid)" then
                            select t
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
            return "not found"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        var resultText = "Tab not found"
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if output == "ok" {
                resultText = "Tab focused"
            }
        } catch {
            logger.warning("AppleScript failed: \(error)")
            resultText = "AppleScript error"
        }

        try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
            callbackQueryId: query.id, text: resultText))
    }

    /// Handle Follow Up callback: show session CWD info for manual prompt.
    func handleFollowUpCallback(update: TGUpdate, bot: TGBot) async {
        guard let query = update.callbackQuery, let data = query.data else { return }

        guard let idStr = data.split(separator: ":").last, let id = Int(idStr) else {
            try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                callbackQueryId: query.id, text: "Invalid button data"))
            return
        }

        guard let notif = inlineButtonManager.lookupNotification(id: id) else {
            try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                callbackQueryId: query.id, text: "Button expired."))
            return
        }

        try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
            callbackQueryId: query.id, text: "Ask me anything about this session!"))

        let message = """
        <b>💬 Ask About This</b>

        <b>Workspace:</b> \(TelegramFormatter.escapeHtml(notif.workspace))
        <b>CWD:</b> <code>\(TelegramFormatter.escapeHtml(notif.cwd))</code>

        Reply to this message or type any question about this session.
        """
        await sendSilentMessage(message)
    }

    /// Handle Transcript callback: show parsed transcript overview.
    func handleTranscriptCallback(update: TGUpdate, bot: TGBot) async {
        guard let query = update.callbackQuery, let data = query.data else { return }

        guard let idStr = data.split(separator: ":").last, let id = Int(idStr) else {
            try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                callbackQueryId: query.id, text: "Invalid button data"))
            return
        }

        guard let notif = inlineButtonManager.lookupNotification(id: id) else {
            try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                callbackQueryId: query.id, text: "Button expired."))
            return
        }

        try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
            callbackQueryId: query.id, text: "Loading transcript..."))

        let transcriptHtml = formatTranscriptView(transcriptPath: notif.transcriptPath)
        let chunks = TelegramFormatter.chunkTelegramHtml(transcriptHtml)

        if chunks.count <= 1 {
            await sendSilentMessage(chunks.first ?? "<i>Empty transcript</i>")
        } else {
            // Store chunks for pagination
            inlineButtonManager.storeTranscriptPages(notifId: id, chunks: chunks)
            let pageKeyboard = inlineButtonManager.buildTranscriptPaginationKeyboard(
                notifId: id, currentPage: 0, totalPages: chunks.count)
            _ = await sendMessageWithKeyboard(
                chunks[0], keyboard: pageKeyboard, silent: true)
        }
    }

    /// Handle Transcript pagination callback: navigate between pages.
    func handleTranscriptPageCallback(update: TGUpdate, bot: TGBot) async {
        guard let query = update.callbackQuery, let data = query.data else { return }

        // Parse txp:{notifId}:{page}
        let parts = data.split(separator: ":")
        guard parts.count >= 3,
              let notifId = Int(parts[1]),
              let page = Int(parts[2]) else {
            try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                callbackQueryId: query.id, text: "Invalid page data"))
            return
        }

        guard let chunks = inlineButtonManager.lookupTranscriptPages(notifId: notifId),
              page >= 0, page < chunks.count else {
            try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                callbackQueryId: query.id, text: "Page expired."))
            return
        }

        // Edit the message with the requested page
        let pageKeyboard = inlineButtonManager.buildTranscriptPaginationKeyboard(
            notifId: notifId, currentPage: page, totalPages: chunks.count)

        // Get chat and message ID from the callback query's message
        if case .message(let msg) = query.message {
            do {
                try await bot.editMessageText(params: TGEditMessageTextParams(
                    chatId: .chat(msg.chat.id),
                    messageId: msg.messageId,
                    text: chunks[page],
                    parseMode: .html,
                    linkPreviewOptions: TGLinkPreviewOptions(isDisabled: true),
                    replyMarkup: pageKeyboard
                ))
            } catch {
                logger.warning("Failed to edit transcript page: \(error)")
            }
        }

        try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
            callbackQueryId: query.id))
    }

    /// Format a transcript view for the Transcript button callback.
    /// Shows numbered user prompts with tool counts.
    func formatTranscriptView(transcriptPath: String) -> String {
        let entries = TranscriptParser.parse(filePath: transcriptPath)

        // Count prompts and tools inline
        var promptCount = 0
        var toolUseCount = 0
        for entry in entries {
            switch entry {
            case .prompt: promptCount += 1
            case .toolUse: toolUseCount += 1
            default: break
            }
        }

        var lines: [String] = []
        lines.append("<b>Transcript</b> (\(promptCount) prompts, \(toolUseCount) tools)\n")

        // Walk entries and build per-turn summaries
        var turnNumber = 0
        var currentToolCount = 0
        var lastResponseSnippet: String?

        for entry in entries {
            switch entry {
            case .prompt(let text, _):
                // Flush previous turn
                if turnNumber > 0, let resp = lastResponseSnippet {
                    let toolSuffix = currentToolCount > 0 ? " [\(currentToolCount) tools]" : ""
                    lines.append("  \u{2192} \(TelegramFormatter.escapeHtml(String(resp.prefix(200))))\(toolSuffix)")
                }
                turnNumber += 1
                currentToolCount = 0
                lastResponseSnippet = nil
                let snippet = String(text.prefix(200))
                lines.append("\n<b>\(turnNumber).</b> \(TelegramFormatter.escapeHtml(snippet))")

            case .response(let text, _):
                lastResponseSnippet = text

            case .toolUse(_, _):
                currentToolCount += 1

            default:
                break
            }
        }

        // Flush final turn
        if turnNumber > 0, let resp = lastResponseSnippet {
            let toolSuffix = currentToolCount > 0 ? " [\(currentToolCount) tools]" : ""
            lines.append("  \u{2192} \(TelegramFormatter.escapeHtml(String(resp.prefix(500))))\(toolSuffix)")
        }

        if lines.count <= 1 {
            return "<b>Transcript</b>\n\n<i>No turns found.</i>"
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Text Message Handler (MiniMax Q&A)

    /// Handle free-text messages by querying MiniMax with the latest session transcript.
    /// Mirrors the NASIM bot's lastSessionBox pattern.
    func handleTextMessage(update: TGUpdate, bot: TGBot) async {
        guard let message = update.message,
              let text = message.text,
              !text.hasPrefix("/") else { return }

        // Verify it's from our chat
        guard message.chat.id == chatId else { return }

        // Need session context to answer
        guard let session = inlineButtonManager.lastSessionContext else {
            logger.debug("Text message ignored: no session context yet")
            return
        }

        logger.info("Q&A for session \(session.sessionId.prefix(8)): \"\(text.prefix(60))\"")

        // Show typing indicator
        try? await bot.sendChatAction(params: TGSendChatActionParams(
            chatId: .chat(chatId), action: "typing"))

        let systemPrompt = """
        You are a MiniMax AI assistant analyzing a Claude Code session transcript. \
        You are NOT Claude Code — you are a separate AI reviewing what happened in the session.

        IMPORTANT: Format your response for Telegram HTML. Use ONLY these tags:
        - <b>bold</b> for emphasis
        - <i>italic</i> for terms
        - <code>inline code</code> for code/commands
        - <pre>code blocks</pre> for multi-line code
        Do NOT use markdown (**bold**, `code`, - bullets, | tables |). Use plain text bullets with a dash and space.

        Session workspace: \(session.cwd)

        Session transcript:
        \(String(session.transcriptText.prefix(50000)))
        """

        do {
            let result = try await summaryEngine.miniMaxClient.query(
                prompt: text,
                systemPrompt: systemPrompt,
                maxTokens: 2000
            )

            let params = TGSendMessageParams(
                chatId: .chat(chatId),
                text: result.text,
                parseMode: .html,
                replyParameters: TGReplyParameters(messageId: message.messageId)
            )
            try await bot.sendMessage(params: params)
            logger.info("Q&A answer sent (\(result.text.count) chars, \(result.durationMs)ms)")
        } catch {
            logger.error("MiniMax Q&A failed: \(error)")
            let errorMsg = "Sorry, I couldn't process that question: \(String(describing: error).prefix(200))"
            try? await bot.sendMessage(params: TGSendMessageParams(
                chatId: .chat(chatId), text: errorMsg))
        }
    }
}
