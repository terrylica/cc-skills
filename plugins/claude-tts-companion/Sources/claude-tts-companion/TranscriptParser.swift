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
