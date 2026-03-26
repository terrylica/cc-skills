import Foundation
import Logging

/// Model selection for Claude CLI invocations (BOT-05).
///
/// Maps to `--model` flag values for the `claude` CLI tool.
enum ClaudeModel: String, Sendable, CaseIterable {
    case haiku = "haiku"
    case sonnet = "sonnet"
    case opus = "opus"

    /// The display name for Telegram messages.
    var displayName: String {
        switch self {
        case .haiku: return "Haiku"
        case .sonnet: return "Sonnet"
        case .opus: return "Opus"
        }
    }

    /// Parse a model from a command flag string (e.g., "--haiku", "sonnet").
    static func from(flag: String) -> ClaudeModel? {
        let cleaned = flag.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
        return ClaudeModel(rawValue: cleaned)
    }
}

/// A parsed chunk from Claude CLI's streaming NDJSON output (CLI-02).
///
/// The Claude CLI streams responses as newline-delimited JSON objects.
/// Each line has a `type` field indicating the event kind.
enum ClaudeOutputChunk: Sendable {
    /// An assistant text response fragment
    case text(String)
    /// A tool use event (tool name + input summary)
    case toolUse(name: String)
    /// A tool result
    case toolResult(content: String)
    /// The session completed (final message)
    case done(sessionId: String?)
    /// An error from the CLI
    case error(String)
    /// An unrecognized event type
    case unknown(type: String)
}

/// Manages spawning and communicating with the `claude` CLI as a subprocess (CLI-01).
///
/// Key behaviors:
/// - Spawns `claude` via Foundation Process + Pipe
/// - Unsets `CLAUDECODE` env var to avoid recursive invocation (CLI-03)
/// - Streams NDJSON output line-by-line and parses into ClaudeOutputChunk (CLI-02)
/// - Supports model selection via --model flag (BOT-05)
final class ClaudeProcess: @unchecked Sendable {

    private let logger = Logger(label: "claude-process")

    /// The underlying Foundation Process (nil until start() is called).
    private var process: Process?

    /// Lock protecting process state.
    private let lock = NSLock()

    /// Whether the process has been started.
    private var isRunning = false

    /// Buffer for stderr output from the CLI subprocess.
    private var stderrBuffer = Data()

    // MARK: - Public API

    /// Spawn the claude CLI with the given prompt and model.
    ///
    /// The CLI runs as a subprocess with CLAUDECODE unset (CLI-03). Output is
    /// streamed as NDJSON and parsed line-by-line. Each parsed chunk is delivered
    /// to `onChunk` on a background queue. `onComplete` fires when the process exits.
    ///
    /// - Parameters:
    ///   - prompt: The user prompt to send to Claude
    ///   - model: Which Claude model to use (default: sonnet)
    ///   - workingDirectory: Optional working directory for the CLI
    ///   - onChunk: Callback for each parsed NDJSON chunk
    ///   - onComplete: Callback when the process exits (with exit code)
    func start(
        prompt: String,
        model: ClaudeModel = .sonnet,
        workingDirectory: String? = nil,
        onChunk: @escaping @Sendable (ClaudeOutputChunk) -> Void,
        onComplete: @escaping @Sendable (Int32) -> Void
    ) {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            logger.warning("ClaudeProcess already running, ignoring start()")
            return
        }
        isRunning = true
        lock.unlock()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Config.claudeCLIPath)
        proc.arguments = buildArguments(prompt: prompt, model: model)

        // CLI-03: Unset CLAUDECODE to prevent recursive invocation
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        proc.environment = env

        if let dir = workingDirectory {
            proc.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        // Set up stdout pipe for NDJSON streaming
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        // Stream stdout line-by-line on a background queue
        let readQueue = DispatchQueue(label: "com.terryli.claude-process.read", qos: .userInitiated)
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF
                handle.readabilityHandler = nil
                return
            }
            readQueue.async {
                self?.processOutputData(data, onChunk: onChunk)
            }
        }

        // Capture stderr for error reporting
        self.stderrBuffer = Data()
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.lock.lock()
            self?.stderrBuffer.append(data)
            self?.lock.unlock()
        }

        proc.terminationHandler = { [weak self] terminatedProcess in
            let exitCode = terminatedProcess.terminationStatus
            self?.lock.lock()
            let capturedStderr = self?.stderrBuffer ?? Data()
            self?.isRunning = false
            self?.process = nil
            self?.stderrBuffer = Data()
            self?.lock.unlock()

            // Report any stderr content as an error chunk
            if !capturedStderr.isEmpty,
               let errorText = String(data: capturedStderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !errorText.isEmpty {
                onChunk(.error(errorText))
            }

            self?.logger.info("Claude CLI exited with code \(exitCode)")
            onComplete(exitCode)
        }

        lock.lock()
        process = proc
        lock.unlock()

        do {
            try proc.run()
            logger.info("Started claude CLI: model=\(model.rawValue), prompt=\(prompt.prefix(50))...")
        } catch {
            logger.error("Failed to start claude CLI: \(error)")
            lock.lock()
            isRunning = false
            process = nil
            lock.unlock()
            onChunk(.error("Failed to start: \(error.localizedDescription)"))
            onComplete(-1)
        }
    }

    /// Terminate the running claude CLI process.
    func stop() {
        lock.lock()
        let proc = process
        lock.unlock()

        proc?.terminate()
        logger.info("Sent SIGTERM to claude CLI")
    }

    /// Whether the process is currently running.
    var running: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    // MARK: - Private

    /// Partial line buffer for NDJSON parsing (lines may arrive split across reads).
    private var lineBuffer = ""

    /// Build CLI arguments for the given prompt and model.
    private func buildArguments(prompt: String, model: ClaudeModel) -> [String] {
        var args = [
            "--print",           // Non-interactive mode, output to stdout
            "--output-format", "stream-json",  // NDJSON streaming output
            "--model", model.rawValue,
        ]

        // Append the prompt as the positional argument
        args.append(prompt)

        return args
    }

    /// Process raw output data, splitting into lines and parsing NDJSON.
    private func processOutputData(
        _ data: Data,
        onChunk: @escaping @Sendable (ClaudeOutputChunk) -> Void
    ) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        lineBuffer += text
        let lines = lineBuffer.components(separatedBy: "\n")

        // Keep the last incomplete line in the buffer
        lineBuffer = lines.last ?? ""

        // Parse all complete lines (everything except the last)
        for line in lines.dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let chunk = parseNDJSONLine(trimmed) {
                onChunk(chunk)
            }
        }
    }

    /// Parse a single NDJSON line into a ClaudeOutputChunk.
    private func parseNDJSONLine(_ line: String) -> ClaudeOutputChunk? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.debug("Unparseable NDJSON line: \(line.prefix(80))")
            return nil
        }

        let type = json["type"] as? String ?? "unknown"

        switch type {
        case "assistant", "content_block_delta":
            // Extract text from delta or content
            if let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                return .text(text)
            }
            if let content = json["content"] as? String {
                return .text(content)
            }
            return nil  // Skip non-text deltas (e.g., tool_use deltas)

        case "content_block_start":
            // Check if it's a tool_use block
            if let contentBlock = json["content_block"] as? [String: Any],
               contentBlock["type"] as? String == "tool_use",
               let name = contentBlock["name"] as? String {
                return .toolUse(name: name)
            }
            return nil

        case "tool_result":
            let content = json["content"] as? String ?? ""
            return .toolResult(content: String(content.prefix(200)))

        case "message_stop", "result":
            let sessionId = json["session_id"] as? String
            return .done(sessionId: sessionId)

        case "error":
            let message = json["error"] as? String
                ?? (json["message"] as? String)
                ?? "Unknown error"
            return .error(message)

        default:
            return .unknown(type: type)
        }
    }
}
