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

    /// Start memory pressure monitoring.
    ///
    /// Called from CompanionApp.start() after subsystems are created.
    func startMonitoring() {
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

        logger.info("TTSPipelineCoordinator monitoring started (memory pressure)")
    }

    /// Stop monitoring and clean up dispatch sources.
    ///
    /// Called from CompanionApp.shutdown().
    func stopMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        memoryRecoveryWorkItem?.cancel()
        memoryRecoveryWorkItem = nil
        logger.info("TTSPipelineCoordinator monitoring stopped")
    }

    // MARK: - Pipeline Lifecycle

    /// Tracks how many streaming chunks have been fed (for "start playback on first chunk" logic).
    private var streamingChunkCount: Int = 0

    /// Stored completion callback for streaming pipeline (called when playback finishes).
    private var streamingOnComplete: (() -> Void)?

    /// Cancel any in-progress pipeline session.
    ///
    /// Stops the active sync driver, resets AudioStreamPlayer (cancels queued buffers,
    /// keeps engine warm), and stops any AVAudioPlayer playback.
    func cancelCurrentPipeline() {
        let hadActive = activeSyncDriver != nil
        activeSyncDriver?.stop()
        activeSyncDriver = nil
        playbackManager.afplayPlayer.reset()
        playbackManager.stopPlayback()
        subtitlePanel.clearEdgeHint()  // Clear any jagged edges from bisected segments
        isActive = false
        streamingChunkCount = 0
        streamingOnComplete = nil
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

        let afplay = playbackManager.afplayPlayer
        afplay.reset()
        let driver = SubtitleSyncDriver(
            subtitlePanel: subtitlePanel,
            afplayPlayer: afplay,
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

    // MARK: - Streaming Paragraph Pipeline

    /// Start a streaming pipeline session. Creates the SubtitleSyncDriver upfront,
    /// then callers feed chunks incrementally via addStreamingChunk().
    /// Call finalizeStreamingPipeline() after the last chunk is fed.
    ///
    /// - Parameter onComplete: Called when all streaming playback finishes.
    /// - Returns: true if pipeline started successfully.
    @discardableResult
    func startStreamingPipeline(onComplete: (() -> Void)? = nil) -> Bool {
        // Cancel any in-progress session first
        cancelCurrentPipeline()
        isActive = true
        streamingChunkCount = 0
        streamingOnComplete = onComplete

        let afplay = playbackManager.afplayPlayer
        afplay.reset()
        let driver = SubtitleSyncDriver(
            subtitlePanel: subtitlePanel,
            afplayPlayer: afplay,
            onStreamingComplete: { [weak self] in
                self?.isActive = false
                self?.activeSyncDriver = nil
                self?.streamingChunkCount = 0
                self?.logger.info("Streaming pipeline playback complete")
                self?.streamingOnComplete?()
                self?.streamingOnComplete = nil
            }
        )
        activeSyncDriver = driver

        logger.info("Started streaming pipeline session (awaiting paragraph chunks)")
        return true
    }

    /// Feed a synthesized paragraph chunk to the active streaming pipeline.
    /// The driver accumulates chunks for gapless playback.
    ///
    /// Uses the same subtitle logic as startBatchPipeline: paragraph scope with
    /// Kokoro-aligned words and punctuation reattachment.
    func addStreamingChunk(_ chunks: [TTSEngine.ChunkResult], edgeHint: SubtitleBorder.EdgeHint = .none) {
        guard let driver = activeSyncDriver else {
            logger.warning("addStreamingChunk called with no active pipeline -- ignoring")
            return
        }

        guard !chunks.isEmpty else {
            logger.warning("addStreamingChunk called with empty chunks")
            return
        }

        let scope = subtitlePanel.currentSubtitleScope

        if scope == "sentence" {
            // Legacy per-sentence subtitles (paginated to 2-line pages)
            let fontSizeName = subtitlePanel.currentFontSizeName
            for chunk in chunks {
                let pages = SubtitleChunker.chunkIntoPages(text: chunk.text, fontSizeName: fontSizeName)
                driver.addChunk(
                    wavPath: chunk.wavPath,
                    samples: chunk.samples,
                    pages: pages,
                    wordTimings: chunk.wordTimings,
                    nativeOnsets: chunk.wordOnsets,
                    edgeHint: edgeHint
                )
            }
        } else if chunks.count == 1 {
            // Paragraph scope: single page with ALL words (panel auto-sizes).
            let chunk = chunks[0]
            let words: [String]
            if let kokoroWords = chunk.wordTexts, !kokoroWords.isEmpty {
                words = PronunciationProcessor.reattachPunctuation(
                    originalText: chunk.text, kokoroTokens: kokoroWords
                )
                logger.info("Streaming chunk: Kokoro-aligned words with punctuation (\(words.count) words)")
            } else {
                words = PronunciationProcessor.splitWordsMatchingKokoro(chunk.text)
                logger.info("Streaming chunk: fallback splitWordsMatchingKokoro (\(words.count) words)")
            }
            let breaks = PronunciationProcessor.paragraphBreakIndices(chunk.text, displayWords: words)
            let pages = [SubtitlePage(words: words, startWordIndex: 0, paragraphBreaksAfter: breaks)]
            driver.addChunk(
                wavPath: chunk.wavPath,
                samples: chunk.samples,
                pages: pages,
                wordTimings: chunk.wordTimings,
                nativeOnsets: chunk.wordOnsets,
                edgeHint: edgeHint
            )
        } else {
            // Multiple chunks in paragraph mode: merge into one subtitle stream.
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

            let allWords: [String]
            if !allWordTexts.isEmpty {
                let fullText = chunks.map { $0.text }.joined(separator: " ")
                allWords = PronunciationProcessor.reattachPunctuation(
                    originalText: fullText, kokoroTokens: allWordTexts
                )
                logger.info("Streaming chunk: merged Kokoro-aligned words (\(allWords.count) words)")
            } else {
                let fullText = chunks.map { $0.text }.joined(separator: " ")
                allWords = PronunciationProcessor.splitWordsMatchingKokoro(fullText)
                logger.info("Streaming chunk: fallback merged splitWordsMatchingKokoro (\(allWords.count) words)")
            }
            let pages = [SubtitlePage(words: allWords, startWordIndex: 0)]
            driver.addChunk(
                wavPath: chunks.first?.wavPath ?? "",
                samples: allSamples.isEmpty ? nil : allSamples,
                pages: pages,
                wordTimings: allWordTimings,
                nativeOnsets: allWordOnsets.isEmpty ? nil : allWordOnsets,
                edgeHint: edgeHint
            )
        }

        streamingChunkCount += 1

        // Accumulate audio on AfplayPlayer (deferred playback until finalize).
        let afplay = playbackManager.afplayPlayer
        for chunk in chunks {
            if let samples = chunk.samples, !samples.isEmpty {
                afplay.appendChunk(samples: samples)
            }
        }

        logger.info("Fed streaming chunk \(streamingChunkCount) to pipeline (afplay-deferred)")
    }

    /// Signal that all chunks have been fed. No more chunks will arrive.
    /// Schedules the completion callback on the last audio buffer.
    func finalizeStreamingPipeline() {
        guard let driver = activeSyncDriver else { return }
        driver.markAllChunksDelivered()

        // Start afplay playback now that all chunks are accumulated.
        // The driver's startAfplayPlayback() writes the WAV and launches afplay,
        // then starts the 60Hz karaoke timer synced to wall-clock time.
        driver.startAfplayPlayback()

        logger.info("Streaming pipeline finalized with \(streamingChunkCount) total chunks (afplay started)")
    }
}
