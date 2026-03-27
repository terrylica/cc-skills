import AppKit
import AVFoundation
import Logging

/// Drives karaoke subtitle highlighting by polling AVAudioPlayer.currentTime via a 60Hz timer.
///
/// Supports two modes:
/// 1. **Single-shot** (legacy): init with a single player + pages + wordTimings, call start()
/// 2. **Streaming**: init with subtitlePanel only, call addChunk() as chunks arrive
///
/// In streaming mode, the driver manages sequential AVAudioPlayers (one per chunk)
/// with cumulative time offsets for seamless subtitle progression.
@MainActor
final class SubtitleSyncDriver {

    private let logger = Logger(label: "subtitle-sync")

    /// The subtitle panel to update with karaoke highlights
    private let subtitlePanel: SubtitlePanel

    /// High-frequency timer for polling player.currentTime (~60Hz)
    private var timer: DispatchSourceTimer?

    /// Whether playback has finished (prevents further updates)
    private var didFinish: Bool = false

    // MARK: - Single-shot mode properties

    /// The active audio player whose currentTime drives word advancement (single-shot mode)
    private var player: AVAudioPlayer?

    /// Chunked subtitle pages for display (single-shot mode)
    private var pages: [SubtitlePage] = []

    /// Cumulative onset times (wordOnsets[i] = time when word i starts speaking)
    private var wordOnsets: [TimeInterval] = []

    /// Total number of words across all pages
    private var totalWordCount: Int = 0

    /// Current page being displayed
    private var currentPageIndex: Int = 0

    /// Current word index within the current page (-1 = no word highlighted yet)
    private var currentLocalWordIndex: Int = -1

    // MARK: - Streaming mode properties

    /// Whether this driver is in streaming mode
    private var isStreamingMode: Bool = false

    /// Queued chunks waiting to be played
    private struct StreamChunk {
        let wavPath: String
        let pages: [SubtitlePage]
        let wordTimings: [TimeInterval]
        let wordOnsets: [TimeInterval]
        let totalWords: Int
    }

    /// All chunks received so far (played + pending)
    private var streamChunks: [StreamChunk] = []

    /// Index of the chunk currently being played
    private var currentChunkIndex: Int = 0

    /// The player for the currently playing chunk
    private var streamPlayer: AVAudioPlayer?

    /// Delegate retained to prevent dealloc during playback
    private var streamPlaybackDelegate: AnyObject?

    /// Cumulative audio duration of all chunks before the current one
    private var cumulativeOffset: TimeInterval = 0

    /// Whether we are waiting for the next chunk to become available
    private var waitingForNextChunk: Bool = false

    /// Whether all chunks have been delivered (onAllComplete called)
    private var allChunksDelivered: Bool = false

    /// TTSEngine reference for creating players (streaming mode)
    private var ttsEngine: TTSEngine?

    // MARK: - Init (Single-shot mode)

    /// Create a sync driver for the given audio player and subtitle pages.
    ///
    /// - Parameters:
    ///   - player: The AVAudioPlayer currently playing the TTS audio
    ///   - pages: Chunked subtitle pages from SubtitleChunker
    ///   - wordTimings: Per-word DURATIONS (not onsets) from TTSEngine
    ///   - subtitlePanel: The panel to update with karaoke highlights
    init(player: AVAudioPlayer, pages: [SubtitlePage], wordTimings: [TimeInterval], subtitlePanel: SubtitlePanel) {
        self.subtitlePanel = subtitlePanel
        self.player = player
        self.pages = pages
        self.totalWordCount = pages.reduce(0) { $0 + $1.wordCount }
        self.isStreamingMode = false

        // Convert per-word durations to cumulative onset times
        var onsets: [TimeInterval] = []
        var cumulative: TimeInterval = 0
        for timing in wordTimings {
            onsets.append(cumulative)
            cumulative += timing
        }
        self.wordOnsets = onsets

        logger.info("SubtitleSyncDriver init (single-shot): \(pages.count) pages, \(totalWordCount) words, duration=\(String(format: "%.2f", player.duration))s")
    }

    // MARK: - Init (Streaming mode)

    /// Create a sync driver for streaming mode. Call addChunk() as chunks arrive.
    ///
    /// - Parameters:
    ///   - subtitlePanel: The panel to update with karaoke highlights
    ///   - ttsEngine: TTSEngine instance for creating AVAudioPlayers
    init(subtitlePanel: SubtitlePanel, ttsEngine: TTSEngine) {
        self.subtitlePanel = subtitlePanel
        self.ttsEngine = ttsEngine
        self.isStreamingMode = true

        logger.info("SubtitleSyncDriver init (streaming): awaiting first chunk")
    }

    // MARK: - Public API

    /// Start the polling timer and show the first page (single-shot mode).
    func start() {
        guard !isStreamingMode else {
            logger.warning("start() called on streaming-mode driver -- use addChunk() instead")
            return
        }
        guard !pages.isEmpty else { return }

        // Show first page with first word highlighted
        subtitlePanel.highlightWord(at: 0, in: pages[0].words)
        currentPageIndex = 0
        currentLocalWordIndex = 0

        startTimer()
        logger.info("SubtitleSyncDriver started (60Hz polling, single-shot)")
    }

    /// Add a streaming chunk. On the first chunk, starts playback immediately.
    func addChunk(wavPath: String, pages: [SubtitlePage], wordTimings: [TimeInterval]) {
        guard isStreamingMode else {
            logger.warning("addChunk() called on single-shot driver")
            return
        }

        // Convert per-word durations to cumulative onset times
        var onsets: [TimeInterval] = []
        var cumulative: TimeInterval = 0
        for timing in wordTimings {
            onsets.append(cumulative)
            cumulative += timing
        }

        let totalWords = pages.reduce(0) { $0 + $1.wordCount }
        let chunk = StreamChunk(
            wavPath: wavPath,
            pages: pages,
            wordTimings: wordTimings,
            wordOnsets: onsets,
            totalWords: totalWords
        )
        streamChunks.append(chunk)

        logger.info("addChunk[\(streamChunks.count - 1)]: \(pages.count) pages, \(totalWords) words, wav=\(wavPath)")

        // If this is the first chunk, start playing immediately
        if streamChunks.count == 1 {
            playStreamChunk(at: 0)
            startTimer()
        } else if waitingForNextChunk {
            // We were waiting for this chunk -- start it now
            waitingForNextChunk = false
            playStreamChunk(at: currentChunkIndex)
        }
    }

    /// Signal that all chunks have been delivered.
    func markAllChunksDelivered() {
        allChunksDelivered = true
        logger.info("All streaming chunks delivered (\(streamChunks.count) total)")
    }

    /// Stop the polling timer (called on cancellation or when playback ends).
    func stop() {
        timer?.cancel()
        timer = nil
        streamPlayer?.stop()
    }

    deinit {
        timer?.cancel()
    }

    // MARK: - Streaming Playback

    /// Start playing a specific stream chunk.
    private func playStreamChunk(at index: Int) {
        guard index < streamChunks.count else {
            if allChunksDelivered {
                finishPlayback()
            } else {
                waitingForNextChunk = true
                logger.info("Waiting for chunk \(index) to be synthesized...")
            }
            return
        }

        currentChunkIndex = index
        let chunk = streamChunks[index]

        // Calculate cumulative offset from all previous chunks
        cumulativeOffset = 0
        for i in 0..<index {
            cumulativeOffset += streamChunks[i].wordTimings.reduce(0, +)
        }

        // Set up pages and onsets for the tick() logic
        self.pages = chunk.pages
        self.wordOnsets = chunk.wordOnsets
        self.totalWordCount = chunk.totalWords
        self.currentPageIndex = 0
        self.currentLocalWordIndex = -1

        // Show first page
        if let firstPage = chunk.pages.first {
            subtitlePanel.highlightWord(at: 0, in: firstPage.words)
            currentPageIndex = 0
            currentLocalWordIndex = 0
        }

        // Create and start player
        guard let engine = ttsEngine else {
            logger.error("No TTSEngine reference for streaming playback")
            return
        }

        guard let newPlayer = engine.play(wavPath: chunk.wavPath, completion: { [weak self] in
            // Playback delegate fires on completion -- but we handle
            // chunk transitions via tick() polling instead
        }) else {
            logger.error("Failed to create player for chunk \(index)")
            // Try next chunk
            DispatchQueue.main.async { [weak self] in
                self?.playStreamChunk(at: index + 1)
            }
            return
        }

        streamPlayer = newPlayer
        logger.info("Playing stream chunk \(index)/\(streamChunks.count - 1), cumulativeOffset=\(String(format: "%.2f", cumulativeOffset))s")
    }

    // MARK: - Timer

    private func startTimer() {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        source.resume()
        timer = source
    }

    // MARK: - Timer Callback

    private func tick() {
        guard !didFinish else { return }

        if isStreamingMode {
            tickStreaming()
        } else {
            tickSingleShot()
        }
    }

    private func tickSingleShot() {
        guard let player = player else { return }

        let t = player.currentTime

        // Find global word index for current time via linear scan of onsets
        var globalIdx = 0
        for i in 0..<wordOnsets.count {
            if t >= wordOnsets[i] {
                globalIdx = i
            } else {
                break
            }
        }
        globalIdx = min(globalIdx, max(totalWordCount - 1, 0))

        // Convert global index to page + local index
        var targetPageIndex = 0
        var localIndex = globalIdx
        for (pi, page) in pages.enumerated() {
            if globalIdx >= page.startWordIndex && globalIdx < page.startWordIndex + page.wordCount {
                targetPageIndex = pi
                localIndex = globalIdx - page.startWordIndex
                break
            }
        }

        // Update UI only when something changed
        if targetPageIndex != currentPageIndex {
            currentPageIndex = targetPageIndex
            currentLocalWordIndex = localIndex
            subtitlePanel.highlightWord(at: localIndex, in: pages[targetPageIndex].words)
        } else if localIndex != currentLocalWordIndex {
            currentLocalWordIndex = localIndex
            subtitlePanel.highlightWord(at: localIndex, in: pages[currentPageIndex].words)
        }

        if !player.isPlaying {
            finishPlayback()
        }
    }

    private func tickStreaming() {
        guard let currentPlayer = streamPlayer else {
            if waitingForNextChunk { return }
            return
        }

        let t = currentPlayer.currentTime

        // Find global word index for current time within this chunk
        var globalIdx = 0
        for i in 0..<wordOnsets.count {
            if t >= wordOnsets[i] {
                globalIdx = i
            } else {
                break
            }
        }
        globalIdx = min(globalIdx, max(totalWordCount - 1, 0))

        // Convert global index to page + local index
        var targetPageIndex = 0
        var localIndex = globalIdx
        for (pi, page) in pages.enumerated() {
            if globalIdx >= page.startWordIndex && globalIdx < page.startWordIndex + page.wordCount {
                targetPageIndex = pi
                localIndex = globalIdx - page.startWordIndex
                break
            }
        }

        // Update UI only when something changed
        if targetPageIndex != currentPageIndex {
            currentPageIndex = targetPageIndex
            currentLocalWordIndex = localIndex
            subtitlePanel.highlightWord(at: localIndex, in: pages[targetPageIndex].words)
        } else if localIndex != currentLocalWordIndex {
            currentLocalWordIndex = localIndex
            subtitlePanel.highlightWord(at: localIndex, in: pages[currentPageIndex].words)
        }

        // Check if current chunk's playback finished
        if !currentPlayer.isPlaying {
            // Advance to next chunk
            playStreamChunk(at: currentChunkIndex + 1)
        }
    }

    // MARK: - Private

    private func finishPlayback() {
        guard !didFinish else { return }
        didFinish = true
        logger.info("SubtitleSyncDriver: playback finished, lingering \(SubtitleStyle.lingerDuration)s then hiding")
        stop()

        DispatchQueue.main.asyncAfter(deadline: .now() + SubtitleStyle.lingerDuration) { [weak self] in
            self?.subtitlePanel.hide()
        }
    }
}
