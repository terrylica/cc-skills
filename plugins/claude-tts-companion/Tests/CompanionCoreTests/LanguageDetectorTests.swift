@testable import CompanionCore
import Testing

@Suite struct LanguageDetectorTests {
    @Test func detectsEnglishTextByDefault() {
        let result = LanguageDetector.detect(text: "Hello world, this is a test")
        #expect(result.lang == "en-us")
        #expect(result.voiceName == "af_heart")
    }

    @Test func detectsCJKTextAboveThreshold() {
        // >20% CJK characters triggers Chinese detection
        let result = LanguageDetector.detect(text: "你好世界，这是一个测试内容的文字")
        #expect(result.lang == "cmn")
    }

    @Test func detectsEnglishWithMinorCJK() {
        // <20% CJK should still be English
        let result = LanguageDetector.detect(text: "This is mostly English text with 你好")
        #expect(result.lang == "en-us")
    }

    @Test func handlesEmptyText() {
        let result = LanguageDetector.detect(text: "")
        #expect(result.lang == "en-us")
        #expect(result.voiceName == "af_heart")
    }
}
