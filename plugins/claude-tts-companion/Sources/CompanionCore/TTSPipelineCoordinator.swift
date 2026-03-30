import Foundation
import Logging

/// Serializes access to the shared AudioStreamPlayer + SubtitleSyncDriver lifecycle.
///
/// Both TelegramBot and HTTPControlServer need to reset AudioStreamPlayer and create
/// SubtitleSyncDrivers. Without coordination, simultaneous requests produce interleaved
/// audio or silent drops. This coordinator is the single owner of:
/// 1. AudioStreamPlayer reset/schedule lifecycle
/// 2. SubtitleSyncDriver creation and teardown
/// 3. Memory pressure monitoring and subtitle-only degradation
/// 4. Audio route change recovery wiring
///
/// @MainActor because SubtitleSyncDriver and PlaybackManager are both @MainActor.
@MainActor
public final class TTSPipelineCoordinator {

    private let logger = Logger(label: "tts-pipeline-coordinator")

    private let playbackManager: PlaybackManager
    private let subtitlePanel: SubtitlePanel

    /// The active sync driver for the current pipeline session.
    /// Only the coordinator creates and destroys these.
    private var activeSyncDriver: SubtitleSyncDriver?

    /// Whether a pipeline session is currently running.
    private var isActive: Bool = false

    /// Whether the pipeline is busy (callers check to decide subtitle-only fallback).
    var isBusy: Bool { isActive }

    // MARK: - Memory Pressure

    /// Dispatch source monitoring system memory pressure events.
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// Set to true under .warning or .critical memory pressure.
    /// Auto-clears after 60 seconds of no new pressure events.
    private var isMemoryConstrained: Bool = false

    /// Pending auto-recovery work item (cancelled on each new pressure event).
    private var memoryRecoveryWorkItem: DispatchWorkItem?

    /// Whether callers should skip TTS synthesis and show subtitle-only.
    /// True when system is under memory pressure (.warning or .critical).
    var shouldUseSubtitleOnly: Bool { isMemoryConstrained }

    init(playbackManager: PlaybackManager, subtitlePanel: SubtitlePanel) {
        self.playbackManager = playbackManager
        self.subtitlePanel = subtitlePanel
        logger.info("TTSPipelineCoordinator created")
    }

    // MARK: - Monitoring

    /// Start memory pressure monitoring and wire audio route change callback.
    ///
    /// Called from CompanionApp.start() after subsystems are created.
    func startMonitoring() {
        // Memory pressure monitoring via DispatchSource
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data
            if event.contains(.critical) {
                self.isMemoryConstrained = true
                self.cancelCurrentPipeline()
                self.logger.critical("Memory pressure CRITICAL -- cancelled active TTS pipeline, subtitle-only mode active")
            } else if event.contains(.warning) {
                self.isMemoryConstrained = true
                self.logger.warning("Memory pressure WARNING -- new TTS requests will use subtitle-only mode")
            }
            // Auto-recover after 60s of no new pressure events
            self.memoryRecoveryWorkItem?.cancel()
            let recovery = DispatchWorkItem { [weak self] in
                self?.isMemoryConstrained = false
                self?.logger.info("Memory pressure cleared (60s auto-recovery)")
            }
            self.memoryRecoveryWorkItem = recovery
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: recovery)
        }
        source.resume()
        memoryPressureSource = source

        // Wire audio route change callback from AudioStreamPlayer
        playbackManager.audioStreamPlayer.onRouteChange = { [weak self] in
            self?.handleAudioRouteChange()
        }

        logger.info("TTSPipelineCoordinator monitoring started (memory pressure + audio route)")
    }

    /// Stop monitoring and clean up dispatch sources.
    ///
    /// Called from CompanionApp.shutdown().
    func stopMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        memoryRecoveryWorkItem?.cancel()
        memoryRecoveryWorkItem = nil
        playbackManager.audioStreamPlayer.onRouteChange = nil
        logger.info("TTSPipelineCoordinator monitoring stopped")
    }

    /// Handle audio route change (Bluetooth disconnect, USB DAC removal).
    ///
    /// The AudioStreamPlayer already restarted the engine on the new device.
    /// We cancel the current pipeline so the in-progress audio stops cleanly.
    /// The next TTS request will work on the new audio device automatically.
    private func handleAudioRouteChange() {
        logger.warning("Audio route changed -- cancelling current pipeline for graceful recovery")
        cancelCurrentPipeline()
    }

    // MARK: - Pipeline Lifecycle

    /// Cancel any in-progress pipeline session.
    ///
    /// Stops the active sync driver, resets AudioStreamPlayer (cancels queued buffers,
    /// keeps engine warm), and stops any AVAudioPlayer playback.
    func cancelCurrentPipeline() {
        let hadActive = activeSyncDriver != nil
        activeSyncDriver?.stop()
        activeSyncDriver = nil
        playbackManager.audioStreamPlayer.reset()
        playbackManager.stopPlayback()
        isActive = false
        if hadActive {
            logger.info("Cancelled active pipeline session")
        }
    }

    /// Start a batch pipeline session: cancel any in-progress session, create a new
    /// SubtitleSyncDriver, add all chunks, and begin gapless playback.
    ///
    /// - Parameters:
    ///   - chunks: Synthesized TTS chunks from TTSEngine.synthesizeStreaming()
    ///   - onComplete: Called when all chunks have finished playing
    func startBatchPipeline(
        chunks: [TTSEngine.ChunkResult],
        onComplete: (() -> Void)? = nil
    ) {
        // Cancel any in-progress session first
        cancelCurrentPipeline()
        isActive = true

        guard !chunks.isEmpty else {
            isActive = false
            logger.warning("startBatchPipeline called with no chunks")
            return
        }

        // Create sync driver for batch playback
        let driver = SubtitleSyncDriver(
            subtitlePanel: subtitlePanel,
            audioStreamPlayer: playbackManager.audioStreamPlayer,
            onStreamingComplete: { [weak self] in
                self?.isActive = false
                self?.activeSyncDriver = nil
                self?.logger.info("Pipeline batch playback complete")
                onComplete?()
            }
        )
        activeSyncDriver = driver

        // Add chunks to the driver.
        // "paragraph" scope: combine all text into one subtitle stream.
        // "sentence" scope: each chunk gets its own subtitle pages.
        let fontSizeName = subtitlePanel.currentFontSizeName
        let scope = subtitlePanel.currentSubtitleScope

        if scope == "sentence" {
            // Legacy per-sentence subtitles (paginated to 2-line pages)
            for chunk in chunks {
                let pages = SubtitleChunker.chunkIntoPages(text: chunk.text, fontSizeName: fontSizeName)
                driver.addChunk(
                    wavPath: chunk.wavPath,
                    samples: chunk.samples,
                    pages: pages,
                    wordTimings: chunk.wordTimings,
                    nativeOnsets: chunk.wordOnsets
                )
            }
        } else if chunks.count == 1 {
            // Paragraph scope: single page with ALL words (panel auto-sizes).
            let chunk = chunks[0]
            // Use Kokoro's word texts for 1:1 onset alignment, but re-attach
            // punctuation from the original text for display. Kokoro's Misaki/spaCy
            // tokens strip trailing punctuation (e.g., "running" not "running.").
            let words: [String]
            if let kokoroWords = chunk.wordTexts, !kokoroWords.isEmpty {
                words = PronunciationProcessor.reattachPunctuation(
                    originalText: chunk.text, kokoroTokens: kokoroWords
                )
                logger.info("Using Kokoro-aligned words with punctuation for subtitle display (\(words.count) words)")
                if words.count <= 30 {
                    logger.info("[PUNCT-FIX] Display words: \(words.joined(separator: " | "))")
                }
            } else {
                words = PronunciationProcessor.splitWordsMatchingKokoro(chunk.text)
                logger.info("Fallback to splitWordsMatchingKokoro for subtitle display (\(words.count) words)")
            }
            let breaks = PronunciationProcessor.paragraphBreakIndices(chunk.text, displayWords: words)
            let pages = [SubtitlePage(words: words, startWordIndex: 0, paragraphBreaksAfter: breaks)]
            driver.addChunk(
                wavPath: chunk.wavPath,
                samples: chunk.samples,
                pages: pages,
                wordTimings: chunk.wordTimings,
                nativeOnsets: chunk.wordOnsets
            )
        } else {
            // Multiple chunks in paragraph mode: merge into one subtitle stream.
            // Word onsets are chunk-relative, so re-accumulate to absolute time.
            var allSamples: [Float] = []
            var allWordTimings: [TimeInterval] = []
            var allWordOnsets: [TimeInterval] = []
            var allWordTexts: [String] = []
            var cumulativeTime: TimeInterval = 0

            for chunk in chunks {
                allSamples.append(contentsOf: chunk.samples ?? [])
                allWordTimings.append(contentsOf: chunk.wordTimings)
                if let onsets = chunk.wordOnsets {
                    for onset in onsets {
                        allWordOnsets.append(onset + cumulativeTime)
                    }
                }
                if let texts = chunk.wordTexts {
                    allWordTexts.append(contentsOf: texts)
                }
                cumulativeTime += chunk.audioDuration
            }

            // Use Kokoro's word texts for onset alignment, re-attach punctuation for display.
            let allWords: [String]
            if !allWordTexts.isEmpty {
                let fullText = chunks.map { $0.text }.joined(separator: " ")
                allWords = PronunciationProcessor.reattachPunctuation(
                    originalText: fullText, kokoroTokens: allWordTexts
                )
                logger.info("Using merged Kokoro-aligned words with punctuation for subtitle display (\(allWords.count) words)")
            } else {
                let fullText = chunks.map { $0.text }.joined(separator: " ")
                allWords = PronunciationProcessor.splitWordsMatchingKokoro(fullText)
                logger.info("Fallback to splitWordsMatchingKokoro for multi-chunk subtitle display (\(allWords.count) words)")
            }
            let pages = [SubtitlePage(words: allWords, startWordIndex: 0)]
            driver.addChunk(
                wavPath: chunks.first?.wavPath ?? "",
                samples: allSamples.isEmpty ? nil : allSamples,
                pages: pages,
                wordTimings: allWordTimings,
                nativeOnsets: allWordOnsets.isEmpty ? nil : allWordOnsets
            )
        }

        // Start batch playback: schedules ALL buffers, then plays gaplessly
        driver.startBatchPlayback()

        logger.info("Started batch pipeline with \(chunks.count) chunks")
    }
}
