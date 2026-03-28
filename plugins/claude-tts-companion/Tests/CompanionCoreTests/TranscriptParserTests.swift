@testable import CompanionCore
import Foundation
import Testing

@Suite struct TranscriptParserTests {
    @Test func parsesUserPromptFromJsonl() {
        let jsonl = """
        {"type":"user","message":{"content":"Hello, how are you?"},"timestamp":"2026-03-27T10:00:00Z"}
        """
        let entries = TranscriptParser.parse(content: jsonl)
        #expect(entries.count == 1)
        if case .prompt(let text, _) = entries[0] {
            #expect(text == "Hello, how are you?")
        } else {
            Issue.record("Expected .prompt entry")
        }
    }

    @Test func parsesAssistantResponseFromJsonl() {
        let jsonl = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"I am fine, thanks!"}]}}
        """
        let entries = TranscriptParser.parse(content: jsonl)
        #expect(entries.count == 1)
        if case .response(let text, _) = entries[0] {
            #expect(text == "I am fine, thanks!")
        } else {
            Issue.record("Expected .response entry")
        }
    }

    @Test func parsesToolUseFromAssistantEntry() {
        let jsonl = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read"}]}}
        """
        let entries = TranscriptParser.parse(content: jsonl)
        #expect(entries.count == 1)
        if case .toolUse(let name, _) = entries[0] {
            #expect(name == "Read")
        } else {
            Issue.record("Expected .toolUse entry")
        }
    }

    @Test func handlesInvalidJsonGracefully() {
        let jsonl = "this is not valid json\n{also broken"
        let entries = TranscriptParser.parse(content: jsonl)
        #expect(entries.isEmpty)
    }

    @Test func skipsUnknownTypeEntries() {
        let jsonl = """
        {"type":"progress","data":{}}
        """
        let entries = TranscriptParser.parse(content: jsonl)
        #expect(entries.isEmpty)
    }

    @Test func parsesMultipleEntriesFromContent() {
        let jsonl = """
        {"type":"user","message":{"content":"First prompt"}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"First response"}]}}
        {"type":"user","message":{"content":"Second prompt"}}
        """
        let entries = TranscriptParser.parse(content: jsonl)
        #expect(entries.count == 3)
    }

    @Test func identifiesSystemNoise() {
        #expect(TranscriptParser.isSystemNoise("<command-name>test</command-name>"))
        #expect(TranscriptParser.isSystemNoise("This session is being continued from a previous conversation"))
        #expect(!TranscriptParser.isSystemNoise("A normal user prompt about coding"))
    }

    @Test func parsesFileBasedTranscript() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test-transcript-\(UUID().uuidString).jsonl")
        let content = """
        {"type":"user","message":{"content":"Test prompt"}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"Test response"}]}}
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let entries = TranscriptParser.parse(filePath: tempFile.path)
        #expect(entries.count == 2)
    }
}
