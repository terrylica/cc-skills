@testable import CompanionCore
import Testing
import AppKit

@Suite(.serialized)
@MainActor
struct BionicRendererTests {

    // MARK: - boldPrefixLength

    @Test func emptyStringReturnsZero() {
        #expect(BionicRenderer.boldPrefixLength("") == 0)
    }

    @Test func singleCharReturnsOne() {
        #expect(BionicRenderer.boldPrefixLength("a") == 1)
    }

    @Test func twoCharsReturnsOne() {
        // 0.4 * 2 = 0.8, ceil = 1
        #expect(BionicRenderer.boldPrefixLength("ab") == 1)
    }

    @Test func threeCharsReturnsTwo() {
        // 0.4 * 3 = 1.2, ceil = 2
        #expect(BionicRenderer.boldPrefixLength("abc") == 2)
    }

    @Test func fiveCharsReturnsTwo() {
        // 0.4 * 5 = 2.0, ceil = 2
        #expect(BionicRenderer.boldPrefixLength("hello") == 2)
    }

    @Test func sevenCharsReturnsThree() {
        // 0.4 * 7 = 2.8, ceil = 3
        #expect(BionicRenderer.boldPrefixLength("testing") == 3)
    }

    @Test func tenCharsReturnsFour() {
        // 0.4 * 10 = 4.0, ceil = 4
        #expect(BionicRenderer.boldPrefixLength("abcdefghij") == 4)
    }

    @Test func fourCharsReturnsTwo() {
        // 0.4 * 4 = 1.6, ceil = 2
        #expect(BionicRenderer.boldPrefixLength("word") == 2)
    }

    // MARK: - render

    @Test func renderProducesBoldPrefixAndRegularSuffix() {
        let result = BionicRenderer.render(words: ["Hello"], fontSizeName: "medium")
        let str = result.string
        #expect(str == "Hello")

        // First 2 chars ("He") should be bold
        var boldRange = NSRange(location: 0, length: 0)
        let boldFont = result.attribute(.font, at: 0, effectiveRange: &boldRange) as? NSFont
        #expect(boldFont != nil)
        #expect(boldRange.length >= 2)

        // Chars at index 2 ("l") should be regular
        var regularRange = NSRange(location: 0, length: 0)
        let regularFont = result.attribute(.font, at: 2, effectiveRange: &regularRange) as? NSFont
        #expect(regularFont != nil)

        // Bold and regular should use different weights
        #expect(boldFont != regularFont)
    }

    @Test func renderMultipleWordsSeparatedBySpaces() {
        let result = BionicRenderer.render(words: ["Hello", "world"], fontSizeName: "medium")
        #expect(result.string == "Hello world")
    }

    @Test func renderEmptyArrayReturnsEmptyString() {
        let result = BionicRenderer.render(words: [], fontSizeName: "medium")
        #expect(result.string == "")
    }

    @Test func renderSingleCharWord() {
        let result = BionicRenderer.render(words: ["I"], fontSizeName: "medium")
        #expect(result.string == "I")
        // Single char word: all bold
        var range = NSRange(location: 0, length: 0)
        let font = result.attribute(.font, at: 0, effectiveRange: &range) as? NSFont
        #expect(font != nil)
        #expect(range.length == 1)
    }

    // MARK: - DisplayMode

    @Test func displayModeFromValidStrings() {
        #expect(DisplayMode.from(string: "bionic") == .bionic)
        #expect(DisplayMode.from(string: "karaoke") == .karaoke)
        #expect(DisplayMode.from(string: "plain") == .plain)
    }

    @Test func displayModeFromInvalidStringDefaultsToKaraoke() {
        #expect(DisplayMode.from(string: "invalid") == .karaoke)
        #expect(DisplayMode.from(string: "") == .karaoke)
        #expect(DisplayMode.from(string: "BIONIC") == .karaoke)
    }
}
