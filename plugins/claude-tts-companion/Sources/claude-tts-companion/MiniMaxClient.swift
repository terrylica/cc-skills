import Foundation
import Logging

/// Result of a MiniMax API query.
struct MiniMaxResult {
    /// The text content extracted from the response
    let text: String
    /// Time taken for the API call in milliseconds
    let durationMs: Int
    /// Number of output tokens reported by the API (nil if not present)
    let outputTokens: Int?
}

/// URLSession-based client for the MiniMax API (Anthropic-compatible endpoint).
///
/// Integrates with `CircuitBreaker` to stop sending requests after repeated failures.
/// Uses async/await URLSession API -- no completion handlers.
final class MiniMaxClient: @unchecked Sendable {

    private let logger = Logger(label: "minimax-client")
    private let session = URLSession.shared

    /// Circuit breaker for failure tracking (public for status queries)
    let circuitBreaker: CircuitBreaker

    init(circuitBreaker: CircuitBreaker = CircuitBreaker()) {
        self.circuitBreaker = circuitBreaker
    }

    /// Query the MiniMax API with a prompt and system prompt.
    ///
    /// - Parameters:
    ///   - prompt: The user message content
    ///   - systemPrompt: The system-level instruction
    ///   - maxTokens: Maximum tokens in the response (default from Config)
    /// - Returns: A `MiniMaxResult` with the extracted text and metadata
    /// - Throws: `SummaryError` for all failure cases
    func query(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int = Config.summaryMaxTokens
    ) async throws -> MiniMaxResult {
        // Check circuit breaker first
        if circuitBreaker.isOpen {
            throw SummaryError.circuitBreakerOpen
        }

        // Check API key
        guard let apiKey = Config.miniMaxAPIKey else {
            throw SummaryError.missingAPIKey
        }

        // Build request
        let urlString = "\(Config.miniMaxBaseURL)/v1/messages"
        guard let url = URL(string: urlString) else {
            throw SummaryError.decodingError("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2024-10-22", forHTTPHeaderField: "anthropic-version")

        // Encode body
        let body: [String: Any] = [
            "model": Config.miniMaxModel,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw SummaryError.decodingError("Failed to encode request body: \(error)")
        }

        // Make API call
        let startTime = CFAbsoluteTimeGetCurrent()
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            circuitBreaker.recordFailure()
            throw SummaryError.apiError(statusCode: 0, body: "Network error: \(error.localizedDescription)")
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let durationMs = Int(elapsed * 1000)

        // Check HTTP status
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let bodyStr = String(data: data, encoding: .utf8) ?? "(unreadable)"
            circuitBreaker.recordFailure()
            throw SummaryError.apiError(statusCode: httpResponse.statusCode, body: bodyStr)
        }

        // Parse response JSON
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            circuitBreaker.recordFailure()
            throw SummaryError.decodingError("Invalid JSON: \(error)")
        }

        guard let dict = json as? [String: Any] else {
            circuitBreaker.recordFailure()
            throw SummaryError.decodingError("Response is not a JSON object")
        }

        // Extract text from content blocks, filtering to type == "text"
        guard let content = dict["content"] as? [[String: Any]] else {
            circuitBreaker.recordFailure()
            throw SummaryError.decodingError("Missing 'content' array in response")
        }

        let textBlocks = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }

        let text = textBlocks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            circuitBreaker.recordFailure()
            throw SummaryError.emptyResponse
        }

        // Extract output tokens if available
        let outputTokens = (dict["usage"] as? [String: Any])?["output_tokens"] as? Int

        // Success -- reset circuit breaker
        circuitBreaker.recordSuccess()

        logger.info(
            "MiniMax query complete: model=\(Config.miniMaxModel), duration=\(durationMs)ms, tokens=\(outputTokens ?? 0), text=\(text.count) chars"
        )

        return MiniMaxResult(text: text, durationMs: durationMs, outputTokens: outputTokens)
    }
}
