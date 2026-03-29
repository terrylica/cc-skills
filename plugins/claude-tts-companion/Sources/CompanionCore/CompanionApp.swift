import AppKit
import Foundation
import Logging

/// Top-level coordinator that owns all subsystems of the claude-tts-companion service.
///
/// Extracts all wiring logic from main.swift so that:
/// 1. main.swift is ultra-thin (~50 lines: NSApplication + SIGTERM + run loop)
/// 2. All business logic lives in CompanionCore, testable via @testable import
/// 3. Subsystem lifetimes are managed by a single owner (no scattered keepAlive vars)
public final class CompanionApp: @unchecked Sendable {
    private let logger = Logger(label: Config.appName)

    // All subsystems as properties
    private let settingsStore: SettingsStore
    private let subtitlePanel: SubtitlePanel
    private let playbackManager: PlaybackManager
    private let sherpaOnnxEngine: SherpaOnnxEngine
    private let ttsEngine: TTSEngine
    private let captionHistory: CaptionHistory
    private let captionHistoryPanel: CaptionHistoryPanel
    private let pipelineCoordinator: TTSPipelineCoordinator
    private let ttsQueue: TTSQueue
    private let httpServer: HTTPControlServer
    private let miniMaxClient: MiniMaxClient
    private let summaryEngine: SummaryEngine
    private let autoContinue: AutoContinueEvaluator
    private let notificationProcessor: NotificationProcessor
    private var thinkingWatcher: ThinkingWatcher!
    private var telegramBot: TelegramBot?
    private var notificationWatcher: NotificationWatcher!

    @MainActor public init() {
        // Create subsystems (same order as original main.swift)
        settingsStore = SettingsStore()
        subtitlePanel = SubtitlePanel(settingsStore: settingsStore)
        // PlaybackManager created BEFORE TTSEngine (owns audio hardware lifecycle)
        playbackManager = PlaybackManager()
        sherpaOnnxEngine = SherpaOnnxEngine()
        ttsEngine = TTSEngine(playbackManager: playbackManager, sherpaOnnxEngine: sherpaOnnxEngine)
        captionHistory = CaptionHistory()
        captionHistoryPanel = CaptionHistoryPanel(captionHistory: captionHistory)
        pipelineCoordinator = TTSPipelineCoordinator(playbackManager: playbackManager, subtitlePanel: subtitlePanel)
        ttsQueue = TTSQueue(ttsEngine: ttsEngine, pipelineCoordinator: pipelineCoordinator, subtitlePanel: subtitlePanel, captionHistory: captionHistory)
        httpServer = HTTPControlServer(
            settingsStore: settingsStore,
            subtitlePanel: subtitlePanel,
            playbackManager: playbackManager,
            ttsEngine: ttsEngine,
            captionHistory: captionHistory,
            captionHistoryPanel: captionHistoryPanel,
            pipelineCoordinator: pipelineCoordinator,
            ttsQueue: ttsQueue
        )
        miniMaxClient = MiniMaxClient()
        summaryEngine = SummaryEngine(client: miniMaxClient)
        autoContinue = AutoContinueEvaluator(client: miniMaxClient)
        notificationProcessor = NotificationProcessor()
    }

    @MainActor public func start() {
        logger.info("TTS backend: Python Kokoro server (\(Config.pythonTTSServerURL)) + sherpa-onnx CJK")

        // Check Python TTS server health (non-blocking, logs warning if unavailable)
        Task {
            await ttsEngine.checkPythonServerHealth()
        }

        // Start hardware event monitoring (memory pressure + audio route changes)
        pipelineCoordinator.startMonitoring()

        // Wire caption history onChange for live panel refresh
        captionHistory.onChange = { [weak self] in
            self?.captionHistoryPanel.refresh()
        }

        // Position subtitle panel
        subtitlePanel.positionOnScreen()

        // Create thinking watcher (EXT-04: summarizes extended thinking via MiniMax)
        thinkingWatcher = ThinkingWatcher(client: miniMaxClient) { [weak self] summary in
            guard let self = self else { return }
            self.logger.info("Thinking summary: \(summary)")
            DispatchQueue.main.async {
                self.subtitlePanel.show(text: summary)
                self.captionHistory.record(summary)
            }
        }

        // Start HTTP server in background task
        Task {
            do {
                logger.info("Starting HTTP control API on port \(Config.httpPort)")
                try await httpServer.start()
            } catch {
                logger.warning("HTTP server failed to start: \(error) -- continuing without HTTP API")
            }
        }

        // Start Telegram bot if configured (graceful fallback if no token)
        if let token = Config.telegramBotToken, let chatIdStr = Config.telegramChatId, let chatId = Int64(chatIdStr) {
            let bot = TelegramBot(
                botToken: token,
                chatId: chatId,
                summaryEngine: summaryEngine,
                playbackManager: playbackManager,
                ttsEngine: ttsEngine,
                subtitlePanel: subtitlePanel,
                pipelineCoordinator: pipelineCoordinator,
                ttsQueue: ttsQueue
            )
            telegramBot = bot
            httpServer.setBot(bot)
            Task {
                do {
                    try await bot.start()
                    logger.info("Telegram bot started successfully")
                } catch {
                    logger.warning("Telegram bot failed to start: \(error) -- continuing without bot")
                }
            }
        } else {
            logger.warning("TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set -- bot disabled")
        }

        // Create notification watcher with full processing pipeline (AUTO-01)
        notificationWatcher = NotificationWatcher(directoryPath: Config.notificationDir) { [weak self] filePath in
            guard let self = self else { return }
            self.handleNotification(filePath: filePath)
        }
        notificationWatcher.start()

        logger.info("Starting \(Config.appName)")

        // Show TTS demo only when bot is disabled (no token = dev mode)
        if telegramBot == nil {
            showDemoTTS()
        }
    }

    @MainActor public func shutdown() {
        logger.info("Shutting down")
        pipelineCoordinator.stopMonitoring()
        subtitlePanel.hide()
        captionHistoryPanel.hide()
        notificationWatcher?.stop()
        thinkingWatcher?.stop()
        if let bot = telegramBot {
            Task { await bot.stop() }
        }
    }
}

// MARK: - Notification Handling

private extension CompanionApp {

    /// Process a notification file detected by NotificationWatcher.
    /// Extracted from main.swift's inline closure (lines 98-204).
    func handleNotification(filePath: String) {
        notificationProcessor.processIfReady(filePath: filePath) { [weak self] path in
            guard let self = self else { return }

            // Brief delay -- DispatchSource fires on file creation before write completes
            Thread.sleep(forTimeInterval: 0.2)

            // Read the notification JSON file (retry once after delay if empty)
            var data = FileManager.default.contents(atPath: path)
            if data == nil || data!.isEmpty {
                Thread.sleep(forTimeInterval: 0.5)
                data = FileManager.default.contents(atPath: path)
            }
            guard let fileData = data, !fileData.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any] else {
                self.logger.warning("Could not parse notification file: \(path)")
                return
            }

            // The stop hook (telegram-notify-stop.ts) writes camelCase keys
            let sessionId = json["sessionId"] as? String ?? json["session_id"] as? String ?? "unknown"
            let transcriptPath = json["transcriptPath"] as? String ?? json["transcript_path"] as? String
            let cwd = json["cwd"] as? String
            let itermSessionId = json["itermSessionId"] as? String ?? json["iterm_session_id"] as? String
            let source = json["source"] as? String
            let notificationType = json["notificationType"] as? String
            let message = json["message"] as? String

            self.logger.info("Session notification: \(sessionId) source=\(source ?? "stop-hook") type=\(notificationType ?? "none")")

            // Notification-hook sourced: Claude Code is waiting for input (plan mode, permission, etc.)
            // These are lightweight — just TTS the notification message, no full transcript processing.
            if source == "notification-hook", let msg = message, !msg.isEmpty {
                self.logger.info("Notification-hook: type=\(notificationType ?? "unknown"), message=\(msg.prefix(80))")
                let projectName = self.summaryEngine.formatProjectName(cwd)
                let ttsText = "Attention in \(projectName). \(msg)"
                Task {
                    if let bot = self.telegramBot {
                        // Send lightweight Telegram message
                        let telegramMsg = "🔔 <b>\(projectName)</b>\n\(msg)"
                        await bot.sendSilentMessage(telegramMsg)
                    }
                    // Queue TTS for the notification
                    let _ = await self.ttsQueue.enqueue(text: ttsText, greeting: nil, priority: .automated)
                }
                return
            }

            // Dedup check: skip if transcript unchanged within TTL (REL-01)
            if let tp = transcriptPath {
                if self.notificationProcessor.shouldSkipDedup(sessionId: sessionId, transcriptPath: tp) {
                    self.logger.info("Dedup: skipping re-notification for session \(sessionId.prefix(8))")
                    return
                }
            }

            Task {
                // If we have a transcript, evaluate auto-continue and send rich notification
                if let tp = transcriptPath {
                    let workDir = cwd ?? ""
                    let result = await self.autoContinue.evaluate(sessionId: sessionId, transcriptPath: tp, cwd: workDir)
                    self.logger.info("Auto-continue decision: \(result.decision.rawValue) -- \(result.reason)")

                    // Send rich decision notification to Telegram (EVAL-05)
                    if let bot = self.telegramBot {
                        // Check if this is an early exit (limits, errors, sweep_done) vs active decision
                        let isEarlyExit = !result.shouldBlock && (
                            result.reason.contains("cap") ||
                            result.reason.contains("Max iterations") ||
                            result.reason.contains("Max runtime") ||
                            result.reason.contains("failed") ||
                            result.reason.contains("No turns")
                        )

                        if isEarlyExit {
                            // Lightweight exit notification
                            let exitMessage = self.autoContinue.formatExitMessage(
                                reason: result.reason,
                                sessionId: sessionId,
                                cwd: workDir,
                                state: result.state,
                                maxIterations: AutoContinueEvaluator.MAX_ITERATIONS,
                                maxRuntimeMin: Double(AutoContinueEvaluator.MAX_RUNTIME_MIN)
                            )
                            await bot.sendSilentMessage(exitMessage)
                        } else {
                            // Full rich decision notification
                            let message = self.autoContinue.formatDecisionMessage(
                                result: result,
                                sessionId: sessionId,
                                cwd: workDir,
                                maxIterations: AutoContinueEvaluator.MAX_ITERATIONS,
                                maxRuntimeMin: Double(AutoContinueEvaluator.MAX_RUNTIME_MIN)
                            )
                            await bot.sendSilentMessage(message)
                        }
                    }
                }

                // Parse transcript for session notification (FMT-01, FMT-02, FMT-03)
                if let tp = transcriptPath {
                    let entries = TranscriptParser.parse(filePath: tp)
                    let turns = TranscriptParser.entriesToTurns(entries)

                    // Extract metadata for rich notification formatting
                    let gitBranch = self.extractGitBranch(from: tp)
                    let entryStartTime = self.extractFirstTimestamp(entries)
                    let entryLastActivity = self.extractLastTimestamp(entries)

                    if let bot = self.telegramBot {
                        await bot.sendSessionNotification(
                            sessionId: sessionId,
                            turns: turns,
                            cwd: cwd,
                            gitBranch: gitBranch,
                            startTime: entryStartTime,
                            lastActivity: entryLastActivity,
                            itermSessionId: itermSessionId,
                            transcriptPath: tp
                        )
                    }
                }

                // Record successful processing for future dedup (REL-01)
                if let tp = transcriptPath {
                    self.notificationProcessor.recordProcessed(sessionId: sessionId, transcriptPath: tp)
                }
            }
        }
    }
}

// MARK: - Helpers

private extension CompanionApp {

    /// Extract git branch from JSONL transcript (first event with gitBranch field).
    func extractGitBranch(from transcriptPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: transcriptPath),
              let content = String(data: data, encoding: .utf8) else { return nil }
        // Scan first 20 lines for gitBranch field (usually in early events)
        let lines = content.components(separatedBy: .newlines)
        for line in lines.prefix(20) {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let branch = json["gitBranch"] as? String ?? json["git_branch"] as? String else { continue }
            if !branch.isEmpty { return branch }
        }
        return nil
    }

    /// Extract the first timestamp from parsed transcript entries.
    func extractFirstTimestamp(_ entries: [TranscriptEntry]) -> Date? {
        for entry in entries {
            switch entry {
            case .prompt(_, let ts): if let ts = ts { return ts }
            case .response(_, let ts): if let ts = ts { return ts }
            case .toolUse(_, let ts): if let ts = ts { return ts }
            case .toolResult(_, let ts): if let ts = ts { return ts }
            case .unknown: continue
            }
        }
        return nil
    }

    /// Extract the last timestamp from parsed transcript entries.
    func extractLastTimestamp(_ entries: [TranscriptEntry]) -> Date? {
        for entry in entries.reversed() {
            switch entry {
            case .prompt(_, let ts): if let ts = ts { return ts }
            case .response(_, let ts): if let ts = ts { return ts }
            case .toolUse(_, let ts): if let ts = ts { return ts }
            case .toolResult(_, let ts): if let ts = ts { return ts }
            case .unknown: continue
            }
        }
        return nil
    }

    /// Show a TTS demo subtitle when running in dev mode (no Telegram bot).
    func showDemoTTS() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s delay
            let demoText = "Welcome to claude TTS companion, your real-time subtitle overlay with karaoke highlighting"
            do {
                let ttsResult = try await ttsEngine.synthesizeWithTimestamps(text: demoText)
                logger.info("TTS demo: \(ttsResult.audioDuration)s audio, \(ttsResult.wordTimings.count) words")
                subtitlePanel.showUtterance(ttsResult.text, wordTimings: ttsResult.wordTimings)
                captionHistory.record(ttsResult.text)
                playbackManager.play(wavPath: ttsResult.wavPath)
            } catch {
                logger.error("TTS demo failed: \(error)")
                subtitlePanel.demo()
            }
        }
    }
}
