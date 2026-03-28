@testable import CompanionCore
import Testing

@Suite struct PronunciationProcessorTests {

    @Test func replacesPluginWithHyphenated() {
        let result = PronunciationProcessor.preprocessText("This plugin is great")
        #expect(result == "This plug-in is great")
    }

    @Test func replacesPluginsWithHyphenated() {
        let result = PronunciationProcessor.preprocessText("All plugins work")
        #expect(result == "All plug-ins work")
    }

    @Test func replacesCapitalizedPlugin() {
        let result = PronunciationProcessor.preprocessText("Plugin system")
        #expect(result == "Plug-in system")
    }

    @Test func replacesCapitalizedPlugins() {
        let result = PronunciationProcessor.preprocessText("Plugins are useful")
        #expect(result == "Plug-ins are useful")
    }

    @Test func doesNotReplacePartialMatches() {
        // Word boundary \b should prevent matching inside other words
        let result = PronunciationProcessor.preprocessText("unplugin is different")
        #expect(result == "unplugin is different")
    }

    @Test func doesNotReplacePluginfo() {
        let result = PronunciationProcessor.preprocessText("pluginfo tool")
        #expect(result == "pluginfo tool")
    }

    @Test func leavesTextWithoutOverridesUnchanged() {
        let text = "Hello world, this is a normal sentence."
        let result = PronunciationProcessor.preprocessText(text)
        #expect(result == text)
    }

    @Test func handlesMultipleReplacementsInOneString() {
        let result = PronunciationProcessor.preprocessText(
            "The plugin and its plugins")
        #expect(result == "The plug-in and its plug-ins")
    }
}
