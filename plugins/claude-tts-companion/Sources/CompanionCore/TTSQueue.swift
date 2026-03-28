// Priority-aware FIFO queue for TTS requests.
// User-initiated (BTT) preempts automated (hooks). Single worker serializes GPU access.
import Foundation
import Logging

/// Priority level for TTS requests.
public enum TTSPriority: Sendable {
    /// Claude Code session hooks — queued, droppable, preemptable.
    case automated
    /// BetterTouchTool hotkey — preempts everything, blocks automated until done.
    case userInitiated
}

/// Result of attempting to enqueue a TTS request.
public enum TTSEnqueueResult: Sendable {
    case queued(position: Int)
    case rejected(reason: String)
}

/// Cooperative cancellation token shared between queue and synthesis loop.
/// Checked between sentences in TTSEngine.synthesizeStreaming().
public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    public func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
}

/// Priority-aware FIFO queue that serializes TTS synthesis and playback.
///
/// - Automated requests (hooks): queued up to 3 deep, drop-oldest on overflow
/// - User-initiated requests (BTT): cancel in-flight + drain queue + play immediately
/// - Single worker: only one synthesis + playback at a time (single GPU)
public actor TTSQueue {

    private let logger = Logger(label: "tts-queue")

    // Dependencies
    private let ttsEngine: TTSEngine
    private let pipelineCoordinator: TTSPipelineCoordinator
    private let subtitlePanel: SubtitlePanel
    private let captionHistory: CaptionHistory

    // Queue state
    private struct WorkItem {
        let id: UUID
        let text: String
        let greeting: String?
        let priority: TTSPriority
    }

    private var queue: [WorkItem] = []
    private var currentTask: Task<Void, Never>?
    private var currentToken: CancellationToken?
    private var userRequestActive = false

    static let maxAutomatedQueueDepth = 3

    public init(ttsEngine: TTSEngine, pipelineCoordinator: TTSPipelineCoordinator, subtitlePanel: SubtitlePanel, captionHistory: CaptionHistory) {
        self.ttsEngine = ttsEngine
        self.pipelineCoordinator = pipelineCoordinator
        self.subtitlePanel = subtitlePanel
        self.captionHistory = captionHistory
    }

    // MARK: - Public API

    /// Enqueue a TTS request. Returns immediately with queue status.
    /// Automated requests may be rejected (503) if a user request is active.
    public func enqueue(text: String, greeting: String?, priority: TTSPriority) -> TTSEnqueueResult {
        if priority == .userInitiated {
            return enqueueUserInitiated(text: text)
        } else {
            return enqueueAutomated(text: text, greeting: greeting)
        }
    }

    /// Enqueue a user-initiated request and wait for playback to complete.
    /// Used by HTTP /tts/speak with X-TTS-Priority: user-initiated.
    public func enqueueAndAwait(text: String) async {
        // Preempt: cancel current + drain queue
        preempt()

        // Execute synchronously (awaits playback completion)
        await executeWorkItem(WorkItem(
            id: UUID(), text: text, greeting: nil, priority: .userInitiated
        ))

        userRequestActive = false
        processNext()
    }

    // MARK: - Private: Enqueue Logic

    private func enqueueUserInitiated(text: String) -> TTSEnqueueResult {
        preempt()

        let item = WorkItem(id: UUID(), text: text, greeting: nil, priority: .userInitiated)
        currentTask = Task { [weak self] in
            await self?.executeWorkItem(item)
            await self?.onWorkItemComplete()
        }

        return .queued(position: 0)
    }

    private func enqueueAutomated(text: String, greeting: String?) -> TTSEnqueueResult {
        if userRequestActive {
            return .rejected(reason: "User-initiated request in progress")
        }

        // Drop oldest if at capacity
        while queue.count >= Self.maxAutomatedQueueDepth {
            let dropped = queue.removeFirst()
            logger.info("Dropped oldest automated TTS request: \(dropped.id)")
        }

        let item = WorkItem(id: UUID(), text: text, greeting: greeting, priority: .automated)
        queue.append(item)
        logger.info("Queued automated TTS request: position \(queue.count), \(text.count) chars")

        // Start worker if idle
        if currentTask == nil {
            processNext()
        }

        return .queued(position: queue.count)
    }

    // MARK: - Private: Preemption

    private func preempt() {
        // Cancel in-flight work
        currentToken?.cancel()
        currentTask?.cancel()
        currentTask = nil

        // Cancel playback immediately
        DispatchQueue.main.async { [pipelineCoordinator] in
            pipelineCoordinator.cancelCurrentPipeline()
        }

        // Drain automated queue
        let droppedCount = queue.count
        queue.removeAll()
        if droppedCount > 0 {
            logger.info("Preemption: dropped \(droppedCount) queued automated requests")
        }

        userRequestActive = true
    }

    // MARK: - Private: Worker

    private func processNext() {
        guard !queue.isEmpty else {
            currentTask = nil
            currentToken = nil
            return
        }

        let item = queue.removeFirst()
        currentTask = Task { [weak self] in
            await self?.executeWorkItem(item)
            await self?.onWorkItemComplete()
        }
    }

    private func onWorkItemComplete() {
        if userRequestActive {
            userRequestActive = false
            logger.info("User-initiated request complete — automated requests unblocked")
        }
        processNext()
    }

    private func executeWorkItem(_ item: WorkItem) async {
        let token = CancellationToken()
        currentToken = token

        // Memory pressure check
        let memoryConstrained = await MainActor.run { pipelineCoordinator.shouldUseSubtitleOnly }
        if memoryConstrained {
            logger.warning("Memory pressure — subtitle-only for \(item.text.count) chars")
            showSubtitleFallback(item)
            return
        }

        // Circuit breaker check
        if await ttsEngine.isTTSCircuitBreakerOpen {
            logger.warning("Circuit breaker open — subtitle-only for \(item.text.count) chars")
            showSubtitleFallback(item)
            return
        }

        // Build full text with greeting
        let fullText: String
        if let greeting = item.greeting, !greeting.isEmpty {
            fullText = "\(greeting) \(item.text)"
        } else {
            fullText = item.text
        }

        logger.info("Synthesizing \(item.priority == .userInitiated ? "USER" : "auto") TTS: \(fullText.count) chars")

        // Synthesize with cooperative cancellation
        let chunks = await ttsEngine.synthesizeStreamingAutoRoute(
            text: fullText,
            cancellationCheck: { token.isCancelled }
        )

        // Check cancellation between synthesis and playback
        if Task.isCancelled || token.isCancelled {
            logger.info("TTS cancelled before playback")
            return
        }

        guard !chunks.isEmpty else {
            logger.warning("No chunks produced — subtitle-only fallback")
            showSubtitleFallback(item)
            return
        }

        // Record to caption history for scrollback
        captionHistory.record(fullText)

        // Start playback and await completion
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { [pipelineCoordinator, logger] in
                pipelineCoordinator.startBatchPipeline(
                    chunks: chunks,
                    onComplete: {
                        logger.info("Playback complete for \(item.priority == .userInitiated ? "USER" : "auto") request")
                        continuation.resume()
                    }
                )
            }
        }
    }

    private func showSubtitleFallback(_ item: WorkItem) {
        let text = item.greeting.map { "\($0) \(item.text)" } ?? item.text
        DispatchQueue.main.async { [subtitlePanel] in
            subtitlePanel.show(text: text)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                subtitlePanel.hide()
            }
        }
    }
}
