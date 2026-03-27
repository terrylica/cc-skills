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

    /// Pre-buffered player for the NEXT chunk (gapless transition)
    private var nextStreamPlayer: AVAudioPlayer?

    /// Delegate for the pre-buffered next player (must be retained)
    private var nextPlaybackDelegate: AnyObject?

    /// Index of the chunk that nextStreamPlayer is prepared for (-1 = none)
    private var prebufferedChunkIndex: Int = -1

    /// Cumulative audio duration of all chunks before the current one
    private var cumulativeOffset: TimeInterval = 0

    /// Whether we are waiting for the next chunk to become available
    private var waitingForNextChunk: Bool = false

    /// The chunk index we last logged "Waiting for" (prevents 60Hz log spam)
    private var lastWaitingLoggedChunk: Int = -1

    /// Whether all chunks have been delivered (onAllComplete called)
    private var allChunksDelivered: Bool = false

    /// TTSEngine reference for creating players (streaming mode)
    private var ttsEngine: TTSEngine?

    /// Called when all streaming playback finishes (after last chunk plays to completion)
    private var onStreamingComplete: (() -> Void)?

    /// App Nap prevention token. macOS may apply App Nap to accessory apps with no
    /// visible windows, which delays DispatchSourceTimer callbacks and degrades
    /// the 60Hz karaoke poller. beginActivity() returns a token that prevents this.
    private var appNapActivity: NSObjectProtocol?

    // MARK: - Init (Single-shot mode)

    /// Create a sync driver for the given audio player and subtitle pages.
    ///
    /// - Parameters:
    ///   - player: The AVAudioPlayer currently playing the TTS audio
    ///   - pages: Chunked subtitle pages from SubtitleChunker
    ///   - wordTimings: Per-word DURATIONS (not onsets) from TTSEngine
    ///   - nativeOnsets: Native word onset times from MToken.start_ts (nil = derive from durations)
    ///   - subtitlePanel: The panel to update with karaoke highlights
    init(player: AVAudioPlayer, pages: [SubtitlePage], wordTimings: [TimeInterval], nativeOnsets: [TimeInterval]? = nil, subtitlePanel: SubtitlePanel) {
        self.subtitlePanel = subtitlePanel
        self.player = player
        self.pages = pages
        self.totalWordCount = pages.reduce(0) { $0 + $1.wordCount }
        self.isStreamingMode = false

        if let nativeOnsets = nativeOnsets, nativeOnsets.count == totalWordCount {
            // Use ground-truth onset times from Kokoro duration model.
            // These include leading silence and inter-word gaps that
            // duration-based cumulation would lose.
            self.wordOnsets = nativeOnsets
            logger.info("SubtitleSyncDriver init (single-shot, native onsets): \(pages.count) pages, \(totalWordCount) words, firstOnset=\(String(format: "%.3f", nativeOnsets.first ?? 0))s, duration=\(String(format: "%.2f", player.duration))s")
        } else {
            if let nativeOnsets = nativeOnsets, nativeOnsets.count != totalWordCount {
                logger.warning("Onset count (\(nativeOnsets.count)) != word count (\(totalWordCount)) -- falling back to duration-derived onsets")
            }
            // Fallback: convert per-word durations to cumulative onset times (starts at 0)
            var onsets: [TimeInterval] = []
            var cumulative: TimeInterval = 0
            for timing in wordTimings {
                onsets.append(cumulative)
                cumulative += timing
            }
            self.wordOnsets = onsets
            logger.info("SubtitleSyncDriver init (single-shot, duration-derived): \(pages.count) pages, \(totalWordCount) words, duration=\(String(format: "%.2f", player.duration))s")
        }
    }

    // MARK: - Init (Streaming mode)

    /// Create a sync driver for streaming mode. Call addChunk() as chunks arrive.
    ///
    /// - Parameters:
    ///   - subtitlePanel: The panel to update with karaoke highlights
    ///   - ttsEngine: TTSEngine instance for creating AVAudioPlayers
    ///   - onStreamingComplete: Called when all chunks have finished playing (not just synthesized)
    init(subtitlePanel: SubtitlePanel, ttsEngine: TTSEngine, onStreamingComplete: (() -> Void)? = nil) {
        self.subtitlePanel = subtitlePanel
        self.ttsEngine = ttsEngine
        self.isStreamingMode = true
        self.onStreamingComplete = onStreamingComplete

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
    ///
    /// - Parameters:
    ///   - wavPath: Path to the WAV file for this chunk
    ///   - pages: Subtitle pages for this chunk
    ///   - wordTimings: Per-word durations from TTSEngine
    ///   - nativeOnsets: Native word onset times from MToken.start_ts (nil = derive from durations)
    func addChunk(wavPath: String, pages: [SubtitlePage], wordTimings: [TimeInterval], nativeOnsets: [TimeInterval]? = nil) {
        guard isStreamingMode else {
            logger.warning("addChunk() called on single-shot driver")
            return
        }

        let totalWords = pages.reduce(0) { $0 + $1.wordCount }
        let onsets: [TimeInterval]
        if let nativeOnsets = nativeOnsets, nativeOnsets.count == totalWords {
            // Use ground-truth onset times from Kokoro duration model
            onsets = nativeOnsets
        } else {
            if let nativeOnsets = nativeOnsets, nativeOnsets.count != totalWords {
                logger.warning("addChunk: onset count (\(nativeOnsets.count)) != word count (\(totalWords)) -- falling back to duration-derived onsets")
            }
            // Fallback: convert per-word durations to cumulative onset times (starts at 0)
            var computed: [TimeInterval] = []
            var cumulative: TimeInterval = 0
            for timing in wordTimings {
                computed.append(cumulative)
                cumulative += timing
            }
            onsets = computed
        }

        let chunk = StreamChunk(
            wavPath: wavPath,
            pages: pages,
            wordTimings: wordTimings,
            wordOnsets: onsets,
            totalWords: totalWords
        )
        streamChunks.append(chunk)

        logger.info("addChunk[\(streamChunks.count - 1)]: \(pages.count) pages, \(totalWords) words, wav=\(wavPath)")

        let newChunkIndex = streamChunks.count - 1

        // If this is the first chunk, start playing immediately
        if streamChunks.count == 1 {
            playStreamChunk(at: 0)
            startTimer()
        } else if waitingForNextChunk {
            // We were waiting for this chunk -- start it now
            waitingForNextChunk = false
            playStreamChunk(at: currentChunkIndex)
        } else if newChunkIndex == currentChunkIndex + 1 && prebufferedChunkIndex != newChunkIndex {
            // This is the chunk right after the currently playing one -- pre-buffer it now
            prebufferNextChunk(after: currentChunkIndex)
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

        // Clean up WAV files for current and pre-buffered players.
        // AVAudioPlayer.stop() does NOT trigger the delegate callback
        // (audioPlayerDidFinishPlaying), so the delegate's WAV cleanup
        // never fires. Manually delete the files to prevent /tmp/ leak.
        if let currentIndex = currentChunkIndexIfValid {
            let wavPath = streamChunks[currentIndex].wavPath
            try? FileManager.default.removeItem(atPath: wavPath)
            logger.info("Cleaned up WAV for stopped stream chunk \(currentIndex): \(wavPath)")
        }
        streamPlayer?.stop()

        if prebufferedChunkIndex >= 0, prebufferedChunkIndex < streamChunks.count {
            let wavPath = streamChunks[prebufferedChunkIndex].wavPath
            try? FileManager.default.removeItem(atPath: wavPath)
            logger.info("Cleaned up WAV for pre-buffered chunk \(prebufferedChunkIndex): \(wavPath)")
        }
        nextStreamPlayer?.stop()
        nextStreamPlayer = nil
        nextPlaybackDelegate = nil
        prebufferedChunkIndex = -1

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

    /// Safe accessor for current chunk index (only valid if chunks exist).
    private var currentChunkIndexIfValid: Int? {
        guard currentChunkIndex >= 0, currentChunkIndex < streamChunks.count else { return nil }
        return currentChunkIndex
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
                if lastWaitingLoggedChunk != index {
                    lastWaitingLoggedChunk = index
                    logger.info("Waiting for chunk \(index) to be synthesized...")
                }
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

        // Pre-buffer the next chunk for gapless transition
        prebufferNextChunk(after: index)
    }

    /// Fast-path chunk transition: use a pre-buffered player instead of creating one.
    private func advanceToPrebuilt(index: Int, player: AVAudioPlayer) {
        guard index < streamChunks.count else {
            if allChunksDelivered {
                finishPlayback()
            } else {
                waitingForNextChunk = true
                if lastWaitingLoggedChunk != index {
                    lastWaitingLoggedChunk = index
                    logger.info("Waiting for chunk \(index) to be synthesized...")
                }
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

        // Promote the pre-buffered player to active
        streamPlayer = player
        streamPlaybackDelegate = nextPlaybackDelegate
        nextStreamPlayer = nil
        nextPlaybackDelegate = nil
        prebufferedChunkIndex = -1

        // Start playback (~0ms since prepareToPlay() was already called)
        player.play()
        logger.info("Playing stream chunk \(index)/\(streamChunks.count - 1) (PRE-BUFFERED), cumulativeOffset=\(String(format: "%.2f", cumulativeOffset))s")

        // Pre-buffer the chunk after this one
        prebufferNextChunk(after: index)
    }

    /// Pre-buffer the next chunk's AVAudioPlayer while the current one is still playing.
    /// This eliminates the ~500ms-1s gap caused by synchronous player creation.
    private func prebufferNextChunk(after index: Int) {
        let nextIndex = index + 1
        guard nextIndex < streamChunks.count else {
            // Next chunk not yet available -- will be pre-buffered when addChunk() delivers it
            return
        }
        guard prebufferedChunkIndex != nextIndex else {
            // Already pre-buffered
            return
        }

        let chunk = streamChunks[nextIndex]
        guard let engine = ttsEngine else { return }

        if let prepared = engine.preparePlayer(wavPath: chunk.wavPath, completion: { }) {
            nextStreamPlayer = prepared.player
            nextPlaybackDelegate = prepared.delegate
            prebufferedChunkIndex = nextIndex
            logger.info("Pre-buffered chunk \(nextIndex) for gapless transition")
        }
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
    }

    private func tickStreaming() {
        guard let currentPlayer = streamPlayer else {
            if waitingForNextChunk { return }
            return
        }

        // Check playback ended BEFORE reading currentTime.
        // AVAudioPlayer resets currentTime to 0 when it finishes,
        // which would cause a spurious highlight of word 0 (bounceback).
        if !currentPlayer.isPlaying {
            // Advance to next chunk -- use pre-buffered player if available
            let nextIndex = currentChunkIndex + 1
            if prebufferedChunkIndex == nextIndex, let readyPlayer = nextStreamPlayer {
                // Fast path: pre-buffered player is ready, just play() (~0ms vs ~500ms)
                advanceToPrebuilt(index: nextIndex, player: readyPlayer)
            } else {
                // Slow path: no pre-buffered player, create on-demand (will have gap)
                playStreamChunk(at: nextIndex)
            }
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

        DispatchQueue.main.asyncAfter(deadline: .now() + SubtitleStyle.lingerDuration) { [weak self] in
            self?.subtitlePanel.hide()
        }
    }
}
