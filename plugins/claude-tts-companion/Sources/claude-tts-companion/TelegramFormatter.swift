import Foundation

/// Pure-function utilities for Telegram HTML formatting and fence-aware message chunking.
/// Ported from the TypeScript format.ts and fences.ts in claude-telegram-sync.
enum TelegramFormatter {

    /// Maximum message length for Telegram Bot API.
    static let telegramMaxLength = 4096

    // MARK: - HTML Escaping

    /// Escape HTML special characters for Telegram's HTML parse mode.
    static func escapeHtml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Fence Span Parsing

    /// A span of text enclosed in a fenced code block (``` or ~~~).
    struct FenceSpan {
        let start: Int      // character offset of opening fence line
        let end: Int        // character offset past the closing fence line (or end of text)
        let openLine: String
        let marker: String  // the fence characters (e.g. "```" or "~~~")
        let indent: String  // leading whitespace of the opening fence
    }

    /// Parse all fenced code block spans in the given text.
    /// Walks line-by-line matching CommonMark fence patterns: up to 3 spaces indent, then 3+ backticks or tildes.
    static func parseFenceSpans(_ text: String) -> [FenceSpan] {
        let chars = Array(text)
        var spans: [FenceSpan] = []
        var lineStart = 0
        var openFence: (start: Int, line: String, marker: String, indent: String, markerLen: Int)?

        func processLine(_ lineChars: ArraySlice<Character>) {
            let line = String(lineChars)

            // Try to match fence pattern: /^( {0,3})(`{3,}|~{3,})(.*)$/
            var idx = lineChars.startIndex
            var indentCount = 0
            while idx < lineChars.endIndex && lineChars[idx] == " " && indentCount < 3 {
                idx = lineChars.index(after: idx)
                indentCount += 1
            }
            let indent = String(repeating: " ", count: indentCount)

            guard idx < lineChars.endIndex else {
                lineStart += lineChars.count + 1 // +1 for newline
                return
            }

            let fenceChar = lineChars[idx]
            guard fenceChar == "`" || fenceChar == "~" else {
                lineStart += lineChars.count + 1
                return
            }

            var markerLen = 0
            let markerStart = idx
            while idx < lineChars.endIndex && lineChars[idx] == fenceChar {
                idx = lineChars.index(after: idx)
                markerLen += 1
            }

            guard markerLen >= 3 else {
                lineStart += lineChars.count + 1
                return
            }

            let marker = String(lineChars[markerStart..<lineChars.index(markerStart, offsetBy: markerLen)])

            if let open = openFence {
                // Check if this is a closing fence: same character, at least as many, no info string
                let restAfterMarker = String(lineChars[idx...]).trimmingCharacters(in: .whitespaces)
                if fenceChar == open.marker.first! && markerLen >= open.markerLen && restAfterMarker.isEmpty {
                    let endOffset = lineStart + lineChars.count + 1
                    spans.append(FenceSpan(
                        start: open.start,
                        end: min(endOffset, chars.count),
                        openLine: open.line,
                        marker: open.marker,
                        indent: open.indent
                    ))
                    openFence = nil
                }
            } else {
                // Opening fence -- backtick fences must not have backticks in the info string
                if fenceChar == "`" {
                    let rest = String(lineChars[idx...])
                    if rest.contains("`") {
                        lineStart += lineChars.count + 1
                        return
                    }
                }
                openFence = (start: lineStart, line: line, marker: marker, indent: indent, markerLen: markerLen)
            }

            lineStart += lineChars.count + 1
        }

        // Split into lines and process
        var currentLineStart = chars.startIndex
        lineStart = 0
        for i in chars.indices {
            if chars[i] == "\n" {
                processLine(chars[currentLineStart..<i])
                currentLineStart = chars.index(after: i)
            }
        }
        // Process last line (no trailing newline)
        if currentLineStart <= chars.endIndex {
            // Reset lineStart for the final line -- it was already set by the loop
            let finalLine = chars[currentLineStart..<chars.endIndex]
            if !finalLine.isEmpty {
                processLine(finalLine)
            }
        }

        // If there's an unclosed fence, emit a span to end of text
        if let open = openFence {
            spans.append(FenceSpan(
                start: open.start,
                end: chars.count,
                openLine: open.line,
                marker: open.marker,
                indent: open.indent
            ))
        }

        return spans
    }

    /// Find the fence span containing the given character index, if any.
    static func findFenceSpanAt(_ spans: [FenceSpan], index: Int) -> FenceSpan? {
        spans.first { index >= $0.start && index < $0.end }
    }

    /// Check whether a break at the given character index is safe (not inside a fenced code block).
    static func isSafeFenceBreak(_ spans: [FenceSpan], index: Int) -> Bool {
        findFenceSpanAt(spans, index: index) == nil
    }

    // MARK: - Fence-Aware Chunking

    /// Split text into chunks that fit within Telegram's message limit, respecting fenced code blocks.
    /// Two-phase approach: (1) split on paragraph boundaries outside fences, (2) pack into chunks.
    static func chunkTelegramHtml(_ text: String, limit: Int = telegramMaxLength) -> [String] {
        guard text.count > limit else { return [text] }

        let spans = parseFenceSpans(text)

        // Phase 1: Split into paragraphs on blank-line boundaries outside fences
        let paragraphs = splitIntoParagraphs(text, spans: spans)

        // Phase 2: Pack paragraphs into chunks
        var chunks: [String] = []
        var current = ""

        for paragraph in paragraphs {
            if paragraph.count > limit {
                // Flush current chunk if non-empty
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                // Split oversized paragraph
                let subChunks = splitOversizedParagraph(paragraph, limit: limit, spans: spans)
                chunks.append(contentsOf: subChunks)
            } else if current.count + paragraph.count + (current.isEmpty ? 0 : 2) > limit {
                // Would exceed limit -- start new chunk
                if !current.isEmpty {
                    chunks.append(current)
                }
                current = paragraph
            } else {
                if current.isEmpty {
                    current = paragraph
                } else {
                    current += "\n\n" + paragraph
                }
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks.isEmpty ? [text] : chunks
    }

    /// Split text into paragraphs on double-newline boundaries that are outside fenced code blocks.
    private static func splitIntoParagraphs(_ text: String, spans: [FenceSpan]) -> [String] {
        let chars = Array(text)
        var paragraphs: [String] = []
        var paragraphStart = 0

        var i = 0
        while i < chars.count {
            // Look for \n followed by optional \t then \n+ (paragraph break)
            if chars[i] == "\n" && i + 1 < chars.count {
                var j = i + 1
                // Skip optional tab
                if j < chars.count && chars[j] == "\t" { j += 1 }
                if j < chars.count && chars[j] == "\n" {
                    // Found a paragraph boundary -- check if it's outside a fence
                    if isSafeFenceBreak(spans, index: i) {
                        // Skip all consecutive newlines
                        while j < chars.count && (chars[j] == "\n" || chars[j] == "\t" || chars[j] == " ") {
                            j += 1
                        }
                        let para = String(chars[paragraphStart..<i]).trimmingCharacters(in: .newlines)
                        if !para.isEmpty {
                            paragraphs.append(para)
                        }
                        paragraphStart = j
                        i = j
                        continue
                    }
                }
            }
            i += 1
        }

        // Remaining text
        if paragraphStart < chars.count {
            let para = String(chars[paragraphStart...]).trimmingCharacters(in: .newlines)
            if !para.isEmpty {
                paragraphs.append(para)
            }
        }

        return paragraphs
    }

    /// Split an oversized paragraph into chunks, respecting fence boundaries.
    private static func splitOversizedParagraph(_ text: String, limit: Int, spans: [FenceSpan]) -> [String] {
        var chunks: [String] = []
        var remaining = text

        while remaining.count > limit {
            let windowEnd = remaining.index(remaining.startIndex, offsetBy: limit)
            let window = String(remaining[..<windowEnd])

            let breakIdx = pickSafeBreakIndex(window, spans: parseFenceSpans(remaining))

            if breakIdx > 0 {
                let splitPoint = remaining.index(remaining.startIndex, offsetBy: breakIdx)
                let chunk = String(remaining[..<splitPoint]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty {
                    chunks.append(chunk)
                }
                remaining = String(remaining[splitPoint...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                // No safe break -- force split at limit
                let chunk = String(remaining[..<windowEnd])
                chunks.append(chunk)
                remaining = String(remaining[windowEnd...])
            }
        }

        if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(remaining.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return chunks
    }

    /// Pick the best break index within a window, preferring newline > whitespace, outside fenced blocks.
    static func pickSafeBreakIndex(_ window: String, spans: [FenceSpan]) -> Int {
        let chars = Array(window)
        var bestNewline = -1
        var bestSpace = -1

        // Scan backwards from the end for safe break points
        var i = chars.count - 1
        while i > 0 {
            if isSafeFenceBreak(spans, index: i) {
                if chars[i] == "\n" && bestNewline < 0 {
                    bestNewline = i
                    break // newline is the best option
                }
                if (chars[i] == " " || chars[i] == "\t") && bestSpace < 0 {
                    bestSpace = i
                }
            }
            i -= 1
        }

        if bestNewline > 0 { return bestNewline }
        if bestSpace > 0 { return bestSpace }
        return 0
    }

    // MARK: - Markdown to HTML Conversion

    /// Convert a subset of Markdown to Telegram HTML.
    /// Handles: code blocks (```), inline code (`), bold (**), italic (*), links [text](url).
    /// Code blocks are processed first to avoid inline pattern interference.
    static func markdownToTelegramHtml(_ markdown: String) -> String {
        var result = ""
        let chars = Array(markdown)
        var i = 0

        while i < chars.count {
            // Check for fenced code blocks: ```
            if i + 2 < chars.count && chars[i] == "`" && chars[i+1] == "`" && chars[i+2] == "`" {
                // Find the info string (language) on the same line
                var j = i + 3
                while j < chars.count && chars[j] != "\n" { j += 1 }
                let infoString = String(chars[(i+3)..<j]).trimmingCharacters(in: .whitespaces)

                // Find closing ```
                var closeIdx: Int? = nil
                var k = j + 1
                while k + 2 < chars.count {
                    if chars[k] == "`" && chars[k+1] == "`" && chars[k+2] == "`" {
                        closeIdx = k
                        break
                    }
                    k += 1
                }

                if let close = closeIdx {
                    let codeContent: String
                    if j < chars.count {
                        codeContent = String(chars[(j+1)..<close])
                    } else {
                        codeContent = ""
                    }
                    if infoString.isEmpty {
                        result += "<pre>" + escapeHtml(codeContent) + "</pre>"
                    } else {
                        result += "<pre><code class=\"language-\(escapeHtml(infoString))\">" + escapeHtml(codeContent) + "</code></pre>"
                    }
                    // Skip past closing ```
                    i = close + 3
                    // Skip optional newline after closing fence
                    if i < chars.count && chars[i] == "\n" { i += 1 }
                    continue
                }
            }

            // Check for inline code: `
            if chars[i] == "`" {
                var j = i + 1
                while j < chars.count && chars[j] != "`" && chars[j] != "\n" { j += 1 }
                if j < chars.count && chars[j] == "`" {
                    let code = String(chars[(i+1)..<j])
                    result += "<code>" + escapeHtml(code) + "</code>"
                    i = j + 1
                    continue
                }
            }

            // Check for bold: **text**
            if i + 1 < chars.count && chars[i] == "*" && chars[i+1] == "*" {
                var j = i + 2
                while j + 1 < chars.count {
                    if chars[j] == "*" && chars[j+1] == "*" { break }
                    j += 1
                }
                if j + 1 < chars.count && chars[j] == "*" && chars[j+1] == "*" {
                    let content = String(chars[(i+2)..<j])
                    result += "<b>" + content + "</b>"
                    i = j + 2
                    continue
                }
            }

            // Check for italic: *text* (single asterisk, not followed by another)
            if chars[i] == "*" && (i + 1 >= chars.count || chars[i+1] != "*") {
                var j = i + 1
                while j < chars.count && chars[j] != "*" && chars[j] != "\n" { j += 1 }
                if j < chars.count && chars[j] == "*" {
                    let content = String(chars[(i+1)..<j])
                    result += "<i>" + content + "</i>"
                    i = j + 1
                    continue
                }
            }

            // Check for links: [text](url)
            if chars[i] == "[" {
                var j = i + 1
                while j < chars.count && chars[j] != "]" && chars[j] != "\n" { j += 1 }
                if j < chars.count && chars[j] == "]" && j + 1 < chars.count && chars[j+1] == "(" {
                    var k = j + 2
                    while k < chars.count && chars[k] != ")" && chars[k] != "\n" { k += 1 }
                    if k < chars.count && chars[k] == ")" {
                        let linkText = String(chars[(i+1)..<j])
                        let url = String(chars[(j+2)..<k])
                        result += "<a href=\"\(escapeHtml(url))\">\(escapeHtml(linkText))</a>"
                        i = k + 1
                        continue
                    }
                }
            }

            // Default: escape and append
            let ch = chars[i]
            switch ch {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(ch)
            }
            i += 1
        }

        return result
    }

    // MARK: - HTML Tag Stripping

    /// Strip HTML tags from text (plain text fallback for send failures).
    static func stripHtmlTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
