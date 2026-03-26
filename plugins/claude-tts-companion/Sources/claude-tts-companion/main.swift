import AppKit
import Foundation
import Logging
import CSherpaOnnx

// Unbuffer stdout/stderr for launchd (Pitfall 5)
setbuf(stdout, nil)
setbuf(stderr, nil)

// Configure logging first
LoggingSystem.bootstrap(StreamLogHandler.standardError)
let logger = Logger(label: Config.appName)

// Verify C interop works -- call a trivial sherpa-onnx function
let version = String(cString: SherpaOnnxGetVersionStr())
logger.info("sherpa-onnx C API version: \(version)")

// Set up NSApplication as accessory (no dock icon, no app switcher)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Create subtitle overlay panel
let subtitlePanel = SubtitlePanel()
subtitlePanel.positionOnScreen()

// Create TTS engine (model loads lazily on first synthesis, TTS-03)
let ttsEngine = TTSEngine()

// Create settings store (persists to ~/.config/claude-tts-companion/settings.json)
let settingsStore = SettingsStore()

// Create caption history ring buffer (EXT-01: scrollable caption history + clipboard copy)
let captionHistory = CaptionHistory()

// Create HTTP control API server
let httpServer = HTTPControlServer(
    settingsStore: settingsStore,
    subtitlePanel: subtitlePanel,
    ttsEngine: ttsEngine,
    captionHistory: captionHistory
)

// Start HTTP server in background task
Task {
    do {
        logger.info("Starting HTTP control API on port \(Config.httpPort)")
        try await httpServer.start()
    } catch {
        logger.warning("HTTP server failed to start: \(error) -- continuing without HTTP API")
    }
}

// Create shared MiniMax client (single circuit breaker for summaries + auto-continue)
let miniMaxClient = MiniMaxClient()

// Create summary engine for AI session narratives
let summaryEngine = SummaryEngine(client: miniMaxClient)

// Create auto-continue evaluator (shares circuit breaker with summary engine)
let autoContinue = AutoContinueEvaluator(client: miniMaxClient)

// Create thinking watcher (EXT-04: summarizes extended thinking via MiniMax)
let thinkingWatcher = ThinkingWatcher(client: miniMaxClient) { summary in
    logger.info("Thinking summary: \(summary)")
    // Display thinking summary on subtitle panel
    DispatchQueue.main.async {
        subtitlePanel.show(text: summary)
        captionHistory.record(summary)
    }
}

// Start Telegram bot if configured (graceful fallback if no token)
nonisolated(unsafe) var telegramBot: TelegramBot? = nil
if let token = Config.telegramBotToken, let chatIdStr = Config.telegramChatId, let chatId = Int64(chatIdStr) {
    let bot = TelegramBot(
        botToken: token,
        chatId: chatId,
        summaryEngine: summaryEngine,
        ttsEngine: ttsEngine,
        subtitlePanel: subtitlePanel
    )
    telegramBot = bot
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

// Create NotificationWatcher for session-end file detection (AUTO-01)
let notificationWatcher = NotificationWatcher { filePath in
    // Brief delay — DispatchSource fires on file creation before write completes
    Thread.sleep(forTimeInterval: 0.2)

    // Read the notification JSON file (retry once after delay if empty)
    var data = FileManager.default.contents(atPath: filePath)
    if data == nil || data!.isEmpty {
        Thread.sleep(forTimeInterval: 0.5)
        data = FileManager.default.contents(atPath: filePath)
    }
    guard let fileData = data, !fileData.isEmpty,
          let json = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any] else {
        logger.warning("Could not parse notification file: \(filePath)")
        return
    }

    // The stop hook (telegram-notify-stop.ts) writes camelCase keys
    let sessionId = json["sessionId"] as? String ?? json["session_id"] as? String ?? "unknown"
    let transcriptPath = json["transcriptPath"] as? String ?? json["transcript_path"] as? String
    let cwd = json["cwd"] as? String

    logger.info("Session notification: \(sessionId)")

    Task {
        // If we have a transcript, evaluate auto-continue
        if let tp = transcriptPath {
            let (decision, reason) = await autoContinue.evaluate(transcriptPath: tp)
            logger.info("Auto-continue decision: \(decision.rawValue) -- \(reason)")

            // Send decision notification to Telegram
            let decisionLabel: String
            switch decision {
            case .continue: decisionLabel = "CONTINUE"
            case .sweep: decisionLabel = "SWEEP"
            case .redirect: decisionLabel = "REDIRECT"
            case .done: decisionLabel = "DONE"
            }
            if let bot = telegramBot {
                await bot.sendNotification("<b>[\(decisionLabel)]</b> \(reason)")
            }
        }

        // Parse transcript for session notification (FMT-01, FMT-02, FMT-03)
        if let tp = transcriptPath {
            let entries = TranscriptParser.parse(filePath: tp)
            let turns = TranscriptParser.entriesToTurns(entries)

            // Extract metadata for rich notification formatting
            let gitBranch = extractGitBranch(from: tp)
            let entryStartTime = extractFirstTimestamp(entries)
            let entryLastActivity = extractLastTimestamp(entries)

            if let bot = telegramBot {
                await bot.sendSessionNotification(
                    sessionId: sessionId,
                    turns: turns,
                    cwd: cwd,
                    gitBranch: gitBranch,
                    startTime: entryStartTime,
                    lastActivity: entryLastActivity
                )
            }
        }
    }
}
notificationWatcher.start()

// Set up SIGTERM handler using DispatchSource (not signal(), per research)
let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)  // Let DispatchSource handle it
sigSource.setEventHandler {
    logger.info("SIGTERM received, shutting down")
    subtitlePanel.hide()
    // Stop file watcher and thinking watcher
    notificationWatcher.stop()
    thinkingWatcher.stop()
    // Stop Telegram bot
    if let bot = telegramBot {
        Task { await bot.stop() }
    }
    // Post dummy event to unblock RunLoop (Pitfall 4: NSApplication.stop requires event)
    let event = NSEvent.otherEvent(
        with: .applicationDefined, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, subtype: 0, data1: 0, data2: 0
    )!
    app.postEvent(event, atStart: true)
    app.stop(nil)
}
sigSource.resume()

// Store references globally to prevent ARC deallocation (Pitfall 3)
nonisolated(unsafe) var keepAlive: (any DispatchSourceSignal)? = sigSource
nonisolated(unsafe) var keepTTS: TTSEngine? = ttsEngine
nonisolated(unsafe) var keepSummary: SummaryEngine? = summaryEngine
nonisolated(unsafe) var keepNotificationWatcher: NotificationWatcher? = notificationWatcher
nonisolated(unsafe) var keepAutoContinue: AutoContinueEvaluator? = autoContinue
nonisolated(unsafe) var keepHTTPServer: HTTPControlServer? = httpServer
nonisolated(unsafe) var keepSettingsStore: SettingsStore? = settingsStore
nonisolated(unsafe) var keepCaptionHistory: CaptionHistory? = captionHistory
nonisolated(unsafe) var keepThinkingWatcher: ThinkingWatcher? = thinkingWatcher

logger.info("Starting \(Config.appName)")

// Show TTS demo only when bot is disabled (no token = dev mode)
if telegramBot == nil {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let demoText = "Welcome to claude TTS companion, your real-time subtitle overlay with karaoke highlighting"
        ttsEngine.synthesizeWithTimestamps(text: demoText) { result in
            switch result {
            case .success(let ttsResult):
                logger.info("TTS demo: \(ttsResult.audioDuration)s audio, \(ttsResult.wordTimings.count) words")
                DispatchQueue.main.async {
                    subtitlePanel.showUtterance(ttsResult.text, wordTimings: ttsResult.wordTimings)
                    captionHistory.record(ttsResult.text)
                }
                ttsEngine.play(wavPath: ttsResult.wavPath)
            case .failure(let error):
                logger.error("TTS demo failed: \(error)")
                // Fallback to subtitle-only demo
                DispatchQueue.main.async {
                    subtitlePanel.demo()
                }
            }
        }
    }
}

// MARK: - Helpers

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

// Enter run loop (blocks forever until SIGTERM)
app.run()

logger.info("\(Config.appName) exited cleanly")
