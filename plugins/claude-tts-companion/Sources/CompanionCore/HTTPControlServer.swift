import FlyingFox
import Foundation
import Logging

/// Partial update struct for subtitle settings (all fields optional for PATCH semantics).
public struct SubtitleSettingsUpdate: Codable, Sendable {
    var fontSize: String?
    var position: String?
    var opacity: Double?
    var karaokeEnabled: Bool?
    var screen: String?
}

/// Partial update struct for TTS settings (all fields optional for PATCH semantics).
public struct TTSSettingsUpdate: Codable, Sendable {
    var enabled: Bool?
    var voice: String?
    var speed: Double?
}

/// Request body for POST /subtitle/show.
private struct ShowSubtitleRequest: Codable {
    let text: String
    let duration: Double?
}

/// Request body for POST /tts/test.
private struct TTSTestRequest: Codable {
    let text: String?
}

/// Simple success response.
private struct OkResponse: Codable {
    let ok: Bool
}

/// Error response body.
private struct ErrorResponse: Codable {
    let error: String
}

/// Health endpoint response (API-01).
private struct HealthResponse: Codable {
    let status: String
    let uptime_seconds: Int
    let rss_mb: Double
    let tts_synthesis_count: Int
    let tts_restart_threshold: Int
    let mlx_memory_active_mb: Int?
    let mlx_memory_cache_mb: Int?
    let mlx_memory_peak_mb: Int?
    let subsystems: SubsystemStatus
}

/// Subsystem status within health response.
private struct SubsystemStatus: Codable {
    let bot: String
    let tts: String
    let subtitle: String
}

/// Response body for GET /captions.
private struct CaptionsResponse: Codable {
    let captions: [CaptionEntry]
    let total: Int
}

/// Response body for POST /captions/copy.
private struct CopyResponse: Codable {
    let ok: Bool
    let copied: Int
}

/// HTTP control API server wrapping FlyingFox (API-01 through API-08).
///
/// Provides REST endpoints for health monitoring, settings management,
/// subtitle/TTS control, and caption history. Binds to localhost only (loopback) for security.
public final class HTTPControlServer: @unchecked Sendable {

    private let logger = Logger(label: "http-api")

    private let settingsStore: SettingsStore
    private let subtitlePanel: SubtitlePanel
    private let playbackManager: PlaybackManager
    private let ttsEngine: TTSEngine
    private let captionHistory: CaptionHistory
    private let pipelineCoordinator: TTSPipelineCoordinator
    private let startTime: Date
    private var telegramBot: TelegramBot?

    init(settingsStore: SettingsStore, subtitlePanel: SubtitlePanel, playbackManager: PlaybackManager, ttsEngine: TTSEngine, captionHistory: CaptionHistory, pipelineCoordinator: TTSPipelineCoordinator) {
        self.settingsStore = settingsStore
        self.subtitlePanel = subtitlePanel
        self.playbackManager = playbackManager
        self.ttsEngine = ttsEngine
        self.captionHistory = captionHistory
        self.pipelineCoordinator = pipelineCoordinator
        self.startTime = Date()
    }

    /// Start the HTTP server on the configured port (blocks until server stops).
    /// Set the TelegramBot reference for health status reporting.
    func setBot(_ bot: TelegramBot) {
        self.telegramBot = bot
    }

    func start() async throws {
        let server = HTTPServer(address: .loopback(port: Config.httpPort))

        // API-01: Health endpoint
        await server.appendRoute("GET /health") { [self] _ in
            return await healthResponse()
        }

        // API-02: Get all settings
        await server.appendRoute("GET /settings") { [self] _ in
            let settings = settingsStore.getSettings()
            return jsonResponse(settings)
        }

        // API-03: Update subtitle settings
        await server.appendRoute("POST /settings/subtitle") { [self] request in
            do {
                let body = try await request.bodyData
                let update = try JSONDecoder().decode(SubtitleSettingsUpdate.self, from: body)
                settingsStore.updateSubtitle { s in
                    if let v = update.fontSize { s.fontSize = v }
                    if let v = update.position { s.position = v }
                    if let v = update.opacity { s.opacity = v }
                    if let v = update.karaokeEnabled { s.karaokeEnabled = v }
                    if let v = update.screen { s.screen = v }
                }
                let settings = settingsStore.getSettings()
                return jsonResponse(settings)
            } catch {
                return errorResponse("Invalid request body: \(error.localizedDescription)", status: .badRequest)
            }
        }

        // API-04: Update TTS settings
        await server.appendRoute("POST /settings/tts") { [self] request in
            do {
                let body = try await request.bodyData
                let update = try JSONDecoder().decode(TTSSettingsUpdate.self, from: body)
                settingsStore.updateTTS { s in
                    if let v = update.enabled { s.enabled = v }
                    if let v = update.voice { s.voice = v }
                    if let v = update.speed { s.speed = v }
                }
                let settings = settingsStore.getSettings()
                return jsonResponse(settings)
            } catch {
                return errorResponse("Invalid request body: \(error.localizedDescription)", status: .badRequest)
            }
        }

        // API-05: Show subtitle text
        await server.appendRoute("POST /subtitle/show") { [self] request in
            do {
                let body = try await request.bodyData
                let showReq = try JSONDecoder().decode(ShowSubtitleRequest.self, from: body)
                await MainActor.run { subtitlePanel.show(text: showReq.text) }
                if let duration = showReq.duration {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                        subtitlePanel.hide()
                    }
                }
                return jsonResponse(OkResponse(ok: true))
            } catch {
                return errorResponse("Invalid request body: \(error.localizedDescription)", status: .badRequest)
            }
        }

        // API-06: Hide subtitle
        await server.appendRoute("POST /subtitle/hide") { [self] _ in
            await MainActor.run { subtitlePanel.hide() }
            return jsonResponse(OkResponse(ok: true))
        }

        // API-09: TTS test — synthesize + play + karaoke subtitles (streaming)
        await server.appendRoute("POST /tts/test") { [self] request in
            do {
                let body = try await request.bodyData
                let testReq = try JSONDecoder().decode(TTSTestRequest.self, from: body)
                let text = testReq.text ?? "Claude TTS companion is working. Karaoke subtitles are synced with audio playback."
                let settings = settingsStore.getSettings()
                let voiceName = settings.tts.voice
                let speed = Float(settings.tts.speed)

                // Check memory pressure before synthesis (HARD-02, HARD-03)
                let memoryConstrained = await MainActor.run { self.pipelineCoordinator.shouldUseSubtitleOnly }
                if memoryConstrained {
                    self.logger.warning("TTS test: memory pressure -- subtitle-only mode")
                    await MainActor.run {
                        self.subtitlePanel.show(text: text)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            self.subtitlePanel.hide()
                        }
                    }
                    return HTTPResponse(
                        statusCode: .ok,
                        headers: [.contentType: "application/json"],
                        body: try! JSONEncoder().encode(["status": "subtitle_only", "reason": "memory_pressure"])
                    )
                }

                logger.info("TTS test: streaming synthesis for \(text.count) chars")

                // Batch-then-play: collect all chunks, then play them all at once.
                // Zero GPU work during playback -- eliminates memory bus contention.
                let chunks = await ttsEngine.synthesizeStreaming(
                    text: text,
                    voiceName: voiceName,
                    speed: speed
                )

                self.logger.info("TTS test: all \(chunks.count) chunks synthesized -- starting batch playback")

                await MainActor.run {
                    guard !chunks.isEmpty else {
                        self.logger.warning("TTS test: no chunks produced -- showing subtitle-only fallback")
                        self.subtitlePanel.show(text: text)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            self.subtitlePanel.hide()
                        }
                        return
                    }

                    self.pipelineCoordinator.startBatchPipeline(
                        chunks: chunks,
                        onComplete: {
                            self.logger.info("TTS test batch playback complete")
                            Task { await checkMemoryLifecycleRestart() }
                        }
                    )
                }

                return jsonResponse(OkResponse(ok: true))
            } catch {
                return errorResponse("Invalid request body: \(error.localizedDescription)", status: .badRequest)
            }
        }

        // API-07: Get caption history
        await server.appendRoute("GET /captions") { [self] _ in
            let entries = captionHistory.getAll()
            let response = CaptionsResponse(captions: entries, total: captionHistory.count)
            return jsonResponse(response)
        }

        // API-08: Copy captions to clipboard
        await server.appendRoute("POST /captions/copy") { [self] _ in
            let copied = await MainActor.run { captionHistory.copyToClipboard() }
            return jsonResponse(CopyResponse(ok: true, copied: copied))
        }

        logger.info("HTTP control API starting on localhost:\(Config.httpPort)")
        try await server.run()
    }

    // MARK: - Private Helpers

    /// Build the health response with uptime and RSS (API-01).
    private func healthResponse() async -> HTTPResponse {
        let uptimeSeconds = Int(Date().timeIntervalSince(startTime))
        let rssMB = currentRSSMB()
        let diag = await ttsEngine.memoryDiagnostics()

        let health = HealthResponse(
            status: "ok",
            uptime_seconds: uptimeSeconds,
            rss_mb: rssMB,
            tts_synthesis_count: diag.synthesisCount,
            tts_restart_threshold: TTSEngine.maxSynthesisBeforeRestart,
            mlx_memory_active_mb: diag.mlxActive.map { $0 / (1024 * 1024) },
            mlx_memory_cache_mb: diag.mlxCache.map { $0 / (1024 * 1024) },
            mlx_memory_peak_mb: diag.mlxPeak.map { $0 / (1024 * 1024) },
            subsystems: SubsystemStatus(
                bot: telegramBot?.watching == true ? "watching" : (telegramBot != nil ? "stopped" : "unknown"),
                tts: "ready",
                subtitle: "ready"
            )
        )
        return jsonResponse(health)
    }

    /// Get current process RSS in megabytes via mach_task_basic_info.
    private func currentRSSMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576
    }

    /// Encode any Encodable value to a JSON HTTPResponse.
    private func jsonResponse<T: Encodable>(_ value: T, status: HTTPStatusCode = .ok) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else {
            return HTTPResponse(statusCode: .internalServerError)
        }
        return HTTPResponse(
            statusCode: status,
            headers: [.contentType: "application/json"],
            body: data
        )
    }

    /// Build a JSON error response.
    private func errorResponse(_ message: String, status: HTTPStatusCode) -> HTTPResponse {
        return jsonResponse(ErrorResponse(error: message), status: status)
    }
}
