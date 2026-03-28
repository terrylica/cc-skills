import Foundation
import Logging

/// Module-level memory lifecycle support.
///
/// HTTPControlServer and TelegramBot call `checkMemoryLifecycleRestart()` after TTS playback.
/// This was a free function in main.swift; now it lives in CompanionCore as a module-level
/// function backed by a registered TTSEngine + restart callback.
///
/// CompanionApp registers itself during `start()` via `MemoryLifecycle.register(...)`.

private let logger = Logger(label: "memory-lifecycle")

/// Holds the registered TTSEngine and restart callback for memory lifecycle checks.
public enum MemoryLifecycle {
    nonisolated(unsafe) static var ttsEngine: TTSEngine?
    nonisolated(unsafe) static var restartHandler: ((String) -> Void)?

    /// Register the TTSEngine and restart handler. Called once during CompanionApp.start().
    public static func register(ttsEngine: TTSEngine, restartHandler: @escaping (String) -> Void) {
        self.ttsEngine = ttsEngine
        self.restartHandler = restartHandler
    }
}

/// Check synthesis count and trigger planned restart if threshold reached.
/// Called after playback completes (not during synthesis) so the user hears
/// the complete audio before the service restarts.
///
/// Async because TTSEngine is an actor -- property access requires await.
func checkMemoryLifecycleRestart() async {
    guard let engine = MemoryLifecycle.ttsEngine else { return }
    if await engine.shouldRestartForMemory {
        let diag = await engine.memoryDiagnostics()
        let reason = "Synthesis count \(diag.synthesisCount) reached threshold \(TTSEngine.maxSynthesisBeforeRestart)"
        if let handler = MemoryLifecycle.restartHandler {
            handler(reason)
        } else {
            logger.warning("Memory lifecycle restart needed but no handler registered: \(reason)")
        }
    }
}
