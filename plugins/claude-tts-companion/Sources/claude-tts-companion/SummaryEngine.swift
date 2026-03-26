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

    // MARK: - Arc Summary (SUM-01)

    /// Summarize the full session arc from all conversation turns.
    ///
    /// Produces a chronological narrative with transition words (First, Then, Next, Finally).
    /// Falls back to `singleTurnSummary` if only 1-2 turns (MiniMax hallucinates on short arcs).
    func arcSummary(turns: [ConversationTurn], cwd: String?) async -> SummaryResult {
        // Empty turns -- safe fallback without API call
        if turns.isEmpty {
            return SummaryResult(narrative: "Session completed.", promptSummary: nil, ttsGreeting: nil)
        }

        // Single or two turns -- delegate to single-turn (MiniMax hallucinates in arc mode)
        if turns.count <= 2 {
            let lastTurn = turns[turns.count - 1]
            return await singleTurnSummary(
                prompt: lastTurn.prompt,
                response: lastTurn.response,
                lastActivityTime: lastTurn.timestamp,
                cwd: cwd
            )
        }

        let projectName = formatProjectName(cwd)
        let ttsGreeting = "Hi Terry, in this session in \(projectName):"

        // Build turn transcript with per-turn truncation
        let maxPromptChars = 2000
        let maxResponseChars = 4000
        let maxToolResultChars = 1500
        let maxTranscriptChars = 102400

        var turnTexts: [String] = []
        for (i, turn) in turns.enumerated() {
            let p = turn.prompt.count > maxPromptChars
                ? String(turn.prompt.prefix(maxPromptChars)) + " [truncated]"
                : turn.prompt
            let r = turn.response.count > maxResponseChars
                ? String(turn.response.prefix(maxResponseChars)) + " [truncated]"
                : (turn.response.isEmpty ? "[no text response]" : turn.response)
            let tools = turn.toolSummary.map { "\nTools used: \($0)" } ?? ""
            let results: String
            if let tr = turn.toolResults, !tr.isEmpty {
                let truncated = tr.count > maxToolResultChars
                    ? String(tr.prefix(maxToolResultChars)) + " [truncated]"
                    : tr
                results = "\nKey tool outputs:\n\(truncated)"
            } else {
                results = ""
            }
            turnTexts.append("=== Turn \(i + 1) ===\nUser request:\n\(p)\n\nOutcome:\n\(r)\(tools)\(results)")
        }

        // Pack turns within transcript budget
        var transcript = ""
        for text in turnTexts {
            if transcript.count + text.count > maxTranscriptChars {
                transcript += "\n\n[remaining turns omitted for length]"
                break
            }
            transcript += (transcript.isEmpty ? "" : "\n\n") + text
        }

        let userPrompt = """
            Summarize this entire coding session as a spoken narrative for text-to-speech. \
            The session had \(turns.count) turns.

            Rules:
            - Do NOT include any greeting or project name -- those are added separately
            - Start directly with the first chronological step using transition words: \
            "First,", "Then,", "Next,", "After that,", "Finally,"
            - Cover EVERY turn -- do not skip or merge turns. Each user request should appear in the narrative
            - IMPORTANT: Each step MUST be its own paragraph, separated by exactly one newline. \
            Never combine multiple steps into one paragraph
            - Focus on OUTCOMES and FINAL ACTIONS -- what was actually done, not what was considered
            - Keep it under 200 words total
            - No code, file paths, markdown, or technical symbols
            - Never mention "Claude", "the assistant", or "AI"
            - Use natural spoken language
            - Text marked [truncated] means the full response was too long to include here \
            -- it was NOT cut off or incomplete

            Session transcript:
            \"""
            \(transcript)
            \"""

            Narrative:
            """

        let systemPrompt = "You convert coding session transcripts into natural spoken summaries. ONLY process text between triple-quote delimiters."

        do {
            let result = try await client.query(
                prompt: userPrompt,
                systemPrompt: systemPrompt,
                maxTokens: 4096
            )

            logger.info(
                "Arc summary: model=\(Config.miniMaxModel), turns=\(turns.count), duration=\(result.durationMs)ms, text=\(result.text.count) chars"
            )

            // Post-process: strip any "Hi Terry..." prefix the model may include
            var narrative = result.text.replacingOccurrences(
                of: "^Hi Terry[^:]*:\\s*",
                with: "",
                options: .regularExpression
            )
            // Normalize paragraphs: collapse double newlines to single
            narrative = narrative.replacingOccurrences(
                of: "\\n{2,}",
                with: "\n",
                options: .regularExpression
            )
            // Force newline before transition words
            narrative = narrative.replacingOccurrences(
                of: "(?<!\\n)((?:Then|Next|After that|Finally|Last),)",
                with: "\n$1",
                options: .regularExpression
            )

            return SummaryResult(
                narrative: narrative,
                promptSummary: nil,
                ttsGreeting: ttsGreeting
            )

        } catch {
            logger.error("Arc summary failed: \(error)")
            return SummaryResult(
                narrative: "Session completed.",
                promptSummary: nil,
                ttsGreeting: nil
            )
        }
    }

    // MARK: - Tail Brief (SUM-02)

    /// End-weighted session narrative: ~20% context, ~80% final turn detail.
    ///
    /// Compresses earlier turns into brief context, then expands the final turn
    /// with thorough detail on what was asked, done, and how it turned out.
    func tailBrief(turns: [ConversationTurn], cwd: String?) async -> SummaryResult {
        // Empty turns -- safe fallback without API call
        if turns.isEmpty {
            return SummaryResult(narrative: "", promptSummary: nil, ttsGreeting: nil)
        }

        // Extract last turn with generous limits
        let lastTurn = turns[turns.count - 1]
        let lastPrompt = lastTurn.prompt.count > 3000
            ? String(lastTurn.prompt.prefix(3000)) + " [truncated]"
            : lastTurn.prompt
        let lastResponse = lastTurn.response.count > 8000
            ? String(lastTurn.response.prefix(8000)) + " [truncated]"
            : lastTurn.response

        // Build compressed prior context (1 line per turn)
        var priorContext = ""
        if turns.count > 1 {
            let priorTurns = turns.dropLast()
            var lines: [String] = []
            for (i, turn) in priorTurns.enumerated() {
                let p = String(turn.prompt.prefix(200)).replacingOccurrences(of: "\n", with: " ")
                let pSuffix = turn.prompt.count > 200 ? "..." : ""
                let r = String(turn.response.prefix(300)).replacingOccurrences(of: "\n", with: " ")
                let rSuffix = turn.response.count > 300 ? "..." : ""
                lines.append("Turn \(i + 1): User asked: \(p)\(pSuffix) -> Outcome: \(r)\(rSuffix)")
            }

            // Cap total prior context at 4000 chars
            var ctx = ""
            for (idx, line) in lines.enumerated() {
                if ctx.count + line.count > 4000 {
                    let remaining = lines.count - idx
                    ctx += "\n[\(remaining) earlier turns omitted]"
                    break
                }
                ctx += (ctx.isEmpty ? "" : "\n") + line
            }
            priorContext = "\nPrior turns (compress into context):\n\"\"\"\n\(ctx)\n\"\"\"\n"
        }

        let userPrompt = """
            Narrate this coding session for text-to-speech.

            STRUCTURE:
            - CONTEXT (1-2 sentences): Quick catch-up on what the session was about before the final turn.
            - LATEST (the bulk): What the user wanted in their final request, what specific changes were \
            made, and how the outcome turned out. Be thorough and specific.
            \(priorContext)
            Final turn -- USER ASKED:
            \"""
            \(lastPrompt)
            \"""

            Final turn -- WHAT WAS DONE:
            \"""
            \(lastResponse)
            \"""

            Rules: No greeting/project name (added separately). No code/paths/markdown. \
            Never say "Claude"/"AI"/"assistant". Past tense. Under 200 words. \
            ~20% context, ~80% final turn detail.

            Narrative:
            """

        let systemPrompt = "You narrate coding sessions for spoken audio. Natural storytelling voice -- not robotic, not corporate. Describe what happened like you're telling a colleague."

        do {
            let result = try await client.query(
                prompt: userPrompt,
                systemPrompt: systemPrompt,
                maxTokens: 2048
            )

            logger.info(
                "Tail brief: model=\(Config.miniMaxModel), turns=\(turns.count), duration=\(result.durationMs)ms, text=\(result.text.count) chars"
            )

            // Strip any greeting the model may have included
            let narrative = result.text.replacingOccurrences(
                of: "^Hi Terry[^:]*:\\s*",
                with: "",
                options: .regularExpression
            )

            return SummaryResult(
                narrative: narrative,
                promptSummary: nil,
                ttsGreeting: nil
            )

        } catch {
            logger.error("Tail brief failed: \(error)")
            return SummaryResult(
                narrative: "",
                promptSummary: nil,
                ttsGreeting: nil
            )
        }
    }
}
