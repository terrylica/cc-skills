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
    private let ttsEngine: TTSEngine
    private let captionHistory: CaptionHistory
    private let pipelineCoordinator: TTSPipelineCoordinator
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
        ttsEngine = TTSEngine(playbackManager: playbackManager)
        captionHistory = CaptionHistory()
        pipelineCoordinator = TTSPipelineCoordinator(playbackManager: playbackManager, subtitlePanel: subtitlePanel)
        httpServer = HTTPControlServer(
            settingsStore: settingsStore,
            subtitlePanel: subtitlePanel,
            playbackManager: playbackManager,
            ttsEngine: ttsEngine,
            captionHistory: captionHistory,
            pipelineCoordinator: pipelineCoordinator
        )
        miniMaxClient = MiniMaxClient()
        summaryEngine = SummaryEngine(client: miniMaxClient)
        autoContinue = AutoContinueEvaluator(client: miniMaxClient)
        notificationProcessor = NotificationProcessor()
    }

    @MainActor public func start() {
        logger.info("TTS backend: kokoro-ios MLX (bf16)")

        // Register memory lifecycle handler so HTTPControlServer/TelegramBot can trigger restart
        MemoryLifecycle.register(ttsEngine: ttsEngine) { [weak self] reason in
            self?.plannedRestart(reason: reason)
        }

        // Start hardware event monitoring (memory pressure + audio route changes)
        pipelineCoordinator.startMonitoring()

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
                pipelineCoordinator: pipelineCoordinator
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
        notificationWatcher = NotificationWatcher { [weak self] filePath in
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

            self.logger.info("Session notification: \(sessionId)")

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

// MARK: - Memory Lifecycle

private extension CompanionApp {

    /// Triggers a graceful process exit for IOAccelerator memory reclaim.
    /// Uses exit code 42 (non-zero) so launchd KeepAlive restarts the service.
    /// exit(0) would NOT trigger restart because KeepAlive.SuccessfulExit = false.
    ///
    /// Must be called on the main thread (accesses MainActor-isolated subtitlePanel).
    func plannedRestart(reason: String) {
        logger.warning("Planned restart: \(reason)")
        DispatchQueue.main.async { [self] in
            subtitlePanel.hide()
            notificationWatcher.stop()
            thinkingWatcher.stop()
            if let bot = telegramBot {
                Task { await bot.stop() }
            }
            // Give async cleanup 1 second to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.logger.info("Exiting with code 42 for launchd restart")
                exit(42)
            }
        }
    }

    /// Check synthesis count and trigger planned restart if threshold reached.
    /// Called after playback completes (not during synthesis) so the user hears
    /// the complete audio before the service restarts.
    /// Async because TTSEngine is an actor.
    func checkMemoryLifecycleRestart() async {
        if await ttsEngine.shouldRestartForMemory {
            let diag = await ttsEngine.memoryDiagnostics()
            plannedRestart(reason: "Synthesis count \(diag.synthesisCount) reached threshold \(TTSEngine.maxSynthesisBeforeRestart)")
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
