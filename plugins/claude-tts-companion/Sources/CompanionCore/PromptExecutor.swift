@preconcurrency import Dispatch
import Foundation
import Logging

/// Parse model override flags from the start of a /prompt command string.
///
/// Supported flags (case-insensitive, must appear at start of text):
///   --haiku            -> Config.haikuModel
///   --sonnet           -> Config.sonnetModel
///   --opus             -> Config.opusModel
///   --model <model-id> -> literal model ID
///   (no flag)          -> Config.sonnetModel (default)
///
/// Returns the resolved model ID string and the cleaned prompt text with flag stripped.
func parsePromptFlags(_ raw: String) -> (model: String, text: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    let lower = trimmed.lowercased()

    // --model <id>
    if lower.hasPrefix("--model ") || lower.hasPrefix("--model\t") {
        let afterFlag = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces)
        if let spaceIdx = afterFlag.firstIndex(where: { $0.isWhitespace }) {
            let modelId = String(afterFlag[..<spaceIdx])
            let text = String(afterFlag[spaceIdx...]).trimmingCharacters(in: .whitespaces)
            return (model: modelId, text: text)
        }
        return (model: afterFlag, text: "")
    }

    let shortFlags: [(flag: String, model: String)] = [
        ("--haiku", Config.haikuModel),
        ("--sonnet", Config.sonnetModel),
        ("--opus", Config.opusModel),
    ]

    for (flag, modelId) in shortFlags {
        if lower == flag {
            return (model: modelId, text: "")
        }
        if lower.hasPrefix(flag + " ") {
            let text = String(trimmed.dropFirst(flag.count)).trimmingCharacters(in: .whitespaces)
            return (model: modelId, text: text)
        }
    }

    return (model: Config.sonnetModel, text: trimmed)
}

/// Short display label for a model ID (used in Telegram status messages).
///
/// - "claude-haiku-4-5" -> "haiku"
/// - "claude-sonnet-4-6" -> "sonnet"
/// - "claude-opus-4-6" -> "opus"
/// - "custom-model-name" -> "custom-model"
func modelLabel(_ modelId: String) -> String {
    let lower = modelId.lowercased()
    if lower.contains("haiku") { return "haiku" }
    if lower.contains("sonnet") { return "sonnet" }
    if lower.contains("opus") { return "opus" }
    let parts = modelId.split(separator: "-")
    if parts.count >= 2 {
        return "\(parts[0])-\(parts[1])"
    }
    return modelId
}

/// Thread-safe mutable state shared between @Sendable callbacks during prompt execution.
/// Uses NSLock (non-async context only) to protect all mutable fields.
private final class PromptStreamState: @unchecked Sendable {
    private let lock = NSLock()

    private var _accumulatedText = ""
    private var _toolNames: [String] = []
    private var _lastEditTime: Date = .distantPast
    private var _lastEditedText = ""
    private var _hasError = false
    private var _sessionId: String?
    private var _completed = false

    var accumulatedText: String {
        get { lock.lock(); defer { lock.unlock() }; return _accumulatedText }
    }
    func appendText(_ text: String) {
        lock.lock(); _accumulatedText += text; lock.unlock()
    }
    var toolNames: [String] {
        lock.lock(); defer { lock.unlock() }; return _toolNames
    }
    func addToolName(_ name: String) {
        lock.lock()
        if !_toolNames.contains(name) { _toolNames.append(name) }
        lock.unlock()
    }
    var lastEditTime: Date {
        get { lock.lock(); defer { lock.unlock() }; return _lastEditTime }
        set { lock.lock(); _lastEditTime = newValue; lock.unlock() }
    }
    var lastEditedText: String {
        get { lock.lock(); defer { lock.unlock() }; return _lastEditedText }
        set { lock.lock(); _lastEditedText = newValue; lock.unlock() }
    }
    var hasError: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _hasError }
        set { lock.lock(); _hasError = newValue; lock.unlock() }
    }
    var sessionId: String? {
        get { lock.lock(); defer { lock.unlock() }; return _sessionId }
        set { lock.lock(); _sessionId = newValue; lock.unlock() }
    }
    var completed: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _completed }
        set { lock.lock(); _completed = newValue; lock.unlock() }
    }

    /// Snapshot all fields atomically for final message construction.
    func snapshot() -> (text: String, tools: [String], hasError: Bool, sessionId: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (_accumulatedText, _toolNames, _hasError, _sessionId)
    }
}

/// Orchestrates /prompt command execution: spawns Claude CLI, streams response
/// to Telegram via edit-in-place, with mutex, rate limiting, and circuit breaker.
///
/// Design mirrors the TypeScript prompt-executor.ts from claude-telegram-sync.
/// Closures for sendMessage/editMessage are injected to avoid coupling to TelegramBot.
///
/// All mutable executor state is accessed only via the serial `stateQueue` to avoid
/// NSLock-in-async-context errors from Swift 6 strict concurrency.
public final class PromptExecutor: @unchecked Sendable {
    private let logger = Logger(label: "prompt-executor")

    /// Serial queue protecting executor-level mutable state (mutex, rate limit, circuit breaker).
    private let stateQueue = DispatchQueue(label: "com.terryli.prompt-executor.state")

    // Executor state (access ONLY on stateQueue)
    private var _isExecuting = false
    private var _lastExecutionTime: Date = .distantPast
    private var _currentProcess: ClaudeProcess?
    private var _consecutiveFailures = 0
    private var _disabledUntil: Date = .distantPast

    // Constants
    private let minIntervalSeconds: TimeInterval = 30
    private let maxFailures = 3
    private let disableDurationSeconds: TimeInterval = 600
    private let editThrottleSeconds: TimeInterval = 1.5
    private let minInitialChars = 200

    // MARK: - Public API

    /// Execute a prompt: spawn Claude CLI, stream output to Telegram via edit-in-place.
    func execute(
        prompt: String,
        model: String,
        cwd: String,
        resumeSessionId: String? = nil,
        sendMessage: @escaping @Sendable (String) async -> Int?,
        editMessage: @escaping @Sendable (Int, String) async -> Void
    ) async {

        // Pre-flight checks on serial queue (synchronous, no async context)
        enum PreflightResult {
            case proceed
            case circuitOpen(remaining: Int)
            case busy
            case rateLimited(wait: Int)
        }

        let preflight: PreflightResult = stateQueue.sync {
            // 1. Circuit breaker
            if Date() < _disabledUntil {
                let remaining = Int(_disabledUntil.timeIntervalSinceNow)
                return .circuitOpen(remaining: remaining)
            }
            // 2. Mutex
            if _isExecuting {
                return .busy
            }
            // 3. Rate limit
            let elapsed = Date().timeIntervalSince(_lastExecutionTime)
            if elapsed < minIntervalSeconds {
                let wait = Int(minIntervalSeconds - elapsed) + 1
                return .rateLimited(wait: wait)
            }
            // Acquire
            _isExecuting = true
            _lastExecutionTime = Date()
            return .proceed
        }

        switch preflight {
        case .circuitOpen(let remaining):
            _ = await sendMessage("Circuit breaker open -- prompt execution disabled for \(remaining)s after \(maxFailures) consecutive failures.")
            return
        case .busy:
            _ = await sendMessage("A prompt is already executing. Please wait for it to finish.")
            return
        case .rateLimited(let wait):
            _ = await sendMessage("Rate limited -- try again in \(wait)s.")
            return
        case .proceed:
            break
        }

        // Ensure we release mutex on exit
        defer {
            stateQueue.sync {
                _isExecuting = false
                _currentProcess = nil
            }
        }

        // 4. Send initial status message
        let label = modelLabel(model)
        let statusText: String
        if let sid = resumeSessionId {
            statusText = "Resuming \(sid.prefix(8))... (\(label))"
        } else {
            statusText = "Thinking... (\(label))"
        }

        guard let messageId = await sendMessage(statusText) else {
            logger.error("Failed to send initial status message")
            return
        }

        let startTime = Date()

        // 5. Map model string to ClaudeModel enum
        let claudeModel: ClaudeModel
        if let parsed = ClaudeModel.from(flag: model) {
            claudeModel = parsed
        } else {
            let lower = model.lowercased()
            if lower.contains("haiku") {
                claudeModel = .haiku
            } else if lower.contains("opus") {
                claudeModel = .opus
            } else {
                claudeModel = .sonnet
            }
        }

        // 6. Spawn ClaudeProcess
        let process = ClaudeProcess()
        stateQueue.sync { _currentProcess = process }

        // Thread-safe shared state for streaming callbacks
        let state = PromptStreamState()
        let minChars = self.minInitialChars
        let throttle = self.editThrottleSeconds

        // Bridge callback-based ClaudeProcess API to async
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in

            // Timeout: cancel after Config.promptTimeoutSeconds
            let timeoutItem = DispatchWorkItem { [weak process] in
                process?.stop()
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + .seconds(Config.promptTimeoutSeconds),
                execute: timeoutItem
            )

            process.start(
                prompt: prompt,
                model: claudeModel,
                workingDirectory: cwd,
                onChunk: { chunk in
                    switch chunk {
                    case .text(let text):
                        state.appendText(text)

                        let now = Date()
                        let timeSinceEdit = now.timeIntervalSince(state.lastEditTime)
                        let currentText = state.accumulatedText

                        guard currentText.count >= minChars,
                              timeSinceEdit >= throttle else { return }

                        let preview = PromptExecutor.buildPreview(currentText, model: label)
                        guard preview != state.lastEditedText else { return }

                        state.lastEditTime = now
                        state.lastEditedText = preview

                        let msgId = messageId
                        Task { await editMessage(msgId, preview) }

                    case .toolUse(let name):
                        state.addToolName(name)

                    case .error:
                        state.hasError = true

                    case .done(let sid):
                        state.sessionId = sid

                    case .toolResult, .unknown:
                        break
                    }
                },
                onComplete: { exitCode in
                    timeoutItem.cancel()
                    guard !state.completed else { return }
                    state.completed = true

                    let snap = state.snapshot()
                    let elapsedTime = Date().timeIntervalSince(startTime)
                    let msgId = messageId

                    Task {
                        let finalMessage: String
                        if exitCode == 15 || exitCode == 137 {
                            finalMessage = "<b>Timeout</b> (\(label)) -- prompt execution exceeded \(Config.promptTimeoutSeconds)s limit."
                        } else if snap.text.isEmpty && snap.hasError {
                            finalMessage = "<b>Error</b> (\(label)) -- Claude CLI failed with exit code \(exitCode)."
                        } else {
                            let durationStr = String(format: "%.1fs", elapsedTime)
                            var header = "<b>\(TelegramFormatter.escapeHtml(label))</b> (\(durationStr))"
                            if let sid = snap.sessionId {
                                header += " <code>\(TelegramFormatter.escapeHtml(String(sid.prefix(8))))</code>"
                            }
                            if !snap.tools.isEmpty {
                                let toolStr = snap.tools.map { TelegramFormatter.escapeHtml($0) }.joined(separator: ", ")
                                header += "\nTools: \(toolStr)"
                            }
                            let body = TelegramFormatter.markdownToTelegramHtml(snap.text)
                            finalMessage = "\(header)\n\n\(body)"
                        }

                        let chunks = TelegramFormatter.chunkTelegramHtml(finalMessage)
                        if let firstChunk = chunks.first {
                            await editMessage(msgId, firstChunk)
                        }
                        for chunk in chunks.dropFirst() {
                            _ = await sendMessage(chunk)
                        }

                        continuation.resume()
                    }
                }
            )
        }

        // Record success/failure for circuit breaker
        let snap = state.snapshot()
        stateQueue.sync {
            if snap.hasError && snap.text.isEmpty {
                _consecutiveFailures += 1
                if _consecutiveFailures >= maxFailures {
                    _disabledUntil = Date().addingTimeInterval(disableDurationSeconds)
                    logger.warning("Circuit breaker tripped: disabled for \(Int(disableDurationSeconds))s")
                }
            } else {
                _consecutiveFailures = 0
            }
        }

        logger.info("Prompt execution complete: \(snap.text.count) chars, \(snap.tools.count) tools")
    }

    /// Cancel any running prompt execution.
    func cancel() {
        stateQueue.sync { _currentProcess?.stop() }
    }

    // MARK: - Private

    /// Build a preview of the accumulated text for edit-in-place (last 2000 chars).
    fileprivate static func buildPreview(_ text: String, model: String) -> String {
        let maxPreview = 2000
        let truncated: String
        if text.count > maxPreview {
            truncated = "...\n" + String(text.suffix(maxPreview))
        } else {
            truncated = text
        }
        let html = TelegramFormatter.markdownToTelegramHtml(truncated)
        return "<b>\(TelegramFormatter.escapeHtml(model))</b> (streaming...)\n\n\(html)"
    }
}
