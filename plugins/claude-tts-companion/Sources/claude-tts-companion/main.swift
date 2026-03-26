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

// Create summary engine for AI session narratives
let summaryEngine = SummaryEngine()

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

// Set up SIGTERM handler using DispatchSource (not signal(), per research)
let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)  // Let DispatchSource handle it
sigSource.setEventHandler {
    logger.info("SIGTERM received, shutting down")
    subtitlePanel.hide()
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

logger.info("Starting \(Config.appName)")

// Show subtitle demo only when bot is disabled (no token = dev mode)
if telegramBot == nil {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        subtitlePanel.demo()
    }
}

// Enter run loop (blocks forever until SIGTERM)
app.run()

logger.info("\(Config.appName) exited cleanly")
