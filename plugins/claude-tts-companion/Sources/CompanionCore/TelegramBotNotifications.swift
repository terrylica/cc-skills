import Foundation

// MARK: - Session Notifications (BOT-03, BOT-04, FMT-01, FMT-02, FMT-03)

extension TelegramBot {

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
            aiNarrative: !arc.narrative.hasPrefix("Summary unavailable") && !arc.narrative.hasPrefix("Empty session") ? arc.narrative : nil,
            promptSummary: condensedPrompt
        )

        // Render rich HTML notification with metadata header
        let message = TelegramFormatter.renderSessionNotification(notifData)

        // Gate Arc Summary Telegram send (TTS-12)
        if FeatureGates.summarizerTgEnabled {
            // If rendering produced nothing useful, send minimal fallback
            if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await sendMessage("<b>Session Complete</b>\n\n<i>Summary unavailable — MiniMax returned empty or the circuit breaker is open. Check companion logs for details.</i>")
            } else if let tp = transcriptPath {
                // Attach inline keyboard when transcript is available (BTN-01)
                let workspace = (cwd as NSString?)?.lastPathComponent ?? "unknown"
                let notifId = inlineButtonManager.registerNotification(
                    cwd: cwd ?? "unknown",
                    workspace: workspace,
                    transcriptPath: tp
                )

                // Populate session context for MiniMax Q&A (Ask About This)
                let transcriptText = turns.enumerated().map { (i, t) in
                    "Turn \(i + 1):\nUser: \(String(t.prompt.prefix(2000)))\nAssistant: \(String(t.response.prefix(4000)))"
                }.joined(separator: "\n\n")
                inlineButtonManager.lastSessionContext = InlineButtonManager.SessionContext(
                    transcriptText: transcriptText,
                    cwd: cwd ?? "unknown",
                    sessionId: sessionId ?? "unknown"
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

    /// Show text as a static subtitle with auto-hide after linger + 5s.
    ///
    /// Used as graceful degradation when TTS is unavailable (model missing,
    /// circuit breaker open, synthesis failure, or no chunks produced).
    /// Safe to call from any thread -- dispatches to main internally.
    func showSubtitleOnlyFallback(text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.subtitlePanel.show(text: text)
            // Schedule cancellable hide -- cancelled automatically if SubtitlePanel.show(),
            // hide(), or updateAttributedText() is called before timer fires.
            self.subtitlePanel.lingerThenHide(after: SubtitleStyle.lingerDuration + 5.0)
        }
    }

    /// Enqueue text for TTS synthesis via the priority queue.
    /// Memory pressure and circuit breaker are checked by TTSQueue.executeWorkItem().
    /// Rejected requests (user request active) fall back to subtitle-only.
    func dispatchTTS(text: String, greeting: String?) async {
        let result = await ttsQueue.enqueue(text: text, greeting: greeting, priority: .automated)
        switch result {
        case .queued(let pos):
            logger.info("TTS queued at position \(pos): \(text.count) chars")
        case .rejected(let reason):
            logger.warning("TTS rejected (\(reason)) — subtitle-only fallback (\(text.count) chars)")
            let fullText = greeting.map { "\($0) \(text)" } ?? text
            showSubtitleOnlyFallback(text: fullText)
        }
    }
}
