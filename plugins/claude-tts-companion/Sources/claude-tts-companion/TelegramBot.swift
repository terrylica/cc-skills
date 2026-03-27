import Foundation
import Logging
import SwiftTelegramBot

/// Telegram bot using swift-telegram-sdk long polling.
/// Wraps TGBot actor and provides command handlers + message sending.
final class TelegramBot: @unchecked Sendable {
    fileprivate let logger = Logger(label: "telegram-bot")
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
    private var syncDriver: SubtitleSyncDriver?

    // Streaming TTS guard: prevents new dispatch from interrupting in-progress streaming.
    // Protected by NSLock for thread safety -- accessed from both notification handler
    // thread (check) and main thread (clear via onStreamingComplete).
    private let streamingLock = NSLock()
    private var _isStreamingInProgress: Bool = false
    private var isStreamingInProgress: Bool {
        get { streamingLock.lock(); defer { streamingLock.unlock() }; return _isStreamingInProgress }
        set { streamingLock.lock(); defer { streamingLock.unlock() }; _isStreamingInProgress = newValue }
    }

    // Inline button state manager (BTN-01, BTN-02, BTN-03)
    let inlineButtonManager = InlineButtonManager()

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
        lastActivity: Date?,
        itermSessionId: String? = nil,
        transcriptPath: String? = nil
    ) async {
        guard isWatching else {
            logger.info("Skipping notification -- bot not watching")
            return
        }

        // Early exit if all outlets are disabled (TTS-12)
        guard !FeatureGates.allOutletsDisabled else {
            logger.info("All notification outlets disabled -- skipping")
            return
        }

        // Generate both summaries concurrently
        async let arcResult = summaryEngine.arcSummary(turns: turns, cwd: cwd)
        async let tailResult = summaryEngine.tailBrief(turns: turns, cwd: cwd)

        let arc = await arcResult
        let tail = await tailResult

        // Extract last user prompt from turns (FMT-02)
        let lastPrompt = turns.last(where: { !$0.prompt.isEmpty })?.prompt

        // Condense long prompts for Telegram display (PROMPT-04)
        // arc.promptSummary is set for single-turn sessions via ||| parsing;
        // for multi-turn sessions, use MiniMax to condense if >800 chars.
        let condensedPrompt: String?
        if let summary = arc.promptSummary {
            condensedPrompt = summary
        } else if let raw = lastPrompt, raw.count > 800 {
            condensedPrompt = await summaryEngine.summarizePromptForDisplay(rawPrompt: raw)
        } else {
            condensedPrompt = nil
        }

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
            promptSummary: condensedPrompt
        )

        // Render rich HTML notification with metadata header
        let message = TelegramFormatter.renderSessionNotification(notifData)

        // Gate Arc Summary Telegram send (TTS-12)
        if FeatureGates.summarizerTgEnabled {
            // If rendering produced nothing useful, send minimal fallback
            if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await sendMessage("<b>Session Complete</b>\n\n<i>Summary generation failed or was skipped.</i>")
            } else if let tp = transcriptPath {
                // Attach inline keyboard when transcript is available (BTN-01)
                let workspace = (cwd as NSString?)?.lastPathComponent ?? "unknown"
                let notifId = inlineButtonManager.registerNotification(
                    cwd: cwd ?? "unknown",
                    workspace: workspace,
                    transcriptPath: tp
                )
                let keyboard = inlineButtonManager.buildInlineKeyboard(
                    itermSessionId: itermSessionId,
                    notifId: notifId
                )

                // Focus Tab dedup: remove buttons from previous message for same tab (BTN-03)
                if let sessId = itermSessionId,
                   let prev = inlineButtonManager.previousFocusTabMessage(itermSessionId: sessId) {
                    await removeInlineKeyboard(chatId: prev.chatId, messageId: prev.messageId)
                }

                if let msgId = await sendMessageWithKeyboard(message, keyboard: keyboard) {
                    // Track for future dedup
                    if let sessId = itermSessionId {
                        inlineButtonManager.trackFocusTab(itermSessionId: sessId, chatId: chatId, messageId: msgId)
                    }
                }
            } else {
                await sendMessage(message)
            }
        } else {
            logger.info("Arc Summary TG outlet disabled")
        }

        // Gate Tail Brief Telegram send (TTS-12)
        if FeatureGates.tbrTgEnabled {
            if !tail.narrative.isEmpty {
                let tbrMessage = "<b>Tail Brief</b>:\n\(TelegramFormatter.escapeHtml(tail.narrative))"
                await sendSilentMessage(tbrMessage)
            }
        }

        // Gate TTS dispatch for Tail Brief with karaoke subtitles (TTS-11, TTS-12)
        if FeatureGates.tbrTtsEnabled {
            if !tail.narrative.isEmpty {
                let projectName = summaryEngine.formatProjectName(cwd)
                let ttsGreeting = "Hi Terry, you were working in \(projectName):"
                await dispatchTTS(text: tail.narrative, greeting: ttsGreeting)
            }
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
    ///
    /// Uses streaming sentence-chunked synthesis when `Config.streamingTTS` is true,
    /// falling back to full-paragraph synthesis for future low-RTF models.
    private func dispatchTTS(text: String, greeting: String?) async {
        // Guard: skip if a streaming synthesis pipeline is still playing (prevents early cutoff)
        if isStreamingInProgress {
            logger.warning("Skipping TTS dispatch — streaming synthesis in progress (\(text.count) chars dropped)")
            return
        }

        // Build full TTS text with optional greeting
        let fullText: String
        if let greeting = greeting, !greeting.isEmpty {
            fullText = "\(greeting) \(text)"
        } else {
            fullText = text
        }

        // Detect language to select correct voice (TTS-10)
        let langResult = LanguageDetector.detect(text: fullText)
        if langResult.lang == "cmn" {
            logger.warning("CJK text detected but kokoro-ios is English-only; using English voice '\(langResult.voiceName)'")
        }
        logger.info("Dispatching TTS: \(fullText.count) chars, lang=\(langResult.lang), voice=\(langResult.voiceName), streaming=\(Config.streamingTTS)")

        if Config.streamingTTS {
            dispatchStreamingTTS(text: fullText, voiceName: langResult.voiceName)
        } else {
            dispatchFullTTS(text: fullText, voiceName: langResult.voiceName)
        }
    }

    /// Streaming TTS: synthesize sentence-by-sentence, play first chunk ASAP.
    private func dispatchStreamingTTS(text: String, voiceName: String) {
        // Mark streaming as in-progress to prevent new dispatches from interrupting
        isStreamingInProgress = true

        // Cancel previous playback IMMEDIATELY when a new session dispatches.
        // Previously this was deferred to the first-chunk-ready callback, leaving a
        // ~4-18s window where the old SyncDriver's 60Hz timer polled a dead player
        // (spamming "Waiting for chunk N" logs and showing stale subtitles).
        ttsEngine.stopPlayback()
        // SyncDriver is @MainActor -- dispatch stop to main queue.
        // Use async (not sync) to avoid deadlock if we're already on main.
        // The synthesis queue starts work concurrently, but the first chunk takes
        // ~2-18s to synthesize, so the main-queue stop completes well before
        // the onChunkReady callback dispatches back to main.
        let driverToStop = syncDriver
        syncDriver = nil
        DispatchQueue.main.async {
            driverToStop?.stop()
        }

        // Use NSLock-protected flag for thread safety (TTS queue -> main thread).
        let firstChunkLock = NSLock()
        var _firstChunkDispatched = false

        ttsEngine.synthesizeStreaming(
            text: text,
            voiceName: voiceName,
            onChunkReady: { [weak self] chunk in
                guard let self = self else { return }
                self.logger.info("Streaming chunk \(chunk.chunkIndex + 1)/\(chunk.totalChunks) ready: \(String(format: "%.2f", chunk.audioDuration))s")

                firstChunkLock.lock()
                let isFirst = !_firstChunkDispatched
                if isFirst { _firstChunkDispatched = true }
                firstChunkLock.unlock()

                DispatchQueue.main.async {
                    if isFirst {
                        // Create streaming sync driver with completion to clear in-progress flag
                        let driver = SubtitleSyncDriver(
                            subtitlePanel: self.subtitlePanel,
                            ttsEngine: self.ttsEngine,
                            onStreamingComplete: { [weak self] in
                                self?.isStreamingInProgress = false
                                self?.logger.info("Streaming playback complete — new TTS dispatches unblocked")
                            }
                        )
                        self.syncDriver = driver
                    }

                    // Chunk pages using pixel-width measurement with the current dynamic font size
                    let fontSizeName = self.subtitlePanel.currentFontSizeName
                    let pages = SubtitleChunker.chunkIntoPages(text: chunk.text, fontSizeName: fontSizeName)
                    self.syncDriver?.addChunk(
                        wavPath: chunk.wavPath,
                        pages: pages,
                        wordTimings: chunk.wordTimings,
                        nativeOnsets: chunk.wordOnsets
                    )
                }
            },
            onAllComplete: { [weak self] in
                guard let self = self else { return }
                self.logger.info("All streaming TTS chunks synthesized")

                firstChunkLock.lock()
                let hadChunks = _firstChunkDispatched
                firstChunkLock.unlock()

                DispatchQueue.main.async {
                    if hadChunks {
                        // SyncDriver was created — it will clear isStreamingInProgress
                        // when playback finishes via onStreamingComplete callback
                        self.syncDriver?.markAllChunksDelivered()
                    } else {
                        // No chunks were ever produced (synthesis failed entirely)
                        self.isStreamingInProgress = false
                        self.logger.warning("Streaming complete with no chunks — clearing in-progress flag")
                    }
                }
            }
        )
    }

    /// Full-paragraph TTS: synthesize everything, then play (legacy path).
    /// Preserved for future TTS models with lower RTF where streaming is unnecessary.
    private func dispatchFullTTS(text: String, voiceName: String) {
        ttsEngine.synthesizeWithTimestamps(text: text, voiceName: voiceName) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let ttsResult):
                self.logger.info("TTS synthesis complete: \(String(format: "%.2f", ttsResult.audioDuration))s")

                // Cancel previous playback only when new audio is ready
                self.ttsEngine.stopPlayback()

                DispatchQueue.main.async {
                    self.syncDriver?.stop()
                    self.syncDriver = nil

                    let fontSizeName = self.subtitlePanel.currentFontSizeName
                    let pages = SubtitleChunker.chunkIntoPages(text: ttsResult.text, fontSizeName: fontSizeName)
                    guard let player = self.ttsEngine.play(wavPath: ttsResult.wavPath, completion: {
                        self.logger.info("TTS playback complete")
                    }) else {
                        self.logger.error("AVAudioPlayer creation failed — skipping subtitles")
                        return
                    }
                    let driver = SubtitleSyncDriver(
                        player: player,
                        pages: pages,
                        wordTimings: ttsResult.wordTimings,
                        nativeOnsets: ttsResult.wordOnsets,
                        subtitlePanel: self.subtitlePanel
                    )
                    self.syncDriver = driver
                    driver.start()
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

        // MARK: - Callback Query Handlers (BTN-01, BTN-02, BTN-03)

        // Focus Tab: switch iTerm2 to the session's tab
        await add(TGCallbackQueryHandler(name: "focusTab", pattern: "^iterm:") { [weak self] update in
            guard let self = self else { return }
            let bot = self.bot
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
                self.telegramBot.logger.warning("AppleScript failed: \(error)")
                resultText = "AppleScript error"
            }

            try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                callbackQueryId: query.id, text: resultText))
        })

        // Follow Up: show session CWD info for manual prompt
        await add(TGCallbackQueryHandler(name: "followUp", pattern: "^fu:") { [weak self] update in
            guard let self = self else { return }
            let bot = self.bot
            guard let query = update.callbackQuery, let data = query.data else { return }

            guard let idStr = data.split(separator: ":").last, let id = Int(idStr) else {
                try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                    callbackQueryId: query.id, text: "Invalid button data"))
                return
            }

            guard let notif = self.telegramBot.inlineButtonManager.lookupNotification(id: id) else {
                try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                    callbackQueryId: query.id, text: "Button expired."))
                return
            }

            try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                callbackQueryId: query.id, text: "Following up"))

            let message = """
            <b>Follow Up</b>

            <b>Workspace:</b> \(TelegramFormatter.escapeHtml(notif.workspace))
            <b>CWD:</b> <code>\(TelegramFormatter.escapeHtml(notif.cwd))</code>

            Use /prompt to send a follow-up message to Claude in this directory.
            """
            await self.telegramBot.sendSilentMessage(message)
        })

        // Transcript: show parsed transcript overview
        await add(TGCallbackQueryHandler(name: "transcript", pattern: "^tx:") { [weak self] update in
            guard let self = self else { return }
            let bot = self.bot
            guard let query = update.callbackQuery, let data = query.data else { return }

            guard let idStr = data.split(separator: ":").last, let id = Int(idStr) else {
                try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                    callbackQueryId: query.id, text: "Invalid button data"))
                return
            }

            guard let notif = self.telegramBot.inlineButtonManager.lookupNotification(id: id) else {
                try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                    callbackQueryId: query.id, text: "Button expired."))
                return
            }

            try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                callbackQueryId: query.id, text: "Loading transcript..."))

            let transcriptHtml = self.telegramBot.formatTranscriptView(transcriptPath: notif.transcriptPath)
            let chunks = TelegramFormatter.chunkTelegramHtml(transcriptHtml)

            if chunks.count <= 1 {
                await self.telegramBot.sendSilentMessage(chunks.first ?? "<i>Empty transcript</i>")
            } else {
                // Store chunks for pagination
                self.telegramBot.inlineButtonManager.storeTranscriptPages(notifId: id, chunks: chunks)
                let pageKeyboard = self.telegramBot.inlineButtonManager.buildTranscriptPaginationKeyboard(
                    notifId: id, currentPage: 0, totalPages: chunks.count)
                _ = await self.telegramBot.sendMessageWithKeyboard(
                    chunks[0], keyboard: pageKeyboard, silent: true)
            }
        })

        // Transcript pagination: navigate pages
        await add(TGCallbackQueryHandler(name: "transcriptPage", pattern: "^txp:") { [weak self] update in
            guard let self = self else { return }
            let bot = self.bot
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

            guard let chunks = self.telegramBot.inlineButtonManager.lookupTranscriptPages(notifId: notifId),
                  page >= 0, page < chunks.count else {
                try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                    callbackQueryId: query.id, text: "Page expired."))
                return
            }

            // Edit the message with the requested page
            let pageKeyboard = self.telegramBot.inlineButtonManager.buildTranscriptPaginationKeyboard(
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
                    self.telegramBot.logger.warning("Failed to edit transcript page: \(error)")
                }
            }

            try? await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                callbackQueryId: query.id))
        })
    }
}
