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
    // Read the notification JSON file
    guard let data = FileManager.default.contents(atPath: filePath),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        logger.warning("Could not parse notification file: \(filePath)")
        return
    }

    let sessionId = json["session_id"] as? String ?? "unknown"
    let transcriptPath = json["transcript_path"] as? String
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

        // Parse transcript for session notification
        if let tp = transcriptPath {
            let entries = TranscriptParser.parse(filePath: tp)
            let turns = entriesToTurns(entries)
            if let bot = telegramBot {
                await bot.sendSessionNotification(turns: turns, cwd: cwd)
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

// Show subtitle demo only when bot is disabled (no token = dev mode)
if telegramBot == nil {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        subtitlePanel.demo()
    }
}

// MARK: - Helpers

/// Convert transcript entries into conversation turns for session notifications.
func entriesToTurns(_ entries: [TranscriptEntry]) -> [ConversationTurn] {
    var turns: [ConversationTurn] = []
    var currentPrompt: (text: String, timestamp: Date?)? = nil
    var toolNames: [String] = []
    var toolResults: [String] = []

    for entry in entries {
        switch entry {
        case .prompt(let text, let ts):
            // If we had a pending prompt without a response, flush it
            if let prompt = currentPrompt {
                turns.append(ConversationTurn(
                    prompt: prompt.text, response: "",
                    timestamp: prompt.timestamp, toolSummary: nil, toolResults: nil
                ))
            }
            currentPrompt = (text, ts)
            toolNames = []
            toolResults = []
        case .response(let text, let ts):
            if let prompt = currentPrompt {
                let toolSummary = toolNames.isEmpty ? nil : toolNames.joined(separator: ", ")
                let toolResultStr = toolResults.isEmpty ? nil : toolResults.joined(separator: "\n")
                turns.append(ConversationTurn(
                    prompt: prompt.text, response: text,
                    timestamp: prompt.timestamp ?? ts, toolSummary: toolSummary, toolResults: toolResultStr
                ))
                currentPrompt = nil
            }
        case .toolUse(let name, _):
            toolNames.append(name)
        case .toolResult(let content, _):
            if !content.isEmpty { toolResults.append(String(content.prefix(500))) }
        case .unknown:
            break
        }
    }
    // Flush any trailing prompt
    if let prompt = currentPrompt {
        turns.append(ConversationTurn(
            prompt: prompt.text, response: "",
            timestamp: prompt.timestamp, toolSummary: nil, toolResults: nil
        ))
    }
    return turns
}

// Enter run loop (blocks forever until SIGTERM)
app.run()

logger.info("\(Config.appName) exited cleanly")
