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
    var displayMode: String?
    var subtitleScope: String?
    var bionicSuffixOpacity: Double?
}

/// Partial update struct for TTS settings (all fields optional for PATCH semantics).
public struct TTSSettingsUpdate: Codable, Sendable {
    var enabled: Bool?
    var voice: String?
    var speed: Double?
    var paragraphBudget: Int?
}

/// Request body for POST /subtitle/show.
private struct ShowSubtitleRequest: Codable {
    let text: String
    let duration: Double?
}

/// Request body for POST /tts/speak.
private struct TTSSpeakRequest: Codable {
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
    let subsystems: SubsystemStatus
    let audio_routing_clean: Bool?
    let audio_routing_warnings: [String]?
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
    private let captionHistoryPanel: CaptionHistoryPanel
    private let pipelineCoordinator: TTSPipelineCoordinator
    private let ttsQueue: TTSQueue
    private let startTime: Date
    private var telegramBot: TelegramBot?

    /// Audio routing diagnostic results, set by CompanionApp at startup.
    var audioRoutingClean: Bool = true
    var audioRoutingWarnings: [String] = []

    init(settingsStore: SettingsStore, subtitlePanel: SubtitlePanel, playbackManager: PlaybackManager, ttsEngine: TTSEngine, captionHistory: CaptionHistory, captionHistoryPanel: CaptionHistoryPanel, pipelineCoordinator: TTSPipelineCoordinator, ttsQueue: TTSQueue) {
        self.settingsStore = settingsStore
        self.subtitlePanel = subtitlePanel
        self.playbackManager = playbackManager
        self.ttsEngine = ttsEngine
        self.captionHistory = captionHistory
        self.captionHistoryPanel = captionHistoryPanel
        self.pipelineCoordinator = pipelineCoordinator
        self.ttsQueue = ttsQueue
        self.startTime = Date()
    }

    /// Start the HTTP server on the configured port (blocks until server stops).
    /// Set the TelegramBot reference for health status reporting.
    func setBot(_ bot: TelegramBot) {
        self.telegramBot = bot
    }

    func start() async throws {
        // 300s timeout: user-initiated TTS blocks for synthesis + playback (20-90s+).
        // FlyingFox default is 15s which causes HTTP 500 for any text longer than ~5 words.
        let server = HTTPServer(address: .loopback(port: Config.httpPort), timeout: 300)

        // API-01: Health endpoint
        await server.appendRoute("GET /health") { [self] _ in
            return healthResponse()
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
                    if let v = update.displayMode {
                        s.displayMode = v
                        // Mutual exclusion: bionic/plain disable karaoke, karaoke enables it (D-03)
                        switch DisplayMode.from(string: v) {
                        case .bionic, .plain:
                            s.karaokeEnabled = false
                        case .karaoke:
                            s.karaokeEnabled = true
                        }
                    }
                    if let v = update.subtitleScope { s.subtitleScope = v }
                    if let v = update.bionicSuffixOpacity { s.bionicSuffixOpacity = max(0.1, min(1.0, v)) }
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
                    if let v = update.paragraphBudget { s.paragraphBudget = max(0, v) }
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

        // API-09: TTS speak — synthesize + play + karaoke subtitles (streaming)
        // Primary endpoint for external callers (tts_kokoro.sh, SwiftBar, etc.)
        await server.appendRoute("POST /tts/speak") { [self] request in
            do {
                let body = try await request.bodyData
                let speakReq = try JSONDecoder().decode(TTSSpeakRequest.self, from: body)
                let text = speakReq.text ?? "Claude TTS companion is working. Karaoke subtitles are synced with audio playback."

                // Read priority header: X-TTS-Priority: user-initiated | automated (default)
                let priorityHeader = request.headers[HTTPHeader("X-TTS-Priority")]
                let priority: TTSPriority = (priorityHeader == "user-initiated") ? .userInitiated : .automated

                if priority == .userInitiated {
                    // User-initiated (BTT): preempt everything, await playback completion
                    logger.info("TTS speak: user-initiated priority, \(text.count) chars")
                    await ttsQueue.enqueueAndAwait(text: text)
                    return jsonResponse(OkResponse(ok: true))
                } else {
                    // Automated: enqueue, return immediately with status
                    let result = await ttsQueue.enqueue(text: text, greeting: nil, priority: .automated)
                    switch result {
                    case .queued(let pos):
                        logger.info("TTS speak: queued at position \(pos), \(text.count) chars")
                        return jsonResponse(OkResponse(ok: true))
                    case .rejected(let reason):
                        logger.warning("TTS speak: rejected — \(reason)")
                        return HTTPResponse(
                            statusCode: .serviceUnavailable,
                            headers: [.contentType: "application/json"],
                            body: try! JSONEncoder().encode(["error": reason])
                        )
                    }
                }
            } catch {
                return errorResponse("Invalid request body: \(error.localizedDescription)", status: .badRequest)
            }
        }

        // API-10: TTS stop — cancel in-flight synthesis and stop audio immediately
        await server.appendRoute("POST /tts/stop") { [self] _ in
            logger.info("TTS stop requested via HTTP")
            await ttsQueue.stopAll()
            return jsonResponse(OkResponse(ok: true))
        }

        // API-11: TTS status — queue depth, playing state, pipeline info
        await server.appendRoute("GET /tts/status") { [self] _ in
            let queueStatus = await ttsQueue.status
            let pipelineActive = await MainActor.run { pipelineCoordinator.isBusy }
            let response: [String: Any] = [
                "queueDepth": queueStatus.queueDepth,
                "isPlaying": queueStatus.isPlaying || pipelineActive,
                "userRequestActive": queueStatus.userRequestActive,
                "maxQueueDepth": queueStatus.maxQueueDepth,
                "pipelineActive": pipelineActive,
            ]
            // Manual JSON since [String: Any] isn't Codable
            let json = try! JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
            return HTTPResponse(
                statusCode: .ok,
                headers: [.contentType: "application/json"],
                body: json
            )
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

        // CAPT-04: Show caption history panel
        await server.appendRoute("POST /captions/panel/show") { [self] _ in
            await MainActor.run { captionHistoryPanel.show() }
            return jsonResponse(OkResponse(ok: true))
        }

        // CAPT-04: Hide caption history panel
        await server.appendRoute("POST /captions/panel/hide") { [self] _ in
            await MainActor.run { captionHistoryPanel.hide() }
            return jsonResponse(OkResponse(ok: true))
        }

        logger.info("HTTP control API starting on localhost:\(Config.httpPort)")
        try await server.run()
    }

    // MARK: - Private Helpers

    /// Build the health response with uptime and RSS (API-01).
    private func healthResponse() -> HTTPResponse {
        let uptimeSeconds = Int(Date().timeIntervalSince(startTime))
        let rssMB = currentRSSMB()

        let health = HealthResponse(
            status: audioRoutingClean ? "ok" : "degraded",
            uptime_seconds: uptimeSeconds,
            rss_mb: rssMB,
            subsystems: SubsystemStatus(
                bot: telegramBot?.watching == true ? "watching" : (telegramBot != nil ? "stopped" : "unknown"),
                tts: "ready",
                subtitle: "ready"
            ),
            audio_routing_clean: audioRoutingClean,
            audio_routing_warnings: audioRoutingWarnings.isEmpty ? nil : audioRoutingWarnings
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
