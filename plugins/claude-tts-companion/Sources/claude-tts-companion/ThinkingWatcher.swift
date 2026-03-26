import Foundation
import Logging

/// Monitors a Claude Code JSONL transcript for extended thinking blocks and summarizes them via MiniMax.
///
/// Uses `JSONLTailer` to follow a growing transcript file. When thinking content is detected
/// (type == "thinking" in JSONL entries), it accumulates the text and periodically summarizes
/// it via MiniMax API for TTS playback or subtitle display.
///
/// Thread safety: NSLock guards mutable state (consistent with TTSEngine, CircuitBreaker patterns).
final class ThinkingWatcher: @unchecked Sendable {

    private let logger = Logger(label: "thinking-watcher")
    private let lock = NSLock()

    private let client: MiniMaxClient
    private var tailer: JSONLTailer?

    /// Accumulated thinking text since last summary
    private var thinkingBuffer: String = ""
    /// Minimum characters before triggering a summary
    private let summaryThreshold: Int
    /// Callback invoked with the summarized thinking text
    private let onSummary: @Sendable (String) -> Void

    /// Whether a summary is currently in-flight (prevents concurrent summarization)
    private var isSummarizing: Bool = false

    /// Create a thinking watcher.
    ///
    /// - Parameters:
    ///   - client: Shared MiniMax client (reuses circuit breaker)
    ///   - summaryThreshold: Minimum chars of thinking text before summarizing (default 500)
    ///   - onSummary: Callback with the summarized thinking text
    init(
        client: MiniMaxClient,
        summaryThreshold: Int = 500,
        onSummary: @escaping @Sendable (String) -> Void
    ) {
        self.client = client
        self.summaryThreshold = summaryThreshold
        self.onSummary = onSummary
    }

    /// Start watching a JSONL transcript file for thinking blocks.
    ///
    /// - Parameter filePath: Absolute path to the transcript.jsonl file
    func start(filePath: String) {
        stop()  // Clean up any previous tailer

        let tailer = JSONLTailer(filePath: filePath) { [weak self] lines in
            self?.processLines(lines)
        }
        self.tailer = tailer
        tailer.start()
        logger.info("ThinkingWatcher started on \(filePath)")
    }

    /// Stop watching and flush any pending thinking text.
    func stop() {
        tailer?.stop()
        tailer = nil

        lock.lock()
        let pending = thinkingBuffer
        thinkingBuffer = ""
        lock.unlock()

        if !pending.isEmpty {
            logger.info("ThinkingWatcher stopped with \(pending.count) chars unflushed")
        }
    }

    /// Force summarize any accumulated thinking text.
    func flush() {
        lock.lock()
        let text = thinkingBuffer
        thinkingBuffer = ""
        lock.unlock()

        if !text.isEmpty {
            triggerSummary(text: text)
        }
    }

    // MARK: - Private

    /// Process new JSONL lines, extracting thinking content.
    private func processLines(_ lines: [String]) {
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Look for thinking content in the JSONL entry
            // Claude Code JSONL format: {"type": "assistant", "message": {"content": [{"type": "thinking", "thinking": "..."}]}}
            guard let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else {
                continue
            }

            for block in content {
                guard let blockType = block["type"] as? String,
                      blockType == "thinking",
                      let thinkingText = block["thinking"] as? String,
                      !thinkingText.isEmpty else {
                    continue
                }

                lock.lock()
                thinkingBuffer += thinkingText + "\n"
                let bufferLength = thinkingBuffer.count
                let currentlySummarizing = isSummarizing
                let textToSummarize = bufferLength >= summaryThreshold && !currentlySummarizing
                    ? thinkingBuffer : nil
                if textToSummarize != nil {
                    thinkingBuffer = ""
                }
                lock.unlock()

                if let text = textToSummarize {
                    triggerSummary(text: text)
                }
            }
        }
    }

    /// Summarize accumulated thinking text via MiniMax.
    private func triggerSummary(text: String) {
        lock.lock()
        guard !isSummarizing else {
            // Re-add to buffer if a summary is already in-flight
            thinkingBuffer += text
            lock.unlock()
            return
        }
        isSummarizing = true
        lock.unlock()

        Task {
            let truncated = String(text.prefix(8000))
            let prompt = """
                Summarize this internal reasoning/thinking process in 1-2 natural spoken sentences \
                suitable for text-to-speech. Focus on what is being figured out or decided. \
                Do not mention "Claude", "AI", or "the assistant". Use past tense.

                Thinking text:
                \"""
                \(truncated)
                \"""

                Summary:
                """

            let systemPrompt = "You summarize reasoning processes into brief spoken narratives. Natural language only."

            do {
                let result = try await self.client.query(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    maxTokens: 256
                )
                self.logger.info("Thinking summary: \(result.durationMs)ms, \(result.text.count) chars")
                self.onSummary(result.text)
            } catch {
                self.logger.warning("Thinking summary failed: \(error)")
            }

            self.markSummarizingComplete()
        }
    }

    /// Reset the summarizing flag from a synchronous context (avoids NSLock in async).
    private func markSummarizingComplete() {
        lock.lock()
        isSummarizing = false
        lock.unlock()
    }
}
