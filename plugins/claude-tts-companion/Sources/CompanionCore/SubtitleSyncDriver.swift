// FILE-SIZE-OK — dual-mode sync driver (single-shot + streaming) sharing 80%+ logic
import AppKit
import AVFoundation
import Logging

/// Drives karaoke subtitle highlighting by polling AVAudioPlayer.currentTime via a 60Hz timer.
///
/// Supports two modes:
/// 1. **Single-shot** (legacy): init with a single player + pages + wordTimings, call start()
/// 2. **Streaming**: init with subtitlePanel only, call addChunk() as chunks arrive.
///    Uses AVAudioEngine-based AudioStreamPlayer for gapless chunk playback.
///
/// In streaming mode, the driver feeds raw PCM samples to AudioStreamPlayer.scheduleBuffer()
/// for seamless back-to-back playback on the real-time audio thread.
@MainActor
public final class SubtitleSyncDriver {

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
        let samples: [Float]?
        let pages: [SubtitlePage]
        let wordTimings: [TimeInterval]
        let wordOnsets: [TimeInterval]
        let totalWords: Int
        let audioDuration: TimeInterval
    }

    /// All chunks received so far (played + pending)
    private var streamChunks: [StreamChunk] = []

    /// Index of the chunk currently being played
    private var currentChunkIndex: Int = 0

    /// Cumulative audio duration of all chunks before the current one.
    /// Used to compute global playback time from AudioStreamPlayer.currentTime.
    private var cumulativeOffset: TimeInterval = 0

    /// The time at which the current chunk started playing (from AudioStreamPlayer.currentTime).
    /// Set when we schedule a chunk. currentTime within chunk = audioStreamPlayer.currentTime - chunkStartTime.
    private var chunkStartTime: TimeInterval = 0

    /// Whether we are waiting for the next chunk to become available
    private var waitingForNextChunk: Bool = false

    /// The chunk index we last logged "Waiting for" (prevents 60Hz log spam)
    private var lastWaitingLoggedChunk: Int = -1

    /// Whether all chunks have been delivered (onAllComplete called)
    private var allChunksDelivered: Bool = false

    /// AudioStreamPlayer reference for gapless streaming playback.
    /// Received directly (decoupled from TTSEngine -- SubtitleSyncDriver only needs playback, not synthesis).
    private var audioStreamPlayer: AudioStreamPlayer?

    /// Called when all streaming playback finishes (after last chunk plays to completion)
    private var onStreamingComplete: (() -> Void)?

    /// App Nap prevention token. macOS may apply App Nap to accessory apps with no
    /// visible windows, which delays DispatchSourceTimer callbacks and degrades
    /// the 60Hz karaoke poller. beginActivity() returns a token that prevents this.
    private var appNapActivity: NSObjectProtocol?

    /// Whether the current chunk's completion callback has fired (set by AudioStreamPlayer callback).
    /// Checked by the 60Hz tick to know when to advance to the next chunk.
    private var currentChunkComplete: Bool = false

    // MARK: - Legacy streaming mode properties (AVAudioPlayer-based, for single-shot)

    /// The player for the currently playing chunk (single-shot mode only)
    private var streamPlayer: AVAudioPlayer?

    /// Delegate retained to prevent dealloc during playback
    private var streamPlaybackDelegate: AnyObject?

    // MARK: - Onset Resolution

    /// Resolve word onset times: use native onsets if count matches, otherwise derive from durations.
    ///
    /// Centralizes the onset computation shared by both init paths and addChunk().
    /// Native onsets (from Kokoro duration model) include leading silence and inter-word gaps
    /// that duration-based cumulation would lose.
    private static func resolveOnsets(
        nativeOnsets: [TimeInterval]?,
        wordTimings: [TimeInterval],
        totalWords: Int,
        logger: Logger
    ) -> [TimeInterval] {
        if let nativeOnsets = nativeOnsets, nativeOnsets.count == totalWords {
            return nativeOnsets
        }
        if let nativeOnsets = nativeOnsets, nativeOnsets.count != totalWords {
            logger.warning("Onset count (\(nativeOnsets.count)) != word count (\(totalWords)) -- falling back to duration-derived onsets")
        }
        // Fallback: convert per-word durations to cumulative onset times (starts at 0)
        var onsets: [TimeInterval] = []
        var cumulative: TimeInterval = 0
        for timing in wordTimings {
            onsets.append(cumulative)
            cumulative += timing
        }
        return onsets
    }

    // MARK: - Init (Single-shot mode)

    /// Create a sync driver for the given audio player and subtitle pages.
    ///
    /// - Parameters:
    ///   - player: The AVAudioPlayer currently playing the TTS audio
    ///   - pages: Chunked subtitle pages from SubtitleChunker
    ///   - wordTimings: Per-word DURATIONS (not onsets) from TTSEngine
    ///   - nativeOnsets: Native word onset times from Python MLX server (nil = derive from durations)
    ///   - subtitlePanel: The panel to update with karaoke highlights
    init(player: AVAudioPlayer, pages: [SubtitlePage], wordTimings: [TimeInterval], nativeOnsets: [TimeInterval]? = nil, subtitlePanel: SubtitlePanel) {
        self.subtitlePanel = subtitlePanel
        self.player = player
        self.pages = pages
        self.totalWordCount = pages.reduce(0) { $0 + $1.wordCount }
        self.isStreamingMode = false

        self.wordOnsets = SubtitleSyncDriver.resolveOnsets(
            nativeOnsets: nativeOnsets,
            wordTimings: wordTimings,
            totalWords: totalWordCount,
            logger: logger
        )
        let mode = nativeOnsets != nil && nativeOnsets?.count == totalWordCount ? "native onsets" : "duration-derived"
        logger.info("SubtitleSyncDriver init (single-shot, \(mode)): \(pages.count) pages, \(totalWordCount) words, duration=\(String(format: "%.2f", player.duration))s")
    }

    // MARK: - Init (Streaming mode)

    /// Create a sync driver for batch-then-play streaming mode.
    ///
    /// Uses AudioStreamPlayer (AVAudioEngine) for gapless chunk playback.
    /// Call addChunk() for each synthesized chunk, then startBatchPlayback()
    /// to schedule ALL buffers and begin gapless playback.
    ///
    /// **Batch-then-play pattern:** All synthesis completes before any playback starts.
    /// This eliminates GPU/memory bus contention on Apple Silicon unified memory.
    ///
    /// - Parameters:
    ///   - subtitlePanel: The panel to update with karaoke highlights
    ///   - audioStreamPlayer: AudioStreamPlayer instance for gapless playback
    ///   - onStreamingComplete: Called when all chunks have finished playing (not just synthesized)
    init(subtitlePanel: SubtitlePanel, audioStreamPlayer: AudioStreamPlayer, onStreamingComplete: (() -> Void)? = nil) {
        self.subtitlePanel = subtitlePanel
        self.audioStreamPlayer = audioStreamPlayer
        self.isStreamingMode = true
        self.onStreamingComplete = onStreamingComplete

        logger.info("SubtitleSyncDriver init (streaming, batch-then-play): awaiting chunks")
    }

    // MARK: - Public API

    /// Start the polling timer and show the first page (single-shot mode).
    func start() {
        guard !isStreamingMode else {
            logger.warning("start() called on streaming-mode driver -- use addChunk() instead")
            return
        }
        guard !pages.isEmpty else { return }

        // Show first page with first word highlighted (full display pipeline)
        subtitlePanel.highlightWord(at: 0, in: pages[0].words, isPageTransition: true)
        currentPageIndex = 0
        currentLocalWordIndex = 0

        startTimer()
        logger.info("SubtitleSyncDriver started (60Hz polling, single-shot)")
    }

    /// Add a synthesized chunk to the batch. Does NOT start playback.
    ///
    /// Call this for each chunk as synthesis completes, then call startBatchPlayback()
    /// after all chunks are added to schedule ALL buffers and begin gapless playback.
    ///
    /// - Parameters:
    ///   - wavPath: Path to the WAV file for this chunk (kept for fallback/cleanup)
    ///   - samples: Raw float32 PCM samples at 24kHz (preferred, avoids WAV I/O)
    ///   - pages: Subtitle pages for this chunk
    ///   - wordTimings: Per-word durations from TTSEngine
    ///   - nativeOnsets: Native word onset times from Python MLX server (nil = derive from durations)
    func addChunk(wavPath: String, samples: [Float]? = nil, pages: [SubtitlePage], wordTimings: [TimeInterval], nativeOnsets: [TimeInterval]? = nil) {
        guard isStreamingMode else {
            logger.warning("addChunk() called on single-shot driver")
            return
        }

        let totalWords = pages.reduce(0) { $0 + $1.wordCount }
        let onsets = SubtitleSyncDriver.resolveOnsets(
            nativeOnsets: nativeOnsets,
            wordTimings: wordTimings,
            totalWords: totalWords,
            logger: logger
        )
        // Compute audioDuration from actual sample count when available.
        // TTSEngine appends trailing silence padding (100ms) to each chunk's PCM samples,
        // but wordTimings only sum to the raw (unpadded) duration. Since AVAudioEngine
        // plays the padded samples, cumulative offsets must use the padded duration to
        // keep karaoke highlighting in sync across chunks.
        let audioDuration: TimeInterval
        if let samples = samples, !samples.isEmpty {
            audioDuration = Double(samples.count) / 24000.0
        } else {
            audioDuration = wordTimings.reduce(0, +)
        }

        let chunk = StreamChunk(
            wavPath: wavPath,
            samples: samples,
            pages: pages,
            wordTimings: wordTimings,
            wordOnsets: onsets,
            totalWords: totalWords,
            audioDuration: audioDuration
        )
        streamChunks.append(chunk)

        logger.info("addChunk[\(streamChunks.count - 1)]: \(pages.count) pages, \(totalWords) words, wav=\(wavPath), hasSamples=\(samples != nil)")
    }

    /// Schedule ALL collected chunks on AudioStreamPlayer and begin gapless playback.
    ///
    /// **Batch-then-play pattern:** This method is called AFTER all synthesis is complete.
    /// It schedules every chunk's PCM buffer on the AVAudioEngine player node before
    /// starting the 60Hz karaoke timer. Since all GPU work is done, playback runs with
    /// zero memory bus contention.
    ///
    /// Must be called on the main thread (@MainActor).
    func startBatchPlayback() {
        guard isStreamingMode else {
            logger.warning("startBatchPlayback() called on single-shot driver")
            return
        }
        guard !streamChunks.isEmpty else {
            logger.warning("startBatchPlayback() called with no chunks")
            finishPlayback()
            return
        }

        allChunksDelivered = true

        guard let asp = audioStreamPlayer else {
            logger.error("No AudioStreamPlayer reference for batch playback")
            return
        }

        // Schedule ALL buffers on AudioStreamPlayer before starting playback.
        // AVAudioPlayerNode queues them internally for gapless back-to-back rendering.
        for (index, chunk) in streamChunks.enumerated() {
            let isLastChunk = (index == streamChunks.count - 1)

            if let samples = chunk.samples {
                asp.scheduleChunk(samples: samples) { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        // Clean up WAV file
                        try? FileManager.default.removeItem(atPath: chunk.wavPath)

                        if isLastChunk {
                            // Last buffer finished playing — playback is complete
                            self.currentChunkComplete = true
                            self.logger.info("Last chunk \(index) playback complete — finishing")
                        } else {
                            self.logger.info("Chunk \(index) buffer played back")
                        }
                    }
                }
            } else {
                // Fallback: schedule from WAV file
                asp.scheduleFile(wavPath: chunk.wavPath) { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if isLastChunk {
                            self.currentChunkComplete = true
                            self.logger.info("Last chunk \(index) playback complete (WAV) — finishing")
                        }
                    }
                }
            }
        }

        logger.info("Batch playback: scheduled \(streamChunks.count) buffers on AudioStreamPlayer")

        // Activate the first chunk for karaoke tracking
        activateChunk(at: 0)
        chunkStartTime = 0  // First chunk starts at time 0

        // Start the 60Hz karaoke timer
        startTimer()

        logger.info("Batch playback started: \(streamChunks.count) chunks, total duration \(String(format: "%.2f", streamChunks.reduce(0) { $0 + $1.audioDuration }))s")
    }

    /// Signal that all chunks have been delivered (legacy compatibility).
    /// In batch-then-play mode, startBatchPlayback() handles this automatically.
    func markAllChunksDelivered() {
        allChunksDelivered = true
        logger.info("All streaming chunks delivered (\(streamChunks.count) total)")
    }

    /// Stop the polling timer (called on cancellation or when playback ends).
    func stop() {
        timer?.cancel()
        timer = nil

        // Reset AudioStreamPlayer for streaming mode (cancels queued buffers)
        if isStreamingMode {
            audioStreamPlayer?.reset()

            // Clean up WAV files for any unplayed chunks
            for chunk in streamChunks {
                try? FileManager.default.removeItem(atPath: chunk.wavPath)
            }
        }

        // Stop legacy single-shot player
        streamPlayer?.stop()

        // End App Nap prevention
        if let activity = appNapActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appNapActivity = nil
        }

        // If stopped externally (not via finishPlayback), ensure callback fires
        if !didFinish {
            onStreamingComplete?()
            onStreamingComplete = nil
        }
    }

    deinit {
        timer?.cancel()
    }

    // MARK: - Streaming Playback (AVAudioEngine)

    /// Activate a chunk: compute cumulative offset, configure pages/onsets for tick(), show first page.
    ///
    /// Shared setup for streaming chunks -- prepares the tick() state (pages, wordOnsets,
    /// totalWordCount) and displays the first page.
    ///
    /// - Returns: false if the chunk index is out of range (caller should handle waiting/finishing).
    @discardableResult
    private func activateChunk(at index: Int) -> Bool {
        guard index < streamChunks.count else {
            if allChunksDelivered {
                // Don't finish immediately -- wait for AudioStreamPlayer to drain
                // The completion callback for the last buffer will trigger finishPlayback
                return false
            } else {
                waitingForNextChunk = true
                if lastWaitingLoggedChunk != index {
                    lastWaitingLoggedChunk = index
                    logger.info("Waiting for chunk \(index) to be synthesized...")
                }
            }
            return false
        }

        currentChunkIndex = index
        let chunk = streamChunks[index]

        // Calculate cumulative offset from all previous chunks
        cumulativeOffset = 0
        for i in 0..<index {
            cumulativeOffset += streamChunks[i].audioDuration
        }

        // Set up pages and onsets for the tick() logic
        self.pages = chunk.pages
        self.wordOnsets = chunk.wordOnsets
        self.totalWordCount = chunk.totalWords
        self.currentPageIndex = 0
        self.currentLocalWordIndex = -1
        self.currentChunkComplete = false

        // Show first page (full display pipeline for initial chunk display)
        if let firstPage = chunk.pages.first {
            subtitlePanel.highlightWord(at: 0, in: firstPage.words, isPageTransition: true)
            currentPageIndex = 0
            currentLocalWordIndex = 0
        }

        return true
    }

    // MARK: - Timer

    private func startTimer() {
        // Prevent App Nap from delaying our 60Hz timer. macOS can throttle timers
        // for accessory apps that have no visible windows. beginActivity() tells
        // the system we're doing user-initiated work (TTS playback + karaoke sync).
        if appNapActivity == nil {
            appNapActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiated,
                reason: "TTS karaoke subtitle playback"
            )
        }

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

        // Check playback ended BEFORE reading currentTime.
        // AVAudioPlayer resets currentTime to 0 when it finishes,
        // which would cause a spurious highlight of word 0 (bounceback).
        if !player.isPlaying {
            finishPlayback()
            return
        }

        updateHighlight(for: player.currentTime)
    }

    private func tickStreaming() {
        // Check if the last chunk's playback completed (set by completion callback)
        if currentChunkComplete {
            finishPlayback()
            return
        }

        guard let asp = audioStreamPlayer else { return }

        // AudioStreamPlayer.currentTime is cumulative across ALL scheduled buffers.
        // Determine which chunk we're in and compute local time within it.
        let globalTime = asp.currentTime

        // Find the active chunk based on cumulative time boundaries
        var cumulative: TimeInterval = 0
        var targetChunkIndex = currentChunkIndex
        for (i, chunk) in streamChunks.enumerated() {
            if globalTime < cumulative + chunk.audioDuration {
                targetChunkIndex = i
                break
            }
            cumulative += chunk.audioDuration
            // If we've passed all chunks, stay on the last one
            if i == streamChunks.count - 1 {
                targetChunkIndex = i
                cumulative -= chunk.audioDuration  // back up to start of last chunk
            }
        }

        // If we've moved to a new chunk, activate it (updates pages/onsets for karaoke)
        if targetChunkIndex != currentChunkIndex {
            activateChunk(at: targetChunkIndex)
            // Update chunkStartTime to the cumulative offset of the new chunk
            chunkStartTime = cumulative
        }

        let chunkLocalTime = max(0, globalTime - chunkStartTime)
        updateHighlight(for: chunkLocalTime)
    }

    /// Map a playback timestamp to a word index, resolve the page, and update the subtitle panel.
    ///
    /// Shared by both tickSingleShot() and tickStreaming() -- the word-onset lookup,
    /// page resolution, and UI-change-detection logic is identical for both modes.
    private func updateHighlight(for currentTime: TimeInterval) {
        // Find global word index for current time via linear scan of onsets
        var globalIdx = 0
        for i in 0..<wordOnsets.count {
            if currentTime >= wordOnsets[i] {
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
            // Page transition: full display pipeline (positionOnScreen, orderFront, diagnostics)
            currentPageIndex = targetPageIndex
            currentLocalWordIndex = localIndex
            subtitlePanel.highlightWord(at: localIndex, in: pages[targetPageIndex].words, isPageTransition: true)
        } else if localIndex != currentLocalWordIndex {
            // Per-word update: lightweight path (only set attributedStringValue)
            currentLocalWordIndex = localIndex
            subtitlePanel.highlightWord(at: localIndex, in: pages[currentPageIndex].words)
        }
    }

    // MARK: - Private

    private func finishPlayback() {
        guard !didFinish else { return }
        didFinish = true
        logger.info("SubtitleSyncDriver: playback finished, lingering \(SubtitleStyle.lingerDuration)s then hiding")
        stop()

        // Notify caller that streaming playback is fully complete
        onStreamingComplete?()
        onStreamingComplete = nil

        // Capture subtitlePanel directly — not [weak self] — because the driver
        // may be deallocated by TTSPipelineCoordinator before the linger timer fires.
        // If self is nil when the timer runs, hide() never executes and the subtitle
        // stays on screen permanently.
        let panel = subtitlePanel
        DispatchQueue.main.asyncAfter(deadline: .now() + SubtitleStyle.lingerDuration) {
            panel.hide()
        }
    }
}
