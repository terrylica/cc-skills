import Foundation
import Logging

/// Represents a single entry from a Claude Code JSONL transcript.
///
/// Claude Code writes session transcripts as newline-delimited JSON where each
/// line has a `type` field indicating what kind of event occurred. This parser
/// extracts the fields needed for Telegram bot notifications and session summaries.
enum TranscriptEntry: Sendable {
    /// A user prompt (type: "human")
    case prompt(text: String, timestamp: Date?)
    /// An assistant response (type: "assistant")
    case response(text: String, timestamp: Date?)
    /// A tool use event (type: "tool_use")
    case toolUse(name: String, timestamp: Date?)
    /// A tool result (type: "tool_result")
    case toolResult(content: String, timestamp: Date?)
    /// An unknown or unsupported entry type
    case unknown(type: String)
}

/// Summary statistics extracted from a parsed JSONL transcript.
struct TranscriptSummary: Sendable {
    /// Total number of user prompts
    let promptCount: Int
    /// Total number of assistant responses
    let responseCount: Int
    /// Total number of tool calls made
    let toolUseCount: Int
    /// Text of the first user prompt (if any)
    let firstPrompt: String?
    /// Text of the last assistant response (if any)
    let lastResponse: String?
    /// All unique tool names used in the session
    let toolNames: Set<String>
}

/// Parses Claude Code JSONL transcript files into typed entries.
///
/// JSONL transcripts are written by Claude Code at:
///   `~/.claude/projects/{hash}/sessions/{id}/transcript.jsonl`
///
/// Each line is a JSON object with at minimum a `type` field. The parser
/// handles malformed lines gracefully by logging and skipping them (BOT-07).
enum TranscriptParser {

    private static let logger = Logger(label: "transcript-parser")

    // MARK: - Noise Filtering

    /// System-injected content patterns -- never real user prompts.
    /// Ported verbatim from legacy TypeScript transcript-parser.ts.
    static let noisePatterns: [String] = [
        "<command-name>",
        "<local-command",
        "<local-command-caveat>",
        "<task-notification>",
        "<system-reminder>",
        "<bash-stdout>",
        "<bash-stderr>",
        "<bash-input>",
        "<summary>",
        "<task-id>",
        "<status>",
        "<output-file>",
        "<teammate-message",
        "This session is being continued from a previous conversation",
        "Stop hook feedback",
        "fd out from online",
        "Implement the following plan",
        "Tool loaded",
        "[Request interrupted by user",
    ]

    /// Regex noise patterns (statusline pastes, interrupted requests).
    private static let noiseRegexPatterns: [String] = [
        "M:\\d+ D:\\d+ S:\\d+",        // statusline paste (e.g. "M:4 D:0 S:0 U:6")
        "^\\[Request interrupted",      // interrupted requests (bracket form)
    ]

    /// Check if content is system-injected noise (not a real user prompt).
    static func isSystemNoise(_ content: String) -> Bool {
        for pattern in noisePatterns {
            if content.contains(pattern) { return true }
        }
        for regexPattern in noiseRegexPatterns {
            if let regex = try? NSRegularExpression(pattern: regexPattern),
               regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
                return true
            }
        }
        return false
    }

    /// Check if a prompt is a real user prompt (non-trivial, non-noise).
    static func isRealPrompt(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 10 && !isSystemNoise(text)
    }

    /// Strip skill-injected expansion content appended after the user's real prompt.
    /// Skill expansions (e.g. /ru encourage) append instructions after \n\n,
    /// typically starting with bold uppercase, markdown headers, or block formatting.
    /// Ported from legacy TypeScript transcript-parser.ts lines 123-131.
    static func stripSkillExpansion(_ text: String) -> String {
        guard let range = text.range(of: "\n\n") else { return text }
        let afterBreak = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        let pattern = "^(\\*\\*[A-Z]|#{1,4}\\s|---\\s*\\n|>\\s|-\\s\\[|TRIGGERS\\b)"
        if afterBreak.range(of: pattern, options: .regularExpression) != nil {
            return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// Get the last real user prompt from a list of prompt strings.
    /// Walks backwards to find the first prompt where isRealPrompt is true.
    /// Truncates to 1000 chars with "..." suffix if longer.
    static func getLastUserPrompt(from prompts: [String]) -> String {
        for prompt in prompts.reversed() {
            if isRealPrompt(prompt) {
                if prompt.count > 1000 {
                    return String(prompt.prefix(1000)) + "..."
                }
                return prompt
            }
        }
        return "(no prompts)"
    }

    // MARK: - Turn Extraction

    /// Convert transcript entries into conversation turns for session notifications.
    ///
    /// Matches legacy TypeScript `extractSessionSummary` turn-building logic:
    /// - Filters noise entries and short prompts
    /// - Strips skill expansions from prompts
    /// - Finds the LONGEST assistant response per turn (not the first)
    /// - Aggregates tool counts as "Edit x3, Bash x2" format
    /// - Collects substantial tool results (truncated, capped)
    static func entriesToTurns(_ entries: [TranscriptEntry]) -> [ConversationTurn] {
        var turns: [ConversationTurn] = []
        var i = 0

        while i < entries.count {
            // Find next real user prompt
            guard case .prompt(let promptText, let promptTs) = entries[i] else {
                i += 1
                continue
            }

            // Filter noise and trivial prompts
            if isSystemNoise(promptText) || promptText.trimmingCharacters(in: .whitespacesAndNewlines).count <= 10 {
                i += 1
                continue
            }

            // Strip skill expansion from prompt
            let cleanPrompt = stripSkillExpansion(promptText)

            // Scan forward for responses, tools until next real prompt
            var bestResponse = ""
            var toolCounts: [String: Int] = [:]
            var collectedToolResults: [String] = []
            var totalToolResultChars = 0
            i += 1

            while i < entries.count {
                switch entries[i] {
                case .prompt(let nextText, _):
                    // Check if this is a real prompt (starts new turn) or noise (skip)
                    if !isSystemNoise(nextText) && nextText.trimmingCharacters(in: .whitespacesAndNewlines).count > 10 {
                        // Real prompt -- end of current turn, don't advance i
                        break
                    }
                    // Noise prompt -- skip it
                    i += 1
                    continue
                case .response(let text, _):
                    // Keep the LONGEST response (not the first)
                    if text.count > bestResponse.count {
                        bestResponse = text
                    }
                    i += 1
                    continue
                case .toolUse(let name, _):
                    toolCounts[name, default: 0] += 1
                    i += 1
                    continue
                case .toolResult(let content, _):
                    // Capture substantial tool results (content > 50 chars), truncated to 300 each
                    if content.count > 50 && totalToolResultChars < 3000 {
                        let truncated = String(content.prefix(300))
                        collectedToolResults.append(truncated)
                        totalToolResultChars += truncated.count
                    }
                    i += 1
                    continue
                case .unknown:
                    i += 1
                    continue
                }
                // If we hit the break above (real prompt), stop scanning
                break
            }

            // Skip empty turns (no response AND no tools)
            if bestResponse.isEmpty && toolCounts.isEmpty {
                continue
            }

            // Format tool summary as "Edit x3, Bash x2, Read x5"
            let toolSummary: String? = toolCounts.isEmpty ? nil : toolCounts
                .sorted(by: { $0.key < $1.key })
                .map { name, count in count > 1 ? "\(name) x\(count)" : name }
                .joined(separator: ", ")

            let toolResultStr: String? = collectedToolResults.isEmpty ? nil :
                collectedToolResults.joined(separator: "\n---\n")

            turns.append(ConversationTurn(
                prompt: cleanPrompt,
                response: bestResponse,
                timestamp: promptTs,
                toolSummary: toolSummary,
                toolResults: toolResultStr
            ))
        }

        return turns
    }

    /// Parse a JSONL transcript file at the given path.
    ///
    /// - Parameter path: Absolute path to the .jsonl file
    /// - Returns: Array of parsed entries (malformed lines are skipped)
    static func parse(filePath path: String) -> [TranscriptEntry] {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            logger.warning("Could not read transcript file: \(path)")
            return []
        }
        return parse(content: content)
    }

    /// Parse JSONL content from a string.
    ///
    /// - Parameter content: Raw JSONL string (newline-delimited JSON objects)
    /// - Returns: Array of parsed entries (malformed lines are skipped)
    static func parse(content: String) -> [TranscriptEntry] {
        var entries: [TranscriptEntry] = []
        let lines = content.components(separatedBy: .newlines)

        for (lineNumber, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let data = trimmed.data(using: .utf8) else {
                logger.debug("Line \(lineNumber + 1): not valid UTF-8, skipping")
                continue
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    logger.debug("Line \(lineNumber + 1): not a JSON object, skipping")
                    continue
                }

                let entry = parseEntry(json: json)
                entries.append(entry)
            } catch {
                logger.debug("Line \(lineNumber + 1): JSON parse error: \(error.localizedDescription)")
            }
        }

        return entries
    }

    /// Generate a summary from parsed transcript entries.
    ///
    /// Counts prompts, responses, and tool uses, and captures the first prompt
    /// and last response for notification display (BOT-07).
    static func summarize(entries: [TranscriptEntry]) -> TranscriptSummary {
        var promptCount = 0
        var responseCount = 0
        var toolUseCount = 0
        var firstPrompt: String?
        var lastResponse: String?
        var toolNames: Set<String> = []

        for entry in entries {
            switch entry {
            case .prompt(let text, _):
                promptCount += 1
                if firstPrompt == nil {
                    firstPrompt = text
                }
            case .response(let text, _):
                responseCount += 1
                lastResponse = text
            case .toolUse(let name, _):
                toolUseCount += 1
                toolNames.insert(name)
            case .toolResult:
                break  // counted via toolUse
            case .unknown:
                break
            }
        }

        return TranscriptSummary(
            promptCount: promptCount,
            responseCount: responseCount,
            toolUseCount: toolUseCount,
            firstPrompt: firstPrompt,
            lastResponse: lastResponse,
            toolNames: toolNames
        )
    }

    // MARK: - Private

    /// Parse a single JSON object into a TranscriptEntry.
    private static func parseEntry(json: [String: Any]) -> TranscriptEntry {
        let type = json["type"] as? String ?? "unknown"
        let timestamp = parseTimestamp(json["timestamp"])

        switch type {
        case "human":
            let text = extractText(from: json)
            return .prompt(text: text, timestamp: timestamp)

        case "assistant":
            let text = extractText(from: json)
            return .response(text: text, timestamp: timestamp)

        case "tool_use":
            let name = json["name"] as? String ?? "unknown_tool"
            return .toolUse(name: name, timestamp: timestamp)

        case "tool_result":
            let content = extractText(from: json)
            return .toolResult(content: content, timestamp: timestamp)

        default:
            return .unknown(type: type)
        }
    }

    /// Extract text content from a transcript JSON entry.
    ///
    /// Claude Code transcript entries store text in various formats:
    /// - `message.content` as a string
    /// - `message.content` as an array of content blocks with `text` fields
    /// - `content` directly as a string
    private static func extractText(from json: [String: Any]) -> String {
        // Try message.content path first
        if let message = json["message"] as? [String: Any] {
            if let content = message["content"] as? String {
                return content
            }
            if let blocks = message["content"] as? [[String: Any]] {
                let texts = blocks.compactMap { block -> String? in
                    if block["type"] as? String == "text" {
                        return block["text"] as? String
                    }
                    return nil
                }
                if !texts.isEmpty {
                    return texts.joined(separator: "\n")
                }
            }
        }

        // Try direct content field
        if let content = json["content"] as? String {
            return content
        }

        // Try content as array of blocks
        if let blocks = json["content"] as? [[String: Any]] {
            let texts = blocks.compactMap { block -> String? in
                if block["type"] as? String == "text" {
                    return block["text"] as? String
                }
                return nil
            }
            return texts.joined(separator: "\n")
        }

        return ""
    }

    /// Parse a timestamp from various possible formats.
    private static func parseTimestamp(_ value: Any?) -> Date? {
        guard let value = value else { return nil }

        if let isoString = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: isoString)
                ?? ISO8601DateFormatter().date(from: isoString)
        }

        if let epoch = value as? Double {
            return Date(timeIntervalSince1970: epoch)
        }

        if let epoch = value as? Int {
            return Date(timeIntervalSince1970: Double(epoch))
        }

        return nil
    }
}
