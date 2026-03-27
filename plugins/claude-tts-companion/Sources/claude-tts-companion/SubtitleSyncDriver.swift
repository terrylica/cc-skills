import AppKit
import AVFoundation
import Logging

/// Drives karaoke subtitle highlighting by polling AVAudioPlayer.currentTime via a 60Hz timer.
///
/// Replaces the DispatchWorkItem timer scheduling approach with a high-frequency
/// polling loop that reads the true playback position each tick. Self-correcting:
/// if ticks are late, the next tick jumps to the correct word based on actual
/// audio position. No magic delay constants needed.
@MainActor
final class SubtitleSyncDriver {

    private let logger = Logger(label: "subtitle-sync")

    /// The active audio player whose currentTime drives word advancement
    private let player: AVAudioPlayer

    /// Chunked subtitle pages for display
    private let pages: [SubtitlePage]

    /// Cumulative onset times (wordOnsets[i] = time when word i starts speaking)
    private let wordOnsets: [TimeInterval]

    /// The subtitle panel to update with karaoke highlights
    private let subtitlePanel: SubtitlePanel

    /// High-frequency timer for polling player.currentTime (~60Hz)
    private var timer: DispatchSourceTimer?

    /// Current page being displayed
    private var currentPageIndex: Int = 0

    /// Current word index within the current page (-1 = no word highlighted yet)
    private var currentLocalWordIndex: Int = -1

    /// Total number of words across all pages
    private let totalWordCount: Int

    /// Whether playback has finished (prevents further updates)
    private var didFinish: Bool = false

    // MARK: - Init

    /// Create a sync driver for the given audio player and subtitle pages.
    ///
    /// - Parameters:
    ///   - player: The AVAudioPlayer currently playing the TTS audio
    ///   - pages: Chunked subtitle pages from SubtitleChunker
    ///   - wordTimings: Per-word DURATIONS (not onsets) from TTSEngine
    ///   - subtitlePanel: The panel to update with karaoke highlights
    init(player: AVAudioPlayer, pages: [SubtitlePage], wordTimings: [TimeInterval], subtitlePanel: SubtitlePanel) {
        self.player = player
        self.pages = pages
        self.subtitlePanel = subtitlePanel
        self.totalWordCount = pages.reduce(0) { $0 + $1.wordCount }

        // Convert per-word durations to cumulative onset times:
        // wordOnsets[0] = 0, wordOnsets[1] = wordTimings[0], wordOnsets[i] = sum(wordTimings[0..<i])
        var onsets: [TimeInterval] = []
        var cumulative: TimeInterval = 0
        for timing in wordTimings {
            onsets.append(cumulative)
            cumulative += timing
        }
        self.wordOnsets = onsets

        logger.info("SubtitleSyncDriver init: \(pages.count) pages, \(totalWordCount) words, duration=\(String(format: "%.2f", player.duration))s")
    }

    // MARK: - Public API

    /// Start the polling timer and show the first page.
    func start() {
        guard !pages.isEmpty else { return }

        // Show first page with first word highlighted
        subtitlePanel.highlightWord(at: 0, in: pages[0].words)
        currentPageIndex = 0
        currentLocalWordIndex = 0

        // Create a 60Hz timer on the main queue for UI updates
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        source.resume()
        timer = source

        logger.info("SubtitleSyncDriver started (60Hz polling)")
    }

    /// Stop the polling timer (called on cancellation or when playback ends).
    func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit {
        timer?.cancel()
    }

    // MARK: - Timer Callback

    private func tick() {
        guard !didFinish else { return }

        let t = player.currentTime

        // Detect external stop (player reset to 0 while not playing)
        if !player.isPlaying && t == 0 && !didFinish {
            // Could be pre-start or external interruption. If we've already started
            // and player stopped, treat as finished.
            if currentLocalWordIndex > 0 {
                logger.info("SubtitleSyncDriver: player stopped externally at t=0")
                finishPlayback()
                return
            }
        }

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
            logger.info("SubtitleSyncDriver: page \(targetPageIndex), word \(localIndex) at t=\(String(format: "%.3f", t))s")
        } else if localIndex != currentLocalWordIndex {
            currentLocalWordIndex = localIndex
            subtitlePanel.highlightWord(at: localIndex, in: pages[currentPageIndex].words)
        }

        // Check if playback finished naturally
        if !player.isPlaying && t > 0 {
            finishPlayback()
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
