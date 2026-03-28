import Foundation
import Logging

/// Serializes access to the shared AudioStreamPlayer + SubtitleSyncDriver lifecycle.
///
/// Both TelegramBot and HTTPControlServer need to reset AudioStreamPlayer and create
/// SubtitleSyncDrivers. Without coordination, simultaneous requests produce interleaved
/// audio or silent drops. This coordinator is the single owner of:
/// 1. AudioStreamPlayer reset/schedule lifecycle
/// 2. SubtitleSyncDriver creation and teardown
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

    init(playbackManager: PlaybackManager, subtitlePanel: SubtitlePanel) {
        self.playbackManager = playbackManager
        self.subtitlePanel = subtitlePanel
        logger.info("TTSPipelineCoordinator created")
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

        // Add all chunks to the driver
        for chunk in chunks {
            let fontSizeName = subtitlePanel.currentFontSizeName
            let pages = SubtitleChunker.chunkIntoPages(text: chunk.text, fontSizeName: fontSizeName)
            driver.addChunk(
                wavPath: chunk.wavPath,
                samples: chunk.samples,
                pages: pages,
                wordTimings: chunk.wordTimings,
                nativeOnsets: chunk.wordOnsets
            )
        }

        // Start batch playback: schedules ALL buffers, then plays gaplessly
        driver.startBatchPlayback()

        logger.info("Started batch pipeline with \(chunks.count) chunks")
    }
}
