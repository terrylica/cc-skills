import Foundation

// MARK: - Fence Parsing & Telegram HTML Chunking

extension TelegramFormatter {

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
    /// Uses strict greater-than on start to match legacy TS behavior.
    static func findFenceSpanAt(_ spans: [FenceSpan], index: Int) -> FenceSpan? {
        spans.first { index > $0.start && index < $0.end }
    }

    /// Check whether a break at the given character index is safe (not inside a fenced code block).
    static func isSafeFenceBreak(_ spans: [FenceSpan], index: Int) -> Bool {
        findFenceSpanAt(spans, index: index) == nil
    }

    // MARK: - Fence-Aware Chunking

    /// Split text into chunks that fit within Telegram's message limit, respecting fenced code blocks.
    /// When forced to split inside a fence, closes and re-opens the fence across chunks.
    static func chunkTelegramHtml(_ text: String, limit: Int = telegramMaxLength) -> [String] {
        guard !text.isEmpty else { return [] }
        guard text.count > limit else { return [text] }

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let spans = parseFenceSpans(normalized)

        // Phase 1: Split on paragraph boundaries (blank lines) outside fences
        let paragraphPattern = "\n[\\t ]*\n+"
        var parts: [String] = []
        var lastIdx = normalized.startIndex

        if let regex = try? NSRegularExpression(pattern: paragraphPattern, options: []) {
            let nsStr = normalized as NSString
            let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: nsStr.length))
            for m in matches {
                let matchStart = m.range.location
                if !isSafeFenceBreak(spans, index: matchStart) { continue }
                let partEnd = normalized.index(normalized.startIndex, offsetBy: matchStart)
                parts.append(String(normalized[lastIdx..<partEnd]))
                lastIdx = normalized.index(normalized.startIndex, offsetBy: matchStart + m.range.length)
            }
        }
        parts.append(String(normalized[lastIdx...]))

        // Phase 2: Pack paragraphs into chunks, split oversized ones with fence awareness
        var chunks: [String] = []
        var current = ""

        for part in parts {
            let paragraph = part.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            guard !paragraph.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            if !current.isEmpty && (current + "\n\n" + paragraph).count <= limit {
                current += "\n\n" + paragraph
                continue
            }

            if !current.isEmpty {
                chunks.append(current)
                current = ""
            }

            if paragraph.count <= limit {
                current = paragraph
                continue
            }

            // Oversized paragraph: fence-aware splitting
            chunks.append(contentsOf: chunkMarkdownText(paragraph, limit: limit))
        }

        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    /// Fence-aware text chunking with fence close/reopen.
    /// Prefers newline > whitespace > hard break.
    private static func chunkMarkdownText(_ text: String, limit: Int) -> [String] {
        guard !text.isEmpty else { return [] }
        guard text.count > limit else { return [text] }

        var chunks: [String] = []
        var remaining = text

        while remaining.count > limit {
            let spans = parseFenceSpans(remaining)
            let windowEnd = remaining.index(remaining.startIndex, offsetBy: min(limit, remaining.count))
            let window = String(remaining[..<windowEnd])

            // Find safe break point (outside fences, prefer newline > whitespace)
            let softBreak = pickSafeBreakIndex(window, spans: spans)
            var breakIdx = softBreak > 0 ? softBreak : limit

            // Check if we're breaking inside a fence
            var fenceToSplit: FenceSpan? = nil
            if !isSafeFenceBreak(spans, index: breakIdx) {
                if let fence = findFenceSpanAt(spans, index: breakIdx) {
                    let closeLine = "\(fence.indent)\(fence.marker)"
                    let maxIdx = limit - (closeLine.count + 1)

                    if maxIdx <= 0 {
                        // Close-line too long, fall back to hard break
                        breakIdx = limit
                    } else {
                        // Find a newline inside the fence to break at
                        let minProgress = min(remaining.count, fence.start + fence.openLine.count + 2)
                        var lastNl = remaining[..<remaining.index(remaining.startIndex, offsetBy: min(max(0, limit - closeLine.count - 1) + 1, remaining.count))].lastIndex(of: "\n")
                        var pickedNewline = false

                        while let nl = lastNl {
                            let candidate = remaining.distance(from: remaining.startIndex, to: remaining.index(after: nl))
                            if candidate < minProgress { break }
                            let atFence = findFenceSpanAt(spans, index: candidate)
                            if let atFence = atFence, atFence.start == fence.start {
                                breakIdx = max(1, candidate)
                                pickedNewline = true
                                break
                            }
                            // Search for previous newline
                            let searchEnd = nl
                            if searchEnd > remaining.startIndex {
                                lastNl = remaining[..<searchEnd].lastIndex(of: "\n")
                            } else {
                                lastNl = nil
                            }
                        }

                        if !pickedNewline {
                            if minProgress > limit - closeLine.count {
                                breakIdx = limit
                            } else {
                                breakIdx = max(minProgress, maxIdx)
                                fenceToSplit = findFenceSpanAt(spans, index: breakIdx)
                                if let f = fenceToSplit, f.start != fence.start {
                                    fenceToSplit = nil
                                }
                            }
                        } else {
                            let atBreak = findFenceSpanAt(spans, index: breakIdx)
                            fenceToSplit = (atBreak != nil && atBreak!.start == fence.start) ? atBreak : nil
                        }
                    }
                }
            }

            let breakPoint = remaining.index(remaining.startIndex, offsetBy: min(breakIdx, remaining.count))
            var rawChunk = String(remaining[..<breakPoint])
            guard !rawChunk.isEmpty else { break }

            let brokeOnSep = breakIdx < remaining.count && remaining[breakPoint].isWhitespace
            let nextStartOffset = min(remaining.count, breakIdx + (brokeOnSep ? 1 : 0))
            let nextStartIndex = remaining.index(remaining.startIndex, offsetBy: nextStartOffset)
            var next = String(remaining[nextStartIndex...])

            if let fence = fenceToSplit {
                // Close the fence in this chunk, re-open in next
                let closeLine = "\(fence.indent)\(fence.marker)"
                if rawChunk.hasSuffix("\n") {
                    rawChunk = "\(rawChunk)\(closeLine)"
                } else {
                    rawChunk = "\(rawChunk)\n\(closeLine)"
                }
                next = "\(fence.openLine)\n\(next)"
            } else {
                // Strip leading newlines from continuation
                var i = next.startIndex
                while i < next.endIndex && next[i] == "\n" {
                    i = next.index(after: i)
                }
                if i > next.startIndex {
                    next = String(next[i...])
                }
            }

            chunks.append(rawChunk)
            remaining = next
        }

        if !remaining.isEmpty {
            chunks.append(remaining)
        }

        return chunks
    }

    /// Split text into paragraphs on double-newline boundaries that are outside fenced code blocks.
    private static func splitIntoParagraphs(_ text: String, spans: [FenceSpan]) -> [String] {
        let chars = Array(text)
        var paragraphs: [String] = []
        var paragraphStart = 0

        var i = 0
        while i < chars.count {
            if chars[i] == "\n" && i + 1 < chars.count {
                var j = i + 1
                if j < chars.count && chars[j] == "\t" { j += 1 }
                if j < chars.count && chars[j] == "\n" {
                    if isSafeFenceBreak(spans, index: i) {
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
        return chunkMarkdownText(text, limit: limit)
    }

    /// Pick the best break index within a window, preferring newline > whitespace, outside fenced blocks.
    static func pickSafeBreakIndex(_ window: String, spans: [FenceSpan]) -> Int {
        let chars = Array(window)
        var lastNewline = -1
        var lastWhitespace = -1

        for i in 0..<chars.count {
            guard isSafeFenceBreak(spans, index: i) else { continue }
            if chars[i] == "\n" {
                lastNewline = i
            } else if chars[i] == " " || chars[i] == "\t" {
                lastWhitespace = i
            }
        }

        if lastNewline > 0 { return lastNewline }
        if lastWhitespace > 0 { return lastWhitespace }
        return -1
    }
}
