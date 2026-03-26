import Foundation
import Logging

/// A single conversation turn (user prompt + assistant response).
struct ConversationTurn {
    let prompt: String
    let response: String
    let timestamp: Date?
    /// Tool usage summary, e.g. "Bash(3), Read(5), Write(2)"
    let toolSummary: String?
    /// Key tool outputs for additional context
    let toolResults: String?
}

/// Result of a summary generation.
struct SummaryResult {
    /// The narrative text (for both TTS and Telegram display)
    let narrative: String
    /// Extracted prompt summary (single-turn only)
    let promptSummary: String?
    /// TTS-only audio preamble (e.g. "Hi Terry, in cc skills:"). Not for Telegram display.
    let ttsGreeting: String?
}

/// Generates session narratives via MiniMax API for TTS playback.
///
/// Three summary types:
/// - `singleTurnSummary`: "you prompted me X ago to..." for single exchanges
/// - `arcSummary`: chronological full-session narrative with transition words
/// - `tailBrief`: end-weighted narrative (20% context, 80% final turn)
///
/// All methods share the same `MiniMaxClient` and circuit breaker.
/// Empty/short inputs return safe fallbacks without calling the API.
final class SummaryEngine: @unchecked Sendable {

    private let client: MiniMaxClient
    private let logger = Logger(label: "summary-engine")

    init(client: MiniMaxClient = MiniMaxClient()) {
        self.client = client
    }

    // MARK: - Helpers

    /// Format a date into conversational relative time for TTS.
    func formatTimeAgo(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        let seconds = Int(elapsed)
        let minutes = seconds / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if seconds < 5 {
            return "just now"
        }
        if seconds < 60 {
            return "\(seconds) seconds ago"
        }
        if minutes < 60 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }
        // Hours and minutes
        let hourPart = hours == 1 ? "1 hour" : "\(hours) hours"
        if remainingMinutes == 0 { return "\(hourPart) ago" }
        let minPart = remainingMinutes == 1 ? "1 minute" : "\(remainingMinutes) minutes"
        return "\(hourPart) and \(minPart) ago"
    }

    /// Format project directory name for TTS announcement.
    /// ".claude" -> "Dot claude", "my-project" -> "my project"
    func formatProjectName(_ cwd: String?) -> String {
        guard let cwd = cwd else { return "unknown project" }
        let components = cwd.split(separator: "/").map(String.init)
        guard let folderName = components.last, !folderName.isEmpty else {
            return "unknown project"
        }
        if folderName.hasPrefix(".") {
            let name = String(folderName.dropFirst())
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
            return "Dot \(name)"
        }
        return folderName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Single-Turn Summary (SUM-03)

    /// Generate a "you prompted me X ago to..." narrative from a single exchange.
    ///
    /// Parses the model's `|||` delimiter to separate prompt summary from response summary.
    /// On any error (including circuit breaker), returns a safe fallback.
    func singleTurnSummary(
        prompt: String,
        response: String,
        lastActivityTime: Date?,
        cwd: String?
    ) async -> SummaryResult {
        // Strip code-fenced blocks to avoid summarizing quoted content
        let strippedPrompt = prompt.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: "[quoted code block]",
            options: .regularExpression
        )
        let truncatedPrompt = String(strippedPrompt.prefix(2000))
        let truncatedResponse = String(response.prefix(10000))

        // Compute deterministic intro components
        let timeAgo: String
        if let activityTime = lastActivityTime {
            timeAgo = formatTimeAgo(activityTime)
        } else {
            timeAgo = "a while ago"
        }

        let projectName = formatProjectName(cwd)
        let ttsGreeting = "Hi Terry, you were working in \(projectName)."

        let userPrompt = """
            Generate a two-part spoken summary for text-to-speech. Do NOT include any greeting or intro \
            -- that is added separately.

            Part 1 -- PROMPT SUMMARY (under 30 words):
            Summarize ONLY the "Most recent request" below -- ignore any earlier conversation history. \
            This will be preceded by "you prompted me to", so start with an infinitive verb phrase \
            (e.g. "get precise timestamps", "lower the reading speed", "add forensic logging").

            Part 2 -- RESPONSE SUMMARY (under 50 words):
            Summarize what was accomplished. Focus on outcomes and key actions taken.

            Output format -- produce EXACTLY this (no extra text):
            [prompt summary] ||| [response summary]

            The ||| delimiter is mandatory. It separates the two parts.

            Rules:
            - Never mention "Claude Code", "Claude", "Anthropic", or "the assistant".
            - Use natural spoken language. No code, file paths, markdown, or technical symbols.
            - Do NOT start with "You asked" or "The user" -- just describe the request directly.

            Most recent request:
            \"""
            \(truncatedPrompt)
            \"""

            Final response:
            \"""
            \(truncatedResponse)
            \"""

            Summary:
            """

        let systemPrompt = "You convert text to natural spoken language. ONLY process the text explicitly provided by the user between triple-quote delimiters."

        do {
            let result = try await client.query(
                prompt: userPrompt,
                systemPrompt: systemPrompt,
                maxTokens: 2048
            )

            logger.info(
                "Single-turn summary: model=\(Config.miniMaxModel), duration=\(result.durationMs)ms, text=\(result.text.count) chars"
            )

            // Parse the ||| delimiter
            let parts = result.text.components(separatedBy: "|||").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if parts.count >= 2 {
                let promptSummary = parts[0]
                let responseSummary = parts[1...].joined(separator: " ")
                let narrative = "You prompted me \(timeAgo) to \(promptSummary). Here's my response to you in summary: \(responseSummary)"
                return SummaryResult(
                    narrative: narrative,
                    promptSummary: promptSummary,
                    ttsGreeting: ttsGreeting
                )
            }

            // Fallback if model didn't use the delimiter
            let narrative = "You prompted me \(timeAgo) to \(result.text)"
            return SummaryResult(
                narrative: narrative,
                promptSummary: nil,
                ttsGreeting: ttsGreeting
            )

        } catch {
            logger.error("Single-turn summary failed: \(error)")
            return SummaryResult(
                narrative: "Session completed.",
                promptSummary: nil,
                ttsGreeting: nil
            )
        }
    }
}
